from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin_permission, require_child
from app.integrations.youtube import get_youtube_client
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.video import (
	CollectionItemCreate,
	ContentReportCreate,
	ContentReportPublic,
	ContentReportReceipt,
	ContentReportResolve,
	VideoAdminPublic,
	VideoCategoryCreate,
	VideoCategoryPublic,
	VideoCategoryUpdate,
	VideoCollectionCreate,
	VideoCreate,
	VideoFeedItem,
	VideoUpdate,
	YouTubeApproveRequest,
	YouTubeDiscoverRequest,
	YouTubeDiscoverResult,
	YouTubeImportRequest,
	YouTubeRecheckRequest,
	YouTubeRecheckResult,
	YouTubeReviewDecision,
	YouTubeReviewPublic,
	YouTubeReviewStatus,
	YouTubeRevokeRequest,
	YouTubeTrustedChannelPublic,
	YouTubeTrustedChannelRequest,
)
from app.services import youtube_review_service
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


SHORTS_MAX_SECONDS = 180


def _feed_item(video, channel_name: str | None = None) -> VideoFeedItem:
	is_youtube = video.video_source == "youtube"
	return VideoFeedItem(
		id=video.id,
		title=video.title,
		description=video.description,
		thumbnail_url=video.thumbnail_url,
		duration_seconds=video.duration_seconds,
		category_id=video.category_id,
		language_code=video.language_code,
		content_rating=video.content_rating,
		video_source=video.video_source,
		youtube_video_id=video.external_video_id if is_youtube else None,
		channel_name=channel_name if is_youtube else None,
	)


def _channel_names(session: Session, videos) -> dict[UUID, str]:
	if not videos:
		return {}
	Review = get_model("YouTubeContentReview")
	return {
		video_id: channel_name
		for video_id, channel_name in session.query(Review.video_id, Review.channel_title)
		.filter(
			Review.video_id.in_(video.id for video in videos),
			Review.channel_title.is_not(None),
		)
		.all()
		if channel_name
	}


@router.get("/feed", response_model=list[VideoFeedItem])
def video_feed(
	category_id: UUID | None = None,
	limit: int = Query(default=20, ge=1, le=50),
	offset: int = Query(default=0, ge=0, le=10_000),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	videos = eligible_feed(session, child, category_id, limit, offset)
	channels = _channel_names(session, videos) if any(video.video_source == "youtube" for video in videos) else {}
	return [_feed_item(video, channels.get(video.id)) for video in videos]


@router.get("/shorts", response_model=list[VideoFeedItem])
def video_shorts(
	category_id: UUID | None = None,
	limit: int = Query(default=20, ge=1, le=50),
	offset: int = Query(default=0, ge=0, le=10_000),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	videos = eligible_feed(session, child, category_id, limit, offset, max_duration_seconds=SHORTS_MAX_SECONDS)
	channels = _channel_names(session, videos) if any(video.video_source == "youtube" for video in videos) else {}
	return [_feed_item(video, channels.get(video.id)) for video in videos]


@router.post("/report", response_model=ContentReportReceipt, status_code=201)
def report_video(
	request: ContentReportCreate,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> ContentReportReceipt:
	"""Parents (or a child's device, behind the parent gate) flag a video for review."""
	if user.role not in {"parent", "child"}:
		raise HTTPException(status_code=403, detail="Parent or child access required")
	receipt = youtube_review_service.report_video(session, user, request.video_id, request.reason, request.details)
	return ContentReportReceipt(**receipt)


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


@admin_router.post("/youtube/discover", response_model=YouTubeDiscoverResult)
def admin_youtube_discover(
	request: YouTubeDiscoverRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeDiscoverResult:
	"""Search a fixed topic and store new results as unpublished review candidates."""
	return YouTubeDiscoverResult(**youtube_review_service.discover(session, admin, get_youtube_client(), request))


@admin_router.post("/youtube/import", response_model=YouTubeReviewPublic, status_code=201)
def admin_youtube_import(
	request: YouTubeImportRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.import_video(session, admin, get_youtube_client(), request.url))


@admin_router.get("/youtube/channels", response_model=list[YouTubeTrustedChannelPublic])
def admin_youtube_channels(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeTrustedChannelPublic]:
	return [
		YouTubeTrustedChannelPublic.model_validate(row)
		for row in youtube_review_service.list_trusted_channels(session, limit, offset)
	]


@admin_router.post("/youtube/channels/trust", response_model=YouTubeTrustedChannelPublic)
def admin_youtube_trust_channel(
	request: YouTubeTrustedChannelRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelPublic:
	return YouTubeTrustedChannelPublic.model_validate(youtube_review_service.trust_channel(session, admin, request))


@admin_router.post("/youtube/channels/{channel_id}/untrust", response_model=YouTubeTrustedChannelPublic)
def admin_youtube_untrust_channel(
	channel_id: str,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelPublic:
	return YouTubeTrustedChannelPublic.model_validate(youtube_review_service.untrust_channel(session, admin, channel_id))


@admin_router.get("/youtube/reviews", response_model=list[YouTubeReviewPublic])
def admin_youtube_reviews(
	status: YouTubeReviewStatus | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeReviewPublic]:
	return [YouTubeReviewPublic(**row) for row in youtube_review_service.list_reviews(session, status, limit, offset)]


@admin_router.post("/youtube/reviews/{review_id}/approve", response_model=YouTubeReviewPublic)
def admin_youtube_approve(
	review_id: UUID,
	request: YouTubeApproveRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.approve(session, admin, get_youtube_client(), review_id, request))


@admin_router.post("/youtube/reviews/{review_id}/reject", response_model=YouTubeReviewPublic)
def admin_youtube_reject(
	review_id: UUID,
	request: YouTubeReviewDecision,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.decide(session, admin, review_id, "rejected", request.notes))


@admin_router.post("/youtube/reviews/{review_id}/quarantine", response_model=YouTubeReviewPublic)
def admin_youtube_quarantine(
	review_id: UUID,
	request: YouTubeReviewDecision,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.decide(session, admin, review_id, "quarantined", request.notes))


@admin_router.post("/youtube/reviews/{review_id}/reopen", response_model=YouTubeReviewPublic)
def admin_youtube_reopen(
	review_id: UUID,
	request: YouTubeReviewDecision,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.decide(session, admin, review_id, "pending_review", request.notes))


@admin_router.post("/youtube/reviews/{review_id}/revoke", response_model=YouTubeReviewPublic)
def admin_youtube_revoke(
	review_id: UUID,
	request: YouTubeRevokeRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	"""Withdraw an approved video from every child feed immediately."""
	return YouTubeReviewPublic(**youtube_review_service.revoke(session, admin, review_id, request.reason))


@admin_router.post("/youtube/recheck", response_model=YouTubeRecheckResult)
def admin_youtube_recheck(
	request: YouTubeRecheckRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeRecheckResult:
	return YouTubeRecheckResult(**youtube_review_service.recheck(session, get_youtube_client(), request.limit, admin.id))


@admin_router.get("/reports", response_model=list[ContentReportPublic])
def admin_list_reports(
	status: str | None = Query(default="open", pattern="^(open|resolved|dismissed)$"),
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[ContentReportPublic]:
	rows = youtube_review_service.list_reports(session, status, limit, offset)
	return [ContentReportPublic.model_validate(row) for row in rows]


@admin_router.post("/reports/{report_id}/resolve", response_model=ContentReportPublic)
def admin_resolve_report(
	report_id: UUID,
	request: ContentReportResolve,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> ContentReportPublic:
	report = youtube_review_service.resolve_report(session, admin, report_id, request.status)
	return ContentReportPublic.model_validate(report)
