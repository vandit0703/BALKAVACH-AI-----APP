"""Hosted-video entitlement checks must work on rows freshly loaded from PostgreSQL.

The existing integration tests keep the Python objects they inserted (naive
datetimes). A real request loads ``timestamptz`` columns, which psycopg returns as
timezone-aware values, and comparing those with a naive "now" raises TypeError.
"""

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.db.base import get_model
from app.schemas.video import PlaybackStartRequest
from app.services.video_access_service import record_heartbeat, start_playback
from app.utils import utc_naive
from tests.test_flows_integration import _seed_family, _seed_video


class _Provider:
    def issue_playback_url(self, video, session_id, expires_at):
        return f"https://media.example.test/{session_id}"

    def revoke_playback(self, session_id):
        return None


@pytest.fixture
def playback(isolated_test_session, monkeypatch):
    monkeypatch.setattr("app.services.video_access_service.get_video_playback_provider", lambda: _Provider())
    session = isolated_test_session
    parent, family, child, _ = _seed_family(session)
    video = _seed_video(session, parent.id)
    now = utc_naive(datetime.now(timezone.utc))
    Reward = get_model("Reward")
    Redemption = get_model("RedemptionRequest")
    Entitlement = get_model("VideoAccessEntitlement")
    reward = Reward(
        family_id=family.id, created_by=parent.id, name="Video time", reward_type="video_time", star_cost=1,
        video_id=video.id, access_duration_seconds=120, is_active=True,
    )
    session.add(reward)
    session.flush()
    redemption = Redemption(reward_id=reward.id, child_id=child.id, star_cost_at_request=1, status="fulfilled", requested_at=now)
    session.add(redemption)
    session.flush()
    entitlement = Entitlement(
        child_id=child.id, redemption_id=redemption.id, video_id=video.id, granted_seconds=120, consumed_seconds=0,
        granted_at=now, valid_from=now - timedelta(minutes=1), expires_at=now + timedelta(hours=1), status="active",
    )
    session.add(entitlement)
    session.commit()
    session.expire_all()  # force a real reload: timestamps now come back timezone-aware
    return session, child, video, entitlement.id


def test_start_playback_works_on_reloaded_rows(playback):
    session, child, video, entitlement_id = playback
    started = start_playback(
        session, child, PlaybackStartRequest(video_id=video.id, entitlement_id=entitlement_id, device_session_id=f"device-{uuid4()}")
    )
    assert started.remaining_seconds > 0
    assert str(started.playback_url).startswith("https://media.example.test/")


def test_heartbeat_works_on_reloaded_rows(playback):
    session, child, video, entitlement_id = playback
    started = start_playback(
        session, child, PlaybackStartRequest(video_id=video.id, entitlement_id=entitlement_id, device_session_id=f"device-{uuid4()}")
    )
    session.expire_all()
    beat = record_heartbeat(session, child, started.session_id)
    assert beat.accepted_seconds >= 0
