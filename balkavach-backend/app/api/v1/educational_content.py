from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.admin import EducationalContentPublic
from app.services.video_service import child_age
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
    the playback-session API. An admin-curated external link (for example a YouTube
    URL with no hosted video behind it) is just a link, so the child gets it.
    """
    if item.requires_entitlement:
        return False
    return not (item.video_id or item.collection_id)


@router.get("", response_model=list[EducationalContentPublic])
def list_educational_content(
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    child=Depends(require_child),
    session: Session = Depends(get_db),
) -> list[EducationalContentPublic]:
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
    for item in candidates:
        if item.requires_entitlement and not _has_active_entitlement(session, child.id, item):
            continue
        if item.video_id or item.collection_id:
            target = get_model("Video") if item.video_id else get_model("VideoCollection")
            target_id = item.video_id or item.collection_id
            conditions = [target.id == target_id, target.is_published.is_(True)]
            if item.video_id:
                conditions.append(youtube_visibility_clause(target))
            target_row = session.query(target).filter(*conditions).one_or_none()
            if target_row is None or not target_row.age_min <= age <= target_row.age_max:
                continue
        eligible.append(
            EducationalContentPublic(
                id=item.id,
                title=item.title,
                description=item.description,
                content_type=item.content_type,
                category_id=item.category_id,
                language_code=item.language_code,
                content_url=item.content_url if _may_expose_url(item) else None,
                thumbnail_url=item.thumbnail_url,
                video_id=item.video_id,
                collection_id=item.collection_id,
                requires_entitlement=item.requires_entitlement,
                is_active=item.is_active,
            )
        )
        if len(eligible) >= offset + limit:
            break
    return eligible[offset : offset + limit]