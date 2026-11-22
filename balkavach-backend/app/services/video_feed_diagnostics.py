"""Read-only answer to "why does this child's video feed look empty?".

It counts how many videos survive each feed rule in turn, using the very same rule list the feed applies
(``video_service.feed_conditions``), so the explanation cannot drift from the behaviour. Nothing is written.
The ``videos.feed.empty`` log line and ``python -m app.cli video-feed-diagnose`` both use it.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import re
from typing import Any, Literal
from uuid import UUID

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, aliased

from app.core.config import settings
from app.db.base import get_model, has_model
from app.utils import utc_aware, utc_naive

FeedFormat = Literal["short", "regular"]
_YOUTUBE_ID = re.compile(r"^[A-Za-z0-9_-]{11}$")

# What it means when a stage is the one that removed the last candidates.
STAGE_MEANING = {
	"published": "no video is published",
	"age_band": "no published video is approved for this child's age",
	"content_rating": "no video for this age has a general or educational rating",
	"language": "no video matches the child's language (or English)",
	"active_category": "the matching videos are all in inactive categories",
	"youtube_approved": (
		"the matching YouTube videos are not approved, rights-cleared and made-for-kids, "
		"or are unavailable/quarantined/revoked"
	),
	"not_a_duplicate": "the remaining videos are duplicates of an earlier row",
	"format_short": "there is no eligible video of 1-60 seconds",
	"format_regular": "there is no eligible video longer than 60 seconds (or of unknown length)",
	"requested_category": "nothing in the requested category",
}


def funnel(
	session: Session,
	*,
	age: int,
	languages: list[str],
	child_id: UUID | None = None,
	category_id: UUID | None = None,
	video_format: FeedFormat | None = None,
) -> dict[str, Any]:
	"""``{"total", "stages": [{"stage", "remaining", "removed"}], "limiting_stage", "eligible"}``.

	``limiting_stage`` is the first rule after which nothing is left (``None`` when something is eligible)."""
	from app.services.video_service import feed_conditions

	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory")
	conditions = feed_conditions(
		Video,
		VideoCategory,
		aliased(Video),
		age=age,
		languages=languages,
		child_id=child_id,
		category_id=category_id,
		video_format=video_format,
	)
	base = session.query(Video.id).outerjoin(VideoCategory, VideoCategory.id == Video.category_id)
	total = base.count()
	stages: list[dict[str, Any]] = []
	applied: list[object] = []
	previous = total
	limiting: str | None = None
	for name, clause in conditions:
		applied.append(clause)
		remaining = base.filter(*applied).count()
		stages.append({"stage": name, "remaining": remaining, "removed": previous - remaining})
		if remaining == 0 and limiting is None:
			limiting = name
		previous = remaining
	condition_by_name = dict(conditions)
	moderation_rules = ("published", "content_rating", "youtube_approved")
	age_language_rules = (*moderation_rules, "age_band", "language")
	breakdown = {
		"candidate_total": total,
		"after_publication": base.filter(condition_by_name["published"]).count(),
		"after_moderation": base.filter(*(condition_by_name[name] for name in moderation_rules)).count(),
		"after_age_language": base.filter(*(condition_by_name[name] for name in age_language_rules)).count(),
		"eligible_before_paging": previous,
		"publication_status_counts": {
			"published" if is_published else "unpublished": count
			for is_published, count in session.query(Video.is_published, func.count(Video.id))
			.group_by(Video.is_published)
			.all()
		},
	}
	youtube_ids = [
		external_id
		for (external_id,) in session.query(Video.external_video_id).filter(Video.video_source == "youtube").all()
	]
	breakdown["youtube_id_counts"] = {
		"valid": sum(isinstance(external_id, str) and _YOUTUBE_ID.fullmatch(external_id) is not None for external_id in youtube_ids),
		"missing": sum(external_id is None or external_id == "" for external_id in youtube_ids),
		"invalid": sum(
			external_id is not None and external_id != "" and (not isinstance(external_id, str) or _YOUTUBE_ID.fullmatch(external_id) is None)
			for external_id in youtube_ids
		),
	}
	if has_model("YouTubeContentReview"):
		Review = get_model("YouTubeContentReview")
		moderation_status_counts: dict[str, int] = {}
		moderation_rows = (
			session.query(Review.status, func.count(Video.id))
			.select_from(Video)
			.outerjoin(Review, Review.video_id == Video.id)
			.filter(Video.video_source == "youtube")
			.group_by(Review.status)
			.all()
		)
		for status, count in moderation_rows:
			label = "unreviewed" if status is None else str(status)
			if re.fullmatch(r"[a-z_]{1,32}", label) is None:
				label = "other"
			moderation_status_counts[label] = moderation_status_counts.get(label, 0) + count
		breakdown["moderation_status_counts"] = moderation_status_counts
	else:
		breakdown["moderation_status_counts"] = {"review_table_missing": 1}
	freshness = youtube_verification(session)
	breakdown["youtube_verification_counts"] = (
		{
			"approved": freshness["approved"],
			"recently_verified": freshness["recently_verified"],
			"not_recently_verified": freshness["not_recently_verified"],
		}
		if freshness is not None
		else {"review_table_missing": 1}
	)
	return {
		"total": total,
		"stages": stages,
		"limiting_stage": limiting,
		"eligible": previous,
		"diagnostic_counts": breakdown,
	}


def youtube_verification(session: Session) -> dict[str, Any] | None:
	"""Approved YouTube reviews and verification recency (informational; recency does not hide feed videos)."""
	if not has_model("YouTubeContentReview"):
		return None
	Review = get_model("YouTubeContentReview")
	fresh_after = utc_naive(datetime.now(timezone.utc) - timedelta(hours=settings.youtube_reverify_hours))
	approved = session.query(func.count(Review.id)).filter(Review.status == "approved").scalar() or 0
	not_recently_verified = (
		session.query(func.count(Review.id))
		.filter(Review.status == "approved", or_(Review.last_verified_at.is_(None), Review.last_verified_at < fresh_after))
		.scalar()
		or 0
	)
	oldest = session.query(func.min(Review.last_verified_at)).filter(Review.status == "approved").scalar()
	return {
		"approved": approved,
		"not_recently_verified": not_recently_verified,
		"recently_verified": approved - not_recently_verified,
		"approved_stale": not_recently_verified,
		"approved_fresh": approved - not_recently_verified,
		"oldest_approved_verification": utc_aware(oldest) if oldest else None,
		"reverify_hours": settings.youtube_reverify_hours,
	}


def youtube_freshness(session: Session) -> dict[str, Any] | None:
	"""Backward-compatible alias for verification recency info."""
	return youtube_verification(session)


def diagnose(
	session: Session,
	*,
	child_id: UUID | None = None,
	age: int | None = None,
	language: str = "en",
) -> dict[str, Any]:
	"""Why the Home and Shorts feeds are (or are not) empty, for one child or for an age and language."""
	from app.services.video_entitlement_service import get_child_video_allowance_today
	from app.services.video_service import child_age, feed_languages

	exhausted: bool | None = None
	has_birth_date: bool | None = None
	if child_id is not None:
		ChildProfile = get_model("ChildProfile")
		User = get_model("User")
		child = session.query(ChildProfile).filter(ChildProfile.id == child_id).one_or_none()
		if child is None:
			return {"error": "child_not_found"}
		user = session.query(User).filter(User.id == child.user_id).one()
		language = user.preferred_language
		age = child_age(child)
		has_birth_date = child.date_of_birth is not None
		exhausted = bool(get_child_video_allowance_today(session, child.id, child.family_id)["is_exhausted"])
	languages = feed_languages(language)
	in_range = age is not None and 3 <= age <= 15

	feeds: dict[str, Any] = {}
	if in_range:
		for name in ("short", "regular"):
			feeds[name] = funnel(session, age=age, languages=languages, child_id=child_id, video_format=name)
	youtube = youtube_verification(session)

	findings: list[str] = []
	if child_id is not None and not has_birth_date:
		findings.append("The child has no birth date: the server shows no videos without an age.")
	elif not in_range:
		findings.append("The age is missing or outside 3-15: the server shows no videos.")
	if exhausted:
		findings.append("Today's video allowance is used up: both feeds are empty by design.")
	for name, result in feeds.items():
		if result["eligible"] == 0:
			stage = result["limiting_stage"]
			findings.append(f"The {name} feed is empty because {STAGE_MEANING.get(stage, stage)}.")
	hidden_by_moderation = max(
		(
			row["removed"]
			for result in feeds.values()
			for row in result["stages"]
			if row["stage"] == "youtube_approved"
		),
		default=0,
	)
	if hidden_by_moderation:
		findings.append(
			f"{hidden_by_moderation} otherwise-eligible YouTube video(s) are hidden because they are not approved, "
			f"rights-cleared, made for kids, or currently available."
		)
	if youtube and youtube.get("not_recently_verified"):
		findings.append(
			f"{youtube['not_recently_verified']} approved YouTube video(s) have not been re-verified recently "
			f"(oldest verification {youtube['oldest_approved_verification']}); they remain eligible while recheck is available "
			"to refresh metadata and availability."
		)
	if not findings:
		findings.append("Both feeds have eligible videos.")
	return {
		"child_id": str(child_id) if child_id else None,
		"age": age,
		"languages": languages,
		"allowance_exhausted": exhausted,
		"feeds": feeds,
		"youtube": youtube,
		"findings": findings,
	}
