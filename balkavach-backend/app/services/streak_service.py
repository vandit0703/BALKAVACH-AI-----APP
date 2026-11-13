"""BalKavach streak service – Phase 2 grace-period state machine.

This is the SOLE place that reads and writes ChildStreak rows.  All public
functions participate in the caller's transaction; none of them call
session.commit().

State machine
─────────────
  ACTIVE    last_activity_date == today (family-local).
            grace_deadline = NULL.
  AT_RISK   last_activity_date < today AND grace_deadline > now_utc.
            Countdown visible to parent / child.
  BROKEN    grace_deadline <= now_utc
              OR (grace_deadline IS NULL AND last_activity_date < (today − 2 days)).
            Streak count is reset on the next qualifying activity.
  RECOVERED child submits a qualifying activity while AT_RISK.
            Streak count is preserved and incremented; next state = ACTIVE.

Grace-deadline calculation
──────────────────────────
  grace_deadline = midnight of (last_activity_date + 3 days) in the family
  timezone, expressed as UTC.

  Example: last_activity 2026-11-10 in Asia/Kolkata
    → grace window ends at 2026-11-13T00:00:00+05:30
    → stored as         2026-11-12T18:30:00Z
"""

from __future__ import annotations

from datetime import date, datetime, time, timedelta, timezone
from typing import Any
from uuid import UUID
from zoneinfo import ZoneInfo

from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.timezone_service import (
    family_timezone_name,
    local_today,
    parse_timezone,
)
from app.utils import utc_aware, utc_naive

_GRACE_DAYS = 3


def _grace_deadline_utc(activity_date: date, tz: ZoneInfo) -> datetime:
    """Return the UTC-aware grace deadline for *activity_date* in *tz*.

    Grace deadline is midnight of (last_activity_date + 3 days) in family
    timezone, converted to UTC.
    """
    midnight_local = datetime.combine(
        activity_date + timedelta(days=_GRACE_DAYS), time.min, tzinfo=tz
    )
    return midnight_local.astimezone(timezone.utc)


def _now_utc(now_utc: datetime | None) -> datetime:
    if now_utc is None:
        return datetime.now(timezone.utc)
    return utc_aware(now_utc)


def compute_streak_state(
    session: Session,
    child_id: UUID,
    family_id: UUID,
    now_utc: datetime | None = None,
) -> dict:
    """Read-only: return the current streak state dict without writing anything.

    Used by GET endpoints that display streak info.
    """
    now = _now_utc(now_utc)
    try:
        today_local = local_today(session, family_id, now)
        tz_name = family_timezone_name(session, family_id)
        tz = parse_timezone(tz_name)
    except Exception:
        tz = ZoneInfo("UTC")
        today_local = now.astimezone(tz).date()

    ChildStreak = get_model("ChildStreak")
    streak = (
        session.query(ChildStreak)
        .filter(ChildStreak.child_id == child_id)
        .one_or_none()
    )

    if streak is None:
        return {
            "child_id": child_id,
            "current_streak": 0,
            "longest_streak": 0,
            "streak_state": "broken",
            "grace_deadline": None,
            "seconds_until_grace_expires": None,
            "last_activity_date": None,
            "last_activity_at": None,
        }

    last_date: date | None = streak.last_activity_date
    if last_date is None:
        return {
            "child_id": child_id,
            "current_streak": streak.current_streak or 0,
            "longest_streak": streak.longest_streak or 0,
            "streak_state": "broken",
            "grace_deadline": None,
            "seconds_until_grace_expires": None,
            "last_activity_date": None,
            "last_activity_at": (
                utc_aware(streak.last_activity_at).isoformat()
                if streak.last_activity_at
                else None
            ),
        }

    # If last activity was recorded today in family timezone -> ACTIVE
    if last_date == today_local:
        return {
            "child_id": child_id,
            "current_streak": streak.current_streak or 0,
            "longest_streak": streak.longest_streak or 0,
            "streak_state": "active",
            "grace_deadline": None,
            "seconds_until_grace_expires": None,
            "last_activity_date": last_date.isoformat(),
            "last_activity_at": (
                utc_aware(streak.last_activity_at).isoformat()
                if streak.last_activity_at
                else None
            ),
        }

    # If row is explicitly broken
    if getattr(streak, "streak_state", None) == "broken":
        return {
            "child_id": child_id,
            "current_streak": streak.current_streak or 0,
            "longest_streak": streak.longest_streak or 0,
            "streak_state": "broken",
            "grace_deadline": None,
            "seconds_until_grace_expires": None,
            "last_activity_date": last_date.isoformat(),
            "last_activity_at": (
                utc_aware(streak.last_activity_at).isoformat()
                if streak.last_activity_at
                else None
            ),
        }

    # last_date < today_local: compute grace deadline
    if streak.grace_deadline is not None:
        grace_dl = utc_aware(streak.grace_deadline)
    else:
        grace_dl = _grace_deadline_utc(last_date, tz)

    if grace_dl <= now:
        state = "broken"
        grace_dl_out = None
        seconds_until = None
    else:
        state = "at_risk"
        grace_dl_out = grace_dl.isoformat()
        seconds_until = max(0, int((grace_dl - now).total_seconds()))

    return {
        "child_id": child_id,
        "current_streak": streak.current_streak or 0,
        "longest_streak": streak.longest_streak or 0,
        "streak_state": state,
        "grace_deadline": grace_dl_out,
        "seconds_until_grace_expires": seconds_until,
        "last_activity_date": last_date.isoformat(),
        "last_activity_at": (
            utc_aware(streak.last_activity_at).isoformat()
            if streak.last_activity_at
            else None
        ),
    }


def record_qualifying_activity(
    session: Session,
    child_id: UUID,
    family_id: UUID,
    now_utc: datetime | None = None,
) -> dict:
    """Record a qualifying activity and update the ChildStreak row.

    Uses SELECT ... FOR UPDATE on the ChildStreak row for safe concurrent access.
    Idempotent: if last_activity_date == today (local), ensures state=active and
    returns existing streak count.

    Transitions:
      - If AT_RISK (grace not expired): recovered -> active, current_streak + 1.
      - If BROKEN or new: current_streak = 1, is_new_after_break = True.
      - If yesterday was last_activity_date: current_streak + 1, streak_extended = True.
      - Always longest_streak = max(longest_streak, current_streak).

    Returns:
      dict with: child_id, current_streak, longest_streak, streak_state,
                 grace_deadline, previous_state, streak_extended (bool),
                 is_new_after_break (bool).
    """
    now = _now_utc(now_utc)
    try:
        today_local = local_today(session, family_id, now)
        tz_name = family_timezone_name(session, family_id)
        tz = parse_timezone(tz_name)
    except Exception:
        tz = ZoneInfo("UTC")
        today_local = now.astimezone(tz).date()

    ChildStreak = get_model("ChildStreak")
    streak = (
        session.query(ChildStreak)
        .filter(ChildStreak.child_id == child_id)
        .with_for_update()
        .one_or_none()
    )

    if streak is None:
        # First-ever qualifying activity for this child
        streak = ChildStreak(
            child_id=child_id,
            current_streak=1,
            longest_streak=1,
            last_activity_date=today_local,
            last_activity_at=utc_naive(now),
            streak_state="active",
            grace_deadline=None,
            streak_notified_state=None,
            updated_at=utc_naive(now),
        )
        session.add(streak)
        return {
            "child_id": child_id,
            "current_streak": 1,
            "longest_streak": 1,
            "streak_state": "active",
            "grace_deadline": None,
            "previous_state": None,
            "streak_extended": False,
            "is_new_after_break": False,
        }

    last_date: date | None = streak.last_activity_date

    # Idempotent: already recorded today in family local date
    if last_date == today_local:
        prev = streak.streak_state or "active"
        streak.streak_state = "active"
        streak.grace_deadline = None
        streak.updated_at = utc_naive(now)
        return {
            "child_id": child_id,
            "current_streak": streak.current_streak,
            "longest_streak": streak.longest_streak,
            "streak_state": "active",
            "grace_deadline": None,
            "previous_state": prev,
            "streak_extended": False,
            "is_new_after_break": False,
        }

    # Evaluate whether grace expired prior to this submission
    if last_date is not None:
        if streak.grace_deadline is not None:
            grace_dl = utc_aware(streak.grace_deadline)
        else:
            grace_dl = _grace_deadline_utc(last_date, tz)
        is_grace_expired = now >= grace_dl
    else:
        is_grace_expired = True

    yesterday = today_local - timedelta(days=1)
    is_broken = (
        is_grace_expired
        or getattr(streak, "streak_state", None) == "broken"
        or (last_date is None)
    )

    if is_broken:
        # Broken streak restarted
        previous_state = "broken"
        new_streak = 1
        new_longest = max(streak.longest_streak or 0, 1)
        streak_extended = False
        is_new_after_break = True
        new_state = "active"
    elif last_date == yesterday:
        # Consecutive day extension
        previous_state = (
            streak.streak_state
            if streak.streak_state in ("active", "at_risk")
            else "active"
        )
        new_streak = (streak.current_streak or 0) + 1
        new_longest = max(streak.longest_streak or 0, new_streak)
        streak_extended = True
        is_new_after_break = False
        new_state = "active"
    else:
        # Missed at least 1 day, but within grace period: RECOVERED -> active
        previous_state = "at_risk"
        new_streak = (streak.current_streak or 0) + 1
        new_longest = max(streak.longest_streak or 0, new_streak)
        streak_extended = True
        is_new_after_break = False
        new_state = "active"

    streak.current_streak = new_streak
    streak.longest_streak = new_longest
    streak.last_activity_date = today_local
    streak.last_activity_at = utc_naive(now)
    streak.streak_state = new_state
    streak.grace_deadline = None
    streak.updated_at = utc_naive(now)

    return {
        "child_id": child_id,
        "current_streak": new_streak,
        "longest_streak": new_longest,
        "streak_state": new_state,
        "grace_deadline": None,
        "previous_state": previous_state,
        "streak_extended": streak_extended,
        "is_new_after_break": is_new_after_break,
    }


def get_streak_summary(session: Session, child_id: UUID) -> dict:
    """Return a serialisable streak summary for the given child.

    Includes countdown seconds so callers don't need to recompute it.
    """
    family_id: UUID | None = None
    try:
        ChildProfile = get_model("ChildProfile")
        child = (
            session.query(ChildProfile)
            .filter(ChildProfile.id == child_id)
            .one_or_none()
        )
        if child is not None:
            family_id = child.family_id
    except Exception:
        family_id = None

    if family_id is not None:
        return compute_streak_state(session, child_id, family_id)

    # Fallback if family_id is unavailable (e.g. mocked session in test)
    ChildStreak = get_model("ChildStreak")
    streak = (
        session.query(ChildStreak)
        .filter(ChildStreak.child_id == child_id)
        .one_or_none()
    )

    if streak is None:
        return {
            "child_id": child_id,
            "current_streak": 0,
            "longest_streak": 0,
            "streak_state": "broken",
            "grace_deadline": None,
            "seconds_until_grace_expires": None,
            "last_activity_date": None,
            "last_activity_at": None,
        }

    now = datetime.now(timezone.utc)
    grace_dl: datetime | None = None
    seconds_until: int | None = None

    if streak.grace_deadline is not None:
        grace_dl = utc_aware(streak.grace_deadline)
        if grace_dl > now:
            seconds_until = max(0, int((grace_dl - now).total_seconds()))

    state = getattr(streak, "streak_state", "active")
    if grace_dl is not None and grace_dl <= now:
        state = "broken"

    return {
        "child_id": child_id,
        "current_streak": streak.current_streak or 0,
        "longest_streak": streak.longest_streak or 0,
        "streak_state": state,
        "grace_deadline": grace_dl.isoformat() if (grace_dl and state == "at_risk") else None,
        "seconds_until_grace_expires": seconds_until if state == "at_risk" else None,
        "last_activity_date": (
            streak.last_activity_date.isoformat()
            if streak.last_activity_date
            else None
        ),
        "last_activity_at": (
            utc_aware(streak.last_activity_at).isoformat()
            if streak.last_activity_at
            else None
        ),
    }


def check_and_update_streak_states(
    session: Session,
    child_ids: list[UUID] | None = None,
) -> list[dict]:
    """Background-job entry point: batch-transition stale streak rows.

    Transitions:
      - AT_RISK -> BROKEN when grace_deadline <= now_utc.
      - ACTIVE  -> AT_RISK when last_activity_date < today (local) AND grace not expired.
      - ACTIVE  -> BROKEN  when last_activity_date < today (local) AND grace already expired.

    Returns a list of dicts: {"child_id": ..., "old_state": ..., "new_state": ...}
    for each changed row.
    """
    now = datetime.now(timezone.utc)
    now_naive = utc_naive(now)
    changes: list[dict] = []

    ChildStreak = get_model("ChildStreak")

    # 1. AT_RISK -> BROKEN (grace expired)
    at_risk_q = session.query(ChildStreak).filter(
        ChildStreak.streak_state == "at_risk",
    )
    if child_ids is not None:
        at_risk_q = at_risk_q.filter(ChildStreak.child_id.in_(child_ids))

    at_risk_rows = at_risk_q.all()
    for row in at_risk_rows:
        is_expired = False
        if row.grace_deadline is not None:
            is_expired = utc_aware(row.grace_deadline) <= now
        elif row.last_activity_date is not None:
            # Fallback if deadline missing
            is_expired = row.last_activity_date < (now.date() - timedelta(days=_GRACE_DAYS))

        if is_expired:
            changes.append(
                {"child_id": row.child_id, "old_state": "at_risk", "new_state": "broken"}
            )
            row.streak_state = "broken"
            row.grace_deadline = None
            row.updated_at = now_naive

    # 2. ACTIVE -> AT_RISK / BROKEN
    active_q = session.query(ChildStreak).filter(
        ChildStreak.streak_state == "active",
        ChildStreak.last_activity_date.isnot(None),
    )
    if child_ids is not None:
        active_q = active_q.filter(ChildStreak.child_id.in_(child_ids))

    active_rows = active_q.all()
    if not active_rows:
        return changes

    # Resolve family_id for all active rows
    family_map: dict[UUID, UUID] = {}
    active_child_ids = [row.child_id for row in active_rows]

    try:
        ChildProfile = get_model("ChildProfile")
        profiles = (
            session.query(ChildProfile.id, ChildProfile.family_id)
            .filter(ChildProfile.id.in_(active_child_ids))
            .all()
        )
        family_map = {p.id: p.family_id for p in profiles}
    except Exception:
        pass

    # Cache timezones per family_id
    tz_cache: dict[UUID, ZoneInfo] = {}

    for row in active_rows:
        fam_id = getattr(row, "family_id", None) or family_map.get(row.child_id)
        if fam_id is not None:
            if fam_id not in tz_cache:
                try:
                    tz_name = family_timezone_name(session, fam_id)
                    tz_cache[fam_id] = parse_timezone(tz_name)
                except Exception:
                    tz_cache[fam_id] = ZoneInfo("UTC")
            tz = tz_cache[fam_id]
        else:
            tz = ZoneInfo("UTC")

        today_local = now.astimezone(tz).date()
        if row.last_activity_date is None or not isinstance(row.last_activity_date, date):
            continue
        if row.last_activity_date >= today_local:
            continue

        grace_dl_utc = _grace_deadline_utc(row.last_activity_date, tz)
        if grace_dl_utc <= now:
            changes.append(
                {"child_id": row.child_id, "old_state": "active", "new_state": "broken"}
            )
            row.streak_state = "broken"
            row.grace_deadline = None
        else:
            changes.append(
                {"child_id": row.child_id, "old_state": "active", "new_state": "at_risk"}
            )
            row.streak_state = "at_risk"
            row.grace_deadline = utc_naive(grace_dl_utc)

        row.updated_at = now_naive

    return changes
