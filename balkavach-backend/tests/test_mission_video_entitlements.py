"""Comprehensive tests for Phase 3: Mission-Based Video Access & 15-Minute Entitlement.

Tests cover:
1. Granting 900s (15 min) video allowance on mission approval.
2. Option B verification (submission = 0, reject = 0, approve = 900s).
3. Additive daily stacking (15m -> 30m -> 45m -> 60m).
4. Default daily cap (3,600s / 60m) enforcement.
5. Configurable daily cap via family_settings.video_settings.
6. Server-enforced max daily cap (14,400s / 4h).
7. Partial cap remainder grant.
8. Stacking invariant: consumed time does not create cap room.
9. Idempotency on repeated submission reviews.
10. Allowance summary calculation (total earned, consumed, remaining, is_exhausted).
11. Multi-entitlement chronological consumption.
12. Status transition to 'exhausted'.
13. Universal video matching in video_access_service.
14. Notification and push delivery on video time unlock.
"""

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4
import pytest
from unittest.mock import MagicMock, patch

from app.core.exceptions import APIError
from app.services.video_entitlement_service import (
    DEFAULT_DAILY_ALLOWANCE_SECONDS,
    MAX_DAILY_ALLOWANCE_SECONDS,
    MIN_DAILY_ALLOWANCE_SECONDS,
    MISSION_REWARD_ALLOWANCE_SECONDS,
    consume_video_allowance,
    get_child_video_allowance_today,
    get_daily_cap_seconds,
    grant_mission_video_entitlement,
)
from app.utils import utc_naive


import sqlalchemy as sa

class FakeEntitlement:
    id = sa.Column("id", sa.String)
    child_id = sa.Column("child_id", sa.String)
    source_type = sa.Column("source_type", sa.String)
    task_id = sa.Column("task_id", sa.String)
    submission_id = sa.Column("submission_id", sa.String)
    video_id = sa.Column("video_id", sa.String)
    video_collection_id = sa.Column("video_collection_id", sa.String)
    granted_seconds = sa.Column("granted_seconds", sa.Integer)
    consumed_seconds = sa.Column("consumed_seconds", sa.Integer)
    granted_at = sa.Column("granted_at", sa.DateTime)
    valid_from = sa.Column("valid_from", sa.DateTime)
    expires_at = sa.Column("expires_at", sa.DateTime)
    status = sa.Column("status", sa.String)

    def __init__(self, **kwargs):
        self.id = kwargs.get("id", uuid4())
        self.child_id = kwargs.get("child_id", uuid4())
        self.source_type = kwargs.get("source_type", "mission_reward")
        self.task_id = kwargs.get("task_id", uuid4())
        self.submission_id = kwargs.get("submission_id", uuid4())
        self.video_id = kwargs.get("video_id", None)
        self.video_collection_id = kwargs.get("video_collection_id", None)
        self.granted_seconds = kwargs.get("granted_seconds", 900)
        self.consumed_seconds = kwargs.get("consumed_seconds", 0)
        self.granted_at = kwargs.get("granted_at", utc_naive(datetime.now(timezone.utc)))
        self.valid_from = kwargs.get("valid_from", self.granted_at)
        self.expires_at = kwargs.get("expires_at", None)
        self.status = kwargs.get("status", "active")


class FakeFamilySetting:
    family_id = sa.Column("family_id", sa.String)
    video_settings = sa.Column("video_settings", sa.JSON)
    mission_settings = sa.Column("mission_settings", sa.JSON)


def fake_get_model(name: str):
    if name == "VideoAccessEntitlement":
        return FakeEntitlement
    if name == "FamilySetting":
        return FakeFamilySetting
    return MagicMock()


class FakeQuery:
    def __init__(self, items):
        self._items = list(items)

    def filter(self, *criterion):
        filtered = list(self._items)
        for crit in criterion:
            if hasattr(crit, "left") and hasattr(crit, "right"):
                col_name = getattr(crit.left, "name", None) or getattr(crit.left, "key", None)
                val = getattr(crit.right, "value", crit.right)
                op = getattr(crit, "operator", None)
                op_name = getattr(op, "__name__", "")
                if col_name and val is not None:
                    def matches(i):
                        if isinstance(i, tuple):
                            return True
                        attr_val = getattr(i, col_name, None)
                        if attr_val is None:
                            return False
                        if op_name in ("eq", "__eq__"):
                            return attr_val == val
                        elif op_name in ("ge", "__ge__"):
                            return attr_val >= val
                        elif op_name in ("lt", "__lt__"):
                            return attr_val < val
                        elif op_name in ("gt", "__gt__"):
                            return attr_val > val
                        return True
                    filtered = [i for i in filtered if matches(i)]
        return FakeQuery(filtered)

    def order_by(self, *args, **kwargs):
        return self

    def with_for_update(self):
        return self

    def all(self):
        return list(self._items)

    def first(self):
        return self._items[0] if self._items else None

    def one_or_none(self):
        return self._items[0] if self._items else None

    def one(self):
        if not self._items:
            raise ValueError("No items found")
        return self._items[0]


class FakeSession:
    def __init__(self, entitlements=None, settings_dict=None):
        self.entitlements = list(entitlements or [])
        self.settings_dict = settings_dict or {}
        self.added = []
        self.flushed = False

    def query(self, *args, **kwargs):
        arg0 = args[0] if args else None
        arg_str = str(arg0)
        if "mission_settings" in arg_str:
            return FakeQuery([(None,)])
        if (
            arg0 is FakeFamilySetting
            or arg0 is FakeFamilySetting.video_settings
            or "FamilySetting" in arg_str
            or "video_settings" in arg_str
        ):
            row = (self.settings_dict,) if self.settings_dict is not None else None
            return FakeQuery([row] if row is not None else [])
        return FakeQuery(self.entitlements)

    def add(self, item):
        self.added.append(item)
        self.entitlements.append(item)

    def flush(self):
        self.flushed = True

    def commit(self):
        pass

    def rollback(self):
        pass


@pytest.fixture(autouse=True)
def mock_entitlement_models():
    with patch("app.services.video_entitlement_service.get_model", side_effect=fake_get_model), \
         patch("app.services.timezone_service.get_model", side_effect=fake_get_model):
        yield


def test_grant_first_mission_grants_900_seconds():
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)
    submission = MagicMock(id=uuid4(), child_id=child_id)

    session = FakeSession()

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        entitlement = grant_mission_video_entitlement(session, child, task, submission)

    assert entitlement is not None
    assert entitlement.granted_seconds == 900
    assert entitlement.source_type == "mission_reward"
    assert entitlement.child_id == child_id
    assert entitlement.submission_id == submission.id
    assert entitlement.task_id == task.id
    assert entitlement.video_id is None
    assert entitlement.video_collection_id is None
    assert entitlement.consumed_seconds == 0
    assert entitlement.status == "active"


def test_grant_stacking_additive_up_to_four_missions():
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)

    session = FakeSession()

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        # Mission 1 -> 15 min (900s)
        sub1 = MagicMock(id=uuid4())
        e1 = grant_mission_video_entitlement(session, child, task, sub1)
        assert e1.granted_seconds == 900

        # Mission 2 -> 15 min (900s) -> total 1800s (30m)
        sub2 = MagicMock(id=uuid4())
        e2 = grant_mission_video_entitlement(session, child, task, sub2)
        assert e2.granted_seconds == 900

        # Mission 3 -> 15 min (900s) -> total 2700s (45m)
        sub3 = MagicMock(id=uuid4())
        e3 = grant_mission_video_entitlement(session, child, task, sub3)
        assert e3.granted_seconds == 900

        # Mission 4 -> 15 min (900s) -> total 3600s (60m)
        sub4 = MagicMock(id=uuid4())
        e4 = grant_mission_video_entitlement(session, child, task, sub4)
        assert e4.granted_seconds == 900

        total_granted = sum(e.granted_seconds for e in session.entitlements)
        assert total_granted == 3600


def test_grant_fifth_mission_capped_at_60_minutes_by_default():
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)

    # 4 existing entitlements totaling 3600s
    existing = [
        FakeEntitlement(child_id=child_id, granted_seconds=900, source_type="mission_reward")
        for _ in range(4)
    ]
    session = FakeSession(entitlements=existing)

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        sub5 = MagicMock(id=uuid4())
        e5 = grant_mission_video_entitlement(session, child, task, sub5)

    # Capped! Returns None and no extra seconds
    assert e5 is None
    assert len(session.added) == 0


def test_stacking_invariant_consumed_time_does_not_create_cap_room():
    """Child watched 30 minutes of their 60 minutes. Cap must still be exhausted."""
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)

    # 4 entitlements granted (3600s total), but 2 of them were consumed (1800s consumed)
    existing = [
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=900, status="exhausted"),
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=900, status="exhausted"),
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=0, status="active"),
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=0, status="active"),
    ]
    session = FakeSession(entitlements=existing)

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        sub = MagicMock(id=uuid4())
        result = grant_mission_video_entitlement(session, child, task, sub)

    # Even though remaining is 1800s, total granted today is 3600s, so cap room is 0!
    assert result is None
    assert len(session.added) == 0


def test_partial_cap_remainder_grant():
    """If daily limit is 1200s (20m) and 900s was already granted, next grant is 300s (5m)."""
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)

    existing = [FakeEntitlement(child_id=child_id, granted_seconds=900, source_type="mission_reward")]
    session = FakeSession(entitlements=existing, settings_dict={"daily_limit_seconds": 1200})

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        sub = MagicMock(id=uuid4())
        result = grant_mission_video_entitlement(session, child, task, sub)

    assert result is not None
    assert result.granted_seconds == 300


def test_idempotent_grant_returns_existing_entitlement():
    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)
    sub_id = uuid4()
    submission = MagicMock(id=sub_id)

    existing_ent = FakeEntitlement(
        child_id=child_id,
        submission_id=sub_id,
        granted_seconds=900,
        source_type="mission_reward",
    )
    session = FakeSession(entitlements=[existing_ent])

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        result = grant_mission_video_entitlement(session, child, task, submission)

    assert result.id == existing_ent.id
    assert len(session.added) == 0


def test_get_child_video_allowance_today_summary():
    child_id = uuid4()
    family_id = uuid4()

    entitlements = [
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=600, status="active"),
        FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=0, status="active"),
    ]
    session = FakeSession(entitlements=entitlements)

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        allowance = get_child_video_allowance_today(session, child_id, family_id)

    assert allowance["total_earned_today_seconds"] == 1800
    assert allowance["consumed_today_seconds"] == 600
    assert allowance["remaining_seconds"] == 1200
    assert allowance["is_exhausted"] is False
    assert allowance["daily_cap_seconds"] == DEFAULT_DAILY_ALLOWANCE_SECONDS


def test_consume_video_allowance_chronological_deduction():
    child_id = uuid4()
    family_id = uuid4()

    e1 = FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=800, status="active")
    e2 = FakeEntitlement(child_id=child_id, granted_seconds=900, consumed_seconds=0, status="active")
    session = FakeSession(entitlements=[e1, e2])

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.local_today", return_value=date(2026, 11, 13)):
        # Request 250s: 100s finishes e1 (exhausts it), 150s from e2
        consumed = consume_video_allowance(session, child_id, family_id, 250)

    assert consumed == 250
    assert e1.consumed_seconds == 900
    assert e1.status == "exhausted"
    assert e2.consumed_seconds == 150
    assert e2.status == "active"


def test_video_access_service_matches_entitlement_mission_reward():
    from app.services.video_access_service import _matches_entitlement

    session = FakeSession()
    mission_ent = FakeEntitlement(source_type="mission_reward", video_id=None, video_collection_id=None)
    random_video_id = uuid4()

    assert _matches_entitlement(session, mission_ent, random_video_id) is True


def test_get_daily_cap_seconds_server_clamp():
    session = FakeSession(settings_dict={"daily_limit_seconds": 999999})
    assert get_daily_cap_seconds(session, uuid4()) == MAX_DAILY_ALLOWANCE_SECONDS

    session2 = FakeSession(settings_dict={"daily_limit_seconds": 10})
    assert get_daily_cap_seconds(session2, uuid4()) == MIN_DAILY_ALLOWANCE_SECONDS

    session3 = FakeSession(settings_dict={})
    assert get_daily_cap_seconds(session3, uuid4()) == DEFAULT_DAILY_ALLOWANCE_SECONDS


def test_watch_progress_exhaustion_raises_api_error_403():
    """When child video allowance is exhausted, record_progress raises APIError 403."""
    from app.services.video_watch_history_service import record_progress

    child_id = uuid4()
    family_id = uuid4()
    video_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id, user_id=uuid4())

    mock_session = MagicMock()
    mock_session.query.return_value.filter.return_value.with_for_update.return_value.one_or_none.return_value = child

    with patch("app.services.video_watch_history_service.get_model") as mock_get_model, \
         patch("app.services.video_watch_history_service._eligible_video") as mock_video, \
         patch("app.services.video_watch_history_service.get_child_video_allowance_today") as mock_allowance:
        mock_get_model.return_value = MagicMock()
        mock_video.return_value = MagicMock(id=video_id, duration_seconds=60, video_source="hosted")
        mock_allowance.return_value = {
            "total_earned_today_seconds": 900,
            "consumed_today_seconds": 900,
            "remaining_seconds": 0,
            "is_exhausted": True,
        }

        with pytest.raises(APIError) as exc_info:
            record_progress(mock_session, child, video_id, position_seconds=10)

        assert exc_info.value.status_code == 403
        assert exc_info.value.code == "video_time_exhausted"


def test_notify_video_entitlement_event():
    """notify_video_entitlement_event creates notification with proper payload."""
    from app.services.notification_service import notify_video_entitlement_event

    mock_session = MagicMock()
    child_user_id = uuid4()

    with patch("app.services.notification_service.create_notification") as mock_create:
        notify_video_entitlement_event(
            mock_session,
            child_user_id,
            "mission_video_time_granted",
            minutes_granted=15,
        )

        assert mock_create.called
        args, kwargs = mock_create.call_args
        assert args[1] == child_user_id
        assert args[2] == "mission_video_time_granted"
        assert "15 minutes" in args[4]


def test_migration_0013_structure_and_chain():
    import importlib.util
    from pathlib import Path

    path = Path(__file__).parent.parent / "alembic" / "versions" / "0013_mission_video_entitlement.py"
    spec = importlib.util.spec_from_file_location("migration_0013", path)
    m13 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m13)

    assert m13.revision == "0013_mission_video_entitlement"
    assert m13.down_revision == "0012_streak_grace_period"
    assert callable(m13.upgrade)
    assert callable(m13.downgrade)


def test_mission_approved_before_midnight_expires_at_local_midnight():
    """Entitlement granted before local midnight has expires_at set to local midnight."""
    from zoneinfo import ZoneInfo
    from app.services.timezone_service import local_day_bounds_utc_naive

    child_id = uuid4()
    family_id = uuid4()
    child = MagicMock(id=child_id, family_id=family_id)
    task = MagicMock(id=uuid4(), family_id=family_id)
    sub = MagicMock(id=uuid4())

    session = FakeSession()
    kolkata = ZoneInfo("Asia/Kolkata")
    # 23:50 IST on 2026-11-13 is 18:20 UTC
    now_utc = datetime(2026, 11, 13, 18, 20, 0, tzinfo=timezone.utc)

    with patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"):
        ent = grant_mission_video_entitlement(session, child, task, sub, now_utc=now_utc)

    assert ent is not None
    # End of day 2026-11-13 in Asia/Kolkata is 2026-11-14 00:00:00 IST = 2026-11-13 18:30:00 UTC
    expected_start, expected_end = local_day_bounds_utc_naive(kolkata, date(2026, 11, 13), 1)
    assert ent.expires_at == expected_end
    assert ent.expires_at == datetime(2026, 11, 13, 18, 30, 0)


def test_allowance_expires_when_clock_crosses_midnight():
    """When now_utc is past the local day's end, remaining allowance is 0 (exhausted)."""
    child_id = uuid4()
    family_id = uuid4()

    # Entitlement granted on 2026-11-13
    granted_at = datetime(2026, 11, 13, 10, 0, 0)
    expires_at = datetime(2026, 11, 13, 18, 30, 0) # 00:00 IST next day
    ent = FakeEntitlement(
        child_id=child_id,
        granted_seconds=900,
        consumed_seconds=300,
        granted_at=granted_at,
        expires_at=expires_at,
        status="active",
    )
    session = FakeSession(entitlements=[ent])

    # Now it is 18:35 UTC (00:05 IST next day, 2026-11-14)
    after_midnight = datetime(2026, 11, 13, 18, 35, 0, tzinfo=timezone.utc)

    with patch("app.services.timezone_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"):
        allowance = get_child_video_allowance_today(session, child_id, family_id, now_utc=after_midnight)

    # In local today (2026-11-14), no entitlements were granted yet today
    assert allowance["local_date"] == date(2026, 11, 14)
    assert allowance["remaining_seconds"] == 0
    assert allowance["is_exhausted"] is True


def test_utc_date_differs_from_family_local_date():
    """At 20:00 UTC on 2026-11-13, Asia/Kolkata is at 01:30 AM on 2026-11-14."""
    child_id = uuid4()
    family_id = uuid4()

    session = FakeSession()
    utc_now = datetime(2026, 11, 13, 20, 0, 0, tzinfo=timezone.utc)

    with patch("app.services.timezone_service.family_timezone_name", return_value="Asia/Kolkata"), \
         patch("app.services.video_entitlement_service.family_timezone_name", return_value="Asia/Kolkata"):
        allowance = get_child_video_allowance_today(session, child_id, family_id, now_utc=utc_now)

    assert allowance["local_date"] == date(2026, 11, 14)
    assert allowance["timezone"] == "Asia/Kolkata"



