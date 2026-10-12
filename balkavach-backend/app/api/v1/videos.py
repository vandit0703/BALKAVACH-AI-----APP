from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin_permission, require_child
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.video import (
	CollectionItemCreate,
	VideoAdminPublic,
	VideoCategoryCreate,
	VideoCategoryPublic,
	VideoCategoryUpdate,
	VideoCollectionCreate,
	VideoCreate,
	VideoFeedItem,
	VideoUpdate,
)
from app.services.admin_service import record_audit
from app.services.video_service import (
	add_collection_video,
	create_category,
	create_collection,
	create_video,
	eligible_feed,
	publish_collection,
	set_video_published,
	update_video,
)

router = APIRouter(prefix="/videos", tags=["videos"])
admin_router = APIRouter(prefix="/admin/videos", tags=["admin videos"])


@router.get("/categories", response_model=list[VideoCategoryPublic])
def list_video_categories(
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoCategoryPublic]:
	VideoCategory = get_model("VideoCategory")
	categories = session.query(VideoCategory).filter(VideoCategory.is_active.is_(True)).order_by(
		VideoCategory.display_order, VideoCategory.name
	).all()
	return [VideoCategoryPublic.model_validate(category) for category in categories]


@router.get("/feed", response_model=list[VideoFeedItem])
def video_feed(
	category_id: UUID | None = None,
	limit: int = Query(default=20, ge=1, le=50),
	offset: int = Query(default=0, ge=0),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	videos = eligible_feed(session, child, category_id, limit, offset)
	return [
		VideoFeedItem(
			id=video.id,
			title=video.title,
			description=video.description,
			thumbnail_url=video.thumbnail_url,
			duration_seconds=video.duration_seconds,
			category_id=video.category_id,
			language_code=video.language_code,
			content_rating=video.content_rating,
		)
		for video in videos
	]


@admin_router.get("", response_model=list[VideoAdminPublic])
def admin_list_videos(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[VideoAdminPublic]:
	Video = get_model("Video")
	rows = session.query(Video).order_by(Video.created_at.desc(), Video.id).offset(offset).limit(limit).all()
	return [VideoAdminPublic.model_validate(video) for video in rows]


@admin_router.post("", response_model=VideoAdminPublic, status_code=201)
def admin_create_video(
	request: VideoCreate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoAdminPublic:
	return VideoAdminPublic.model_validate(create_video(session, admin, request))


@admin_router.patch("/{video_id}", response_model=VideoAdminPublic)
def admin_update_video(
	video_id: UUID,
	request: VideoUpdate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoAdminPublic:
	return VideoAdminPublic.model_validate(update_video(session, admin, video_id, request))


@admin_router.post("/{video_id}/publish", response_model=VideoAdminPublic)
def admin_publish_video(
	video_id: UUID,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoAdminPublic:
	return VideoAdminPublic.model_validate(set_video_published(session, admin, video_id, True))


@admin_router.post("/{video_id}/unpublish", response_model=VideoAdminPublic)
def admin_unpublish_video(
	video_id: UUID,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoAdminPublic:
	return VideoAdminPublic.model_validate(set_video_published(session, admin, video_id, False))


@admin_router.get("/categories", response_model=list[VideoCategoryPublic])
def admin_list_categories(
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[VideoCategoryPublic]:
	VideoCategory = get_model("VideoCategory")
	rows = session.query(VideoCategory).order_by(VideoCategory.display_order, VideoCategory.name).all()
	return [VideoCategoryPublic.model_validate(category) for category in rows]


@admin_router.post("/categories", response_model=VideoCategoryPublic, status_code=201)
def admin_create_category(
	request: VideoCategoryCreate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoCategoryPublic:
	return VideoCategoryPublic.model_validate(create_category(session, admin, request))


@admin_router.patch("/categories/{category_id}", response_model=VideoCategoryPublic)
def admin_update_category(
	category_id: UUID,
	request: VideoCategoryUpdate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> VideoCategoryPublic:
	VideoCategory = get_model("VideoCategory")
	category = session.query(VideoCategory).filter(VideoCategory.id == category_id).with_for_update().one_or_none()
	if category is None:
		raise HTTPException(status_code=404, detail="Video category not found")
	changes = request.model_dump(exclude_unset=True)
	if changes.get("icon_url") is not None:
		changes["icon_url"] = str(changes["icon_url"])
	for field, value in changes.items():
		setattr(category, field, value)
	record_audit(session, admin.id, "video_category.updated", "video_category", category.id, {"fields": sorted(changes)})
	try:
		session.commit()
		session.refresh(category)
	except IntegrityError as error:
		session.rollback()
		raise HTTPException(status_code=409, detail="A category with that name or slug already exists") from error
	return VideoCategoryPublic.model_validate(category)


@admin_router.post("/collections", status_code=201)
def admin_create_collection(
	request: VideoCollectionCreate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
):
	collection = create_collection(session, admin, request)
	return {"id": collection.id, "name": collection.name, "is_published": collection.is_published}


@admin_router.post("/collections/{collection_id}/items", status_code=201)
def admin_add_collection_item(
	collection_id: UUID,
	request: CollectionItemCreate,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
):
	item = add_collection_video(session, admin, collection_id, request.video_id, request.display_order)
	return {"id": item.id, "collection_id": item.collection_id, "video_id": item.video_id}


@admin_router.post("/collections/{collection_id}/publish")
def admin_publish_collection(
	collection_id: UUID,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
):
	collection = publish_collection(session, admin, collection_id, True)
	return {"id": collection.id, "is_published": collection.is_published}


@admin_router.post("/collections/{collection_id}/unpublish")
def admin_unpublish_collection(
	collection_id: UUID,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
):
	collection = publish_collection(session, admin, collection_id, False)
	return {"id": collection.id, "is_published": collection.is_published}
