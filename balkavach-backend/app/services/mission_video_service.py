"""Server-verified playback progress for missions with a video requirement."""

from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.services.video_watch_history_service import (
	MAX_VERIFIED_PROGRESS_GAP_SECONDS,
	accepted_progress_seconds,
	_eligible_video,
)
from app.utils import utc_aware, utc_naive


def _task_for_child(session: Session, task_id: UUID, child):
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == task_id, Task.is_active.is_(True)).one_or_none()
	if task is None or task.family_id != child.family_id:
		raise HTTPException(status_code=404, detail="Mission not found")
	if task.assigned_child_id is not None and task.assigned_child_id != child.id:
		raise HTTPException(status_code=404, detail="Mission not found")
	if not task.required_video_seconds:
		raise APIError(409, "mission_video_not_required", "This mission has no video requirement")
	return task


def _watched_seconds(session: Session, task_id: UUID, child_id: UUID) -> int:
	Watch = get_model("MissionVideoWatchSession")
	return int(
		session.query(func.coalesce(func.sum(Watch.watched_seconds), 0))
		.filter(Watch.task_id == task_id, Watch.child_id == child_id)
		.scalar()
		or 0
	)


def get_mission_video_progress(session: Session, task_id: UUID, child) -> dict:
	task = _task_for_child(session, task_id, child)
	return _progress(session, task, child.id)


def _progress(session: Session, task, child_id: UUID) -> dict:
	required = int(task.required_video_seconds or 0)
	verified = _watched_seconds(session, task.id, child_id)
	return {
		"task_id": task.id,
		"required_video_seconds": required,
		"verified_video_seconds": verified,
		"remaining_video_seconds": max(0, required - verified),
		"is_complete": required > 0 and verified >= required,
	}


def require_video_requirement_complete(session: Session, task, child) -> None:
	if not task.required_video_seconds:
		return
	progress = _progress(session, task, child.id)
	if not progress["is_complete"]:
		raise APIError(
			409,
			"mission_video_incomplete",
			"Watch the required video time before submitting this mission.",
			details={
				"required_video_seconds": progress["required_video_seconds"],
				"verified_video_seconds": progress["verified_video_seconds"],
			},
		)


def _watch_public(session: Session, task, child_id: UUID, watch, accepted: int) -> dict:
	return {
		**_progress(session, task, child_id),
		"session_id": watch.id,
		"accepted_seconds": accepted,
		"status": watch.status,
	}


def start_mission_video_watch(
	session: Session,
	task_id: UUID,
	child,
	video_id: UUID,
	client_session_id: str,
) -> dict:
	ChildProfile = get_model("ChildProfile")
	locked_child = session.query(ChildProfile).filter(
		ChildProfile.id == child.id,
		ChildProfile.is_active.is_(True),
	).with_for_update().one_or_none()
	if locked_child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	task = _task_for_child(session, task_id, locked_child)
	video = _eligible_video(session, locked_child, video_id)
	Watch = get_model("MissionVideoWatchSession")
	now = utc_naive(datetime.now(timezone.utc))
	existing = session.query(Watch).filter(
		Watch.client_session_id == client_session_id,
		Watch.child_id == child.id,
		Watch.task_id == task.id,
		Watch.video_id == video.id,
	).one_or_none()
	if existing is not None:
		last = existing.last_heartbeat_at or existing.started_at
		if last.tzinfo is not None:
			last = utc_naive(last)
		if existing.status == "active" and (now - last).total_seconds() > MAX_VERIFIED_PROGRESS_GAP_SECONDS:
			existing.status = "interrupted"
			existing.ended_at = now
			session.commit()
		return _watch_public(session, task, child.id, existing, 0)
	if session.query(Watch.id).filter(Watch.client_session_id == client_session_id).first():
		raise APIError(409, "mission_video_session_key_conflict", "Please start a new mission video session")
	active = session.query(Watch).filter(
		Watch.child_id == child.id,
		Watch.status == "active",
	).with_for_update().one_or_none()
	if active is not None:
		last = active.last_heartbeat_at or active.started_at
		if last.tzinfo is not None:
			last = utc_naive(last)
		if (now - last).total_seconds() > MAX_VERIFIED_PROGRESS_GAP_SECONDS:
			active.status = "interrupted"
			active.ended_at = now
			session.flush()
		else:
			raise APIError(409, "mission_video_session_active", "Finish or pause the active mission video first")
	watch = Watch(
		id=uuid4(),
		client_session_id=client_session_id,
		task_id=task.id,
		child_id=child.id,
		video_id=video.id,
		started_at=now,
		last_heartbeat_at=now,
		ended_at=None,
		last_position_seconds=0,
		watched_seconds=0,
		last_sequence=-1,
		is_playing=True,
		status="active",
	)
	session.add(watch)
	session.commit()
	return _watch_public(session, task, child.id, watch, 0)


def record_mission_video_heartbeat(
	session: Session,
	session_id: UUID,
	child,
	sequence: int,
	position_seconds: int,
	is_playing: bool,
) -> dict:
	ChildProfile = get_model("ChildProfile")
	locked_child = session.query(ChildProfile).filter(
		ChildProfile.id == child.id,
		ChildProfile.is_active.is_(True),
	).with_for_update().one_or_none()
	if locked_child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	Watch = get_model("MissionVideoWatchSession")
	watch = session.query(Watch).filter(
		Watch.id == session_id,
		Watch.child_id == child.id,
	).with_for_update().one_or_none()
	if watch is None:
		raise HTTPException(status_code=404, detail="Mission video session not found")
	Task = get_model("Task")
	task = _task_for_child(session, watch.task_id, locked_child)
	if watch.status == "completed" and sequence <= watch.last_sequence:
		return _watch_public(session, task, child.id, watch, 0)
	if watch.status != "active":
		raise APIError(409, "mission_video_session_inactive", "Mission video session is no longer active")
	if sequence == watch.last_sequence:
		return _watch_public(session, task, child.id, watch, 0)
	if sequence < watch.last_sequence:
		raise APIError(409, "mission_video_heartbeat_replayed", "This playback heartbeat is out of date")
	video = _eligible_video(session, locked_child, watch.video_id)
	now = utc_naive(datetime.now(timezone.utc))
	previous = watch.last_heartbeat_at or watch.started_at
	if previous.tzinfo is not None:
		previous = utc_naive(previous)
	elapsed = (now - previous).total_seconds()
	if elapsed > MAX_VERIFIED_PROGRESS_GAP_SECONDS:
		watch.status = "interrupted"
		watch.ended_at = now
		watch.last_sequence = sequence
		session.commit()
		return _watch_public(session, task, child.id, watch, 0)
	accepted = accepted_progress_seconds(
		elapsed_seconds=elapsed,
		was_playing=bool(watch.is_playing),
		is_playing=is_playing,
		previous_position=int(watch.last_position_seconds or 0),
		position=position_seconds,
	)
	watch.watched_seconds = int(watch.watched_seconds or 0) + accepted
	watch.last_position_seconds = position_seconds
	watch.last_heartbeat_at = now
	watch.last_sequence = sequence
	watch.is_playing = is_playing
	session.flush()
	progress = _progress(session, task, child.id)
	if progress["is_complete"]:
		watch.status = "completed"
		watch.ended_at = now
	session.commit()
	return _watch_public(session, task, child.id, watch, accepted)


def interrupt_mission_video_watch(session: Session, session_id: UUID, child) -> dict:
	Watch = get_model("MissionVideoWatchSession")
	watch = session.query(Watch).filter(
		Watch.id == session_id,
		Watch.child_id == child.id,
	).with_for_update().one_or_none()
	if watch is None:
		raise HTTPException(status_code=404, detail="Mission video session not found")
	Task = get_model("Task")
	task = session.query(Task).filter(Task.id == watch.task_id).one_or_none()
	if task is None or task.family_id != child.family_id:
		raise HTTPException(status_code=404, detail="Mission video session not found")
	if watch.status == "active":
		watch.status = "interrupted"
		watch.ended_at = utc_naive(datetime.now(timezone.utc))
		session.commit()
	return _watch_public(session, task, child.id, watch, 0)