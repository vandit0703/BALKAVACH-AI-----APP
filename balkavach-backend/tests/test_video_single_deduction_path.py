"""Mission/free allowance has one deduction path (record_progress); the session heartbeat never deducts it.

Mocked session, no database. The locked, concurrent behaviour needs PostgreSQL (TEST_DATABASE_URL).
"""

from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.services import video_access_service as svc
from app.utils import utc_naive


def _session_returning(*objects):
	"""session.query(...) hands out `objects` in call order for .one_or_none()/.first()."""
	queue = list(objects)

	def query(*_args):
		item = queue.pop(0)
		chain = MagicMock()
		for terminal in (chain.filter.return_value.with_for_update.return_value.one_or_none, chain.filter.return_value.first):
			terminal.return_value = item
		return chain

	session = MagicMock()
	session.query.side_effect = query
	return session


def _fixture(source_type, consumed=0):
	now = utc_naive(datetime.now(timezone.utc))
	child = SimpleNamespace(id=uuid4(), family_id=uuid4())
	entitlement = SimpleNamespace(
		id=uuid4(), source_type=source_type, status="active", granted_seconds=900, consumed_seconds=consumed,
		expires_at=now + timedelta(hours=5),
	)
	watch = SimpleNamespace(
		id=uuid4(), child_id=child.id, video_id=uuid4(), entitlement_id=entitlement.id, status="active", ended_at=None,
		started_at=now - timedelta(seconds=25), last_heartbeat_at=now - timedelta(seconds=25), watched_seconds=0,
	)
	return child, entitlement, watch


@pytest.fixture(autouse=True)
def no_provider(monkeypatch):
	monkeypatch.setattr(svc, "_revoke_provider_playback", lambda session_id: None)
	monkeypatch.setattr(svc, "get_model", lambda name: MagicMock())


def test_mission_heartbeat_never_deducts(monkeypatch):
	child, entitlement, watch = _fixture("mission_reward")
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: {"remaining_seconds": 500})
	session = _session_returning(watch, entitlement, object())
	result = svc.record_heartbeat(session, child, watch.id)
	assert result.accepted_seconds == 0
	assert result.remaining_seconds == 500
	assert result.status == "active"
	assert entitlement.consumed_seconds == 0
	assert watch.watched_seconds == 0


def test_repeated_heartbeats_cannot_accumulate_a_charge(monkeypatch):
	child, entitlement, watch = _fixture("mission_reward")
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: {"remaining_seconds": 500})
	for _ in range(5):
		svc.record_heartbeat(_session_returning(watch, entitlement, object()), child, watch.id)
	assert entitlement.consumed_seconds == 0


def test_mission_heartbeat_ends_the_session_at_zero_remaining_without_deducting(monkeypatch):
	child, entitlement, watch = _fixture("mission_reward")
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: {"remaining_seconds": 0})
	result = svc.record_heartbeat(_session_returning(watch, entitlement, object()), child, watch.id)
	assert result.status == "completed"
	assert result.remaining_seconds == 0
	assert entitlement.consumed_seconds == 0
	assert watch.ended_at is not None


def test_star_redemption_pool_still_uses_its_own_accounting(monkeypatch):
	"""Pre-existing separate pool (hosted reward video); deliberately not part of the mission allowance."""
	child, entitlement, watch = _fixture("star_redemption")
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: pytest.fail("must not be consulted"))
	result = svc.record_heartbeat(_session_returning(watch, entitlement, object()), child, watch.id)
	assert result.accepted_seconds == 25
	assert entitlement.consumed_seconds == 25
