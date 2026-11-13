"""Mission-earned video access entitlement and daily allowance management.

Phase 3 Product Rules:
- Parent approval is mandatory before video time is granted.
- Each approved mission grants 900 seconds (15 minutes) of video access.
- Daily stacking is additive (15m, 30m, 45m, 60m).
- Default daily cap is 3,600 seconds (60 minutes), configurable up to 14,400 seconds (4 hours).
- The daily cap is enforced against the total mission allowance *granted today* in the
  family's local calendar day, NOT remaining balance. Consumed time does not create room.
- Idempotency is enforced by unique submission_id on video_access_entitlements.
"""

from datetime import datetime, timezone
import logging
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.timezone_service import (
    family_timezone_name,
    local_day_bounds_utc_naive,
    local_today,
    parse_timezone,
)
from app.utils import utc_naive

logger = logging.getLogger(__name__)

MISSION_REWARD_ALLOWANCE_SECONDS = 900  # 15 minutes per mission
DEFAULT_DAILY_ALLOWANCE_SECONDS = 3600  # 60 minutes default cap
MIN_DAILY_ALLOWANCE_SECONDS = 900  # 15 minutes minimum cap
MAX_DAILY_ALLOWANCE_SECONDS = 14400  # 4 hours maximum allowed cap


def get_daily_cap_seconds(session: Session, family_id: UUID) -> int:
    """Read and clamp the family's daily video allowance cap in seconds."""
    FamilySetting = get_model("FamilySetting")
    row = (
        session.query(FamilySetting.video_settings)
        .filter(FamilySetting.family_id == family_id)
        .first()
    )
    settings_dict = (row[0] or {}) if row else {}
    if not isinstance(settings_dict, dict):
        settings_dict = {}

    raw_cap = settings_dict.get("daily_limit_seconds")
    if raw_cap is None:
        raw_cap = settings_dict.get("default_daily_limit_seconds")

    if not isinstance(raw_cap, int) or isinstance(raw_cap, bool) or raw_cap <= 0:
        return DEFAULT_DAILY_ALLOWANCE_SECONDS

    return max(MIN_DAILY_ALLOWANCE_SECONDS, min(MAX_DAILY_ALLOWANCE_SECONDS, raw_cap))


def get_child_video_allowance_today(
    session: Session,
    child_id: UUID,
    family_id: UUID,
    now_utc: datetime | None = None,
) -> dict[str, Any]:
    """Calculate the child's mission video allowance for the family's local calendar day."""
    if now_utc is None:
        now_utc = datetime.now(timezone.utc)
    now_naive = utc_naive(now_utc)

    tz_name = family_timezone_name(session, family_id)
    zone = parse_timezone(tz_name)
    today = local_today(session, family_id, now_utc)
    start, end = local_day_bounds_utc_naive(zone, today, 1)

    VideoAccessEntitlement = get_model("VideoAccessEntitlement")
    entitlements = (
        session.query(VideoAccessEntitlement)
        .filter(
            VideoAccessEntitlement.child_id == child_id,
            VideoAccessEntitlement.source_type == "mission_reward",
            VideoAccessEntitlement.granted_at >= start,
            VideoAccessEntitlement.granted_at < end,
        )
        .order_by(VideoAccessEntitlement.granted_at.asc())
        .all()
    )

    total_earned = sum(int(e.granted_seconds or 0) for e in entitlements)
    total_consumed = sum(int(e.consumed_seconds or 0) for e in entitlements)
    remaining = max(0, total_earned - total_consumed)
    daily_cap = get_daily_cap_seconds(session, family_id)

    # If the local day has passed beyond `end`, any remaining allowance for today expires
    if now_naive >= end:
        remaining = 0

    return {
        "child_id": child_id,
        "family_id": family_id,
        "local_date": today,
        "timezone": tz_name,
        "total_earned_today_seconds": total_earned,
        "consumed_today_seconds": total_consumed,
        "remaining_seconds": remaining,
        "daily_cap_seconds": daily_cap,
        "is_exhausted": remaining <= 0,
        "active_entitlements_count": len(
            [e for e in entitlements if e.status == "active" and (e.consumed_seconds or 0) < (e.granted_seconds or 0)]
        ),
    }


def grant_mission_video_entitlement(
    session: Session,
    child,
    task,
    submission,
    now_utc: datetime | None = None,
) -> Any | None:
    """Grant video access time upon parent approval of a qualifying mission.

    Enforces:
    - Option B: parent approval check is verified by the caller.
    - Idempotency via submission_id.
    - Daily stacking cap against total mission allowance granted today.
    - End-of-local-day expiration.
    """
    if now_utc is None:
        now_utc = datetime.now(timezone.utc)
    now_naive = utc_naive(now_utc)

    VideoAccessEntitlement = get_model("VideoAccessEntitlement")

    # 1. Idempotency check: if entitlement already exists for this submission, return it
    existing = (
        session.query(VideoAccessEntitlement)
        .filter(VideoAccessEntitlement.submission_id == submission.id)
        .one_or_none()
    )
    if existing is not None:
        logger.info(
            "Video entitlement already exists for submission %s (child %s)",
            submission.id,
            child.id,
        )
        return existing

    # 2. Local calendar day boundaries
    tz_name = family_timezone_name(session, task.family_id)
    zone = parse_timezone(tz_name)
    today = local_today(session, task.family_id, now_utc)
    start, end = local_day_bounds_utc_naive(zone, today, 1)

    # 3. Sum total mission allowance granted today (strictly against daily cap)
    today_entitlements = (
        session.query(VideoAccessEntitlement)
        .filter(
            VideoAccessEntitlement.child_id == child.id,
            VideoAccessEntitlement.source_type == "mission_reward",
            VideoAccessEntitlement.granted_at >= start,
            VideoAccessEntitlement.granted_at < end,
        )
        .all()
    )
    total_granted_today = sum(int(e.granted_seconds or 0) for e in today_entitlements)

    # 4. Check remaining cap room
    daily_cap = get_daily_cap_seconds(session, task.family_id)
    cap_room = max(0, daily_cap - total_granted_today)
    grant_amount = min(MISSION_REWARD_ALLOWANCE_SECONDS, cap_room)

    if grant_amount <= 0:
        logger.info(
            "Child %s has reached daily video cap (%ss granted today of %ss cap)",
            child.id,
            total_granted_today,
            daily_cap,
        )
        return None

    # 5. Create new universal mission-earned entitlement
    entitlement = VideoAccessEntitlement(
        id=uuid4(),
        child_id=child.id,
        source_type="mission_reward",
        task_id=task.id,
        submission_id=submission.id,
        video_id=None,
        video_collection_id=None,
        granted_seconds=grant_amount,
        consumed_seconds=0,
        granted_at=now_naive,
        valid_from=now_naive,
        expires_at=end,
        status="active",
    )
    session.add(entitlement)
    session.flush()
    logger.info(
        "Granted %ss video allowance to child %s for approved mission %s",
        grant_amount,
        child.id,
        task.id,
    )
    return entitlement


def consume_video_allowance(
    session: Session,
    child_id: UUID,
    family_id: UUID,
    seconds_to_consume: int,
    now_utc: datetime | None = None,
) -> int:
    """Consume watch time against today's active mission-reward entitlements.

    Returns the actual number of seconds deducted.
    """
    if seconds_to_consume <= 0:
        return 0

    if now_utc is None:
        now_utc = datetime.now(timezone.utc)
    now_naive = utc_naive(now_utc)

    tz_name = family_timezone_name(session, family_id)
    zone = parse_timezone(tz_name)
    today = local_today(session, family_id, now_utc)
    start, end = local_day_bounds_utc_naive(zone, today, 1)

    VideoAccessEntitlement = get_model("VideoAccessEntitlement")
    active_entitlements = (
        session.query(VideoAccessEntitlement)
        .filter(
            VideoAccessEntitlement.child_id == child_id,
            VideoAccessEntitlement.source_type == "mission_reward",
            VideoAccessEntitlement.status == "active",
            VideoAccessEntitlement.granted_at >= start,
            VideoAccessEntitlement.granted_at < end,
            (VideoAccessEntitlement.expires_at.is_(None)) | (VideoAccessEntitlement.expires_at > now_naive),
        )
        .order_by(VideoAccessEntitlement.granted_at.asc())
        .with_for_update()
        .all()
    )

    remaining_to_consume = seconds_to_consume
    total_consumed = 0

    for ent in active_entitlements:
        ent_remaining = (ent.granted_seconds or 0) - (ent.consumed_seconds or 0)
        if ent_remaining <= 0:
            ent.status = "exhausted"
            continue

        deduct = min(remaining_to_consume, ent_remaining)
        ent.consumed_seconds = (ent.consumed_seconds or 0) + deduct
        total_consumed += deduct
        remaining_to_consume -= deduct

        if ent.consumed_seconds >= ent.granted_seconds:
            ent.status = "exhausted"

        if remaining_to_consume <= 0:
            break

    return total_consumed

