import logging
from datetime import datetime, timedelta, timezone
from uuid import UUID, uuid4

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.integrations import get_video_playback_provider
from app.schemas.video import PlaybackHeartbeatPublic, PlaybackSessionPublic, PlaybackStartRequest
from app.services.video_service import child_age
from app.utils import utc_aware, utc_naive

logger = logging.getLogger(__name__)
MAX_HEARTBEAT_ELAPSED_SECONDS = 30
PLAYBACK_URL_TTL_SECONDS = 60


def _naive(value: datetime | None) -> datetime | None:
	"""Timestamps loaded from PostgreSQL (timestamptz) are timezone-aware, while this
	module computes with naive UTC "now" values; comparing the two raises TypeError."""
	if value is None or value.tzinfo is None:
		return value
	return utc_naive(value)


def accepted_heartbeat_seconds(previous: datetime, now: datetime, remaining: int) -> int:
	elapsed = (now - previous).total_seconds()
	if elapsed < 0:
		raise APIError(409, "invalid_heartbeat", "Playback heartbeat timestamp is invalid")
	return min(int(elapsed), MAX_HEARTBEAT_ELAPSED_SECONDS, max(0, remaining))


def _matches_entitlement(session: Session, entitlement, video_id: UUID) -> bool:
	if entitlement.video_id == video_id:
		return True
	if entitlement.video_collection_id is None:
		return False
	VideoCollection = get_model("VideoCollection")
	collection = session.query(VideoCollection).filter(
		VideoCollection.id == entitlement.video_collection_id,
		VideoCollection.is_published.is_(True),
	).one_or_none()
	if collection is None:
		return False
	VideoCollectionItem = get_model("VideoCollectionItem")
	return bool(session.query(VideoCollectionItem.id).filter(
		VideoCollectionItem.collection_id == collection.id,
		VideoCollectionItem.video_id == video_id,
	).first())


def _issue_url(provider, video, session_id: UUID, now: datetime, remaining: int, entitlement_expires_at):
	expires_at = now + timedelta(seconds=min(PLAYBACK_URL_TTL_SECONDS, remaining))
	if entitlement_expires_at is not None:
		expires_at = min(expires_at, _naive(entitlement_expires_at))
	try:
		return provider.issue_playback_url(video, session_id, utc_aware(expires_at))
	except Exception as error:
		logger.warning("Authorized playback URL issuance failed")
		raise APIError(503, "playback_unavailable", "Authorized video playback is temporarily unavailable") from error


def start_playback(session: Session, child, request: PlaybackStartRequest) -> PlaybackSessionPublic:
	now = utc_naive(datetime.now(timezone.utc))
	ChildProfile = get_model("ChildProfile")
	locked_child = session.query(ChildProfile).filter(
		ChildProfile.id == child.id,
		ChildProfile.is_active.is_(True),
	).with_for_update().one_or_none()
	if locked_child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")

	Video = get_model("Video")
	video = session.query(Video).filter(
		Video.id == request.video_id,
		Video.is_published.is_(True),
		Video.content_rating.in_(["general", "educational"]),
	).one_or_none()
	if video is None:
		raise HTTPException(status_code=404, detail="Video not found")
	User = get_model("User")
	child_user = session.query(User).filter(User.id == locked_child.user_id).one()
	if video.language_code not in {child_user.preferred_language, "en"}:
		raise HTTPException(status_code=403, detail="Video language is not eligible for this child")
	age = child_age(locked_child)
	if not video.age_min <= age <= video.age_max:
		raise HTTPException(status_code=403, detail="Video is not eligible for this child")

	VideoWatchSession = get_model("VideoWatchSession")
	active_session = session.query(VideoWatchSession).filter(
		VideoWatchSession.child_id == child.id,
		VideoWatchSession.status == "active",
		VideoWatchSession.ended_at.is_(None),
	).with_for_update().one_or_none()
	if active_session is not None:
		if active_session.video_id != video.id or active_session.device_session_id != request.device_session_id:
			raise APIError(409, "playback_already_active", "Another playback session is active for this child")
		if active_session.entitlement_id != request.entitlement_id:
			raise APIError(409, "playback_already_active", "Another entitlement is active for this child")
		VideoAccessEntitlement = get_model("VideoAccessEntitlement")
		entitlement = session.query(VideoAccessEntitlement).filter(
			VideoAccessEntitlement.id == active_session.entitlement_id
		).with_for_update().one_or_none()
		if entitlement is None or entitlement.status != "active":
			raise APIError(403, "entitlement_unavailable", "Video access is no longer available")
		if _naive(entitlement.valid_from) > now:
			raise APIError(403, "entitlement_unavailable", "Video access is not valid yet")
		if entitlement.expires_at is not None and _naive(entitlement.expires_at) <= now:
			entitlement.status = "expired"
			active_session.status = "expired"
			active_session.ended_at = now
			session.commit()
			_revoke_provider_playback(active_session.id)
			locked_child = session.query(ChildProfile).filter(ChildProfile.id == child.id).with_for_update().one()
			active_session = None
		else:
			remaining = entitlement.granted_seconds - entitlement.consumed_seconds
			if remaining <= 0:
				entitlement.status = "exhausted"
				active_session.status = "completed"
				active_session.ended_at = now
				session.commit()
				_revoke_provider_playback(active_session.id)
				locked_child = session.query(ChildProfile).filter(ChildProfile.id == child.id).with_for_update().one()
				active_session = None
			elif not _matches_entitlement(session, entitlement, video.id):
				raise APIError(403, "entitlement_unavailable", "Video access is no longer available")
			else:
				provider = get_video_playback_provider()
				url = _issue_url(provider, video, active_session.id, now, remaining, entitlement.expires_at)
				return PlaybackSessionPublic(session_id=active_session.id, playback_url=url, remaining_seconds=remaining)

	VideoAccessEntitlement = get_model("VideoAccessEntitlement")
	entitlements = session.query(VideoAccessEntitlement).filter(
		VideoAccessEntitlement.id == request.entitlement_id,
		VideoAccessEntitlement.child_id == child.id,
		VideoAccessEntitlement.status == "active",
		VideoAccessEntitlement.valid_from <= now,
		(VideoAccessEntitlement.expires_at.is_(None)) | (VideoAccessEntitlement.expires_at > now),
	).with_for_update().all()
	entitlement = next(
		(item for item in entitlements if _matches_entitlement(session, item, video.id)),
		None,
	)
	if entitlement is None:
		raise HTTPException(status_code=403, detail="No valid entitlement for this video")
	remaining = entitlement.granted_seconds - entitlement.consumed_seconds
	if remaining <= 0:
		entitlement.status = "exhausted"
		session.commit()
		raise HTTPException(status_code=403, detail="Video access time has been exhausted")

	provider = get_video_playback_provider()
	session_id = uuid4()
	url = _issue_url(provider, video, session_id, now, remaining, entitlement.expires_at)
	watch = VideoWatchSession(
		id=session_id,
		child_id=child.id,
		video_id=video.id,
		entitlement_id=entitlement.id,
		started_at=now,
		last_heartbeat_at=now,
		ended_at=None,
		watched_seconds=0,
		status="active",
		device_session_id=request.device_session_id,
		created_at=now,
	)
	session.add(watch)
	session.commit()
	return PlaybackSessionPublic(session_id=session_id, playback_url=url, remaining_seconds=remaining)


def record_heartbeat(session: Session, child, session_id: UUID) -> PlaybackHeartbeatPublic:
	VideoWatchSession = get_model("VideoWatchSession")
	watch = session.query(VideoWatchSession).filter(
		VideoWatchSession.id == session_id,
		VideoWatchSession.child_id == child.id,
	).with_for_update().one_or_none()
	if watch is None:
		raise HTTPException(status_code=404, detail="Playback session not found")
	if watch.status != "active" or watch.ended_at is not None:
		raise APIError(409, "playback_not_active", "Playback session is not active")

	VideoAccessEntitlement = get_model("VideoAccessEntitlement")
	entitlement = session.query(VideoAccessEntitlement).filter(
		VideoAccessEntitlement.id == watch.entitlement_id
	).with_for_update().one_or_none()
	now = utc_naive(datetime.now(timezone.utc))
	if entitlement is None:
		watch.status = "blocked"
		watch.ended_at = now
		session.commit()
		raise HTTPException(status_code=403, detail="Video entitlement is unavailable")
	if entitlement.status != "active":
		watch.status = "blocked" if entitlement.status == "revoked" else "expired"
		watch.ended_at = now
		session.commit()
		raise HTTPException(status_code=403, detail="Video entitlement is no longer active")
	if entitlement.expires_at is not None and _naive(entitlement.expires_at) <= now:
		entitlement.status = "expired"
		watch.status = "expired"
		watch.ended_at = now
		session.commit()
		_revoke_provider_playback(session_id)
		raise HTTPException(status_code=403, detail="Video entitlement has expired")

	Video = get_model("Video")
	if not session.query(Video.id).filter(Video.id == watch.video_id, Video.is_published.is_(True)).first():
		watch.status = "blocked"
		watch.ended_at = now
		session.commit()
		_revoke_provider_playback(session_id)
		raise HTTPException(status_code=403, detail="Video is no longer published")

	previous_heartbeat = _naive(watch.last_heartbeat_at or watch.started_at)
	remaining = entitlement.granted_seconds - entitlement.consumed_seconds
	accepted = accepted_heartbeat_seconds(previous_heartbeat, now, remaining)
	entitlement.consumed_seconds += accepted
	watch.watched_seconds += accepted
	if accepted > 0:
		watch.last_heartbeat_at = now
	if entitlement.consumed_seconds >= entitlement.granted_seconds:
		entitlement.status = "exhausted"
		watch.status = "completed"
		watch.ended_at = now
	session.commit()
	if watch.status != "active":
		_revoke_provider_playback(session_id)
	return PlaybackHeartbeatPublic(
		session_id=watch.id,
		accepted_seconds=accepted,
		watched_seconds=watch.watched_seconds,
		remaining_seconds=max(0, entitlement.granted_seconds - entitlement.consumed_seconds),
		status=watch.status,
	)


def interrupt_playback(session: Session, child, session_id: UUID) -> PlaybackHeartbeatPublic:
	VideoWatchSession = get_model("VideoWatchSession")
	watch = session.query(VideoWatchSession).filter(
		VideoWatchSession.id == session_id,
		VideoWatchSession.child_id == child.id,
	).with_for_update().one_or_none()
	if watch is None:
		raise HTTPException(status_code=404, detail="Playback session not found")
	if watch.status != "active":
		raise APIError(409, "playback_not_active", "Playback session is not active")
	now = utc_naive(datetime.now(timezone.utc))
	watch.status = "interrupted"
	watch.ended_at = now
	VideoAccessEntitlement = get_model("VideoAccessEntitlement")
	entitlement = session.query(VideoAccessEntitlement).filter(
		VideoAccessEntitlement.id == watch.entitlement_id
	).one_or_none()
	session.commit()
	_revoke_provider_playback(session_id)
	remaining = max(0, entitlement.granted_seconds - entitlement.consumed_seconds) if entitlement else 0
	return PlaybackHeartbeatPublic(
		session_id=watch.id,
		accepted_seconds=0,
		watched_seconds=watch.watched_seconds,
		remaining_seconds=remaining,
		status=watch.status,
	)


def _revoke_provider_playback(session_id: UUID) -> None:
	try:
		get_video_playback_provider().revoke_playback(session_id)
	except Exception:
		logger.warning("Playback provider did not confirm session revocation")
