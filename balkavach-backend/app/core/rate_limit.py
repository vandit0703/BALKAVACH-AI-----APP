from collections import defaultdict, deque
import hashlib
import logging
from threading import Lock
from time import monotonic

from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)


class FixedWindowLimiter:
	def __init__(self) -> None:
		self._attempts: dict[str, deque[float]] = defaultdict(deque)
		self._lock = Lock()

	def check(self, key: str, *, limit: int, window_seconds: int) -> int | None:
		now = monotonic()
		with self._lock:
			attempts = self._attempts[key]
			while attempts and now - attempts[0] >= window_seconds:
				attempts.popleft()
			if len(attempts) >= limit:
				return max(1, int(window_seconds - (now - attempts[0])))
			attempts.append(now)
			if len(self._attempts) > 10_000:
				self._prune(now, window_seconds)
		return None

	def _prune(self, now: float, window_seconds: int) -> None:
		for key, attempts in list(self._attempts.items()):
			while attempts and now - attempts[0] >= window_seconds:
				attempts.popleft()
			if not attempts:
				del self._attempts[key]


class RedisRateLimiter:
	"""Atomic, shared limiter for multi-instance authentication endpoints."""

	_SCRIPT = """
	local count = redis.call('INCR', KEYS[1])
	if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
	if count > tonumber(ARGV[2]) then return redis.call('TTL', KEYS[1]) end
	return 0
	"""

	def __init__(self, name: str) -> None:
		self._name = name
		self._client = None
		self._script = None

	def _redis(self):
		if not settings.redis_url:
			raise RuntimeError("REDIS_URL is not configured")
		if self._client is None:
			try:
				import redis

				self._client = redis.Redis.from_url(
					settings.redis_url,
					decode_responses=True,
					socket_connect_timeout=1,
					socket_timeout=1,
				)
				self._client.ping()
			except Exception as error:
				raise RuntimeError("Redis authentication limiter is unavailable") from error
		return self._client

	def check(self, key: str, *, limit: int, window_seconds: int) -> int | None:
		try:
			client = self._redis()
			if self._script is None:
				self._script = client.register_script(self._SCRIPT)
			digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
			blocked_for = int(
				self._script(
					keys=[f"{settings.redis_rate_limit_prefix}:{self._name}:{digest}"],
					args=[window_seconds, limit],
				)
			)
			return max(1, blocked_for) if blocked_for > 0 else None
		except Exception as error:
			logger.error("Redis rate limiter failure for %s", self._name, exc_info=error)
			raise HTTPException(
				status_code=503,
				detail="Authentication protection is temporarily unavailable.",
				headers={"Retry-After": "30"},
			) from error


login_limiter = RedisRateLimiter("login")
registration_limiter = RedisRateLimiter("registration")
password_reset_limiter = RedisRateLimiter("password-reset")
parent_pin_limiter = RedisRateLimiter("parent-pin")
parent_mode_limiter = RedisRateLimiter("parent-mode-entry")
password_change_limiter = RedisRateLimiter("password-change")


def enforce(limiter: FixedWindowLimiter, key: str, *, limit: int, window_seconds: int) -> None:
	retry_after = limiter.check(key, limit=limit, window_seconds=window_seconds)
	if retry_after is not None:
		raise HTTPException(
			status_code=429,
			detail="Too many attempts. Please try again later.",
			headers={"Retry-After": str(retry_after)},
		)