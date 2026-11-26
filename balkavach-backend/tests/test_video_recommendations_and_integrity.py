"""Focused tests for video allowance policy, reward integrity, recommendations, and account deletion."""

from types import SimpleNamespace
from uuid import uuid4

from alembic.config import Config
from alembic.script import ScriptDirectory

from app.services import video_entitlement_service as ves
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from app.services.video_service import _child_interest_slugs


def test_free_daily_allowance_is_zero():
	assert ves.FREE_DAILY_ALLOWANCE_SECONDS == 0
	assert ves.MISSION_REWARD_ALLOWANCE_SECONDS == 900


def test_mission_reward_constants():
	assert MISSION_STAR_REWARD == 10
	assert MISSION_XP_REWARD == 15


def test_child_interest_slugs_normalizes_and_handles_missing():
	assert _child_interest_slugs(SimpleNamespace(interests=["Science", " stories ", ""])) == {"science", "stories"}
	assert _child_interest_slugs(SimpleNamespace(interests=None)) == set()
	assert _child_interest_slugs(SimpleNamespace()) == set()


def test_alembic_single_head_includes_0022():
	cfg = Config("alembic.ini")
	script = ScriptDirectory.from_config(cfg)
	heads = script.get_heads()
	assert heads == ["0022_production_readiness"]
	rev_22 = script.get_revision("0022_production_readiness")
	assert rev_22.down_revision == "0021_quiz_system"


def test_create_task_ignores_client_reward_overrides(monkeypatch):
	from fastapi.testclient import TestClient
	from app.core.dependencies import require_parent
	from app.db.session import get_db
	from app.main import app
	import app.api.v1.tasks as task_routes

	captured = {}

	class FakeTask:
		def __init__(self, **kwargs):
			captured.update(kwargs)
			self.id = uuid4()
			self.family_id = kwargs["family_id"]
			self.category_id = kwargs["category_id"]
			self.created_by = kwargs["created_by"]
			self.assigned_child_id = kwargs["assigned_child_id"]
			self.title = kwargs["title"]
			self.description = kwargs["description"]
			self.star_reward = kwargs["star_reward"]
			self.xp_reward = kwargs["xp_reward"]
			self.required_video_seconds = kwargs["required_video_seconds"]
			self.due_at = kwargs["due_at"]
			self.is_active = True
			from datetime import datetime, timezone
			self.created_at = datetime.now(timezone.utc)

	class FakeQuery:
		def filter(self, *args, **kwargs):
			return self

		def first(self):
			return (uuid4(),)

	class FakeSession:
		def query(self, *args, **kwargs):
			return FakeQuery()

		def add(self, obj):
			pass

		def flush(self):
			pass

		def commit(self):
			pass

		def refresh(self, obj):
			pass

	monkeypatch.setattr(task_routes, "get_model", lambda name: FakeTask if name == "Task" else SimpleNamespace(id=1, family_id=1, user_id=1, is_active=SimpleNamespace(is_=lambda v: True)))
	monkeypatch.setattr(task_routes, "notify_task_assigned", lambda session, task: None)
	app.dependency_overrides[require_parent] = lambda: SimpleNamespace(id=uuid4(), role="parent")
	app.dependency_overrides[get_db] = lambda: FakeSession()
	try:
		client = TestClient(app)
		res = client.post(
			"/api/v1/tasks",
			json={
				"family_id": str(uuid4()),
				"title": "Clean desk",
				"star_reward": 9999,
				"xp_reward": 88888,
			},
		)
		assert res.status_code == 201
		assert captured["star_reward"] == 10
		assert captured["xp_reward"] == 15
	finally:
		app.dependency_overrides.clear()


def test_unused_video_allowance_carries_forward_across_midnight(monkeypatch):
	from datetime import datetime, timedelta, timezone
	from unittest.mock import MagicMock

	child_id = uuid4()
	family_id = uuid4()
	yesterday = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=1)
	entitlement = SimpleNamespace(
		id=uuid4(),
		child_id=child_id,
		source_type="mission_reward",
		granted_seconds=900,
		consumed_seconds=300,
		granted_at=yesterday,
		expires_at=None,
		status="active",
	)

	class FakeQuery:
		def __init__(self, result):
			self._result = result

		def filter(self, *args, **kwargs):
			return self

		def order_by(self, *args, **kwargs):
			return self

		def all(self):
			return self._result

		def scalar(self):
			return 0

	call_idx = {"n": 0}

	class FakeSession:
		def query(self, *args, **kwargs):
			idx = call_idx["n"]
			call_idx["n"] += 1
			if idx == 0:
				return FakeQuery([])  # today_entitlements
			if idx == 1:
				return FakeQuery([entitlement])  # active_entitlements (carry-forward)
			return FakeQuery([])

	class _Col:
		def __ge__(self, other): return self
		def __lt__(self, other): return self
		def __eq__(self, other): return self
		def asc(self): return self

	class _FakeModel:
		child_id = _Col()
		source_type = _Col()
		granted_at = _Col()
		status = _Col()
		consumed_seconds = _Col()
		granted_seconds = _Col()
		local_date = _Col()
		free_watched_seconds = _Col()

	monkeypatch.setattr(ves, "family_timezone_name", lambda session, fid: "UTC")
	monkeypatch.setattr(ves, "local_today", lambda session, fid, now: datetime.now(timezone.utc).date())
	monkeypatch.setattr(ves, "get_daily_cap_seconds", lambda session, fid: 3600)
	monkeypatch.setattr(ves, "get_model", lambda name: _FakeModel)

	summary = ves.get_child_video_allowance_today(FakeSession(), child_id, family_id)
	assert summary["remaining_seconds"] == 600
	assert summary["mission_remaining_seconds"] == 600
	assert summary["free_remaining_seconds"] == 0
	assert summary["is_exhausted"] is False


def test_child_cannot_bypass_parent_approval_on_interest_request(monkeypatch):
	from fastapi.testclient import TestClient
	from app.core.dependencies import require_child
	from app.db.session import get_db
	from app.main import app
	import app.api.v1.videos as video_routes

	child = SimpleNamespace(
		id=uuid4(),
		family_id=uuid4(),
		display_name="Mia",
		interests=["science"],
		pending_interest_requests=[],
	)

	class FakeQuery:
		def filter(self, *args, **kwargs):
			return self

		def order_by(self, *args, **kwargs):
			return self

		def all(self):
			return [("science", "Science"), ("stories", "Stories")]

		# The route re-reads the child's row under a lock before comparing the request.
		def with_for_update(self):
			return self

		def populate_existing(self):
			return self

		def one(self):
			return child

	class FakeSession:
		def query(self, *args, **kwargs):
			return FakeQuery()

		def commit(self):
			pass

	monkeypatch.setattr(
		video_routes,
		"get_model",
		lambda name: SimpleNamespace(id=1, slug=1, name=1, display_order=1, is_active=SimpleNamespace(is_=lambda v: True)),
	)
	# Parent notification is covered on PostgreSQL (tests/test_parent_interest_management_pg.py).
	import app.services.notification_service as notifications

	monkeypatch.setattr(notifications, "family_parent_ids", lambda session, family_id: [])
	app.dependency_overrides[require_child] = lambda: child
	app.dependency_overrides[get_db] = lambda: FakeSession()
	try:
		client = TestClient(app)
		res = client.post("/api/v1/videos/interests/request", json={"interests": ["stories", "unknown-slug"]})
		assert res.status_code == 200
		data = res.json()
		# Active interests stay ['science']; only pending_requests gets ['stories'].
		assert data["interests"] == ["science"]
		assert data["pending_requests"] == ["stories"]
		assert child.interests == ["science"]
	finally:
		app.dependency_overrides.clear()
