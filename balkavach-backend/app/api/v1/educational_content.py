from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.db.base import get_model
from app.db.session import get_db
from app.integrations.youtube import parse_youtube_video_id
from app.schemas.admin import EducationalContentChildPublic
from app.services.video_entitlement_service import get_child_video_allowance_today
from app.services.video_service import child_age
from app.services.video_watch_history_service import find_eligible_video
from app.services.youtube_review_service import youtube_visibility_clause

router = APIRouter(prefix="/educational-content", tags=["educational content"])


def _has_active_entitlement(session: Session, child_id: UUID, content) -> bool:
    Entitlement = get_model("VideoAccessEntitlement")
    now = datetime.now(timezone.utc).replace(tzinfo=None)
    rows = session.query(Entitlement).filter(
        Entitlement.child_id == child_id,
        Entitlement.status == "active",
        Entitlement.valid_from <= now,
        (Entitlement.expires_at.is_(None)) | (Entitlement.expires_at > now),
        Entitlement.consumed_seconds < Entitlement.granted_seconds,
    ).all()
    for entitlement in rows:
        if content.video_id and entitlement.video_id == content.video_id:
            return True
        if content.collection_id and entitlement.video_collection_id == content.collection_id:
            return True
    return False


def _may_expose_url(item) -> bool:
    """A URL is shown unless playback must be authorised by the server.

    Hosted videos (a video/collection row) and entitlement-gated content go through
    the playback-session API, so they never carry a URL here. Curated external
    *video* links are further restricted by ``_metered_video`` below.
    """
    if item.requires_entitlement:
        return False
    return not (item.video_id or item.collection_id)


def _is_external_video_link(item) -> bool:
    return item.content_type == "video" and bool(item.content_url) and not (item.video_id or item.collection_id)


def _metered_video(session: Session, child, content_url: str):
    """The eligible catalogue video with the same YouTube id, or None.

    Video time is charged only by ``record_progress`` on a catalogue video, so a
    curated video link is playable only when it can be metered that way. Every
    feed eligibility rule applies (``find_eligible_video``)."""
    youtube_id = parse_youtube_video_id(content_url)
    if youtube_id is None:
        return None
    Video = get_model("Video")
    candidates = (
        session.query(Video.id)
        .filter(Video.video_source == "youtube", Video.external_video_id == youtube_id)
        .order_by(Video.id)
        .all()
    )
    for (video_id,) in candidates:
        video = find_eligible_video(session, child, video_id)
        if video is not None:
            return video
    return None


@router.get("", response_model=list[EducationalContentChildPublic])
def list_educational_content(
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    child=Depends(require_child),
    session: Session = Depends(get_db),
) -> list[EducationalContentChildPublic]:
    User = get_model("User")
    user = session.query(User).filter(User.id == child.user_id).one()
    language_codes = [user.preferred_language]
    if user.preferred_language != "en":
        language_codes.append("en")
    Content = get_model("EducationalContent")
    candidates = session.query(Content).filter(
        Content.is_active.is_(True),
        Content.language_code.in_(language_codes),
    ).order_by(Content.created_at.desc(), Content.id).all()
    eligible = []
    age = child_age(child)
    exhausted: bool | None = None  # read once, only if a metered video needs it
    for item in candidates:
        if item.requires_entitlement and not _has_active_entitlement(session, child.id, item):
            continue
        if item.video_id or item.collection_id:
            if age is None or not 4 <= age <= 15:
                continue
            target = get_model("Video") if item.video_id else get_model("VideoCollection")
            target_id = item.video_id or item.collection_id
            conditions = [target.id == target_id, target.is_published.is_(True)]
            if item.video_id:
                conditions.append(youtube_visibility_clause(target))
            target_row = session.query(target).filter(*conditions).one_or_none()
            if target_row is None or not target_row.age_min <= age <= target_row.age_max:
                continue
        expose_url = _may_expose_url(item)
        metered_video_id = None
        if expose_url and _is_external_video_link(item):
            video = _metered_video(session, child, item.content_url)
            if video is None:
                # Cannot be charged against the allowance: never handed out.
                expose_url = False
            else:
                metered_video_id = video.id
                if exhausted is None:
                    exhausted = bool(
                        get_child_video_allowance_today(session, child.id, child.family_id)["is_exhausted"]
                    )
                if exhausted:
                    # Same rule as the feeds: nothing playable at zero allowance.
                    expose_url = False
        eligible.append(
            EducationalContentChildPublic(
                id=item.id,
                title=item.title,
                description=item.description,
                content_type=item.content_type,
                category_id=item.category_id,
                language_code=item.language_code,
                content_url=item.content_url if expose_url else None,
                thumbnail_url=item.thumbnail_url,
                video_id=item.video_id,
                collection_id=item.collection_id,
                requires_entitlement=item.requires_entitlement,
                is_active=item.is_active,
                metered_video_id=metered_video_id,
            )
        )
        if len(eligible) >= offset + limit:
            break
    return eligible[offset : offset + limit]