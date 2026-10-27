"""Server-side client for the YouTube Data API v3.

Only the backend talks to YouTube. The API key travels in the ``X-Goog-Api-Key``
header rather than the query string, so it never appears in a request URL, in
httpx's request logging, or in any error message raised from here.

Nothing returned by this module is evidence that a video is safe for children.
Search results, ``madeForKids``, channel names, tags and thumbnails are inputs
to screening and human review, never a substitute for them.
"""

import logging
import re
import threading
import time
from typing import Any
from urllib.parse import parse_qs, urlsplit

import httpx

from app.core.config import settings
from app.core.exceptions import APIError

logger = logging.getLogger(__name__)

API_BASE_URL = "https://www.googleapis.com/youtube/v3"
VIDEO_ID_PATTERN = re.compile(r"^[A-Za-z0-9_-]{11}$")
PAGE_TOKEN_PATTERN = re.compile(r"^[A-Za-z0-9_-]{1,128}$")
LANGUAGE_PATTERN = re.compile(r"^[a-z]{2,3}(?:-[A-Za-z]{2,4})?$")
REGION_PATTERN = re.compile(r"^[A-Z]{2}$")
_DURATION_PATTERN = re.compile(r"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$")

_WATCH_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com"}
_EMBED_HOSTS = _WATCH_HOSTS | {"www.youtube-nocookie.com", "youtube-nocookie.com"}
_SHORT_HOSTS = {"youtu.be"}
_THUMBNAIL_HOSTS = {"i.ytimg.com"}

QUOTA_REASONS = {"quotaExceeded", "dailyLimitExceeded", "rateLimitExceeded", "userRateLimitExceeded"}
KEY_REASONS = {"keyInvalid", "keyExpired", "accessNotConfigured", "forbidden", "ipRefererBlocked"}

# Fixed discovery topics. Administrators choose a key; free-text queries are
# never sent, so discovery cannot be steered towards arbitrary content.
DISCOVERY_TOPICS: dict[str, str] = {
	"early_learning": "early learning foundational skills for children",
	"math": "math for kids",
	"science": "science experiments for kids",
	"coding": "coding computer science education for children",
	"stories": "educational stories for children",
	"academic_explainers": "academic explainers for children",
	"nature": "nature education for children",
	"animals": "animals for kids educational",
	"language": "learn english for kids",
	"art": "drawing and art for kids",
	"preschool": "preschool learning",
}


def parse_youtube_video_id(value: str) -> str | None:
	"""Return the 11-character video id from a bare id or an https YouTube URL.

	Anything else (other hosts, http, playlists, channel pages, malformed ids)
	returns None.
	"""
	candidate = (value or "").strip()
	if VIDEO_ID_PATTERN.fullmatch(candidate):
		return candidate
	try:
		parts = urlsplit(candidate)
	except ValueError:
		return None
	if parts.scheme != "https" or parts.username or parts.password or parts.port:
		return None
	host = (parts.hostname or "").lower()
	segments = [segment for segment in parts.path.split("/") if segment]
	video_id: str | None = None
	if host in _SHORT_HOSTS and len(segments) == 1:
		video_id = segments[0]
	elif host in _WATCH_HOSTS and segments == ["watch"]:
		values = parse_qs(parts.query).get("v", [])
		video_id = values[0] if len(values) == 1 else None
	elif host in _WATCH_HOSTS and len(segments) == 2 and segments[0] in {"shorts", "live"}:
		video_id = segments[1]
	elif host in _EMBED_HOSTS and len(segments) == 2 and segments[0] == "embed":
		video_id = segments[1]
	if video_id and VIDEO_ID_PATTERN.fullmatch(video_id):
		return video_id
	return None


def canonical_watch_url(video_id: str) -> str:
	return f"https://www.youtube.com/watch?v={video_id}"


def parse_iso8601_duration(value: str | None) -> int | None:
	"""``PT4M13S`` -> 253. Returns None for missing or unparseable durations."""
	match = _DURATION_PATTERN.fullmatch(value or "")
	if not match or not any(match.groups()):
		return None
	days, hours, minutes, seconds = (int(part) if part else 0 for part in match.groups())
	return days * 86400 + hours * 3600 + minutes * 60 + seconds


def safe_thumbnail_url(snippet: dict[str, Any]) -> str | None:
	"""Pick a thumbnail, accepting only https URLs on YouTube's image host."""
	thumbnails = snippet.get("thumbnails") or {}
	for size in ("high", "medium", "default"):
		url = (thumbnails.get(size) or {}).get("url")
		if not isinstance(url, str):
			continue
		parts = urlsplit(url)
		if parts.scheme == "https" and (parts.hostname or "").lower() in _THUMBNAIL_HOSTS:
			return url
	return None


class YouTubeError(Exception):
	"""Base class; messages never contain the API key."""


class YouTubeNotConfiguredError(YouTubeError):
	pass


class YouTubeQuotaError(YouTubeError):
	pass


class YouTubeUnavailableError(YouTubeError):
	pass


class YouTubeRequestError(YouTubeError):
	pass


def to_api_error(error: YouTubeError) -> APIError:
	if isinstance(error, YouTubeNotConfiguredError):
		return APIError(503, "youtube_not_configured", "YouTube discovery is not configured")
	if isinstance(error, YouTubeQuotaError):
		return APIError(503, "youtube_quota_exhausted", "YouTube quota is exhausted; try again later")
	if isinstance(error, YouTubeRequestError):
		return APIError(502, "youtube_request_rejected", "YouTube rejected the request")
	return APIError(503, "youtube_unavailable", "YouTube could not be reached; try again later")


class _RateLimiter:
	"""Process-wide sliding window on outbound calls, to protect the daily quota."""

	def __init__(self, max_calls: int, per_seconds: float, clock=time.monotonic) -> None:
		self._max_calls = max_calls
		self._per_seconds = per_seconds
		self._clock = clock
		self._calls: list[float] = []
		self._lock = threading.Lock()

	def acquire(self) -> None:
		with self._lock:
			now = self._clock()
			self._calls = [stamp for stamp in self._calls if now - stamp < self._per_seconds]
			if len(self._calls) >= self._max_calls:
				raise YouTubeQuotaError("Local YouTube rate limit reached")
			self._calls.append(now)


class YouTubeClient:
	def __init__(
		self,
		api_key: str | None,
		*,
		transport: httpx.BaseTransport | None = None,
		timeout_seconds: float = 5.0,
		max_retries: int = 2,
		cache_ttl_seconds: float = 900.0,
		cache_max_entries: int = 256,
		rate_limiter: _RateLimiter | None = None,
		clock=time.monotonic,
		sleep=time.sleep,
	) -> None:
		self._api_key = (api_key or "").strip()
		self._transport = transport
		self._timeout = timeout_seconds
		self._max_retries = max_retries
		self._cache_ttl = cache_ttl_seconds
		self._cache_max = cache_max_entries
		self._cache: dict[tuple, tuple[float, dict]] = {}
		self._cache_lock = threading.Lock()
		self._rate_limiter = rate_limiter or _RateLimiter(max_calls=60, per_seconds=60.0, clock=clock)
		self._clock = clock
		self._sleep = sleep

	def __repr__(self) -> str:
		return "YouTubeClient(api_key=<redacted>)"

	def search(
		self,
		topic: str,
		*,
		short: bool = False,
		page_token: str | None = None,
		relevance_language: str | None = None,
		region_code: str | None = None,
		max_results: int = 25,
	) -> dict:
		"""``search.list`` restricted to strict SafeSearch, embeddable videos and a fixed topic.

		Returns ``{"video_ids": [...unique...], "next_page_token": str | None}``.
		"""
		query = DISCOVERY_TOPICS.get(topic)
		if query is None:
			raise ValueError("Unknown discovery topic")
		if page_token is not None and not PAGE_TOKEN_PATTERN.fullmatch(page_token):
			raise ValueError("Malformed page token")
		if relevance_language is not None and not LANGUAGE_PATTERN.fullmatch(relevance_language):
			raise ValueError("Malformed relevance language")
		if region_code is not None and not REGION_PATTERN.fullmatch(region_code):
			raise ValueError("Malformed region code")
		if not 1 <= max_results <= 50:
			raise ValueError("max_results must be between 1 and 50")
		params: dict[str, Any] = {
			"part": "id",
			"q": query,
			"type": "video",
			"safeSearch": "strict",
			"videoEmbeddable": "true",
			"videoSyndicated": "true",
			"maxResults": max_results,
		}
		if short:
			params["videoDuration"] = "short"
		if page_token:
			params["pageToken"] = page_token
		if relevance_language:
			params["relevanceLanguage"] = relevance_language
		if region_code:
			params["regionCode"] = region_code
		data = self._get("search", params)
		video_ids: list[str] = []
		for item in data.get("items") or []:
			video_id = ((item or {}).get("id") or {}).get("videoId")
			if isinstance(video_id, str) and VIDEO_ID_PATTERN.fullmatch(video_id) and video_id not in video_ids:
				video_ids.append(video_id)
		next_token = data.get("nextPageToken")
		if not (isinstance(next_token, str) and PAGE_TOKEN_PATTERN.fullmatch(next_token)):
			next_token = None
		return {"video_ids": video_ids, "next_page_token": next_token}

	def videos(self, video_ids: list[str], *, use_cache: bool = True) -> dict[str, dict]:
		"""``videos.list`` for up to 50 ids, keyed by id. Ids YouTube does not return are absent."""
		unique = list(dict.fromkeys(video_ids))
		if not unique:
			return {}
		if len(unique) > 50 or not all(VIDEO_ID_PATTERN.fullmatch(video_id) for video_id in unique):
			raise ValueError("Between 1 and 50 well-formed video ids are required")
		data = self._get(
			"videos",
			{"part": "snippet,contentDetails,status", "id": ",".join(unique), "maxResults": len(unique)},
			use_cache=use_cache,
		)
		result: dict[str, dict] = {}
		for item in data.get("items") or []:
			video_id = (item or {}).get("id")
			if isinstance(video_id, str) and video_id in unique:
				result[video_id] = item
		return result

	def _get(self, resource: str, params: dict[str, Any], *, use_cache: bool = True) -> dict:
		if not self._api_key:
			raise YouTubeNotConfiguredError("YOUTUBE_API_KEY is not set")
		cache_key = (resource, tuple(sorted((key, str(value)) for key, value in params.items())))
		if use_cache:
			cached = self._cache_get(cache_key)
			if cached is not None:
				return cached
		self._rate_limiter.acquire()
		attempt = 0
		while True:
			try:
				with httpx.Client(transport=self._transport, timeout=self._timeout) as client:
					response = client.get(
						f"{API_BASE_URL}/{resource}",
						params=params,
						headers={"X-Goog-Api-Key": self._api_key, "Accept": "application/json"},
					)
			except httpx.TimeoutException as error:
				if attempt < self._max_retries:
					attempt += 1
					self._sleep(0.5 * attempt)
					continue
				logger.warning("YouTube %s timed out after %d attempts", resource, attempt + 1)
				raise YouTubeUnavailableError("YouTube request timed out") from error
			except httpx.TransportError as error:
				if attempt < self._max_retries:
					attempt += 1
					self._sleep(0.5 * attempt)
					continue
				logger.warning("YouTube %s transport failure (%s)", resource, type(error).__name__)
				raise YouTubeUnavailableError("YouTube could not be reached") from error
			if response.status_code >= 500 and attempt < self._max_retries:
				attempt += 1
				self._sleep(0.5 * attempt)
				continue
			break
		if response.status_code == 200:
			try:
				data = response.json()
			except ValueError as error:
				raise YouTubeUnavailableError("YouTube returned an unreadable response") from error
			if not isinstance(data, dict):
				raise YouTubeUnavailableError("YouTube returned an unexpected response")
			if use_cache:
				self._cache_put(cache_key, data)
			return data
		reason = _error_reason(response)
		logger.warning("YouTube %s failed: HTTP %d (%s)", resource, response.status_code, reason or "unknown")
		if reason in QUOTA_REASONS or response.status_code == 429:
			raise YouTubeQuotaError("YouTube quota exhausted")
		if reason in KEY_REASONS or response.status_code in {401, 403}:
			raise YouTubeNotConfiguredError("YouTube rejected the configured key")
		if response.status_code >= 500:
			raise YouTubeUnavailableError("YouTube is unavailable")
		raise YouTubeRequestError("YouTube rejected the request")

	def _cache_get(self, key: tuple) -> dict | None:
		with self._cache_lock:
			entry = self._cache.get(key)
			if entry is None:
				return None
			expires_at, data = entry
			if self._clock() >= expires_at:
				del self._cache[key]
				return None
			return data

	def _cache_put(self, key: tuple, data: dict) -> None:
		with self._cache_lock:
			if len(self._cache) >= self._cache_max:
				self._cache.pop(next(iter(self._cache)))
			self._cache[key] = (self._clock() + self._cache_ttl, data)


def _error_reason(response: httpx.Response) -> str | None:
	try:
		errors = response.json().get("error", {}).get("errors") or []
	except (ValueError, AttributeError):
		return None
	for error in errors:
		reason = (error or {}).get("reason")
		if isinstance(reason, str):
			return reason
	return None


_client: YouTubeClient | None = None
_client_lock = threading.Lock()


def get_youtube_client() -> YouTubeClient:
	"""The shared client; raises a controlled 503 when no key is configured."""
	global _client
	if not (settings.youtube_api_key or "").strip():
		raise to_api_error(YouTubeNotConfiguredError("YOUTUBE_API_KEY is not set"))
	with _client_lock:
		if _client is None:
			_client = YouTubeClient(settings.youtube_api_key)
		return _client
