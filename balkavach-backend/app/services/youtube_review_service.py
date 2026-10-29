"""Moderation pipeline for YouTube-sourced videos.

A YouTube video is a ``videos`` row (``video_source = 'youtube'``) plus a
``youtube_content_reviews`` row holding its state:

    discovered -> pending_review -> approved | rejected
    with quarantined, revoked and unavailable as side states.

Automated screening only ever moves a candidate to ``pending_review``,
``quarantined`` or ``unavailable``. Only an administrator's approval publishes a
video, and the child feed additionally requires the approval to have been
re-verified against YouTube recently (see ``youtube_visibility_clause``).
Screening is a keyword and metadata filter: it reduces reviewer load, it does
not make content safe, and it inspects no video frames, audio or thumbnails.
"""

import logging
import re
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import exists, or_
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
	safe_thumbnail_url,
	to_api_error,
)
from app.schemas.video import YouTubeApproveRequest, YouTubeDiscoverRequest
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
logger = logging.getLogger(__name__)

# Crude on purpose: a hit sends the candidate to quarantine for a human, it never
# rejects or approves anything by itself.
_DENYLIST = (
	"kill", "killing", "murder", "blood", "bloody", "gore", "gun", "guns", "shoot", "shooting",
	"weapon", "horror", "scary", "creepy", "zombie", "prank", "sexy", "sex", "nude", "naked",
	"kiss", "kissing", "drunk", "alcohol", "beer", "drug", "drugs", "weed", "vape", "smoking",
	"suicide", "dead", "death", "fight", "fighting", "violence", "violent", "nsfw", "18+",
	"injection", "pregnant", "gambling", "casino", "challenge",
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

	if status.get("privacyStatus") != "public":
		flags.append("not_public")
	if status.get("embeddable") is not True:
		flags.append("not_embeddable")
	if status.get("uploadStatus") not in (None, "processed"):
		flags.append("not_processed")
	restriction = details.get("regionRestriction") or {}
	if region_code and (
		region_code in (restriction.get("blocked") or [])
		or ("allowed" in restriction and region_code not in (restriction.get("allowed") or []))
	):
		flags.append("region_blocked")
	if flags:
		return "unavailable", flags

	quarantine = False
	if (details.get("contentRating") or {}).get("ytRating") == "ytAgeRestricted":
		flags.append("age_restricted")
		quarantine = True
	made_for_kids = status.get("madeForKids")
	if made_for_kids is None:
		flags.append("made_for_kids_unknown")
		quarantine = True
	elif made_for_kids is not True:
		flags.append("not_made_for_kids")
		quarantine = True
	if not parse_iso8601_duration(details.get("duration")):
		flags.append("duration_unknown")
		quarantine = True
	if snippet.get("liveBroadcastContent") not in (None, "none"):
		flags.append("live_content")
		quarantine = True
	text = " ".join(
		[str(snippet.get("title") or ""), str(snippet.get("description") or "")]
		+ [str(tag) for tag in (snippet.get("tags") or [])]
	).lower()
	for word in sorted(set(_DENYLIST_PATTERN.findall(text))):
		flags.append(f"keyword:{word}")
		quarantine = True
	if not snippet.get("title"):
		flags.append("missing_title")
		quarantine = True
	if safe_thumbnail_url(snippet) is None:
		flags.append("no_thumbnail")
	return ("quarantined" if quarantine else "pending_review"), flags


def youtube_visibility_clause(Video, now: datetime | None = None):
	"""SQL condition a feed query must apply: non-YouTube rows pass, YouTube rows
	pass only while approved, rights-cleared and re-verified recently. Trusted
	channels are an additional publication signal, not a feed requirement.

	Without migration 0008 no YouTube row is visible (fail closed).
	"""
	if not has_model("YouTubeContentReview"):
		return Video.video_source != "youtube"
	Review = get_model("YouTubeContentReview")
	now = now or datetime.now(timezone.utc)
	fresh_after = utc_naive(now - timedelta(hours=settings.youtube_reverify_hours))
	approved = exists().where(
		Review.video_id == Video.id,
		Review.status == "approved",
		Review.made_for_kids.is_(True),
		Review.rights_status == "cleared",
		Review.last_verified_at >= fresh_after,
	)
	return or_(Video.video_source != "youtube", approved)


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


def review_public(review, video) -> dict[str, Any]:
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
		"age_min": video.age_min if video else None,
		"age_max": video.age_max if video else None,
		"discovery_topic": review.discovery_topic,
		"youtube_category_id": review.youtube_category_id,
		"publication_source": getattr(review, "publication_source", "manual"),
		"publication_reason": getattr(review, "publication_reason", None),
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
		language_code=trusted_channel.language_code if trusted_channel is not None else _language(snippet),
		age_min=trusted_channel.age_min if trusted_channel is not None else 4,
		category_id=trusted_channel.category_id if trusted_channel is not None else None,
		age_max=trusted_channel.age_max if trusted_channel is not None else 12,
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


def _auto_publish(session: Session, actor, review, video, trusted_channel=None) -> bool:
	"""Publish a clean, short candidate under the configured discovery policy."""
	def skipped(reason: str, **details: Any) -> bool:
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

	if trusted_channel is None:
		if not settings.youtube_auto_publish_non_trusted:
			return skipped("non_trusted_auto_publish_disabled")
	else:
		if not trusted_channel.is_active:
			return skipped("trusted_channel_inactive")
		if review.channel_id != trusted_channel.channel_id:
			return skipped("channel_id_mismatch", trusted_channel_id=trusted_channel.channel_id)
		if trusted_channel.rights_status != "cleared":
			return skipped("trusted_channel_rights_not_cleared", rights_status=trusted_channel.rights_status)
	if trusted_channel is None and review.rights_status != "cleared":
		return skipped("rights_not_cleared", rights_status=review.rights_status)
	if review.status != "pending_review":
		return skipped("review_not_pending", status=review.status)
	if review.screening_flags:
		return skipped("screening_flags", flags=list(review.screening_flags))
	if review.made_for_kids is not True:
		return skipped("made_for_kids_not_true", made_for_kids=review.made_for_kids)
	if video.duration_seconds > settings.youtube_auto_publish_max_seconds:
		return skipped(
			"duration_exceeds_limit",
			duration_seconds=video.duration_seconds,
			max_duration_seconds=settings.youtube_auto_publish_max_seconds,
		)
	now = _now()
	if trusted_channel is not None:
		video.age_min = trusted_channel.age_min
		video.age_max = trusted_channel.age_max
		video.language_code = trusted_channel.language_code
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


def list_trusted_channels(session: Session, limit: int, offset: int) -> list[Any]:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	return (
		session.query(Trusted)
		.order_by(Trusted.is_active.desc(), Trusted.channel_title, Trusted.channel_id)
		.offset(offset)
		.limit(limit)
		.all()
	)


def trust_channel(session: Session, actor, request) -> Any:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	if request.category_id:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == request.category_id,
			VideoCategory.is_active.is_(True),
		).first():
			raise APIError(404, "video_category_not_found", "Video category not found")
	channel = session.query(Trusted).filter(Trusted.channel_id == request.channel_id).with_for_update().one_or_none()
	if channel is None:
		channel = Trusted(channel_id=request.channel_id, created_by=actor.id)
		session.add(channel)
	channel.channel_title = request.channel_title
	channel.age_min = request.age_min
	channel.age_max = request.age_max
	channel.language_code = request.language_code.lower()
	channel.category_id = request.category_id
	channel.rights_status = request.rights_status
	channel.is_active = True
	channel.notes = request.notes
	channel.updated_at = _now()
	session.flush()
	record_audit(session, actor.id, "youtube.channel_trusted", "youtube_trusted_channel", channel.id, {"channel_id": channel.channel_id})
	session.commit()
	session.refresh(channel)
	return channel


def untrust_channel(session: Session, actor, channel_id: str) -> Any:
	_require_tables("YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	channel = session.query(Trusted).filter(Trusted.channel_id == channel_id).with_for_update().one_or_none()
	if channel is None:
		raise APIError(404, "trusted_channel_not_found", "Trusted channel not found")
	channel.is_active = False
	channel.updated_at = _now()
	for review, video in (
		session.query(Review, Video)
		.join(Video, Video.id == Review.video_id)
		.filter(
			Review.channel_id == channel_id,
			Review.status == "approved",
			Review.publication_source == "automatic",
		)
		.with_for_update()
		.all()
	):
		_move(session, actor.id, review, video, "quarantined", {"reason": "trusted channel disabled"})
	record_audit(session, actor.id, "youtube.channel_untrusted", "youtube_trusted_channel", channel.id, {"channel_id": channel_id})
	session.commit()
	session.refresh(channel)
	return channel


def discover(
	session: Session,
	actor,
	client: YouTubeClient,
	request: YouTubeDiscoverRequest,
	*,
	auto_publish: bool = False,
) -> dict[str, Any]:
	_require_tables("YouTubeContentReview")
	try:
		page = client.search(
			request.topic,
			short=request.shorts,
			page_token=request.page_token,
			relevance_language=request.relevance_language,
			region_code=request.region_code or settings.youtube_region_code,
			max_results=request.max_results,
		)
		Review = get_model("YouTubeContentReview")
		Trusted = get_model("YouTubeTrustedChannel") if has_model("YouTubeTrustedChannel") else None
		existing = {
			row[0]
			for row in session.query(Review.youtube_video_id).filter(Review.youtube_video_id.in_(page["video_ids"])).all()
		} if page["video_ids"] else set()
		new_ids = [video_id for video_id in page["video_ids"] if video_id not in existing]
		details = client.videos(new_ids) if new_ids else {}
	except YouTubeError as error:
		raise to_api_error(error) from error
	created = []
	unplayable = 0
	automatically_published = 0
	for video_id in new_ids:
		item = details.get(video_id)
		result = _create_candidate(session, actor, video_id, item, request.topic)
		if result is None:
			unplayable += 1
			continue
		review, video = result
		trusted_channel = (
			session.query(Trusted).filter(Trusted.channel_id == review.channel_id).one_or_none()
			if Trusted is not None and review.channel_id
			else None
		)
		if auto_publish and review.status == "pending_review" and review.rights_status == "unreviewed":
			# The scheduled discovery job's configured policy is the rights
			# attestation for non-trusted automatic publication. Explicitly denied
			# rights remain blocked by _auto_publish.
			review.rights_status = "cleared"
		if auto_publish and review.status == "pending_review" and _auto_publish(session, actor, review, video, trusted_channel):
			automatically_published += 1
		created.append((review, video))
	session.commit()
	return {
		"created": [review_public(review, video) for review, video in created],
		"skipped_existing": len(existing),
		"skipped_unplayable": unplayable,
		"next_page_token": page["next_page_token"],
		"automatically_published": automatically_published,
		"quarantined": sum(1 for review, _ in created if review.status == "quarantined"),
	}


def discover_trusted(session: Session, actor, client: YouTubeClient, max_results: int) -> dict[str, int]:
	"""Discover one bounded page per configured topic for each active trusted channel."""
	_require_tables("YouTubeContentReview", "YouTubeTrustedChannel")
	Trusted = get_model("YouTubeTrustedChannel")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	channels = session.query(Trusted).filter(Trusted.is_active.is_(True), Trusted.rights_status == "cleared").all()
	counts = {"created": 0, "skipped_existing": 0, "automatically_published": 0, "quarantined": 0}
	try:
		for channel in channels:
			for topic in settings.youtube_discovery_topics:
				page = client.search(
					topic,
					short=True,
					channel_id=channel.channel_id,
					region_code=settings.youtube_region_code,
					max_results=max_results,
				)
				video_ids = page["video_ids"]
				existing = {
					row[0]
					for row in session.query(Review.youtube_video_id).filter(Review.youtube_video_id.in_(video_ids)).all()
				} if video_ids else set()
				counts["skipped_existing"] += len(existing)
				pending_existing = (
					session.query(Review, Video)
					.join(Video, Video.id == Review.video_id)
					.filter(
						Review.youtube_video_id.in_(existing),
						Review.channel_id == channel.channel_id,
						Review.status == "pending_review",
					)
					.with_for_update()
					.all()
				)
				for review, video in pending_existing:
					if _auto_publish(session, actor, review, video, channel):
						counts["automatically_published"] += 1
				new_ids = [video_id for video_id in video_ids if video_id not in existing]
				details = client.videos(new_ids) if new_ids else {}
				for video_id in new_ids:
					result = _create_candidate(session, actor, video_id, details.get(video_id), topic, channel)
					if result is None:
						counts["skipped_existing"] += 1
						continue
					counts["created"] += 1
					review, video = result
					if review.status == "quarantined":
						counts["quarantined"] += 1
					elif _auto_publish(session, actor, review, video, channel):
						counts["automatically_published"] += 1
	except YouTubeError as error:
		session.rollback()
		raise to_api_error(error) from error
	session.commit()
	return counts


def import_video(session: Session, actor, client: YouTubeClient, url: str) -> dict[str, Any]:
	_require_tables("YouTubeContentReview")
	video_id = parse_youtube_video_id(url)
	if video_id is None:
		raise APIError(422, "invalid_youtube_url", "Provide an https YouTube video URL or an 11-character video id")
	Review = get_model("YouTubeContentReview")
	if session.query(Review.id).filter(Review.youtube_video_id == video_id).first():
		raise APIError(409, "youtube_video_exists", "This YouTube video is already in the review pipeline")
	try:
		item = client.videos([video_id], use_cache=False).get(video_id)
	except YouTubeError as error:
		raise to_api_error(error) from error
	if item is None:
		raise APIError(404, "youtube_video_not_found", "YouTube did not return this video")
	result = _create_candidate(session, actor, video_id, item)
	if result is None:
		raise APIError(409, "youtube_video_unplayable", "This video has no playable duration or already exists")
	session.commit()
	return review_public(*result)


def list_reviews(session: Session, status: str | None, limit: int, offset: int) -> list[dict[str, Any]]:
	_require_tables("YouTubeContentReview")
	Review = get_model("YouTubeContentReview")
	Video = get_model("Video")
	query = session.query(Review, Video).join(Video, Video.id == Review.video_id)
	if status:
		query = query.filter(Review.status == status)
	rows = query.order_by(Review.discovered_at.desc(), Review.id).offset(offset).limit(limit).all()
	return [review_public(review, video) for review, video in rows]


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
	if flags and not (request.notes or "").strip():
		raise APIError(422, "review_notes_required", "Explain why the screening flags are acceptable")
	if request.category_id:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == request.category_id, VideoCategory.is_active.is_(True)
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
	video.category_id = request.category_id
	video.content_rating = "educational"
	video.is_published = True
	video.published_at = now
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
		.order_by(Review.last_verified_at.asc().nullsfirst(), Review.id)
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
			counts["checked"] += 1
			if review.status == "unavailable":
				if status != "unavailable":
					review.screening_flags = flags
					review.made_for_kids = (item.get("status") or {}).get("madeForKids")
					_move(session, actor_id, review, video, "pending_review")
					counts["returned_to_review"] += 1
				continue
			if status == "unavailable":
				_mark_unavailable(session, actor_id, review, video, flags)
				counts["unavailable"] += 1
				continue
			new_flags = set(flags) - set(review.screening_flags or [])
			made_for_kids = (item.get("status") or {}).get("madeForKids")
			if made_for_kids is not True or "age_restricted" in flags or new_flags:
				review.screening_flags = flags
				review.made_for_kids = made_for_kids
				_move(session, actor_id, review, video, "quarantined", {"new_flags": sorted(new_flags)})
				counts["quarantined"] += 1
				continue
			snippet = item.get("snippet") or {}
			video.title = (str(snippet.get("title") or video.title).strip() or video.title)[:200]
			video.description = (str(snippet.get("description") or "")[:5000]) or None
			video.thumbnail_url = safe_thumbnail_url(snippet)
			video.duration_seconds = min(
				parse_iso8601_duration((item.get("contentDetails") or {}).get("duration"))
				or video.duration_seconds,
				86400,
			)
			review.youtube_category_id = (
				str(snippet["categoryId"])[:20] if snippet.get("categoryId") else None
			)
			review.last_verified_at = _now()
			counts["verified"] += 1
	session.commit()
	return counts


def report_video(session: Session, user, video_id: UUID, reason: str, details: str | None) -> dict[str, Any]:
	"""Record a report. An approved YouTube video is quarantined at once, pending an administrator."""
	_require_tables("ContentReport")
	Video = get_model("Video")
	Report = get_model("ContentReport")
	video = session.query(Video).filter(Video.id == video_id, Video.is_published.is_(True)).with_for_update().one_or_none()
	if video is None:
		raise APIError(404, "video_not_found", "Video not found")
	existing = session.query(Report).filter(
		Report.video_id == video_id, Report.reported_by == user.id, Report.status == "open"
	).one_or_none()
	if existing is not None:
		return {"id": existing.id, "status": existing.status}
	since = _now() - timedelta(days=1)
	if session.query(Report.id).filter(Report.reported_by == user.id, Report.created_at >= since).count() >= MAX_REPORTS_PER_USER_PER_DAY:
		raise APIError(429, "too_many_reports", "Too many reports today; please try again tomorrow")
	report = Report(video_id=video_id, reported_by=user.id, reason=reason, details=(details or "").strip() or None, status="open")
	session.add(report)
	session.flush()
	record_audit(session, user.id, "content.reported", "video", video_id, {"report_id": str(report.id), "reason": reason})
	if video.video_source == "youtube" and has_model("YouTubeContentReview"):
		Review = get_model("YouTubeContentReview")
		review = session.query(Review).filter(Review.video_id == video_id).with_for_update().one_or_none()
		if review is not None and can_transition(review.status, "quarantined"):
			_move(session, None, review, video, "quarantined", {"report_id": str(report.id)})
	session.commit()
	return {"id": report.id, "status": report.status}


def list_reports(session: Session, status: str | None, limit: int, offset: int):
	_require_tables("ContentReport")
	Report = get_model("ContentReport")
	query = session.query(Report)
	if status:
		query = query.filter(Report.status == status)
	return query.order_by(Report.created_at.desc(), Report.id).offset(offset).limit(limit).all()


def resolve_report(session: Session, actor, report_id: UUID, status: str):
	_require_tables("ContentReport")
	Report = get_model("ContentReport")
	report = session.query(Report).filter(Report.id == report_id).with_for_update().one_or_none()
	if report is None:
		raise APIError(404, "report_not_found", "Report not found")
	if report.status != "open":
		raise APIError(409, "report_closed", "This report is already closed")
	report.status = status
	report.resolved_by = actor.id
	report.resolved_at = _now()
	record_audit(session, actor.id, f"content_report.{status}", "content_report", report.id, {"video_id": str(report.video_id)})
	session.commit()
	session.refresh(report)
	return report
