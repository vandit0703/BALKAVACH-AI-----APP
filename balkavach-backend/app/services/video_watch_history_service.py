"""Persistent child-specific watch progress and history."""

import logging
import math
from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import or_
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.db.base import get_model
from app.services.video_classification import video_format
from app.services.video_service import child_age
from app.services.video_entitlement_service import (
	FREE_DAILY_ALLOWANCE_SECONDS,
	consume_video_allowance,
	get_child_video_allowance_today,
)
from app.services.charging_path import play_tickets_active
from app.services.video_time_alerts import emit_video_time_alert
from app.services.youtube_review_service import youtube_visibility_clause
from app.utils import utc_aware, utc_naive

logger = logging.getLogger(__name__)

MAX_PROGRESS_INTERVAL_SECONDS = 30
MAX_VERIFIED_PROGRESS_GAP_SECONDS = MAX_PROGRESS_INTERVAL_SECONDS + 2
# Real playback advances the position at about wall-clock speed; a larger jump is a seek.
POSITION_ADVANCE_TOLERANCE_SECONDS = 2


def accepted_progress_seconds(
	*,
	elapsed_seconds: float,
	was_playing: bool,
	is_playing: bool,
	previous_position: int,
	position: int,
) -> int:
	"""Seconds to charge for one progress report. The only watch-time rule; the client never supplies it.

	The interval since the previous report is measured by the server clock and capped. An honest
	"paused" report is free, but the client cannot buy free playback by claiming it is paused while
	the position keeps advancing at playback speed: in that case the position delta is charged
	(never more than the elapsed time). A seek is a jump much larger than the elapsed time and is
	not charged.
	"""
	if elapsed_seconds > MAX_VERIFIED_PROGRESS_GAP_SECONDS:
		return 0
	elapsed = min(MAX_PROGRESS_INTERVAL_SECONDS, max(0, int(elapsed_seconds)))
	if elapsed == 0:
		return 0
	if not was_playing:
		return 0
	advanced = position - previous_position
	if 0 < advanced <= elapsed + POSITION_ADVANCE_TOLERANCE_SECONDS:
		return min(elapsed, advanced)
	return 0


def _public(history, video) -> dict:
	return {
		"video_id": video.id,
		"title": video.title,
		"description": video.description,
		"thumbnail_url": video.thumbnail_url,
		"duration_seconds": video.duration_seconds,
		"category_id": video.category_id,
		"language_code": video.language_code,
		"video_source": video.video_source,
		"youtube_video_id": video.external_video_id if video.video_source == "youtube" else None,
		"video_format": history.video_format,
		"started_at": utc_aware(history.started_at),
		"last_watched_at": utc_aware(history.last_watched_at),
		"last_position_seconds": history.last_position_seconds,
		"watch_duration_seconds": history.watch_duration_seconds,
		"completion_percentage": history.completion_percentage,
		"is_completed": history.is_completed,
	}


def _eligible_video(session: Session, child, video_id: UUID):
	Video = get_model("Video")
	User = get_model("User")
	video = session.query(Video).filter(
		Video.id == video_id,
		Video.is_published.is_(True),
		Video.content_rating.in_(["general", "educational"]),
		youtube_visibility_clause(Video),
	).one_or_none()
	if video is None:
		raise HTTPException(status_code=404, detail="Video not found")
	user = session.query(User).filter(User.id == child.user_id).one()
	age = child_age(child)
	if age is None or not video.age_min <= age <= video.age_max:
		raise HTTPException(status_code=403, detail="Video is not eligible for this child")
	if video.language_code not in {user.preferred_language, "en"}:
		raise HTTPException(status_code=403, detail="Video language is not eligible for this child")
	if video.category_id is not None:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == video.category_id,
			VideoCategory.is_active.is_(True),
		).first():
			raise HTTPException(status_code=403, detail="Video category is not eligible for this child")
	return video


def get_or_create_watch_history(session: Session, child, video, now: datetime):
	"""The child's history row for ``video`` (locked), created on first watch."""
	WatchHistory = get_model("ChildVideoWatchHistory")
	format_name = "short" if video_format(video.video_source, video.duration_seconds) == "short" else "regular"
	history = session.query(WatchHistory).filter(
		WatchHistory.child_id == child.id,
		WatchHistory.video_id == video.id,
	).with_for_update().one_or_none()
	created = history is None
	if created:
		history = WatchHistory(
			child_id=child.id,
			video_id=video.id,
			youtube_video_id=video.external_video_id if video.video_source == "youtube" else None,
			video_format=format_name,
			started_at=now,
			last_watched_at=now,
			last_position_seconds=0,
			watch_duration_seconds=0,
			completion_percentage=0,
			is_completed=False,
			parent_replay_authorized=False,
		)
		session.add(history)
		session.flush()
	else:
		history.last_watched_at = now
		history.parent_replay_authorized = False
	return history, format_name, created


def get_or_create_daily_usage(session: Session, child, local_date, now: datetime, is_playing: bool):
	"""Today's free-allowance ledger row (locked). Returns (row, created)."""
	DailyUsage = get_model("ChildVideoDailyUsage")
	daily_usage = session.query(DailyUsage).filter(
		DailyUsage.child_id == child.id,
		DailyUsage.local_date == local_date,
	).with_for_update().one_or_none()
	if daily_usage is not None:
		return daily_usage, False
	daily_usage = DailyUsage(
		child_id=child.id,
		local_date=local_date,
		free_watched_seconds=0,
		last_heartbeat_at=now,
		is_playing=is_playing,
	)
	session.add(daily_usage)
	session.flush()
	return daily_usage, True


def apply_allowance_charge(
	session: Session,
	child,
	daily_usage,
	accepted: int,
	allowance_before: dict,
	now_aware: datetime,
) -> tuple[int, bool, int]:
	"""Charge ``accepted`` seconds: free time first, then mission grants oldest
	first; re-read the allowance; raise the low-time / time-up alert.

	The one ledger writer, shared by ``record_progress`` and the play-ticket
	heartbeat; ``charging_path.play_tickets_active()`` decides which of the two
	may call it. Returns (remaining_seconds, is_exhausted, free_seconds_charged).
	"""
	free_remaining = max(0, FREE_DAILY_ALLOWANCE_SECONDS - int(daily_usage.free_watched_seconds or 0))
	free_accepted = min(accepted, free_remaining)
	daily_usage.free_watched_seconds += free_accepted
	mission_accepted = accepted - free_accepted
	if mission_accepted:
		consume_video_allowance(session, child.id, child.family_id, mission_accepted, now_utc=now_aware)
	# Sessions run with autoflush=False: without this the re-read below misses
	# the free seconds just charged and over-reports what is left.
	session.flush()
	updated = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
	remaining = int(updated["remaining_seconds"])
	# Low-time / time-up alert, once per threshold. A savepoint keeps a
	# notification problem from undoing the charge above.
	try:
		with session.begin_nested():
			emit_video_time_alert(
				session,
				child,
				before_seconds=int(allowance_before["remaining_seconds"]),
				after_seconds=remaining,
				now=now_aware,
			)
	except Exception:  # noqa: BLE001 - the deduction must still be committed
		logger.exception("Video time alert could not be created")
	return remaining, bool(updated["is_exhausted"]), free_accepted


def update_watch_position(history, video, format_name: str, position_seconds: int, now: datetime) -> None:
	duration = video.duration_seconds
	position = min(position_seconds, duration) if duration and duration > 0 else position_seconds
	percentage = min(100, int(position * 100 / duration)) if duration and duration > 0 else 0
	history.last_position_seconds = position
	history.completion_percentage = max(history.completion_percentage, percentage)
	if duration and duration > 0:
		if format_name == "short":
			percent_threshold = settings.youtube_short_watch_completion_percent
			threshold = min(
				duration,
				max(settings.youtube_short_min_watch_seconds, math.ceil(duration * percent_threshold / 100)),
			)
		else:
			percent_threshold = settings.youtube_long_watch_completion_percent
			threshold = math.ceil(duration * percent_threshold / 100)
		if history.watch_duration_seconds >= threshold and history.completion_percentage >= percent_threshold:
			history.is_completed = True
			history.completed_at = history.completed_at or now


def find_eligible_video(session: Session, child, video_id: UUID):
	"""The video if ``record_progress`` would accept it for this child, else None.

	Same rules as ``_eligible_video`` (published, rating, YouTube visibility, age,
	language, active category), without raising.
	"""
	try:
		return _eligible_video(session, child, video_id)
	except HTTPException:
		return None


def record_progress(
	session: Session,
	child,
	video_id: UUID,
	position_seconds: int,
	is_playing: bool = True,
) -> dict:
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child.id,
		ChildProfile.is_active.is_(True),
	).with_for_update().one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	if play_tickets_active():
		# Exactly one charging path: with tickets active, only ticket heartbeats charge.
		raise APIError(409, "play_ticket_required", "This app version must use play tickets")
	video = _eligible_video(session, child, video_id)
	# One instant for the whole report: aware for the allowance/timezone helpers
	# (utc_naive() refuses naive values), naive for the stored timestamps.
	now_aware = datetime.now(timezone.utc)
	now = utc_naive(now_aware)
	history, format_name, created = get_or_create_watch_history(session, child, video, now)
	previous_position = 0 if created else int(history.last_position_seconds or 0)

	# Mission-earned video allowance enforcement
	remaining_allowance = None
	is_exhausted = False
	allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now_aware)
	if allowance["remaining_seconds"] <= 0:
		raise APIError(
			403,
			"video_time_exhausted",
			"Video access time has been exhausted. Complete missions to earn more video time.",
		)
	daily_usage, usage_created = get_or_create_daily_usage(session, child, allowance["local_date"], now, is_playing)
	accepted = 0
	if not usage_created:
		previous = daily_usage.last_heartbeat_at or now
		if previous.tzinfo is not None:
			previous = utc_naive(previous)
		accepted = accepted_progress_seconds(
			elapsed_seconds=(now - previous).total_seconds(),
			was_playing=bool(daily_usage.is_playing),
			is_playing=is_playing,
			previous_position=previous_position,
			position=position_seconds,
		)
		daily_usage.last_heartbeat_at = now
		daily_usage.is_playing = is_playing
	accepted = min(accepted, allowance["remaining_seconds"])
	history.watch_duration_seconds += accepted
	if accepted > 0:
		remaining_allowance, is_exhausted, _ = apply_allowance_charge(
			session, child, daily_usage, accepted, allowance, now_aware
		)

	update_watch_position(history, video, format_name, position_seconds, now)
	try:
		session.commit()
	except Exception:
		session.rollback()
		raise
	return {
		**_public(history, video),
		"accepted_seconds": accepted,
		"remaining_allowance_seconds": remaining_allowance,
		"is_exhausted": is_exhausted,
	}


def list_child_history(
	session: Session,
	child_id: UUID,
	*,
	continue_watching: bool = False,
	eligible_child=None,
	limit: int = 100,
) -> list[dict]:
	History = get_model("ChildVideoWatchHistory")
	Video = get_model("Video")
	query = session.query(History, Video).join(Video, Video.id == History.video_id).filter(
		History.child_id == child_id,
	)
	if eligible_child is not None:
		age = child_age(eligible_child)
		if age is None:
			return []
		User = get_model("User")
		user = session.query(User).filter(User.id == eligible_child.user_id).one()
		VideoCategory = get_model("VideoCategory")
		query = query.outerjoin(VideoCategory, VideoCategory.id == Video.category_id).filter(
			Video.is_published.is_(True),
			Video.age_min <= age,
			Video.age_max >= age,
			Video.language_code.in_([user.preferred_language, "en"]),
			Video.content_rating.in_(["general", "educational"]),
			or_(Video.category_id.is_(None), VideoCategory.is_active.is_(True)),
			youtube_visibility_clause(Video),
		)
	if continue_watching:
		query = query.filter(
			History.video_format == "regular",
			History.is_completed.is_(False),
			History.last_position_seconds > 0,
			Video.is_published.is_(True),
			Video.content_rating.in_(["general", "educational"]),
			youtube_visibility_clause(Video),
		)
	return [
		_public(history, video)
		for history, video in query.order_by(History.last_watched_at.desc(), History.id).limit(limit).all()
	]


def authorize_replay(session: Session, child_id: UUID, video_id: UUID) -> None:
	History = get_model("ChildVideoWatchHistory")
	history = session.query(History).filter(
		History.child_id == child_id,
		History.video_id == video_id,
	).with_for_update().one_or_none()
	if history is None or not history.is_completed:
		raise APIError(404, "watch_history_not_found", "Completed viewing history not found")
	history.parent_replay_authorized = True
	session.commit()