"""Parent allowance summary: figures are the lock's own figures plus the per-mission breakdown (mocked session)."""

from datetime import date, datetime, timezone
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

from app.services import video_entitlement_service as svc
from app.schemas.video import VideoAllowanceSummaryPublic


class _Col:
	"""Stands in for an ORM column: supports the comparisons the query builds."""

	def __getattr__(self, name):
		return MagicMock()

	def __eq__(self, other): return True
	def __ne__(self, other): return True
	def __ge__(self, other): return True
	def __lt__(self, other): return True
	def __hash__(self): return 1


class _Model:
	def __getattr__(self, name):
		return _Col()


def _allowance(child_id, family_id):
	return {
		"child_id": child_id, "family_id": family_id, "local_date": date(2026, 11, 19), "timezone": "UTC",
		"total_earned_today_seconds": 1800, "consumed_today_seconds": 600, "remaining_seconds": 1200,
		"daily_cap_seconds": 4500, "is_exhausted": False, "active_entitlements_count": 1,
	}


def test_summary_reuses_the_lock_figures_and_lists_missions(monkeypatch):
	child_id, family_id, task_id = uuid4(), uuid4(), uuid4()
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: _allowance(child_id, family_id))
	monkeypatch.setattr(svc, "get_model", lambda name: _Model())
	entitlement = SimpleNamespace(
		task_id=task_id, granted_seconds=900, consumed_seconds=300,
		granted_at=datetime(2026, 11, 19, 8, 0),
	)
	session = MagicMock()
	chain = session.query.return_value
	chain.outerjoin.return_value.filter.return_value.order_by.return_value.all.return_value = [(entitlement, "Tidy your room")]
	session.query.return_value.filter.return_value.scalar.return_value = 400

	summary = svc.get_child_allowance_summary(session, child_id, family_id)

	assert summary["remaining_seconds"] == 1200  # taken from the single calculation, not recomputed
	assert summary["free_allowance_seconds"] == 900
	assert summary["free_consumed_seconds"] == 400
	assert summary["mission_rewards"][0]["task_title"] == "Tidy your room"
	assert summary["mission_rewards"][0]["granted_at"].tzinfo is not None
	public = VideoAllowanceSummaryPublic(**summary)
	assert public.mission_rewards[0].granted_seconds == 900
	assert public.mission_rewards[0].consumed_seconds == 300


def test_free_consumed_never_exceeds_the_free_allowance(monkeypatch):
	child_id, family_id = uuid4(), uuid4()
	monkeypatch.setattr(svc, "get_child_video_allowance_today", lambda *a, **k: _allowance(child_id, family_id))
	monkeypatch.setattr(svc, "get_model", lambda name: _Model())
	session = MagicMock()
	session.query.return_value.outerjoin.return_value.filter.return_value.order_by.return_value.all.return_value = []
	session.query.return_value.filter.return_value.scalar.return_value = 99999
	assert svc.get_child_allowance_summary(session, child_id, family_id)["free_consumed_seconds"] == 900


def test_another_familys_parent_gets_404_and_no_summary(monkeypatch):
	import pytest
	from fastapi import HTTPException

	from app.api.v1 import video_access

	monkeypatch.setattr(video_access, "get_model", lambda name: _Model())
	monkeypatch.setattr(
		video_access, "get_child_allowance_summary", lambda *a, **k: pytest.fail("must not be computed")
	)
	session = MagicMock()
	session.query.return_value.join.return_value.filter.return_value.one_or_none.return_value = None
	with pytest.raises(HTTPException) as refused:
		video_access.get_child_video_summary(uuid4(), SimpleNamespace(id=uuid4()), session)
	assert refused.value.status_code == 404
