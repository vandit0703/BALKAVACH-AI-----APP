import logging
from datetime import datetime, timezone
from typing import Literal
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import case, exists, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, aliased

from app.core.exceptions import APIError
from app.db.base import get_model, has_model
from app.schemas.video import VideoCategoryCreate, VideoCollectionCreate, VideoCreate, VideoUpdate
from app.services.admin_service import record_audit
from app.services.video_classification import regular_clause, short_clause
from app.services.youtube_review_service import youtube_visibility_clause
from app.utils import utc_naive

logger = logging.getLogger(__name__)


def child_age(child) -> int | None:
	today = datetime.now(timezone.utc).date()
	date_of_birth = child.date_of_birth
	if date_of_birth is None or date_of_birth > today:
		return None
	return today.year - date_of_birth.year - (
		(today.month, today.day) < (date_of_birth.month, date_of_birth.day)
	)


def feed_languages(preferred_language: str) -> list[str]:
	"""Languages a child may see: their own, plus English."""
	return [preferred_language] if preferred_language == "en" else [preferred_language, "en"]


def feed_conditions(
	Video,
	VideoCategory,
	DuplicateYouTubeVideo,
	*,
	age: int,
	languages: list[str],
	child_id: UUID | None = None,
	category_id: UUID | None = None,
	video_format: Literal["short", "regular"] | None = None,
) -> list[tuple[str, object]]:
	"""Every rule that decides whether a video may be shown, in order, each with a stable name.

	This is the only definition of feed eligibility: ``eligible_feed`` applies all of it and
	``video_feed_diagnostics`` counts the videos that survive each step, so the two cannot disagree.
	The query must outer-join ``VideoCategory`` on ``Video.category_id``.
	"""
	conditions: list[tuple[str, object]] = [
		("published", Video.is_published.is_(True)),
		("age_band", (Video.age_min <= age) & (Video.age_max >= age)),
		("content_rating", Video.content_rating.in_(["general", "educational"])),
		("language", Video.language_code.in_(languages)),
		("active_category", or_(Video.category_id.is_(None), VideoCategory.is_active.is_(True))),
		# YouTube rows must be approved, rights-cleared, made for kids and re-verified recently.
		("youtube_approved_and_fresh", youtube_visibility_clause(Video)),
		(
			"not_a_duplicate",
			or_(
				Video.video_source != "youtube",
				~exists().where(
					DuplicateYouTubeVideo.video_source == "youtube",
					DuplicateYouTubeVideo.external_video_id == Video.external_video_id,
					DuplicateYouTubeVideo.id < Video.id,
				),
			),
		),
	]
	if video_format == "short":
		conditions.append(("format_short", short_clause(Video)))
	elif video_format == "regular":
		conditions.append(("format_regular", regular_clause(Video)))
	if category_id:
		conditions.append(("requested_category", Video.category_id == category_id))
	if child_id is not None and has_model("ChildVideoWatchHistory"):
		WatchHistory = get_model("ChildVideoWatchHistory")
		# Finished videos leave the feed unless a parent authorised a replay.
		conditions.append((
			"not_already_completed",
			or_(
				~exists().where(
					WatchHistory.child_id == child_id,
					WatchHistory.video_id == Video.id,
					WatchHistory.is_completed.is_(True),
				),
				exists().where(
					WatchHistory.child_id == child_id,
					WatchHistory.video_id == Video.id,
					WatchHistory.parent_replay_authorized.is_(True),
				),
			),
		))
	return conditions


def eligible_feed(
	session: Session,
	child,
	category_id: UUID | None,
	limit: int,
	offset: int,
	video_format: Literal["short", "regular"] | None = None,
):
	"""Videos this child may see. ``video_format`` splits the two feeds with the
	single rule in ``video_classification``: every eligible video is in exactly
	one of them."""
	User = get_model("User")
	user = session.query(User).filter(User.id == child.user_id).one()
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory")
	DuplicateYouTubeVideo = aliased(Video)
	age = child_age(child)
	if age is None or not 3 <= age <= 15:
		if offset == 0:
			logger.info(
				"videos.feed.empty",
				extra={"event": "videos.feed.empty", "stage": "child_age", "age": age, "video_format": video_format},
			)
		return []
	languages = feed_languages(user.preferred_language)
	conditions = feed_conditions(
		Video,
		VideoCategory,
		DuplicateYouTubeVideo,
		age=age,
		languages=languages,
		child_id=child.id,
		category_id=category_id,
		video_format=video_format,
	)
	query = session.query(Video).outerjoin(VideoCategory, VideoCategory.id == Video.category_id).filter(
		*[clause for _, clause in conditions]
	)
	partially_watched = None
	parent_replay = None
	if has_model("ChildVideoWatchHistory"):
		WatchHistory = get_model("ChildVideoWatchHistory")
		partially_watched = exists().where(
			WatchHistory.child_id == child.id,
			WatchHistory.video_id == Video.id,
			WatchHistory.is_completed.is_(False),
			WatchHistory.last_position_seconds > 0,
		)
		parent_replay = exists().where(
			WatchHistory.child_id == child.id,
			WatchHistory.video_id == Video.id,
			WatchHistory.is_completed.is_(True),
			WatchHistory.parent_replay_authorized.is_(True),
		)
	order = [
		case((Video.language_code == user.preferred_language, 0), else_=1),
		Video.display_order,
		Video.published_at.desc().nullslast(),
		Video.id,
	]
	if partially_watched is not None:
		order.insert(0, case((parent_replay, 2), (partially_watched, 1), else_=0))
	result = query.order_by(*order).offset(offset).limit(limit).all()
	if not result and offset == 0:
		# The first page of a feed is empty: say which rule removed the last candidates.
		from app.services.video_feed_diagnostics import funnel

		stages = funnel(
			session,
			age=age,
			languages=languages,
			child_id=child.id,
			category_id=category_id,
			video_format=video_format,
		)
		logger.info(
			"videos.feed.empty",
			extra={
				"event": "videos.feed.empty",
				"age": age,
				"video_format": video_format,
				"requested_category": str(category_id) if category_id else None,
				"limiting_stage": stages["limiting_stage"],
				**{f"stage_{row['stage']}": row["remaining"] for row in stages["stages"]},
			},
		)
	return result


def create_category(session: Session, actor, request: VideoCategoryCreate):
	VideoCategory = get_model("VideoCategory")
	category = VideoCategory(
		name=request.name.strip(),
		slug=request.slug,
		description=request.description,
		icon_url=str(request.icon_url) if request.icon_url else None,
		display_order=request.display_order,
		is_active=True,
	)
	try:
		session.add(category)
		session.flush()
		record_audit(session, actor.id, "video_category.created", "video_category", category.id, {"slug": request.slug})
		session.commit()
		session.refresh(category)
	except IntegrityError as error:
		session.rollback()
		raise APIError(409, "category_conflict", "A category with that name or slug already exists") from error
	return category


def create_video(session: Session, actor, request: VideoCreate):
	if request.video_source == "youtube":
		raise APIError(409, "youtube_requires_review", "Add YouTube videos through the YouTube review pipeline")
	if request.category_id:
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == request.category_id,
			VideoCategory.is_active.is_(True),
		).first():
			raise HTTPException(status_code=404, detail="Video category not found")
	Video = get_model("Video")
	video = Video(
		title=request.title.strip(),
		description=request.description,
		video_source=request.video_source,
		video_url=str(request.video_url),
		external_video_id=request.external_video_id,
		storage_key=request.storage_key,
		thumbnail_url=str(request.thumbnail_url) if request.thumbnail_url else None,
		duration_seconds=request.duration_seconds,
		category_id=request.category_id,
		language_code=request.language_code,
		age_min=request.age_min,
		age_max=request.age_max,
		content_rating=request.content_rating,
		is_published=False,
		display_order=request.display_order,
		uploaded_by=actor.id,
	)
	session.add(video)
	session.flush()
	record_audit(session, actor.id, "video.created", "video", video.id, {"title": video.title})
	session.commit()
	session.refresh(video)
	return video


def update_video(session: Session, actor, video_id: UUID, request: VideoUpdate):
	Video = get_model("Video")
	video = session.query(Video).filter(Video.id == video_id).with_for_update().one_or_none()
	if video is None:
		raise HTTPException(status_code=404, detail="Video not found")
	changes = request.model_dump(exclude_unset=True)
	if video.video_source == "youtube" and set(changes) & {"video_url", "external_video_id", "storage_key"}:
		raise APIError(409, "youtube_requires_review", "A YouTube video's source is fixed by the review pipeline")
	min_age = changes.get("age_min", video.age_min)
	max_age = changes.get("age_max", video.age_max)
	if min_age is not None and max_age is not None and max_age < min_age:
		raise APIError(422, "invalid_age_range", "age_max must be at least age_min")
	required_fields = {
		"video_url",
		"duration_seconds",
		"language_code",
		"age_min",
		"age_max",
		"content_rating",
		"display_order",
	}
	if any(field in changes and changes[field] is None for field in required_fields):
		raise APIError(422, "invalid_video_update", "Required video fields cannot be null")
	if changes.get("category_id"):
		VideoCategory = get_model("VideoCategory")
		if not session.query(VideoCategory.id).filter(
			VideoCategory.id == changes["category_id"], VideoCategory.is_active.is_(True)
		).first():
			raise HTTPException(status_code=404, detail="Video category not found")
	for field in ("video_url", "thumbnail_url"):
		if field in changes and changes[field] is not None:
			changes[field] = str(changes[field])
	for field, value in changes.items():
		setattr(video, field, value)
	record_audit(session, actor.id, "video.updated", "video", video.id, {"fields": sorted(changes)})
	session.commit()
	session.refresh(video)
	return video


def set_video_published(session: Session, actor, video_id: UUID, published: bool):
	Video = get_model("Video")
	video = session.query(Video).filter(Video.id == video_id).with_for_update().one_or_none()
	if video is None:
		raise HTTPException(status_code=404, detail="Video not found")
	if video.video_source == "youtube" and published:
		raise APIError(409, "youtube_requires_review", "Approve YouTube videos through the YouTube review pipeline")
	video.is_published = published
	video.published_at = utc_naive(datetime.now(timezone.utc)) if published else None
	record_audit(
		session,
		actor.id,
		"video.published" if published else "video.unpublished",
		"video",
		video.id,
		{},
	)
	session.commit()
	session.refresh(video)
	return video


def publish_approved_youtube_video(session: Session, actor, review, video, reason: str) -> None:
	"""Publish only a reviewed, rights-cleared YouTube record."""
	if (
		video.video_source != "youtube"
		or review.status != "approved"
		or review.rights_status != "cleared"
		or review.made_for_kids is not True
		or review.screening_flags
		or video.content_rating not in {"general", "educational"}
	):
		raise APIError(409, "youtube_publication_ineligible", "YouTube publication eligibility checks did not pass")
	video.is_published = True
	video.published_at = utc_naive(datetime.now(timezone.utc))
	if hasattr(review, "publication_reason"):
		review.publication_reason = reason
	record_audit(
		session,
		actor.id,
		"youtube.video_published",
		"video",
		video.id,
		{"youtube_video_id": review.youtube_video_id, "publication_source": review.publication_source, "reason": reason},
	)


def create_collection(session: Session, actor, request: VideoCollectionCreate):
	VideoCollection = get_model("VideoCollection")
	collection = VideoCollection(
		name=request.name.strip(),
		description=request.description,
		language_code=request.language_code,
		age_min=request.age_min,
		age_max=request.age_max,
		is_published=False,
		created_by=actor.id,
	)
	session.add(collection)
	session.flush()
	record_audit(session, actor.id, "video_collection.created", "video_collection", collection.id, {})
	session.commit()
	session.refresh(collection)
	return collection


def add_collection_video(session: Session, actor, collection_id: UUID, video_id: UUID, display_order: int):
	VideoCollection = get_model("VideoCollection")
	Video = get_model("Video")
	collection = session.query(VideoCollection).filter(VideoCollection.id == collection_id).with_for_update().one_or_none()
	if collection is None:
		raise HTTPException(status_code=404, detail="Collection not found")
	if not session.query(Video.id).filter(Video.id == video_id, Video.is_published.is_(True)).first():
		raise HTTPException(status_code=404, detail="Published video not found")
	VideoCollectionItem = get_model("VideoCollectionItem")
	item = VideoCollectionItem(collection_id=collection_id, video_id=video_id, display_order=display_order)
	session.add(item)
	session.flush()
	record_audit(session, actor.id, "video_collection.item_added", "video_collection", collection_id, {"video_id": str(video_id)})
	try:
		session.commit()
		session.refresh(item)
	except IntegrityError as error:
		session.rollback()
		raise APIError(409, "video_already_in_collection", "Video is already in this collection") from error
	return item


def publish_collection(session: Session, actor, collection_id: UUID, published: bool):
	VideoCollection = get_model("VideoCollection")
	collection = session.query(VideoCollection).filter(
		VideoCollection.id == collection_id
	).with_for_update().one_or_none()
	if collection is None:
		raise HTTPException(status_code=404, detail="Collection not found")
	if published:
		VideoCollectionItem = get_model("VideoCollectionItem")
		if not session.query(VideoCollectionItem.id).filter(VideoCollectionItem.collection_id == collection_id).first():
			raise APIError(409, "empty_collection", "A collection must contain videos before publishing")
	collection.is_published = published
	record_audit(
		session,
		actor.id,
		"video_collection.published" if published else "video_collection.unpublished",
		"video_collection",
		collection.id,
		{},
	)
	session.commit()
	session.refresh(collection)
	return collection


def rank_next_videos(current, candidates, channels: dict, limit: int) -> list:
	"""Order already-eligible ``candidates`` as "up next" for ``current``.

	Pure scoring over existing fields only: same category (+3), same channel (+2, one
	channel never fills the whole list), same language (+1), a video the child already
	started (+1, so unfinished ones are offered again), then newest first. The caller
	supplies only videos the child is allowed to see, so this can never widen eligibility.
	"""
	own_channel = channels.get(current.id)
	scored = []
	for video in candidates:
		if video.id == current.id:
			continue
		score = 0
		if video.category_id is not None and video.category_id == current.category_id:
			score += 3
		if own_channel is not None and channels.get(video.id) == own_channel:
			score += 2
		if video.language_code == current.language_code:
			score += 1
		created = getattr(video, "created_at", None)
		scored.append((score, created, str(video.id), video))
	# Highest score first; among equals the newest, then a stable id order.
	scored.sort(key=lambda row: (row[1] is None, -(row[1].timestamp() if row[1] else 0), row[2]))
	scored.sort(key=lambda row: -row[0])

	picked, per_channel = [], {}
	for score, _created, _id, video in scored:
		channel = channels.get(video.id)
		if channel is not None and per_channel.get(channel, 0) >= max(2, limit // 2):
			continue
		picked.append(video)
		if channel is not None:
			per_channel[channel] = per_channel.get(channel, 0) + 1
		if len(picked) >= limit:
			break
	return picked
