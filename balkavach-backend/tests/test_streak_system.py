"""Unit tests for the BalKavach daily streak system (Phase 2).

All tests are fully mocked — no live database or network connection is used.
Run with:  pytest -k test_streak  (from the balkavach-backend directory)
"""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta, timezone
from unittest.mock import MagicMock, patch
from zoneinfo import ZoneInfo

import pytest

from app.services.streak_service import (
    _grace_deadline_utc,
    check_and_update_streak_states,
    compute_streak_state,
    get_streak_summary,
    record_qualifying_activity,
)
from app.services.timezone_service import parse_timezone

# ---------------------------------------------------------------------------
# Helpers / constants
# ---------------------------------------------------------------------------

CHILD_A = uuid.uuid4()
CHILD_B = uuid.uuid4()
FAMILY_ID = uuid.uuid4()

NOW_BASE = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)
TODAY_UTC_DATE = NOW_BASE.date()  # 2026-11-10


def _make_streak(
    *,
    child_id=CHILD_A,
    current_streak: int = 0,
    longest_streak: int = 0,
    last_activity_date: date | None = None,
    last_activity_at: datetime | None = None,
    streak_state: str = "active",
    grace_deadline: datetime | None = None,
    streak_notified_state: str | None = None,
) -> MagicMock:
    """Return a MagicMock that looks like a ChildStreak ORM row."""
    row = MagicMock()
    row.child_id = child_id
    row.current_streak = current_streak
    row.longest_streak = longest_streak
    row.last_activity_date = last_activity_date
    row.last_activity_at = last_activity_at
    row.streak_state = streak_state
    row.grace_deadline = grace_deadline
    row.streak_notified_state = streak_notified_state
    return row


def _mock_session_with_streak(streak_row: MagicMock | None) -> MagicMock:
    """
    Build a mock Session whose .query().filter().with_for_update().one_or_none()
    chain returns streak_row (or None for a brand-new child).
    """
    session = MagicMock()
    q = session.query.return_value
    q.filter.return_value = q
    q.with_for_update.return_value = q
    q.one_or_none.return_value = streak_row
    q.first.return_value = streak_row
    q.all.return_value = [streak_row] if streak_row is not None else []
    return session


def _mock_family_timezone(tz_name: str = "UTC"):
    """
    Patch family_timezone_name in both streak_service and timezone_service.
    """
    return patch(
        "app.services.timezone_service.family_timezone_name",
        return_value=tz_name,
    )


# ---------------------------------------------------------------------------
# 1. First submission starts streak at 1
# ---------------------------------------------------------------------------


def test_first_submission_starts_streak_at_1():
    """Brand-new child with no prior streak row: first qualifying activity → streak = 1."""
    session = _mock_session_with_streak(None)  # no existing row

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_streak_cls = MagicMock()
        mock_get_model.return_value = mock_streak_cls

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["current_streak"] == 1
    assert result["streak_state"] == "active"
    assert result["is_new_after_break"] is False
    assert result["streak_extended"] is False


# ---------------------------------------------------------------------------
# 2. Same-day second submission does not increment
# ---------------------------------------------------------------------------


def test_same_day_second_submission_does_not_increment():
    """If last_activity_date == today (family local), streak must not go up again."""
    existing = _make_streak(
        current_streak=5,
        longest_streak=5,
        last_activity_date=date(2026, 11, 10),  # same as NOW_BASE local date in UTC
        streak_state="active",
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["current_streak"] == 5
    assert result["streak_extended"] is False


# ---------------------------------------------------------------------------
# 3. Consecutive day increments streak
# ---------------------------------------------------------------------------


def test_consecutive_day_increments_streak():
    """last_activity_date == yesterday → current_streak += 1."""
    yesterday = date(2026, 11, 9)
    existing = _make_streak(
        current_streak=4,
        longest_streak=4,
        last_activity_date=yesterday,
        streak_state="active",
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["current_streak"] == 5
    assert result["streak_extended"] is True


# ---------------------------------------------------------------------------
# 4. App open without submission does not affect streak (read-only check)
# ---------------------------------------------------------------------------


def test_app_open_without_submission_does_not_affect_streak():
    """
    get_streak_summary is read-only: calling it must NEVER write to the session.
    This covers the scenario where a child opens the app but submits no task.
    """
    existing = _make_streak(
        current_streak=3,
        longest_streak=7,
        last_activity_date=date(2026, 11, 9),
        streak_state="active",
        grace_deadline=None,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        summary = get_streak_summary(session, CHILD_A)

    session.add.assert_not_called()
    session.execute.assert_not_called()
    session.commit.assert_not_called()
    assert summary["current_streak"] == 3


# ---------------------------------------------------------------------------
# 5. One missed day sets at-risk state
# ---------------------------------------------------------------------------


def test_one_missed_day_sets_at_risk_state():
    """
    last_activity_date is 1 day ago and grace_deadline is in the future →
    compute_streak_state returns 'at_risk'.
    """
    grace = datetime(2026, 11, 12, 18, 30, tzinfo=timezone.utc)
    existing = _make_streak(
        current_streak=5,
        last_activity_date=date(2026, 11, 9),
        streak_state="at_risk",
        grace_deadline=grace,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = compute_streak_state(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["streak_state"] == "at_risk"
    assert result["current_streak"] == 5


# ---------------------------------------------------------------------------
# 6. Two missed days still at-risk (within grace window)
# ---------------------------------------------------------------------------


def test_two_missed_days_still_at_risk():
    """
    last_activity = 2 days ago, grace_deadline still in the future → still at_risk.
    """
    grace = datetime(2026, 11, 13, 0, 0, tzinfo=timezone.utc)  # future
    existing = _make_streak(
        current_streak=3,
        last_activity_date=date(2026, 11, 8),
        streak_state="at_risk",
        grace_deadline=grace,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = compute_streak_state(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["streak_state"] == "at_risk"


# ---------------------------------------------------------------------------
# 7. Three missed days breaks streak (grace expired)
# ---------------------------------------------------------------------------


def test_three_missed_days_breaks_streak():
    """
    last_activity = 3 days ago, grace_deadline < now → streak_state = 'broken'.
    """
    grace = datetime(2026, 11, 10, 6, 0, tzinfo=timezone.utc)  # past
    existing = _make_streak(
        current_streak=10,
        last_activity_date=date(2026, 11, 7),
        streak_state="at_risk",
        grace_deadline=grace,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = compute_streak_state(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["streak_state"] == "broken"


# ---------------------------------------------------------------------------
# 8. Return within grace period recovers streak
# ---------------------------------------------------------------------------


def test_return_within_grace_period_recovers_streak():
    """
    Child submits a task while in at_risk state and grace not expired →
    streak_state becomes 'active', streak count preserved + 1.
    """
    grace = datetime(2026, 11, 13, 0, 0, tzinfo=timezone.utc)  # future
    existing = _make_streak(
        current_streak=7,
        longest_streak=7,
        last_activity_date=date(2026, 11, 8),  # 2 days ago
        streak_state="at_risk",
        grace_deadline=grace,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["streak_state"] == "active"
    assert result["current_streak"] == 8  # preserved + 1
    assert result["previous_state"] == "at_risk"
    assert result["is_new_after_break"] is False
    assert result["streak_extended"] is True


# ---------------------------------------------------------------------------
# 9. Return after grace period starts new streak
# ---------------------------------------------------------------------------


def test_return_after_grace_period_starts_new_streak():
    """
    Child submits after grace_deadline has passed → streak resets to 1.
    """
    grace = datetime(2026, 11, 9, 0, 0, tzinfo=timezone.utc)  # past
    existing = _make_streak(
        current_streak=15,
        longest_streak=15,
        last_activity_date=date(2026, 11, 6),
        streak_state="broken",
        grace_deadline=grace,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["current_streak"] == 1
    assert result["streak_state"] == "active"
    assert result["is_new_after_break"] is True


# ---------------------------------------------------------------------------
# 10. Different family timezones
# ---------------------------------------------------------------------------


def test_different_family_timezones():
    """
    Same UTC moment (2026-11-10 20:00 UTC) is:
      - 2026-11-11 01:30 IST  (Asia/Kolkata, UTC+5:30) → next day
      - 2026-11-10 15:00 EST  (America/New_York, UTC-5) → same day

    If a child in Kolkata had last_activity_date=2026-11-10 (yesterday locally),
    the same UTC call records a consecutive day (3 -> 4).
    If a child in New_York had last_activity_date=2026-11-10 (today locally),
    the same UTC call is idempotent (stays 3).
    """
    now = datetime(2026, 11, 10, 20, 0, tzinfo=timezone.utc)

    # --- Kolkata child ---
    kolkata_streak = _make_streak(
        child_id=CHILD_A,
        current_streak=3,
        longest_streak=3,
        last_activity_date=date(2026, 11, 10),
        streak_state="active",
    )
    session_a = _mock_session_with_streak(kolkata_streak)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         patch("app.services.timezone_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.streak_service.family_timezone_name", return_value="Asia/Kolkata"):
        mock_get_model.return_value = MagicMock()

        result_a = record_qualifying_activity(session_a, CHILD_A, FAMILY_ID, now_utc=now)

    assert result_a["current_streak"] == 4
    assert result_a["streak_extended"] is True

    # --- New York child ---
    ny_streak = _make_streak(
        child_id=CHILD_B,
        current_streak=3,
        longest_streak=3,
        last_activity_date=date(2026, 11, 10),
        streak_state="active",
    )
    session_b = _mock_session_with_streak(ny_streak)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         patch("app.services.timezone_service.family_timezone_name", return_value="America/New_York"), \
         patch("app.services.streak_service.family_timezone_name", return_value="America/New_York"):
        mock_get_model.return_value = MagicMock()

        result_b = record_qualifying_activity(session_b, CHILD_B, FAMILY_ID, now_utc=now)

    assert result_b["current_streak"] == 3
    assert result_b["streak_extended"] is False


# ---------------------------------------------------------------------------
# 11. Delayed parent approval does not break existing streak (idempotency)
# ---------------------------------------------------------------------------


def test_delayed_parent_approval_does_not_break_existing_streak():
    """
    Parent approves a task. If child already has activity recorded today,
    record_qualifying_activity is idempotent and does not break or reset streak.
    """
    today = date(2026, 11, 10)
    existing = _make_streak(
        current_streak=6,
        longest_streak=6,
        last_activity_date=today,
        streak_state="active",
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        result = record_qualifying_activity(
            session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE
        )

    assert result["current_streak"] == 6
    assert result["streak_extended"] is False


# ---------------------------------------------------------------------------
# 12. Concurrent submissions handled safely
# ---------------------------------------------------------------------------


def test_concurrent_submissions_handled_safely():
    """
    Two sequential calls to record_qualifying_activity on the same day must both
    return the same streak count (idempotent).
    """
    today = date(2026, 11, 10)
    existing = _make_streak(
        current_streak=4,
        longest_streak=4,
        last_activity_date=today,
        streak_state="active",
    )

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        session1 = _mock_session_with_streak(existing)
        result1 = record_qualifying_activity(session1, CHILD_A, FAMILY_ID, now_utc=NOW_BASE)

        session2 = _mock_session_with_streak(existing)
        result2 = record_qualifying_activity(session2, CHILD_A, FAMILY_ID, now_utc=NOW_BASE)

    assert result1["current_streak"] == result2["current_streak"] == 4
    assert result1["streak_extended"] is False
    assert result2["streak_extended"] is False


# ---------------------------------------------------------------------------
# 13. Duplicate events are idempotent
# ---------------------------------------------------------------------------


def test_duplicate_events_idempotent():
    """
    Calling record_qualifying_activity multiple times with the same child/day
    must always return the same streak value.
    """
    today = date(2026, 11, 10)
    existing = _make_streak(
        current_streak=2,
        longest_streak=5,
        last_activity_date=today,
        streak_state="active",
    )

    results = []
    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        for _ in range(3):
            session = _mock_session_with_streak(existing)
            results.append(record_qualifying_activity(session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE))

    streaks = [r["current_streak"] for r in results]
    assert streaks == [2, 2, 2], f"Expected [2,2,2] but got {streaks}"


# ---------------------------------------------------------------------------
# 14. Multiple children do not affect each other
# ---------------------------------------------------------------------------


def test_multiple_children_do_not_affect_each_other():
    """
    Child B's submission must not change Child A's streak.
    """
    streak_a = _make_streak(
        child_id=CHILD_A,
        current_streak=10,
        longest_streak=10,
        last_activity_date=date(2026, 11, 10),
        streak_state="active",
    )

    session_a = _mock_session_with_streak(streak_a)
    session_b = _mock_session_with_streak(None)  # no existing row for child B

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        summary_a_before = get_streak_summary(session_a, CHILD_A)
        result_b = record_qualifying_activity(session_b, CHILD_B, FAMILY_ID, now_utc=NOW_BASE)
        summary_a_after = get_streak_summary(session_a, CHILD_A)

    assert summary_a_before["current_streak"] == 10
    assert summary_a_after["current_streak"] == 10
    assert result_b["current_streak"] == 1


# ---------------------------------------------------------------------------
# 15. Grace deadline calculated from family timezone
# ---------------------------------------------------------------------------


def test_grace_deadline_calculated_from_family_timezone():
    """
    Grace deadline = midnight of (last_activity_date + 3 days) in family TZ,
    expressed in UTC.

    Example from the spec:
      last_activity_date = 2026-11-10 in Asia/Kolkata
      grace_deadline     = 2026-11-13T00:00:00+05:30
                         = 2026-11-12T18:30:00Z
    """
    tz_kolkata = parse_timezone("Asia/Kolkata")
    activity_date = date(2026, 11, 10)
    deadline_utc = _grace_deadline_utc(activity_date, tz_kolkata)

    expected_utc = datetime(2026, 11, 12, 18, 30, tzinfo=timezone.utc)
    assert deadline_utc == expected_utc

    # Verify compute_streak_state uses this calculation
    existing = _make_streak(
        current_streak=5,
        last_activity_date=date(2026, 11, 9),
        streak_state="active",
        grace_deadline=None,
    )
    session = _mock_session_with_streak(existing)

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         patch("app.services.timezone_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.streak_service.family_timezone_name", return_value="Asia/Kolkata"):
        mock_get_model.return_value = MagicMock()

        # At 2026-11-10 12:00 UTC, last_activity 2026-11-09 is 1 day ago in Kolkata -> at_risk
        state_info = compute_streak_state(session, CHILD_A, FAMILY_ID, now_utc=NOW_BASE)

    assert state_info["streak_state"] == "at_risk"
    # Grace deadline for 2026-11-09 in Asia/Kolkata = 2026-11-12 00:00:00+05:30 -> 2026-11-11 18:30:00 UTC
    expected_dl = datetime(2026, 11, 11, 18, 30, tzinfo=timezone.utc).isoformat()
    assert state_info["grace_deadline"] == expected_dl


# ---------------------------------------------------------------------------
# 16. check_and_update transitions active → at_risk
# ---------------------------------------------------------------------------


def test_check_and_update_transitions_active_to_at_risk():
    """
    check_and_update_streak_states: child with streak_state='active' and
    last_activity_date < today (local) AND grace not yet expired →
    new state should be 'at_risk'.
    """
    now_dt = datetime.now(timezone.utc)
    # yesterday's activity
    yesterday = (now_dt - timedelta(days=1)).date()

    existing = _make_streak(
        current_streak=5,
        last_activity_date=yesterday,
        streak_state="active",
        grace_deadline=None,
    )
    session = _mock_session_with_streak(existing)
    session.query.return_value.filter.return_value.all.return_value = [existing]
    session.query.return_value.all.return_value = [existing]

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        changes = check_and_update_streak_states(session, child_ids=[CHILD_A])

    assert any(
        c.get("old_state") == "active" and c.get("new_state") == "at_risk"
        for c in changes
    ), f"Expected active→at_risk transition, got: {changes}"


# ---------------------------------------------------------------------------
# 17. check_and_update transitions at_risk → broken
# ---------------------------------------------------------------------------


def test_check_and_update_transitions_at_risk_to_broken():
    """
    check_and_update_streak_states: child with streak_state='at_risk' and
    grace_deadline <= now → new state should be 'broken'.
    """
    now_dt = datetime.now(timezone.utc)
    grace_expired = now_dt - timedelta(hours=2)

    existing = _make_streak(
        current_streak=8,
        last_activity_date=(now_dt - timedelta(days=4)).date(),
        streak_state="at_risk",
        grace_deadline=grace_expired,
    )
    session = _mock_session_with_streak(existing)
    session.query.return_value.filter.return_value.all.return_value = [existing]
    session.query.return_value.all.return_value = [existing]

    with patch("app.services.streak_service.get_model") as mock_get_model, \
         _mock_family_timezone("UTC"), \
         patch("app.services.streak_service.family_timezone_name", return_value="UTC"):
        mock_get_model.return_value = MagicMock()

        changes = check_and_update_streak_states(session, child_ids=[CHILD_A])

    assert any(
        c.get("old_state") == "at_risk" and c.get("new_state") == "broken"
        for c in changes
    ), f"Expected at_risk→broken transition, got: {changes}"
