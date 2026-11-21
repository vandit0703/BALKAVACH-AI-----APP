"""Read-only answer to "why does this child's video feed look empty?".

It counts how many videos survive each feed rule in turn, using the very same rule list the feed applies
(``video_service.feed_conditions``), so the explanation cannot drift from the behaviour. Nothing is written.
The ``videos.feed.empty`` log line and ``python -m app.cli video-feed-diagnose`` both use it.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Literal
from uuid import UUID

from sqlalchemy import func, or_
from sqlalchemy.orm import Session, aliased

from app.core.config import settings
from app.db.base import get_model, has_model
from app.utils import utc_aware, utc_naive

FeedFormat = Literal["short", "regular"]

# What it means when a stage is the one that removed the last candidates.
STAGE_MEANING = {
	"published": "no video is published",
	"age_band": "no published video is approved for this child's age",
	"content_rating": "no video for this age has a general or educational rating",
	"language": "no video matches the child's language (or English)",
	"active_category": "the matching videos are all in inactive categories",
	"youtube_approved_and_fresh": (
		"the matching YouTube videos are not approved, rights-cleared and made-for-kids, or were not "
		"re-verified within the re-verification window (run youtube-recheck)"
	),
	"not_a_duplicate": "the remaining videos are duplicates of an earlier row",
	"format_short": "there is no eligible video of 1-60 seconds",
	"format_regular": "there is no eligible video longer than 60 seconds (or of unknown length)",
	"requested_category": "nothing in the requested category",
	"not_already_completed": "this child has already completed every remaining video (parent replay not authorised)",
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
	return {"total": total, "stages": stages, "limiting_stage": limiting, "eligible": previous}


def youtube_freshness(session: Session) -> dict[str, Any] | None:
	"""Approved YouTube reviews, and how many the feed hides because they were not re-verified in time."""
	if not has_model("YouTubeContentReview"):
		return None
	Review = get_model("YouTubeContentReview")
	fresh_after = utc_naive(datetime.now(timezone.utc) - timedelta(hours=settings.youtube_reverify_hours))
	approved = session.query(func.count(Review.id)).filter(Review.status == "approved").scalar() or 0
	stale = (
		session.query(func.count(Review.id))
		.filter(Review.status == "approved", or_(Review.last_verified_at.is_(None), Review.last_verified_at < fresh_after))
		.scalar()
		or 0
	)
	oldest = session.query(func.min(Review.last_verified_at)).filter(Review.status == "approved").scalar()
	return {
		"approved": approved,
		"approved_stale": stale,
		"approved_fresh": approved - stale,
		"oldest_approved_verification": utc_aware(oldest) if oldest else None,
		"reverify_hours": settings.youtube_reverify_hours,
	}


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
	youtube = youtube_freshness(session)

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
	# Both feeds see the same videos at this step (the short/regular split comes later): count them once.
	hidden_by_freshness = max(
		(
			row["removed"]
			for result in feeds.values()
			for row in result["stages"]
			if row["stage"] == "youtube_approved_and_fresh"
		),
		default=0,
	)
	if hidden_by_freshness:
		findings.append(
			f"{hidden_by_freshness} otherwise-eligible YouTube video(s) are hidden by approval or freshness rules"
			+ (
				f"; {youtube['approved_stale']} approved video(s) are stale (oldest verification "
				f"{youtube['oldest_approved_verification']}), which youtube-recheck repairs."
				if youtube and youtube["approved_stale"]
				else "."
			)
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
