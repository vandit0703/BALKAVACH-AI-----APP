from uuid import UUID
import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_admin_permission, require_child, require_parent
from app.integrations.youtube import YouTubeError, get_youtube_client, to_api_error
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.video import (
        CollectionItemCreate,
        ContentReportCreate,
        ContentReportPublic,
        ContentReportReceipt,
        ContentReportResolve,
        UUID,
        VideoAdminPublic,
        VideoCategoryCreate,
        VideoCategoryPublic,
        VideoCategoryUpdate,
        VideoCollectionCreate,
        VideoCreate,
        VideoFeedItem,
        VideoUpdate,
        VideoWatchHistoryPublic,
        VideoWatchProgressPublic,
        VideoWatchProgressRequest,
        YouTubeApproveRequest,
        YouTubeApprovedPublishRequest,
        YouTubeApprovedPublishResult,
        YouTubeAutoReviewRequest,
        YouTubeAutoReviewResult,
        YouTubeChannelDiscoverMoreResult,
        YouTubeChannelDiscoveryPublic,
        YouTubeChannelDiscoveryRunPublic,
        YouTubeChannelVideosResult,
        YouTubeDiagnosticsPublic,
        YouTubeDiscoverRequest,
        YouTubeDiscoverResult,
        YouTubeImportRequest,
        YouTubeRecheckRequest,
        YouTubeRecheckResult,
        YouTubeReviewDecision,
        YouTubeReviewPublic,
        YouTubeReviewStatus,
        YouTubeRevokeRequest,
        YouTubeTrustedChannelDetailPublic,
        YouTubeTrustedChannelPublic,
        YouTubeTrustedChannelRequest,
        YouTubeTrustedChannelUpdateRequest,
)
from app.services import youtube_review_service
from app.services.video_classification import known_duration_or_none, video_format
from app.services.admin_service import record_audit
from app.services.video_service import (
	add_collection_video,
	create_category,
	create_collection,
	create_video,
	eligible_feed,
	rank_next_videos,
	publish_collection,
	set_video_published,
	update_video,
)
from app.services import video_watch_history_service
from app.services.video_entitlement_service import get_child_video_allowance_today

router = APIRouter(prefix="/videos", tags=["videos"])
admin_router = APIRouter(prefix="/admin/videos", tags=["admin videos"])
logger = logging.getLogger(__name__)


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


@router.get("/interests")
def my_video_interests(
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> dict:
	VideoCategory = get_model("VideoCategory")
	cats = (
		session.query(VideoCategory.slug, VideoCategory.name)
		.filter(VideoCategory.is_active.is_(True))
		.order_by(VideoCategory.display_order, VideoCategory.name)
		.all()
	)
	return {
		"interests": list(getattr(child, "interests", None) or []),
		"pending_requests": list(getattr(child, "pending_interest_requests", None) or []),
		"available_categories": [{"slug": str(slug), "name": str(name)} for slug, name in cats if slug],
	}


@router.post("/interests/request")
def request_video_interests(
	payload: dict,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> dict:
	"""Child submits interest change requests; parent approval is required before active interests change (DEC-04)."""
	raw = payload.get("interests")
	if not isinstance(raw, list):
		raise HTTPException(status_code=422, detail="interests must be a list")
	VideoCategory = get_model("VideoCategory")
	cats = (
		session.query(VideoCategory.slug, VideoCategory.name)
		.filter(VideoCategory.is_active.is_(True))
		.order_by(VideoCategory.display_order, VideoCategory.name)
		.all()
	)
	allowed = {str(slug).lower() for slug, _ in cats if slug}
	requested = list(dict.fromkeys(str(item).strip().lower() for item in raw if str(item).strip().lower() in allowed))
	if not hasattr(child, "pending_interest_requests"):
		# Schema without migration 0022: refuse rather than report a request
		# that was never stored.
		raise HTTPException(status_code=503, detail="Interest requests are not available yet")
	child.pending_interest_requests = requested
	session.commit()
	return {
		"interests": list(getattr(child, "interests", None) or []),
		"pending_requests": requested,
		"available_categories": [{"slug": str(slug), "name": str(name)} for slug, name in cats if slug],
	}


def _feed_item(
	video,
	channel_name: str | None = None,
	last_position_seconds: int = 0,
	playback_locked: bool = False,
) -> VideoFeedItem:
	is_youtube = video.video_source == "youtube"
	return VideoFeedItem(
		id=video.id,
		title=video.title,
		description=video.description,
		thumbnail_url=video.thumbnail_url,
		# Null when unknown (see video_classification); never a guess.
		duration_seconds=known_duration_or_none(video.video_source, video.duration_seconds),
		video_format=video_format(video.video_source, video.duration_seconds),
		category_id=video.category_id,
		language_code=video.language_code,
		content_rating=video.content_rating,
		video_source=video.video_source,
		youtube_video_id=video.external_video_id if is_youtube and not playback_locked else None,
		channel_name=channel_name if is_youtube else None,
		last_position_seconds=last_position_seconds,
		playback_locked=playback_locked,
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


def _resume_positions(session: Session, child, videos) -> dict[UUID, int]:
	if not videos:
		return {}
	WatchHistory = get_model("ChildVideoWatchHistory")
	return dict(
		session.query(WatchHistory.video_id, WatchHistory.last_position_seconds)
		.filter(
			WatchHistory.child_id == child.id,
			WatchHistory.video_id.in_(video.id for video in videos),
			WatchHistory.is_completed.is_(False),
		)
		.all()
	)


def _allowance_exhausted(session: Session, child) -> bool:
	"""True when the child has no video time left today (server-side, family-local day).

	The feeds still LIST the catalogue while this is true (browsing needs no approval and an
	empty Home would look broken), but playable identifiers (YouTube ids) are withheld and each
	item says ``playback_locked``, so the lock cannot be bypassed by calling the feed API
	directly instead of using the app screen. Playback itself is refused by the watch-history
	endpoint, which is the single place time is charged.
	"""
	return bool(get_child_video_allowance_today(session, child.id, child.family_id)["is_exhausted"])


def _feed_page(session: Session, child, videos, locked: bool) -> list[VideoFeedItem]:
	channels = _channel_names(session, videos) if any(video.video_source == "youtube" for video in videos) else {}
	positions = _resume_positions(session, child, videos)
	return [
		_feed_item(video, channels.get(video.id), positions.get(video.id, 0), playback_locked=locked)
		for video in videos
	]


@router.get("/feed", response_model=list[VideoFeedItem])
def video_feed(
	category_id: UUID | None = None,
	limit: int = Query(default=20, ge=1, le=50),
	offset: int = Query(default=0, ge=0, le=10_000),
	seed: str | None = Query(default=None, max_length=64),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	# Regular videos only: Shorts (1-60 s) have their own feed, so no video
	# appears in both.
	videos = eligible_feed(
		session, child, category_id, limit, offset, video_format="regular", seed=seed
	)
	return _feed_page(session, child, videos, _allowance_exhausted(session, child))


@router.get("/shorts", response_model=list[VideoFeedItem])
def video_shorts(
	category_id: UUID | None = None,
	limit: int = Query(default=20, ge=1, le=50),
	offset: int = Query(default=0, ge=0, le=10_000),
	seed: str | None = Query(default=None, max_length=64),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	videos = eligible_feed(
		session, child, category_id, limit, offset, video_format="short", seed=seed
	)
	return _feed_page(session, child, videos, _allowance_exhausted(session, child))


@router.get("/{video_id}/next", response_model=list[VideoFeedItem])
def next_videos(
	video_id: UUID,
	limit: int = Query(default=6, ge=1, le=12),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoFeedItem]:
	""""Up next" for a video the child just watched.

	Chosen only from what this child's feeds may already show, so eligibility, age,
	language, moderation and the daily allowance apply exactly as they do there: at zero
	allowance nothing playable is returned.
	"""
	if _allowance_exhausted(session, child):
		return []
	Video = get_model("Video")
	current = session.query(Video).filter(Video.id == video_id, Video.is_published.is_(True)).one_or_none()
	if current is None:
		raise HTTPException(status_code=404, detail="Video not found")
	same_format = video_format(current.video_source, current.duration_seconds)
	other_format = "regular" if same_format == "short" else "short"
	pool = eligible_feed(session, child, None, 60, 0, video_format=same_format)
	if len(pool) < limit + 1:
		pool = pool + eligible_feed(session, child, None, 30, 0, video_format=other_format)
	channels = _channel_names(session, pool + [current]) if any(v.video_source == "youtube" for v in pool) else {}
	ranked = rank_next_videos(current, pool, channels, limit)
	positions = _resume_positions(session, child, ranked)
	return [_feed_item(video, channels.get(video.id), positions.get(video.id, 0)) for video in ranked]


@router.post("/watch-history/{video_id}/progress", response_model=VideoWatchProgressPublic)
def record_video_progress(
	video_id: UUID,
	request: VideoWatchProgressRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> VideoWatchProgressPublic:
	return VideoWatchProgressPublic(**video_watch_history_service.record_progress(
		session, child, video_id, request.position_seconds, request.is_playing
	))


@router.get("/watch-history", response_model=list[VideoWatchHistoryPublic])
def child_video_history(
	limit: int = Query(default=100, ge=1, le=200),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoWatchHistoryPublic]:
	rows = video_watch_history_service.list_child_history(session, child.id, eligible_child=child, limit=limit)
	if _allowance_exhausted(session, child):
		rows = [{**row, "youtube_video_id": None} for row in rows]
	return [VideoWatchHistoryPublic(**row) for row in rows]


@router.get("/watch-history/continue-watching", response_model=list[VideoWatchHistoryPublic])
def continue_watching(
	limit: int = Query(default=20, ge=1, le=50),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[VideoWatchHistoryPublic]:
	rows = video_watch_history_service.list_child_history(
		session, child.id, continue_watching=True, eligible_child=child, limit=limit
	)
	if _allowance_exhausted(session, child):
		rows = [{**row, "youtube_video_id": None} for row in rows]
	return [VideoWatchHistoryPublic(**row) for row in rows]


def _require_parent_child(session: Session, parent, child_id: UUID):
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(
		ChildProfile.id == child_id,
		ChildProfile.is_active.is_(True),
	).one_or_none()
	if child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == child.family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Child profile not found")
	return child


@router.get("/watch-history/children/{child_id}", response_model=list[VideoWatchHistoryPublic])
def parent_video_history(
	child_id: UUID,
	limit: int = Query(default=100, ge=1, le=200),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[VideoWatchHistoryPublic]:
	child = _require_parent_child(session, parent, child_id)
	return [VideoWatchHistoryPublic(**row) for row in video_watch_history_service.list_child_history(
		session, child.id, limit=limit
	)]


@router.post("/watch-history/children/{child_id}/{video_id}/replay", status_code=204)
def parent_authorize_video_replay(
	child_id: UUID,
	video_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> None:
	child = _require_parent_child(session, parent, child_id)
	video_watch_history_service.authorize_replay(session, child.id, video_id)


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
	"""Search a fixed topic. Candidates that pass every automatic rule are approved and
	published; everything else is stored unpublished with the reason it is waiting."""
	return YouTubeDiscoverResult(**youtube_review_service.discover(
		session, admin, get_youtube_client(), request, auto_publish=True
	))


@admin_router.post("/youtube/import", response_model=YouTubeReviewPublic, status_code=201)
def admin_youtube_import(
	request: YouTubeImportRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.import_video(
		session, admin, get_youtube_client(), request.url, auto_publish=True
	))


@admin_router.get("/youtube/channels", response_model=list[YouTubeTrustedChannelPublic])
def admin_youtube_channels(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeTrustedChannelPublic]:
	return [
		YouTubeTrustedChannelPublic.model_validate(row)
		for row in youtube_review_service.list_trusted_channels(session, limit, offset, include_stats=True)
	]


@admin_router.get("/youtube/channels/discover", response_model=list[YouTubeChannelDiscoveryPublic])
def admin_youtube_discover_channels(
	query: str = Query(min_length=2, max_length=100),
	max_results: int = Query(default=10, ge=1, le=25),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeChannelDiscoveryPublic]:
	try:
		results = get_youtube_client().search_channels(query, max_results=max_results)
	except YouTubeError as error:
		raise to_api_error(error) from error
	Trusted = get_model("YouTubeTrustedChannel")
	trusted_ids = {
		row[0] for row in session.query(Trusted.channel_id).filter(Trusted.is_active.is_(True)).all()
	}
	return [
		YouTubeChannelDiscoveryPublic(**channel, is_trusted=channel["channel_id"] in trusted_ids)
		for channel in results
	]


@admin_router.get("/youtube/channels/{channel_id}", response_model=YouTubeTrustedChannelDetailPublic)
def admin_youtube_channel_detail(
	channel_id: str,
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelDetailPublic:
	"""One trusted channel with discovery counts and its derived status."""
	return YouTubeTrustedChannelDetailPublic(**youtube_review_service.channel_detail(session, channel_id))


@admin_router.patch("/youtube/channels/{channel_id}", response_model=YouTubeTrustedChannelPublic)
def admin_youtube_update_channel(
	channel_id: str,
	request: YouTubeTrustedChannelUpdateRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelPublic:
	channel = youtube_review_service.update_trusted_channel(session, admin, channel_id, request)
	# Return enriched/stats-aware representation for the updated channel.
	enriched = youtube_review_service.list_trusted_channels(session, 1, 0, include_stats=True)
	for row in enriched:
		if row.get("channel_id") == channel.channel_id:
			return YouTubeTrustedChannelPublic.model_validate(row)
	return YouTubeTrustedChannelPublic.model_validate(channel)


@admin_router.get("/youtube/channels/{channel_id}/videos", response_model=YouTubeChannelVideosResult)
def admin_youtube_channel_videos(
	channel_id: str,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	status: str | None = Query(default=None),
	video_format: str | None = Query(default=None, alias="format"),
	query: str | None = Query(default=None, min_length=1, max_length=100),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> YouTubeChannelVideosResult:
	return YouTubeChannelVideosResult(**youtube_review_service.list_channel_videos(
		session, channel_id, limit=limit, offset=offset, status=status, video_format_filter=video_format, query=query,
	))


@admin_router.post("/youtube/channels/{channel_id}/discover", response_model=YouTubeChannelDiscoverMoreResult)
def admin_youtube_discover_channel_more(
	channel_id: str,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeChannelDiscoverMoreResult:
	return YouTubeChannelDiscoverMoreResult(**youtube_review_service.discover_channel_more(
		session, admin, get_youtube_client(), channel_id, trigger="manual",
	))


@admin_router.get("/youtube/channels/{channel_id}/discovery-history", response_model=list[YouTubeChannelDiscoveryRunPublic])
def admin_youtube_channel_discovery_history(
	channel_id: str,
	limit: int = Query(default=50, ge=1, le=200),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeChannelDiscoveryRunPublic]:
	return [
		YouTubeChannelDiscoveryRunPublic.model_validate(row)
		for row in youtube_review_service.list_channel_discovery_runs(session, channel_id, limit)
	]


@admin_router.post("/youtube/channels/trust", response_model=YouTubeTrustedChannelPublic)
def admin_youtube_trust_channel(
	request: YouTubeTrustedChannelRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelPublic:
	channel = youtube_review_service.trust_channel(session, admin, request)
	try:
		discovery = youtube_review_service.discover_channel_more(
			session, admin, get_youtube_client(), channel.channel_id, trigger="trust",
		)
	except APIError:
		# Keep trust successful even if initial discovery cannot run; surface counts as unavailable.
		discovery = {"error": "initial_discovery_failed"}
	enriched = youtube_review_service.list_trusted_channels(session, 100, 0, include_stats=True)
	channel_data = None
	for row in enriched:
		if row.get("channel_id") == channel.channel_id:
			channel_data = dict(row)
			break
	if channel_data is None:
		channel_data = YouTubeTrustedChannelPublic.model_validate(channel).model_dump()
	channel_data["initial_discovery"] = discovery
	return YouTubeTrustedChannelPublic(**channel_data)


@admin_router.post("/youtube/channels/{channel_id}/untrust", response_model=YouTubeTrustedChannelPublic)
def admin_youtube_untrust_channel(
	channel_id: str,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeTrustedChannelPublic:
	channel = youtube_review_service.untrust_channel(session, admin, channel_id)
	enriched = youtube_review_service.list_trusted_channels(session, 100, 0, include_stats=True)
	for row in enriched:
		if row.get("channel_id") == channel_id:
			return YouTubeTrustedChannelPublic.model_validate(row)
	return YouTubeTrustedChannelPublic.model_validate(channel)


@admin_router.get("/youtube/reviews", response_model=list[YouTubeReviewPublic])
def admin_youtube_reviews(
	status: YouTubeReviewStatus | None = None,
	publication_source: str | None = Query(default=None, pattern="^(automatic|manual)$"),
	is_published: bool | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> list[YouTubeReviewPublic]:
	return [
		YouTubeReviewPublic(**row)
		for row in youtube_review_service.list_reviews(
			session, status, publication_source, is_published, limit, offset
		)
	]


@admin_router.get("/youtube/diagnostics", response_model=YouTubeDiagnosticsPublic)
def admin_youtube_diagnostics(
	admin=Depends(require_admin_permission("video:read")),
	session: Session = Depends(get_db),
) -> YouTubeDiagnosticsPublic:
	return YouTubeDiagnosticsPublic(**youtube_review_service.diagnostics(session))


@admin_router.post("/youtube/publish-approved", response_model=YouTubeApprovedPublishResult)
def admin_youtube_publish_approved(
	request: YouTubeApprovedPublishRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeApprovedPublishResult:
	return YouTubeApprovedPublishResult(**youtube_review_service.publish_approved_unpublished(
		session, admin, get_youtube_client(), request.limit, request.after_id
	))


@admin_router.post("/youtube/auto-review", response_model=YouTubeAutoReviewResult)
def admin_youtube_auto_review(
	request: YouTubeAutoReviewRequest,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeAutoReviewResult:
	"""Re-verify waiting and screening-quarantined videos; approve those that now qualify."""
	return YouTubeAutoReviewResult(**youtube_review_service.auto_review(
		session, admin, get_youtube_client(), request.limit, request.include_quarantined
	))


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


@admin_router.post("/youtube/reviews/{review_id}/reevaluate", response_model=YouTubeReviewPublic)
def admin_youtube_reevaluate(
	review_id: UUID,
	admin=Depends(require_admin_permission("video:write")),
	session: Session = Depends(get_db),
) -> YouTubeReviewPublic:
	return YouTubeReviewPublic(**youtube_review_service.reevaluate_quarantined(
		session, admin, get_youtube_client(), review_id
	))


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

