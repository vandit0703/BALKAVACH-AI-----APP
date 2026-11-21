"""Android channel mapping, reward amounts in the approval push, and the daily-missions notification."""

import json
from datetime import datetime, timezone

import httpx
import pytest

from app.integrations.fcm import FcmProvider, android_channel_for
from app.services import push_service
from app.services.notification_service import notify_daily_missions_ready
from tests import sqlite_world as shared
from tests.approval_world import approval_db, make_family, make_submission  # noqa: F401
from tests.test_api_push import FakeProvider, _service_account


def _captured_message(notification_type):
    sent = []

    def handler(request: httpx.Request):
        if request.url.host != "fcm.googleapis.com":
            return httpx.Response(200, json={"access_token": "t", "expires_in": 3600})
        sent.append(json.loads(request.content)["message"])
        return httpx.Response(200, json={})

    fcm = FcmProvider(_service_account(), http_client=httpx.Client(transport=httpx.MockTransport(handler)))
    assert fcm.send("x" * 40, "T", "B", {"type": notification_type, "notification_id": "n"}) == "ok"
    return sent[0]


@pytest.mark.parametrize(
    "kind, channel",
    [
        ("daily_missions_ready", "balkavach_missions"),
        ("task_submitted", "balkavach_approvals"),
        ("task_resubmission_requested", "balkavach_approvals"),
        ("task_approved", "balkavach_rewards"),
        ("streak_at_risk", "balkavach_reminders"),
        ("parent_mode_locked", "balkavach_safety"),
        ("something_new", "balkavach_missions"),
    ],
)
def test_fcm_message_targets_the_android_channel_and_brand_icon(kind, channel):
    assert android_channel_for(kind) == channel
    android = _captured_message(kind)["android"]
    assert android["priority"] == "HIGH"
    assert android["notification"]["channel_id"] == channel
    assert android["notification"]["icon"] == "ic_stat_balkavach"


@pytest.fixture
def delivery(monkeypatch):
    fake = FakeProvider()
    monkeypatch.setattr(push_service, "get_push_notification_provider", lambda: fake)
    monkeypatch.setattr(push_service, "_runner", lambda fn: fn())
    return fake


def _deliver_with(session, monkeypatch):
    class _Factory:
        def __enter__(self):
            return session

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr(push_service, "_session_factory", lambda: _Factory())
    push_service.deliver_ready(session)


def test_approval_push_states_the_stars_and_xp_the_server_recorded(approval_db, delivery, monkeypatch):
    family = make_family(approval_db)
    approval_db.add(shared.DeviceToken(user_id=family.child_user.id, token="c" * 40))
    item = make_submission(approval_db, family)
    from app.services.task_service import review_submission
    from app.schemas.task import TaskReviewCreate

    review_submission(approval_db, item.submission.id, family.parent, TaskReviewCreate(decision="approved"))
    _deliver_with(approval_db, monkeypatch)

    approved = [m for m in delivery.sent if m["data"]["type"] == "task_approved"]
    assert len(approved) == 1
    assert "10 Stars and 15 XP" in approved[0]["body"]
    assert set(approved[0]["data"]) == {"type", "notification_id"}
    assert "Saturday Rhythm Rockstar" not in json.dumps(approved[0])


def test_non_approval_push_keeps_the_generic_text(approval_db, delivery, monkeypatch):
    family = make_family(approval_db)
    approval_db.add(shared.DeviceToken(user_id=family.child_user.id, token="c" * 40))
    item = make_submission(approval_db, family)
    from app.services.task_service import review_submission
    from app.schemas.task import TaskReviewCreate

    review_submission(approval_db, item.submission.id, family.parent, TaskReviewCreate(decision="resubmission_requested"))
    _deliver_with(approval_db, monkeypatch)

    retry = [m for m in delivery.sent if m["data"]["type"] == "task_resubmission_requested"]
    assert len(retry) == 1 and "Stars" not in retry[0]["body"]


def test_approval_body_localises_amounts():
    for language in ("en", "hi", "gu"):
        for text in push_service.REWARD_TEXT.values():
            assert text[language].format(stars=10, xp=15)


def test_daily_missions_ready_is_created_once_per_local_day(approval_db):
    family = make_family(approval_db)
    now = datetime(2026, 11, 21, 9, 0, tzinfo=timezone.utc)
    assert notify_daily_missions_ready(approval_db, family.child, now) is not None
    approval_db.commit()
    assert notify_daily_missions_ready(approval_db, family.child, now) is None
    # Asia/Kolkata: 2026-11-21 20:00 UTC is already the 22nd locally.
    assert notify_daily_missions_ready(approval_db, family.child, datetime(2026, 11, 21, 20, 0, tzinfo=timezone.utc)) is not None
