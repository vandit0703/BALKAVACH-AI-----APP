"""Moderation pipeline for YouTube-sourced videos.

A YouTube video is a ``videos`` row (``video_source = 'youtube'``) plus a
``youtube_content_reviews`` row holding its state:

    discovered -> pending_review -> approved | rejected
    with quarantined, revoked and unavailable as side states.

Screening moves a candidate to ``pending_review``, ``quarantined`` or
``unavailable``. A candidate that screening leaves clean is approved and
published automatically (``publication_source = 'automatic'``) when every rule in
``auto_approval_blocker`` passes; ``auto_review`` re-verifies waiting candidates
against YouTube and applies the same rules. Anything that fails stays unpublished
with the reason recorded, and an administrator can still approve, reject or
revoke by hand. Automatic approval never overrides an administrator's decision,
a user report, or an explicit "rights not cleared". The child feed additionally
requires the approval to have been re-verified recently (see
``youtube_visibility_clause``).
Screening is a keyword and metadata filter: it reduces reviewer load, it does
not make content safe, and it inspects no video frames, audio or thumbnails.
"""

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import and_, case, exists, func, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.db.base import get_model, has_model
from app.integrations.youtube import (
	YouTubeClient,
	YouTubeError,
	canonical_watch_url,
	parse_iso8601_duration,
	parse_youtube_video_id,
	safe_channel_thumbnail_url,
	safe_thumbnail_url,
	to_api_error,
)
from app.schemas.video import YOUTUBE_AGE_BANDS, YOUTUBE_AGE_RANGES, YouTubeApproveRequest, YouTubeDiscoverRequest
from app.services.video_classification import known_duration_or_none, regular_clause, short_clause, video_format
from app.services.admin_service import record_audit
from app.utils import utc_aware, utc_naive

TRANSITIONS: dict[str, set[str]] = {
	"discovered": {"pending_review", "quarantined", "unavailable"},
	"pending_review": {"approved", "rejected", "quarantined", "unavailable"},
	"quarantined": {"approved", "rejected", "pending_review", "unavailable"},
	"approved": {"revoked", "quarantined", "unavailable"},
	"rejected": {"pending_review"},
	"revoked": {"pending_review"},
	"unavailable": {"pending_review"},
}

MAX_REPORTS_PER_USER_PER_DAY = 20
TRUSTED_DISCOVERY_MAX_PAGES = 3
logger = logging.getLogger(__name__)

# Crude on purpose: a hit sends the candidate to quarantine for a human, it never
# rejects or approves anything by itself.
_DENYLIST = (
	"kill", "killing", "murder", "blood", "bloody", "gore", "gun", "guns", "shoot", "shooting",
	"weapon", "horror", "scary", "creepy", "zombie", "prank", "sexy", "sex", "nude", "naked",
	"kiss", "kissing", "drunk", "alcohol", "beer", "drug", "drugs", "weed", "vape", "smoking",
	"suicide", "dead", "death", "fight", "fighting", "violence", "violent", "nsfw", "18+",
	"injection", "pregnant", "gambling", "casino",
)
_DENYLIST_PATTERN = re.compile(
	r"(?<![a-z0-9])(" + "|".join(re.escape(word) for word in _DENYLIST) + r")(?![a-z0-9])"
)


def can_transition(current: str, target: str) -> bool:
	return target in TRANSITIONS.get(current, set())


def screen_candidate(item: dict[str, Any], region_code: str | None = None) -> tuple[str, list[str]]:
	"""Classify ``videos.list`` metadata into (status, flags).

	``unavailable`` when the official player cannot show it; ``quarantined`` when
	safety cannot be established from metadata; otherwise ``pending_review``.
	"""
	status = item.get("status") or {}
	snippet = item.get("snippet") or {}
	details = item.get("contentDetails") or {}
	flags: list[str] = []

	privacy_status = status.get("privacyStatus")
	if privacy_status is not None and privacy_status != "public":
		flags.append("not_public")
	elif privacy_status is None:
		flags.append("privacy_status_unknown")
	if status.get("embeddable") is False:
		flags.append("not_embeddable")
	elif status.get("embeddable") is None:
		flags.append("embeddable_unknown")
	upload_status = status.get("uploadStatus")
	if upload_status is not None and upload_status != "processed":
		flags.append("not_processed")
	elif upload_status is None:
		flags.append("upload_status_unknown")
	restriction = details.get("regionRestriction") or {}
	if region_code and (
		region_code in (restriction.get("blocked") or [])
		or ("allowed" in restriction and region_code not in (restriction.get("allowed") or []))
	):
		flags.append("region_blocked")
	if any(flag in flags for flag in ("not_public", "not_embeddable", "not_processed", "region_blocked")):
		return "unavailable", flags

	quarantine = False
	if (details.get("contentRating") or {}).get("ytRating") == "ytAgeRestricted":
		flags.append("age_restricted")
		quarantine = True
	made_for_kids = status.get("madeForKids")
	if made_for_kids is None:
		flags.append("made_for_kids_unknown")
	elif made_for_kids is not True:
		flags.append("not_made_for_kids")
		quarantine = True
	if not parse_iso8601_duration(details.get("duration")):
		flags.append("duration_unknown")
	live_status = snippet.get("liveBroadcastContent")
	if live_status not in (None, "none"):
		flags.append("live_content")
	elif live_status is None:
		flags.append("live_status_unknown")
	text = " ".join(
		[str(snippet.get("title") or ""), str(snippet.get("description") or "")]
		+ [str(tag) for tag in (snippet.get("tags") or [])]
	).lower()
	for word in sorted(set(_DENYLIST_PATTERN.findall(text))):
		flags.append(f"keyword:{word}")
	if not snippet.get("title"):
		flags.append("missing_title")
	if not (snippet.get("defaultAudioLanguage") or snippet.get("defaultLanguage")):
		flags.append("language_unknown")
	if safe_thumbnail_url(snippet) is None:
		flags.append("no_thumbnail")
	return ("quarantined" if quarantine else "pending_review"), flags


def youtube_visibility_clause(Video, now: datetime | None = None):
	"""SQL predicate: a YouTube row is eligible when it is approved, rights-cleared, made for kids, and
	still within the re-verification window. Non-YouTube rows always pass. Without the review table the
	clause is always false for YouTube, so an un-migrated database never leaks a video."""
	from sqlalchemy import exists, literal

	if not has_model("YouTubeContentReview"):
		return Video.video_source != "youtube"
	Review = get_model("YouTubeContentReview")
	now = now or utc_naive(datetime.now(timezone.utc))
	return or_(
		Video.video_source != "youtube",
		exists().where(
			Review.video_id == Video.id,
			Review.status == "approved",
			Review.rights_status == "cleared",
			Review.made_for_kids.is_(True),
		),
	)


def _require_tables(*names: str) -> None:
	if not all(has_model(name) for name in names):
		raise APIError(503, "youtube_review_unavailable", "YouTube moderation storage is not provisioned (migration 0008)")


def _now() -> datetime:
	return utc_naive(datetime.now(timezone.utc))


def _language(snippet: dict[str, Any]) -> str:
	raw = snippet.get("defaultAudioLanguage") or snippet.get("defaultLanguage") or "en"
	primary = str(raw).split("-")[0].lower()
	return primary if re.fullmatch(r"[a-z]{2,3}", primary) else "en"


def _published_at(snippet: dict[str, Any]) -> datetime | None:
	raw = snippet.get("publishedAt")
	if not isinstance(raw, str):
		return None
	try:
		return utc_naive(datetime.fromisoformat(raw.replace("Z", "+00:00")))
	except ValueError:
		return None


def review_public(review, video, category_name: str | None = None) -> dict[str, Any]:
	is_published = bool(video and video.is_published)
	publication_status = "published" if is_published else "unpublished"
	if review.status in {"rejected", "quarantined", "revoked", "unavailable"}:
		publication_status = review.status
	not_published_reason = None if is_published else (
		review.publication_reason
		or (f"review status is {review.status}" if review.status != "approved" else "video is unpublished")
	)
	return {
		"id": review.id,
		"video_id": review.video_id,
		"youtube_video_id": review.youtube_video_id,
		"source_url": review.source_url,
		"channel_id": review.channel_id,
		"channel_title": review.channel_title,
		"source_published_at": utc_aware(review.source_published_at) if review.source_published_at else None,
		"made_for_kids": review.made_for_kids,
		"status": review.status,
		"screening_flags": list(review.screening_flags or []),
		"rights_status": review.rights_status,
		"discovered_at": utc_aware(review.discovered_at),
		"reviewed_by": review.reviewed_by,
		"reviewed_at": utc_aware(review.reviewed_at) if review.reviewed_at else None,
		"review_notes": review.review_notes,
		"last_verified_at": utc_aware(review.last_verified_at) if review.last_verified_at else None,
		"revoked_reason": review.revoked_reason,
		"revoked_at": utc_aware(review.revoked_at) if review.revoked_at else None,
		"title": video.title if video else None,
		"description": video.description if video else None,
		"thumbnail_url": video.thumbnail_url if video else None,
		"duration_seconds": video.duration_seconds if video else None,
		"language_code": video.language_code if video else None,
		"video_format": video_format(video.video_source, video.duration_seconds) if video else None,
		"age_min": video.age_min if video else None,
		"age_max": video.age_max if video else None,
		"category_name": category_name,
		"discovery_topic": review.discovery_topic,
		"youtube_category_id": review.youtube_category_id,
		"publication_source": getattr(review, "publication_source", "manual"),
		"publication_reason": getattr(review, "publication_reason", None),
		"is_published": is_published,
		"published_at": utc_aware(video.published_at) if video and video.published_at else None,
		"category_id": video.category_id if video else None,
		"publication_status": publication_status,
		"not_published_reason": not_published_reason,
	}


def _create_candidate(
	session: Session,
	actor,
	video_id: str,
	item: dict[str, Any] | None,
	discovery_topic: str | None = None,
	trusted_channel=None,
):
	"""Insert an unpublished video + review row. Returns None if the video cannot play."""
	if item is None:
		item = {}
	snippet = item.get("snippet") or {}
	duration = parse_iso8601_duration((item.get("contentDetails") or {}).get("duration"))
	age_band = auto_age_band(trusted_channel)
	if age_band is None:
		age_band = (9, 15) if discovery_topic == "teen_funny_shorts" else (4, 12)
	status, flags = (
		("unavailable", ["not_returned"])
		if not item
		else screen_candidate(item, settings.youtube_region_code)
	)
	Video = get_model("Video")
	Review = get_model("YouTubeContentReview")
	actor_id = actor.id
	video = Video(
		title=(str(snippet.get("title") or video_id).strip() or video_id)[:200],
		description=(str(snippet.get("description") or "")[:5000]) or None,
		video_source="youtube",
		video_url=canonical_watch_url(video_id),
		external_video_id=video_id,
		thumbnail_url=safe_thumbnail_url(snippet),
		duration_seconds=min(duration or 1, 86400),
		language_code=_language(snippet),
		age_min=age_band[0],
		category_id=trusted_channel.category_id if trusted_channel is not None else None,
		age_max=age_band[1],
		content_rating="parent_review_required",
		is_published=False,
		display_order=0,
		uploaded_by=actor_id,
	)
	review_values = dict(
		youtube_video_id=video_id,
		source_url=canonical_watch_url(video_id),
		discovery_topic=discovery_topic,
		youtube_category_id=str(snippet["categoryId"])[:20] if snippet.get("categoryId") else None,
		channel_id=(snippet.get("channelId") or None) and str(snippet["channelId"])[:64],
		channel_title=(snippet.get("channelTitle") or None) and str(snippet["channelTitle"])[:200],
		source_published_at=_published_at(snippet),
		made_for_kids=(item.get("status") or {}).get("madeForKids"),
		status=status,
		screening_flags=flags,
		rights_status="unreviewed",
		discovered_by=actor_id,
		last_verified_at=_now(),
	)
	if hasattr(Review, "publication_source"):
		review_values["publication_source"] = "manual"
	review = Review(**review_values)
	try:
		with session.begin_nested():
			session.add(video)
			session.flush()
			review.video_id = video.id
			session.add(review)
			session.flush()
	except IntegrityError:
		return None
	record_audit(
		session,
		actor_id,
		"youtube.discovered",
		"video",
		video.id,
		{"youtube_video_id": video_id, "status": status, "topic": discovery_topic},
	)
	return review, video


AUTO_BLOCKER_TEXT = {
	"non_trusted_auto_publish_disabled": "automatic approval of non-trusted channels is turned off",
	"trusted_channel_inactive": "the trusted channel is inactive",
	"channel_id_mismatch": "the channel does not match the trusted channel record",
	"trusted_channel_rights_not_cleared": "the trusted channel's rights are not cleared",
	"rights_not_cleared": "rights are not cleared for this video",
	"review_not_pending": "the video is not awaiting review",
	"screening_flags": "screening flags need a person to look at them",
	"made_for_kids_not_true": "YouTube does not mark the video as made for kids",
	"duration_exceeds_limit": "the video is longer than the automatic approval limit",
	"age_band_not_configured": "no supported automatic audience age band is configured (set YOUTUBE_AUTO_PUBLISH_AGE_BAND or a trusted-channel age range)",
	"unsupported_age_band": "the audience range is not a complete age band or contiguous combination of bands",
}


def configured_auto_age_band() -> tuple[int, int] | None:
	"""The operator-chosen audience for automatic approval, or ``None`` if unset or invalid."""
	raw = (settings.youtube_auto_publish_age_band or "").strip()
	try:
		low, high = (int(part) for part in raw.split("-", 1))
	except ValueError:
		return None
	return (low, high) if (low, high) in YOUTUBE_AGE_BANDS else None


def auto_age_band(trusted_channel) -> tuple[int, int] | None:
	"""Audience an automatically approved video would get, if it is a supported band."""
	if trusted_channel is not None:
		band = (trusted_channel.age_min, trusted_channel.age_max)
		if band in YOUTUBE_AGE_RANGES:
			return band
	configured = configured_auto_age_band()
	if configured is not None:
		return configured
	return (3, 15) if trusted_channel is not None else None


def auto_approval_blocker(review, video, trusted_channel=None) -> tuple[str, dict[str, Any]] | None:
	"""Why this candidate may not be approved automatically, or ``None`` if it may.

	Pure policy: reads attributes only. Every rule that gates automatic
	publication lives here, so it is the single place to audit.
	"""
	if trusted_channel is None:
		if not settings.youtube_auto_publish_non_trusted:
			return "non_trusted_auto_publish_disabled", {}
	else:
		if not trusted_channel.is_active:
			return "trusted_channel_inactive", {}
		if review.channel_id != trusted_channel.channel_id:
			return "channel_id_mismatch", {"trusted_channel_id": trusted_channel.channel_id}
		if trusted_channel.rights_status != "cleared":
			return "trusted_channel_rights_not_cleared", {"rights_status": trusted_channel.rights_status}
	if review.rights_status == "not_cleared":
		return "rights_not_cleared", {"rights_status": review.rights_status}
	if trusted_channel is None and review.rights_status != "cleared":
		return "rights_not_cleared", {"rights_status": review.rights_status}
	if review.status != "pending_review":
		return "review_not_pending", {"status": review.status}
	if review.screening_flags:
		return "screening_flags", {"flags": list(review.screening_flags)}
	if review.made_for_kids is not True:
		return "made_for_kids_not_true", {"made_for_kids": review.made_for_kids}
	if auto_age_band(trusted_channel) is None:
		if trusted_channel is None and not (settings.youtube_auto_publish_age_band or "").strip():
			return "age_band_not_configured", {}
		return "unsupported_age_band", {}
	max_seconds = (
		settings.youtube_trusted_auto_publish_max_seconds
		if trusted_channel is not None
		else settings.youtube_auto_publish_max_seconds
	)
	if video.duration_seconds > max_seconds:
		return "duration_exceeds_limit", {
			"duration_seconds": video.duration_seconds,
			"max_duration_seconds": max_seconds,
		}
	return None


def _auto_publish(session: Session, actor, review, video, trusted_channel=None) -> bool:
	"""Publish a clean short or regular candidate under the configured policy."""
	blocker = auto_approval_blocker(review, video, trusted_channel)
	if blocker is not None:
		reason, details = blocker
		logger.info(
			"youtube.auto_publish.skipped",
			extra={
				"event": "youtube.auto_publish.skipped",
				"reason": reason,
				"review_id": str(getattr(review, "id", "")),
				"youtube_video_id": review.youtube_video_id,
				"channel_id": review.channel_id,
				**details,
			},
		)
		return False
	now = _now()
	video.age_min, video.age_max = auto_age_band(trusted_channel)
	if trusted_channel is not None:
		if trusted_channel.language_code:
			video.language_code = trusted_channel.language_code
		if trusted_channel.category_id is not None:
			video.category_id = trusted_channel.category_id
	video.content_rating = "educational"
	video.is_published = True
	video.published_at = now
	review.rights_status = "cleared"
	review.last_verified_at = now
	review.publication_source = "automatic"
	review.publication_reason = (
		f"active trusted channel {trusted_channel.channel_id}; clean metadata screening"
		if trusted_channel is not None
		else "configured non-trusted discovery policy; clean metadata screening"
	)
	_move(
		session,
		actor.id,
		review,
		video,
		"approved",
		{
			"publication_source": "automatic",
			"trusted_channel_id": str(trusted_channel.id) if trusted_channel is not None else None,
		},
	)
	return True


def _trusted_channel_or_404(session: Session, channel_id: str):
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	return channel


def _channel_video_counts(session: Session, channel_id: str) -> dict[str, int]:
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	by_status = dict(
		session.query(Review.status, func.count(Review.id))
		.filter(Review.channel_id == channel_id)
		.group_by(Review.status)
		.all()
	)
	discovered = sum(int(v) for v in by_status.values())
	shorts = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, short_clause(Video)
	).count()
	regular = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, regular_clause(Video)
	).count()
	published_short_count = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True), short_clause(Video)
	).count()
	published_regular_count = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True), regular_clause(Video)
	).count()
	published = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.channel_id == channel_id, Video.is_published.is_(True)
	).count()
	return {
		"discovered": discovered,
		"approved": int(by_status.get("approved", 0)),
		"pending_review": int(by_status.get("pending_review", 0)),
		"quarantined": int(by_status.get("quarantined", 0)),
		"rejected": int(by_status.get("rejected", 0)),
		"unavailable": int(by_status.get("unavailable", 0)),
		"revoked": int(by_status.get("revoked", 0)),
		"published": published,
		"published_shorts": published_short_count,
		"published_regular": published_regular_count,
		"total_videos": discovered,
		"shorts_count": shorts,
		"long_videos_count": regular,
	}


def _channel_to_public_dict(channel, *, status: str | None = None, counts: dict[str, int] | None = None, last_discovery_at=None) -> dict[str, Any]:
	counts = counts or {}
	return {
		"id": channel.id,
		"channel_id": channel.channel_id,
		"channel_title": channel.channel_title,
		"thumbnail_url": channel.thumbnail_url,
		"age_min": channel.age_min,
		"age_max": channel.age_max,
		"language_code": channel.language_code,
		"category_id": channel.category_id,
		"rights_status": channel.rights_status,
		"is_active": channel.is_active,
		"created_by": channel.created_by,
		"notes": channel.notes,
		"created_at": utc_aware(channel.created_at) if channel.created_at else None,
		"updated_at": utc_aware(channel.updated_at) if channel.updated_at else None,
		"status": status or channel_status(channel),
		"total_videos": counts.get("total_videos", counts.get("discovered")),
		"shorts_count": counts.get("shorts_count"),
		"long_videos_count": counts.get("long_videos_count"),
		"last_discovery_at": last_discovery_at,
	}


def _enrich_trusted_channel(session: Session, channel) -> dict[str, Any]:
	counts = _channel_video_counts(session, channel.channel_id)
	last_discovery_at = _channel_last_discovered(session, channel.channel_id)
	return _channel_to_public_dict(channel, status=channel_status(channel), counts=counts, last_discovery_at=utc_aware(last_discovery_at) if last_discovery_at else None)


def list_trusted_channels(session: Session, limit: int, offset: int, *, include_stats: bool = False) -> list[Any]:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	rows = (
		session.query(Trusted)
		.order_by(Trusted.is_active.desc(), Trusted.channel_title, Trusted.channel_id)
		.offset(offset)
		.limit(limit)
		.all()
	)
	if not include_stats:
		return rows
	return [_enrich_trusted_channel(session, row) for row in rows]


def update_trusted_channel(session: Session, actor, channel_id: str, request) -> Any:
	channel = session.query(get_model("YouTubeTrustedChannel")).filter(
		get_model("YouTubeTrustedChannel").channel_id == channel_id
	).with_for_update().one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	changes = request.model_dump(exclude_unset=True)
	if "category_id" in changes and changes["category_id"] is not None:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == changes["category_id"], VideoCategory.is_active.is_(True)
		).first():
			raise APIError(404, "video_category_not_found", "Video category not found")
	if "channel_title" in changes:
		channel.channel_title = changes["channel_title"]
	if "thumbnail_url" in changes:
		channel.thumbnail_url = safe_channel_thumbnail_url(changes["thumbnail_url"])
	if "age_min" in changes:
		channel.age_min = changes["age_min"]
	if "age_max" in changes:
		channel.age_max = changes["age_max"]
	if "language_code" in changes:
		channel.language_code = changes["language_code"].lower() if changes["language_code"] else None
	if "category_id" in changes:
		channel.category_id = changes["category_id"]
	if "rights_status" in changes and changes["rights_status"] is not None:
		channel.rights_status = changes["rights_status"]
	if "is_active" in changes and changes["is_active"] is not None:
		channel.is_active = changes["is_active"]
	if "notes" in changes:
		channel.notes = changes["notes"]
	channel.updated_at = _now()
	session.flush()
	record_audit(session, actor.id, "youtube.channel_updated", "youtube_trusted_channel", channel.id, {
		"channel_id": channel.channel_id, "fields": sorted(changes.keys()),
	})
	session.commit()
	session.refresh(channel)
	return channel


def list_channel_videos(
	session: Session,
	channel_id: str,
	*,
	limit: int = 50,
	offset: int = 0,
	status: str | None = None,
	video_format_filter: str | None = None,
	query: str | None = None,
) -> dict[str, Any]:
	_require_tables("YouTubeTrustedChannel", "YouTubeContentReview")
	_trusted_channel_or_404(session, channel_id)
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory") if has_model("VideoCategory") else None
	q = session.query(Review, Video).join(Video, Video.id == Review.video_id).filter(Review.channel_id == channel_id)
	if VideoCategory is not None:
		q = q.outerjoin(VideoCategory, VideoCategory.id == Video.category_id)
	if status:
		if status == "published":
			q = q.filter(Video.is_published.is_(True))
		elif status == "unpublished":
			q = q.filter(Video.is_published.is_(False))
		else:
			q = q.filter(Review.status == status)
	if video_format_filter == "short":
		q = q.filter(short_clause(Video))
	elif video_format_filter in {"long", "regular"}:
		q = q.filter(regular_clause(Video))
	if query:
		like = f"%{query.strip()}%"
		q = q.filter(or_(Video.title.ilike(like), Review.youtube_video_id.ilike(like)))
	total = q.with_entities(func.count(Review.id)).order_by(None).scalar() or 0
	rows = q.order_by(Review.discovered_at.desc(), Review.id.desc()).offset(offset).limit(limit).all()
	items = []
	for review, video in rows:
		category_name = None
		if video.category_id and VideoCategory is not None:
			category = session.get(VideoCategory, video.category_id)
			category_name = category.name if category else None
		items.append({
			"review_id": review.id,
			"video_id": video.id,
			"youtube_video_id": review.youtube_video_id,
			"title": video.title,
			"thumbnail_url": video.thumbnail_url,
			"duration_seconds": known_duration_or_none(video.video_source, video.duration_seconds),
			"video_format": video_format(video.video_source, video.duration_seconds),
			"discovery_topic": getattr(review, "discovery_topic", None),
			"category_id": video.category_id,
			"category_name": category_name,
			"age_min": video.age_min,
			"age_max": video.age_max,
			"review_status": review.status,
			"publication_status": "published" if video.is_published else review.status,
			"is_published": bool(video.is_published),
			"discovered_at": utc_aware(review.discovered_at) if review.discovered_at else None,
			"source_url": review.source_url,
			"channel_id": review.channel_id,
		})
	return {"items": items, "total": int(total), "limit": limit, "offset": offset}


def list_channel_discovery_runs(session: Session, channel_id: str, limit: int = 50) -> list[Any]:
	_trusted_channel_or_404(session, channel_id)
	if not has_model("YouTubeChannelDiscoveryRun"):
		return []
	Run = get_model("YouTubeChannelDiscoveryRun")
	return (
		session.query(Run)
		.filter(Run.channel_id == channel_id)
		.order_by(Run.started_at.desc(), Run.id.desc())
		.limit(limit)
		.all()
	)


def _discovery_run_values(channel_id: str, actor_id, trigger: str = "manual") -> dict[str, Any]:
	return {
		"channel_id": channel_id,
		"triggered_by": actor_id,
		"trigger": trigger,
		"status": "running",
		"started_at": datetime.now(timezone.utc),
		"scanned_videos": 0, "new_videos": 0, "duplicate_videos": 0, "shorts_count": 0, "long_videos_count": 0,
		"auto_approved_count": 0, "pending_review_count": 0, "quarantined_count": 0, "unavailable_count": 0, "error_count": 0,
	}


def _finalize_discovery_run(run, counts: dict[str, Any] | None, *, status: str = "completed", error_message: str | None = None) -> None:
	run.status = status
	run.completed_at = datetime.now(timezone.utc)
	if counts:
		run.scanned_videos = int(counts.get("scanned_videos", counts.get("created", 0) + counts.get("skipped_existing", 0)))
		run.new_videos = int(counts.get("created", 0))
		run.duplicate_videos = int(counts.get("skipped_existing", 0))
		run.shorts_count = int(counts.get("shorts_count", 0))
		run.long_videos_count = int(counts.get("long_videos_count", 0))
		run.auto_approved_count = int(counts.get("automatically_published", 0))
		run.pending_review_count = int(counts.get("pending_review", 0))
		run.quarantined_count = int(counts.get("quarantined", 0))
		run.unavailable_count = int(counts.get("unavailable", 0))
		run.error_count = int(counts.get("error_count", 0))
	run.error_message = error_message[:2000] if error_message else None


def discover_channel_more(session: Session, actor, client: YouTubeClient, channel_id: str, *, trigger: str = "manual") -> dict[str, Any]:
	"""Run channel-specific trusted discovery with overlap prevention and execution history."""
	channel = _trusted_channel_or_404(session, channel_id)
	if has_model("YouTubeChannelDiscoveryRun"):
		Run = get_model("YouTubeChannelDiscoveryRun")
		existing_running = session.query(Run.id).filter(Run.channel_id == channel_id, Run.status == "running").first()
		if existing_running:
			raise APIError(409, "youtube_channel_discovery_running", "A discovery run is already in progress for this channel")
		run = Run(**_discovery_run_values(channel_id, actor.id, trigger))
		session.add(run)
		session.flush()
	else:
		run = None
	try:
		counts = discover_trusted(session, actor, client, 50, channel_id=channel_id)
		counts.setdefault("scanned_videos", counts.get("created", 0) + counts.get("skipped_existing", 0))
		counts.setdefault("shorts_count", 0)
		counts.setdefault("long_videos_count", 0)
		counts.setdefault("error_count", 0)
		if run is not None:
			_finalize_discovery_run(run, counts, status="completed")
			session.add(run)
		session.commit()
		if run is not None:
			session.refresh(run)
	except YouTubeError as error:
		api_error = to_api_error(error)
		if run is not None:
			try:
				session.rollback()
				# Record failure in a fresh transaction; discovery_trusted already rolled back its work on YouTube errors.
				channel = _trusted_channel_or_404(session, channel_id)
				Run = get_model("YouTubeChannelDiscoveryRun")
				failed = Run(**_discovery_run_values(channel_id, actor.id, trigger))
				failed.status = "failed"
				failed.completed_at = datetime.now(timezone.utc)
				failed.error_count = 1
				failed.error_message = f"{api_error.code}: {api_error.message}"[:2000]
				session.add(failed)
				session.commit()
				run = failed
			except Exception:  # pragma: no cover - best effort
				session.rollback()
				run = None
		raise api_error from error
	except Exception as error:  # pragma: no cover - defensive
		if run is not None:
			try:
				session.rollback()
				Run = get_model("YouTubeChannelDiscoveryRun")
				failed = Run(**_discovery_run_values(channel_id, actor.id, trigger))
				failed.status = "failed"
				failed.completed_at = datetime.now(timezone.utc)
				failed.error_count = 1
				failed.error_message = str(error)[:2000]
				session.add(failed)
				session.commit()
				run = failed
			except Exception:
				session.rollback()
				run = None
		raise
	result = {
		"channel_id": channel_id,
		"channel_title": channel.channel_title if channel else None,
		**counts,
	}
	if run is not None:
		result.update({
			"id": run.id,
			"triggered_by": run.triggered_by,
			"trigger": run.trigger,
			"status": run.status,
			"started_at": utc_aware(run.started_at) if run.started_at else None,
			"completed_at": utc_aware(run.completed_at) if run.completed_at else None,
			"scanned_videos": run.scanned_videos,
			"new_videos": run.new_videos,
			"duplicate_videos": run.duplicate_videos,
			"shorts_count": run.shorts_count,
			"long_videos_count": run.long_videos_count,
			"auto_approved_count": run.auto_approved_count,
			"pending_review_count": run.pending_review_count,
			"quarantined_count": run.quarantined_count,
			"unavailable_count": run.unavailable_count,
			"error_count": run.error_count,
			"error_message": run.error_message,
		})
	return result


def list_reviews(
	session: Session,
	status: str | None,
	publication_source: str | None,
	is_published: bool | None,
	limit: int,
	offset: int,
) -> list[dict[str, Any]]:
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory")
	query = session.query(Review, Video, VideoCategory.name).join(Video, Video.id == Review.video_id).outerjoin(
		VideoCategory, VideoCategory.id == Video.category_id
	)
	if status:
		query = query.filter(Review.status == status)
	if publication_source:
		query = query.filter(Review.publication_source == publication_source)
	if is_published is not None:
		query = query.filter(Video.is_published.is_(is_published))
	rows = query.order_by(Review.discovered_at.desc(), Review.id).offset(offset).limit(limit).all()
	return [review_public(review, video, category_name) for review, video, category_name in rows]


def diagnostics(session: Session) -> dict[str, Any]:
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory")
	status_counts = dict(session.query(Review.status, func.count(Review.id)).group_by(Review.status).all())
	published_by_source = dict(
		session.query(Review.publication_source, func.count(Review.id))
		.join(Video, Video.id == Review.video_id)
		.filter(Video.is_published.is_(True), Review.status == "approved")
		.group_by(Review.publication_source)
		.all()
	)
	approved_by_source = dict(
		session.query(Review.publication_source, func.count(Review.id))
		.filter(Review.status == "approved")
		.group_by(Review.publication_source)
		.all()
	)
	fresh_after = utc_naive(datetime.now(timezone.utc) - timedelta(hours=settings.youtube_reverify_hours))
	oldest_verified = session.query(func.min(Review.last_verified_at)).filter(Review.status == "approved").scalar()
	# Approved videos not recently re-verified. Verification age no longer hides eligible feed videos.
	approved_stale = session.query(func.count(Review.id)).filter(
		Review.status == "approved",
		or_(Review.last_verified_at.is_(None), Review.last_verified_at < fresh_after),
	).scalar() or 0
	latest = None
	last_result: dict[str, int] = {}
	last_recheck = None
	last_recheck_failure = None
	if has_model("AuditLog"):
		_Audit = get_model("AuditLog")
		last_recheck = session.query(_Audit.created_at, _Audit.details).filter(
			_Audit.action == "youtube.recheck.completed"
		).order_by(_Audit.created_at.desc()).first()
		last_recheck_failure = session.query(_Audit.created_at, _Audit.details).filter(
			_Audit.action == "youtube.recheck.failed"
		).order_by(_Audit.created_at.desc()).first()
	if has_model("AuditLog"):
		AuditLog = get_model("AuditLog")
		latest = session.query(AuditLog.created_at, AuditLog.details).filter(
			AuditLog.action == "youtube.discovery.completed"
		).order_by(AuditLog.created_at.desc()).first()
		if latest:
			latest_time = latest[0]
			last_result = {
				str(key): int(value)
				for key, value in (latest[1] or {}).items()
				if isinstance(value, int)
			}
	age_band_clause = or_(*[
		and_(Video.age_min == age_min, Video.age_max == age_max)
		for age_min, age_max in YOUTUBE_AGE_RANGES
	])
	base = session.query(Review, Video).join(Video, Video.id == Review.video_id)
	pending_reasons: dict[str, int] = {}
	quarantine_reasons: dict[str, int] = {}
	publication_failure_reasons: dict[str, int] = {}
	active_category_ids = {
		row[0] for row in session.query(VideoCategory.id).filter(VideoCategory.is_active.is_(True)).all()
	}
	for review, video in base.filter(or_(
		Review.status.in_(["pending_review", "quarantined"]),
		and_(Review.status == "approved", Video.is_published.is_(False)),
	)).all():
		reasons = [f"screening:{flag}" for flag in (review.screening_flags or [])]
		if review.rights_status != "cleared":
			reasons.append(f"rights:{review.rights_status}")
		if review.made_for_kids is not True:
			reasons.append("made_for_kids_not_true")
		if (video.age_min, video.age_max) not in YOUTUBE_AGE_RANGES:
			reasons.append("unsupported_age_band")
		if review.status == "quarantined":
			for reason in reasons or ["no_screening_reason_recorded"]:
				quarantine_reasons[reason] = quarantine_reasons.get(reason, 0) + 1
		if review.status == "pending_review":
			for reason in [*reasons, "waiting_for_manual_review"]:
				pending_reasons[reason] = pending_reasons.get(reason, 0) + 1
		if review.status == "approved" and not video.is_published:
			publication_reasons = list(reasons)
			if video.content_rating not in {"general", "educational"}:
				publication_reasons.append("content_rating_not_publishable")
			if video.category_id is not None and video.category_id not in active_category_ids:
				publication_reasons.append("inactive_category")
			if video_format(video.video_source, video.duration_seconds) != "short":
				publication_reasons.append("not_a_short")
			for reason in publication_reasons or ["eligible_pending_youtube_revalidation"]:
				publication_failure_reasons[reason] = publication_failure_reasons.get(reason, 0) + 1
	eligible = base.outerjoin(VideoCategory, VideoCategory.id == Video.category_id).filter(
		Review.status == "approved",
		Review.rights_status == "cleared",
		Review.made_for_kids.is_(True),
		Review.screening_flags == [],
		Video.is_published.is_(False),
		Video.content_rating.in_(["general", "educational"]),
		age_band_clause,
		VideoCategory.id.is_(None) | VideoCategory.is_active.is_(True),
		Video.duration_seconds > 1,
		Video.duration_seconds <= 60,
	)
	published_shorts = base.outerjoin(VideoCategory, VideoCategory.id == Video.category_id).filter(
		Review.status == "approved",
		Review.rights_status == "cleared",
		Review.made_for_kids.is_(True),
		Review.screening_flags == [],
		Video.is_published.is_(True),
		Video.content_rating.in_(["general", "educational"]),
		age_band_clause,
		or_(VideoCategory.id.is_(None), VideoCategory.is_active.is_(True)),
		Video.duration_seconds > 1,
		Video.duration_seconds <= 60,
	)
	rights_not_cleared = base.filter(Review.rights_status != "cleared").count()
	safety_failed = base.filter(or_(Review.status == "quarantined", Review.screening_flags != [], Review.made_for_kids.is_not(True))).count()
	invalid_age_band = base.filter(~age_band_clause).count()
	format_counts = {"short": 0, "regular": 0, "unknown": 0}
	for source, duration, count in session.query(Video.video_source, Video.duration_seconds, func.count(Video.id)).join(
		Review, Review.video_id == Video.id
	).group_by(Video.video_source, Video.duration_seconds).all():
		format_counts[video_format(source, duration)] += count
	return {
		"total_video_records": session.query(Video.id).count(),
		"total_discovered": session.query(Review.id).count(),
		"automatically_published": published_by_source.get("automatic", 0),
		"manually_published": published_by_source.get("manual", 0),
		"approved_published": base.filter(Review.status == "approved", Video.is_published.is_(True)).count(),
		"approved_unpublished": base.filter(Review.status == "approved", Video.is_published.is_(False)).count(),
		"pending_review_unpublished": base.filter(Review.status == "pending_review", Video.is_published.is_(False)).count(),
		"pending_review": status_counts.get("pending_review", 0),
		"quarantined": status_counts.get("quarantined", 0),
		"rejected": status_counts.get("rejected", 0),
		"revoked": status_counts.get("revoked", 0),
		"unavailable": status_counts.get("unavailable", 0),
		"rights_not_cleared": rights_not_cleared,
		"safety_screening_failed": safety_failed,
		"blocked_by_rights_or_safety": base.filter(or_(Review.rights_status != "cleared", Review.screening_flags != [], Review.made_for_kids.is_not(True))).count(),
		"invalid_age_band": invalid_age_band,
		"eligible_approved_unpublished": eligible.count(),
		"published_shorts": published_shorts.count(),
		"quarantine_reasons": quarantine_reasons,
		"video_format_counts": format_counts,
		"last_discovery_run": utc_aware(latest[0]) if latest else None,
		"last_discovery_result": last_result,
		"publication_failure_reasons": {
			**{f"pending_review:{key}": value for key, value in pending_reasons.items()},
			**{f"approved_unpublished:{key}": value for key, value in publication_failure_reasons.items()},
		},
		"oldest_approved_verification": utc_aware(oldest_verified) if oldest_verified else None,
		"last_recheck_run": utc_aware(last_recheck[0]) if last_recheck else None,
		"last_recheck_result": {
			str(key): int(value) for key, value in (last_recheck[1] or {}).items() if isinstance(value, int)
		} if last_recheck else {},
		"last_recheck_failure": utc_aware(last_recheck_failure[0]) if last_recheck_failure else None,
		"last_recheck_failure_code": (last_recheck_failure[1] or {}).get("code") if last_recheck_failure else None,
		"approved_stale": approved_stale,
		"reverify_hours": settings.youtube_reverify_hours,
		"approved": status_counts.get("approved", 0),
		"approved_automatic": approved_by_source.get("automatic", 0),
		"approved_manual": approved_by_source.get("manual", 0),
		"published": base.filter(Video.is_published.is_(True)).count(),
		"configuration": {
			"database": bool(settings.database_url),
			"youtube_api": bool(settings.youtube_api_key),
			"auto_publish_non_trusted": settings.youtube_auto_publish_non_trusted,
			"discovery_actor": settings.youtube_discovery_actor_id is not None,
		},
	}


def publish_approved_unpublished(
	session: Session,
	actor,
	client: YouTubeClient,
	limit: int,
	after_id: UUID | None = None,
) -> dict[str, Any]:
	"""Revalidate and publish a clean short or regular candidate under the configured policy."""
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	query = session.query(Review, Video).join(Video, Video.id == Review.video_id).filter(
		Review.status == "approved", Video.is_published.is_(False)
	)
	if after_id is not None:
		query = query.filter(Review.id > after_id)
	rows = query.order_by(Review.id).limit(limit).with_for_update(skip_locked=True).all()
	counts: dict[str, int] = {}
	newly_published = 0
	try:
		items = client.videos([review.youtube_video_id for review, _ in rows], use_cache=False)
	except YouTubeError as error:
		session.rollback()
		raise to_api_error(error) from error
	for review, video in rows:
		blocked = False
		if review.rights_status != "cleared":
			counts["rights_not_cleared"] = counts.get("rights_not_cleared", 0) + 1
		item = items.get(review.youtube_video_id)
		if item is None:
			_mark_unavailable(session, actor.id, review, video, ["not_returned"])
			counts["unavailable"] = counts.get("unavailable", 0) + 1
			continue
		checked_status, flags = screen_candidate(item, settings.youtube_region_code)
		review.last_verified_at = _now()
		review.made_for_kids = (item.get("status") or {}).get("madeForKids")
		review.screening_flags = flags
		if checked_status == "unavailable":
			_mark_unavailable(session, actor.id, review, video, flags)
			counts["unavailable"] = counts.get("unavailable", 0) + 1
			continue
		if checked_status == "quarantined":
			_move(session, actor.id, review, video, "quarantined", {"revalidation_flags": flags})
			for flag in flags:
				key = f"screening:{flag}"
				counts[key] = counts.get(key, 0) + 1
			continue
		if flags:
			for flag in flags:
				key = f"screening:{flag}"
				counts[key] = counts.get(key, 0) + 1
			continue
		if review.rights_status != "cleared":
			blocked = True
		if (video.age_min, video.age_max) not in YOUTUBE_AGE_RANGES:
			counts["unsupported_age_band"] = counts.get("unsupported_age_band", 0) + 1
			blocked = True
		if video.content_rating not in {"general", "educational"}:
			counts["content_rating_not_publishable"] = counts.get("content_rating_not_publishable", 0) + 1
			blocked = True
		if video.category_id is not None:
			VideoCategory = get_model("VideoCategory")
			if not session.query(VideoCategory.id).filter(
				VideoCategory.id == video.category_id, VideoCategory.is_active.is_(True)
			).first():
				counts["inactive_category"] = counts.get("inactive_category", 0) + 1
				blocked = True
		duration = parse_iso8601_duration((item.get("contentDetails") or {}).get("duration"))
		if duration is None:
			counts["duration_unknown"] = counts.get("duration_unknown", 0) + 1
			blocked = True
		else:
			video.duration_seconds = duration
			if video_format(video.video_source, duration) != "short":
				counts["not_a_short"] = counts.get("not_a_short", 0) + 1
				blocked = True
		if blocked:
			continue
		if review.rights_status != "cleared":
			continue
		from app.services.video_service import publish_approved_youtube_video
		publish_approved_youtube_video(
			session,
			actor,
			review,
			video,
			"batch republished after fresh YouTube and eligibility checks",
		)
		newly_published += 1
	if rows:
		record_audit(
			session,
			actor.id,
			"youtube.approved_publish_batch",
			"youtube_pipeline",
			None,
			{"checked": len(rows), "newly_published": newly_published, "blocked_by_reason": counts},
		)
	last_id = rows[-1][0].id if rows else after_id
	remaining_query = session.query(Review.id).join(Video, Video.id == Review.video_id).filter(
		Review.status == "approved", Video.is_published.is_(False)
	)
	approved_unpublished_remaining = remaining_query.count()
	has_more = bool(last_id and remaining_query.filter(Review.id > last_id).first())
	session.commit()
	return {
		"checked": len(rows),
		"newly_published": newly_published,
		"blocked_by_reason": counts,
		"approved_unpublished_remaining": approved_unpublished_remaining,
		"next_after_id": last_id if has_more else None,
		"complete": not has_more,
	}


def auto_review(
	session: Session,
	actor,
	client: YouTubeClient,
	limit: int = 50,
	include_quarantined: bool = True,
) -> dict[str, Any]:
	"""Re-verify waiting candidates with YouTube and approve the ones that qualify.

	Never touches approved, rejected, revoked or administrator-quarantined rows,
	and never touches a quarantine caused by a user report. Quarantines raised by
	automated screening are re-screened against fresh metadata: they leave
	quarantine only if every screening rule now passes, and are then judged by the
	same rules as any other pending video. A YouTube error leaves every row as it
	was, so it can be retried later. Re-running is harmless: once approved a row is
	no longer selected.
	"""
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	rows = (
		session.query(Review, Video)
		.join(Video, Video.id == Review.video_id)
		.filter(Review.status == "pending_review")
		.order_by(Review.last_verified_at.asc().nullsfirst(), Review.id)
		.limit(limit)
		.with_for_update(skip_locked=True)
		.all()
	)
	if include_quarantined and len(rows) < limit:
		quarantined = (
			session.query(Review, Video)
			.join(Video, Video.id == Review.video_id)
			.filter(
				Review.status == "quarantined",
				Review.reviewed_by.is_(None),
				Review.screening_flags != [],
			)
		)
		if has_model("ContentReport"):
			Report = get_model("ContentReport")
			quarantined = quarantined.filter(
				~exists().where(Report.video_id == Review.video_id, Report.status == "open")
			)
		rows += (
			quarantined.order_by(Review.last_verified_at.asc().nullsfirst(), Review.id)
			.limit(limit - len(rows))
			.with_for_update(skip_locked=True)
			.all()
		)
	counts: dict[str, Any] = {
		"checked": 0,
		"auto_approved": 0,
		"needs_manual_review": 0,
		"newly_quarantined": 0,
		"still_quarantined": 0,
		"returned_to_pending": 0,
		"unavailable": 0,
		"retry_later": 0,
		"error": None,
		"blocked_reasons": {},
		"quarantine_reasons": {},
	}

	def tally(bucket: str, reason: str) -> None:
		counts[bucket][reason] = counts[bucket].get(reason, 0) + 1

	for start in range(0, len(rows), 50):
		batch = rows[start:start + 50]
		try:
			found = client.videos([review.youtube_video_id for review, _ in batch], use_cache=False)
		except YouTubeError as error:
			# Nothing in this or later batches was judged; leave it all untouched.
			counts["error"] = to_api_error(error).code
			counts["retry_later"] += len(rows) - start
			break
		for review, video in batch:
			counts["checked"] += 1
			item = found.get(review.youtube_video_id)
			if item is None:
				_mark_unavailable(session, actor.id, review, video, ["not_returned"])
				counts["unavailable"] += 1
				continue
			status, flags = screen_candidate(item, settings.youtube_region_code)
			review.last_verified_at = _now()
			review.made_for_kids = (item.get("status") or {}).get("madeForKids")
			if status == "unavailable":
				_mark_unavailable(session, actor.id, review, video, flags)
				counts["unavailable"] += 1
				continue
			old_flags = list(review.screening_flags or [])
			review.screening_flags = flags
			if status == "quarantined":
				if review.status == "pending_review":
					_move(session, actor.id, review, video, "quarantined", {"auto_review_flags": flags})
					counts["newly_quarantined"] += 1
				else:
					counts["still_quarantined"] += 1
				for flag in flags:
					tally("quarantine_reasons", flag)
				continue
			snippet = item.get("snippet") or {}
			video.title = (str(snippet.get("title") or video.title).strip() or video.title)[:200]
			video.thumbnail_url = safe_thumbnail_url(snippet)
			duration = parse_iso8601_duration((item.get("contentDetails") or {}).get("duration"))
			if duration:
				video.duration_seconds = min(duration, 86400)
			if review.status == "quarantined":
				_move(session, actor.id, review, video, "pending_review", {"auto_review_cleared_flags": old_flags})
				counts["returned_to_pending"] += 1
			if flags:
				_note_waiting(review, "screening_flags")
				for flag in flags:
					tally("blocked_reasons", f"screening:{flag}")
				counts["needs_manual_review"] += 1
				continue
			approved, blocker = _try_auto_approve(session, actor, review, video)
			if approved:
				counts["auto_approved"] += 1
			else:
				_note_waiting(review, blocker or "not_published")
				tally("blocked_reasons", blocker or "not_published")
				counts["needs_manual_review"] += 1
	if rows:
		record_audit(
			session,
			actor.id,
			"youtube.auto_review.completed",
			"youtube_pipeline",
			None,
			{key: value for key, value in counts.items() if isinstance(value, int)},
		)
	session.commit()
	return counts


def reevaluate_quarantined(session: Session, actor: Any, client: YouTubeClient, review_id: UUID) -> dict[str, Any]:
	review, video = _locked(session, review_id)
	if review.status != "quarantined":
		raise APIError(409, "youtube_not_quarantined", "Only quarantined videos can be re-evaluated")
	try:
		item = client.videos([review.youtube_video_id], use_cache=False).get(review.youtube_video_id)
	except YouTubeError as error:
		raise to_api_error(error) from error
	old_flags = list(review.screening_flags or [])
	status, flags = screen_candidate(item, settings.youtube_region_code) if item else ("unavailable", ["not_returned"])
	review.screening_flags = flags
	review.made_for_kids = (item.get("status") or {}).get("madeForKids") if item else None
	review.last_verified_at = _now()
	if status == "unavailable":
		_mark_unavailable(session, actor.id, review, video, flags)
	elif status == "pending_review" and not flags:
		_move(session, actor.id, review, video, "pending_review", {"resolved_quarantine_flags": old_flags})
	else:
		review.updated_at = _now()
		record_audit(
			session,
			actor.id,
			"youtube.quarantine.reevaluated",
			"video",
			video.id,
			{"old_flags": old_flags, "current_flags": flags},
		)
	session.commit()
	return review_public(review, video)


def _locked(session: Session, review_id: UUID):
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	review = session.query(Review).filter(Review.id == review_id).with_for_update().one_or_none()
	if review is None:
		raise APIError(404, "youtube_review_not_found", "Review not found")
	video = session.query(Video).filter(Video.id == review.video_id).with_for_update().one()
	return review, video


def _withdraw(video) -> None:
	video.is_published = False
	video.published_at = None
	video.content_rating = "parent_review_required"


def _move(session: Session, actor_id: UUID | None, review, video, target: str, details: dict | None = None) -> None:
	if not can_transition(review.status, target):
		raise APIError(409, "invalid_review_transition", f"Cannot move a {review.status} video to {target}")
	previous = review.status
	review.status = target
	review.updated_at = _now()
	if target != "approved":
		_withdraw(video)
	record_audit(
		session,
		actor_id,
		f"youtube.{target}",
		"video",
		video.id,
		{"from": previous, "youtube_video_id": review.youtube_video_id, **(details or {})},
	)


def _mark_unavailable(session: Session, actor_id, review, video, flags: list[str]) -> None:
	if review.status == "unavailable":
		_withdraw(video)
		return
	review.screening_flags = flags
	_move(session, actor_id, review, video, "unavailable", {"flags": flags})


def approve(session: Session, actor, client: YouTubeClient, review_id: UUID, request: YouTubeApproveRequest) -> dict[str, Any]:
	review, video = _locked(session, review_id)
	if review.status == "quarantined":
		raise APIError(409, "youtube_re_evaluation_required", "Re-evaluate and clear the quarantine before approval")
	if review.status != "pending_review":
		raise APIError(409, "invalid_review_transition", f"Cannot approve a {review.status} video")
	if not can_transition(review.status, "approved"):
		raise APIError(409, "invalid_review_transition", f"Cannot approve a {review.status} video")
	try:
		item = client.videos([review.youtube_video_id], use_cache=False).get(review.youtube_video_id)
	except YouTubeError as error:
		raise to_api_error(error) from error
	status, flags = screen_candidate(item, settings.youtube_region_code) if item else ("unavailable", ["not_returned"])
	if status == "unavailable":
		_mark_unavailable(session, actor.id, review, video, flags)
		session.commit()
		raise APIError(409, "youtube_video_unavailable", "This video can no longer be played in the official player")
	if (item.get("status") or {}).get("madeForKids") is not True:
		raise APIError(409, "not_made_for_kids", "Only videos YouTube marks as made for kids can be shown to children")
	if "age_restricted" in flags:
		raise APIError(409, "age_restricted", "Age-restricted videos cannot be approved")
	if status == "quarantined" or flags:
		review.screening_flags = flags
		if status == "quarantined":
			_move(session, actor.id, review, video, "quarantined", {"flags": flags})
			session.commit()
		raise APIError(409, "youtube_screening_failed", "Resolve screening flags before approving this video")
	category_id = request.category_id if request.category_id is not None else video.category_id
	if category_id:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == category_id, VideoCategory.is_active.is_(True)
		).first():
			raise APIError(404, "video_category_not_found", "Video category not found")
	snippet = item.get("snippet") or {}
	now = _now()
	video.title = (str(snippet.get("title") or video.title).strip() or video.title)[:200]
	video.thumbnail_url = safe_thumbnail_url(snippet)
	video.duration_seconds = min(parse_iso8601_duration((item.get("contentDetails") or {}).get("duration")) or video.duration_seconds, 86400)
	video.age_min = request.age_min
	video.age_max = request.age_max
	video.language_code = request.language_code.lower()
	video.category_id = category_id
	video.content_rating = "educational"
	review.made_for_kids = True
	review.screening_flags = flags
	review.rights_status = request.rights_status
	review.reviewed_by = actor.id
	review.reviewed_at = now
	review.review_notes = request.notes
	review.last_verified_at = now
	review.revoked_reason = None
	review.revoked_at = None
	if hasattr(review, "publication_source"):
		review.publication_source = "manual"
		review.publication_reason = "administrator approval"
	_move(session, actor.id, review, video, "approved", {"age": [request.age_min, request.age_max], "language": video.language_code})
	from app.services.video_service import publish_approved_youtube_video
	publish_approved_youtube_video(session, actor, review, video, "administrator approval after fresh YouTube checks")
	session.commit()
	return review_public(review, video)


def decide(session: Session, actor, review_id: UUID, target: str, notes: str | None) -> dict[str, Any]:
	"""Reject, quarantine or reopen (back to pending_review). Unpublishes immediately."""
	if target not in {"rejected", "quarantined", "pending_review"}:
		raise APIError(422, "invalid_review_transition", "Unsupported decision")
	if target == "rejected" and not (notes or "").strip():
		raise APIError(422, "review_notes_required", "A reason is required when rejecting a video")
	review, video = _locked(session, review_id)
	review.reviewed_by = actor.id
	review.reviewed_at = _now()
	review.review_notes = notes
	if target == "pending_review":
		review.rights_status = "unreviewed"
	_move(session, actor.id, review, video, target)
	session.commit()
	return review_public(review, video)


def revoke(session: Session, actor, review_id: UUID, reason: str) -> dict[str, Any]:
	review, video = _locked(session, review_id)
	now = _now()
	review.revoked_reason = reason.strip()
	review.revoked_at = now
	review.reviewed_by = actor.id
	review.reviewed_at = now
	_move(session, actor.id, review, video, "revoked", {"reason": review.revoked_reason})
	session.commit()
	return review_public(review, video)


def recheck(session: Session, client: YouTubeClient, limit: int, actor_id: UUID | None = None) -> dict[str, int]:
	"""Re-verify approved (and unavailable) videos, oldest verification first.

	Approved videos that disappeared or changed are withdrawn at once; videos that
	came back go to ``pending_review``, never straight back to approved.
	"""
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	reviews = (
		session.query(Review)
		.filter(Review.status.in_(["approved", "unavailable"]))
		# Approved videos first: an unavailable video that is still unavailable keeps its old timestamp, so by
		# age alone it would stay at the front and could starve approved ones of their re-verification.
		.order_by(case((Review.status == "approved", 0), else_=1), Review.last_verified_at.asc().nullsfirst(), Review.id)
		.limit(limit)
		.with_for_update(skip_locked=True)
		.all()
	)
	counts = {"checked": 0, "verified": 0, "quarantined": 0, "unavailable": 0, "returned_to_review": 0}
	for start in range(0, len(reviews), 50):
		batch = reviews[start:start + 50]
		try:
			found = client.videos([review.youtube_video_id for review in batch], use_cache=False)
		except YouTubeError as error:
			session.commit()
			raise to_api_error(error) from error
		videos = {video.id: video for video in session.query(Video).filter(Video.id.in_([r.video_id for r in batch])).all()}
		for review in batch:
			video = videos[review.video_id]
			item = found.get(review.youtube_video_id)
			status, flags = screen_candidate(item, settings.youtube_region_code) if item else ("unavailable", ["not_returned"])
			review.last_verified_at = _now()
			if status == "unavailable":
				_mark_unavailable(session, actor_id, review, video, flags)
				counts["unavailable"] += 1
				continue
			if status == "quarantined":
				_move(session, actor_id, review, video, "quarantined", {"recheck_flags": flags})
				counts["quarantined"] += 1
				continue
			review.status = "approved"
			video.is_published = True
			video.published_at = _now()
			review.rights_status = "cleared"
			review.last_verified_at = _now()
			review.publication_source = "manual"
			review.publication_reason = "revalidation success"
			record_audit(
				session,
				actor_id,
				"youtube.revalidated",
				"video",
				video.id,
				{"youtube_video_id": review.youtube_video_id},
			)
			counts["verified"] += 1
	session.commit()
	return counts
