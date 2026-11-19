"""Persistent child-specific watch progress and history."""

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
from app.services.youtube_review_service import youtube_visibility_clause
from app.utils import utc_aware, utc_naive

MAX_PROGRESS_INTERVAL_SECONDS = 30
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
	elapsed = min(MAX_PROGRESS_INTERVAL_SECONDS, max(0, int(elapsed_seconds)))
	if elapsed == 0:
		return 0
	if was_playing:
		return elapsed
	if is_playing:
		return 0  # resumed just now; the paused interval is free
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
	video = _eligible_video(session, child, video_id)
	WatchHistory = get_model("ChildVideoWatchHistory")
	now = utc_naive(datetime.now(timezone.utc))
	format_name = video_format(video.video_source, video.duration_seconds)
	format_name = "short" if format_name == "short" else "regular"
	history = session.query(WatchHistory).filter(
		WatchHistory.child_id == child.id,
		WatchHistory.video_id == video.id,
	).with_for_update().one_or_none()
	if history is None:
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
		accepted = 0
		previous_position = 0
	else:
		accepted = 0
		previous_position = int(history.last_position_seconds or 0)
		history.last_watched_at = now
		history.parent_replay_authorized = False

	# Mission-earned video allowance enforcement
	remaining_allowance = None
	is_exhausted = False
	allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now)
	if allowance["remaining_seconds"] <= 0:
		raise APIError(
			403,
			"video_time_exhausted",
			"Video access time has been exhausted. Complete missions to earn more video time.",
		)
	DailyUsage = get_model("ChildVideoDailyUsage")
	daily_usage = session.query(DailyUsage).filter(
		DailyUsage.child_id == child.id,
		DailyUsage.local_date == allowance["local_date"],
	).with_for_update().one_or_none()
	if daily_usage is None:
		daily_usage = DailyUsage(
			child_id=child.id,
			local_date=allowance["local_date"],
			free_watched_seconds=0,
			last_heartbeat_at=now,
			is_playing=is_playing,
		)
		session.add(daily_usage)
		session.flush()
		accepted = 0
	else:
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
		free_remaining = max(
			0,
			FREE_DAILY_ALLOWANCE_SECONDS - int(daily_usage.free_watched_seconds or 0),
		)
		free_accepted = min(accepted, free_remaining)
		daily_usage.free_watched_seconds += free_accepted
		mission_accepted = accepted - free_accepted
		if mission_accepted:
			consume_video_allowance(
				session, child.id, child.family_id, mission_accepted, now_utc=now
			)
		updated_allowance = get_child_video_allowance_today(
			session, child.id, child.family_id, now_utc=now
		)
		remaining_allowance = updated_allowance["remaining_seconds"]
		is_exhausted = updated_allowance["is_exhausted"]

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