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
	consume_video_allowance,
	get_child_video_allowance_today,
)
from app.services.youtube_review_service import youtube_visibility_clause
from app.utils import utc_aware, utc_naive

MAX_PROGRESS_INTERVAL_SECONDS = 30


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


def record_progress(session: Session, child, video_id: UUID, position_seconds: int) -> dict:
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
	else:
		previous = history.last_watched_at
		if previous.tzinfo is not None:
			previous = utc_naive(previous)
		accepted = min(
			MAX_PROGRESS_INTERVAL_SECONDS,
			max(0, int((now - previous).total_seconds())),
		)
		history.watch_duration_seconds += accepted
		history.last_watched_at = now
		history.parent_replay_authorized = False

	# Mission-earned video allowance enforcement
	remaining_allowance = None
	is_exhausted = False
	allowance = get_child_video_allowance_today(session, child.id, child.family_id, now_utc=now)
	if allowance["total_earned_today_seconds"] > 0:
		if allowance["remaining_seconds"] <= 0:
			raise APIError(
				403,
				"video_time_exhausted",
				"Video access time has been exhausted. Complete missions to earn more video time.",
			)
		if accepted > 0:
			deducted = consume_video_allowance(
				session, child.id, child.family_id, accepted, now_utc=now
			)
			updated_allowance = get_child_video_allowance_today(
				session, child.id, child.family_id, now_utc=now
			)
			remaining_allowance = updated_allowance["remaining_seconds"]
			is_exhausted = updated_allowance["is_exhausted"]
			if deducted == 0 and remaining_allowance <= 0:
				raise APIError(
					403,
					"video_time_exhausted",
					"Video access time has been exhausted. Complete missions to earn more video time.",
				)
		else:
			remaining_allowance = allowance["remaining_seconds"]
			is_exhausted = remaining_allowance <= 0

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