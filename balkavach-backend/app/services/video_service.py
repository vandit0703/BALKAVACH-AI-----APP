from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import case, or_
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.video import VideoCategoryCreate, VideoCollectionCreate, VideoCreate, VideoUpdate
from app.services.admin_service import record_audit
from app.utils import utc_naive


def child_age(child) -> int:
	if child.date_of_birth is None:
		return 4
	today = datetime.now(timezone.utc).date()
	return max(0, today.year - child.date_of_birth.year - ((today.month, today.day) < (child.date_of_birth.month, child.date_of_birth.day)))


def eligible_feed(session: Session, child, category_id: UUID | None, limit: int, offset: int):
	User = get_model("User")
	user = session.query(User).filter(User.id == child.user_id).one()
	Video = get_model("Video")
	VideoCategory = get_model("VideoCategory")
	age = child_age(child)
	languages = [user.preferred_language]
	if user.preferred_language != "en":
		languages.append("en")
	query = session.query(Video).outerjoin(VideoCategory, VideoCategory.id == Video.category_id).filter(
		Video.is_published.is_(True),
		Video.age_min <= age,
		Video.age_max >= age,
		Video.content_rating.in_(["general", "educational"]),
		Video.language_code.in_(languages),
		or_(Video.category_id.is_(None), VideoCategory.is_active.is_(True)),
	)
	if category_id:
		query = query.filter(Video.category_id == category_id)
	return (
		query.order_by(
			case((Video.language_code == user.preferred_language, 0), else_=1),
			Video.display_order,
			Video.published_at.desc().nullslast(),
			Video.id,
		)
		.offset(offset)
		.limit(limit)
		.all()
	)


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
