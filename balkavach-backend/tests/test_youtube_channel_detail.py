"""Trusted-channel detail/history built from existing tables only (mocked session, no database).

Suspension, sync timestamps and a stored status need new columns; they are deferred (see
docs/deferred-database-integration.md), so nothing here depends on them.
"""

from datetime import datetime
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.core.exceptions import APIError
from app.schemas.video import YouTubeTrustedChannelDetailPublic
from app.services import youtube_review_service as svc


class _Col:
	def __getattr__(self, name):
		return MagicMock()

	def __eq__(self, other):
		return True

	def __hash__(self):
		return 1

	def desc(self):
		return self


class _Model:
	def __getattr__(self, name):
		return _Col()


class _Query:
	"""Any chained call returns itself; terminals pop the next scripted answer."""

	def __init__(self, script):
		self._script = script

	def __getattr__(self, name):
		if name in {"one_or_none", "all", "count", "one", "first"}:
			return lambda *a, **k: self._script.pop(0)
		return lambda *a, **k: self

	def __iter__(self):
		return iter(())


def _session(*answers):
	script = list(answers)
	session = MagicMock()
	session.query.side_effect = lambda *a: _Query(script)
	return session


def _channel(active=True):
	return SimpleNamespace(
		id=uuid4(), channel_id="UC" + "a" * 22, channel_title="Kids", thumbnail_url=None, age_min=5, age_max=8,
		language_code="en", category_id=None, rights_status="cleared", is_active=active, created_by=None,
		created_at=datetime(2026, 11, 1), updated_at=datetime(2026, 11, 2), notes=None,
	)


@pytest.fixture(autouse=True)
def stubs(monkeypatch):
	monkeypatch.setattr(svc, "get_model", lambda name: _Model())
	monkeypatch.setattr(svc, "has_model", lambda name: True)
	monkeypatch.setattr(svc, "func", MagicMock())
	monkeypatch.setattr(svc, "short_clause", lambda Video: True)
	monkeypatch.setattr(svc, "regular_clause", lambda Video: True)


def test_status_is_derived_from_is_active():
	assert svc.channel_status(_channel(True)) == "approved"
	assert svc.channel_status(_channel(False)) == "revoked"


def test_detail_reports_counts_and_split_of_published_formats():
	channel = _channel()
	session = _session(
		channel,
		[("approved", 12), ("pending_review", 3), ("quarantined", 2), ("rejected", 1)],
		4,  # published shorts
		7,  # published regular
		(datetime(2026, 11, 18), datetime(2026, 11, 17)),
	)
	detail = svc.channel_detail(session, channel.channel_id)
	counts = detail["counts"]
	assert counts["discovered"] == 18
	assert counts["approved"] == 12
	assert counts["pending_review"] == 3
	assert counts["quarantined"] == 2
	assert counts["rejected"] == 1
	assert counts["published_shorts"] == 4 and counts["published_regular"] == 7 and counts["published"] == 11
	assert detail["status"] == "approved"
	public = YouTubeTrustedChannelDetailPublic(**detail)
	assert public.channel.channel_id == channel.channel_id
	assert public.last_verified_at == datetime(2026, 11, 17)


def test_a_channel_with_nothing_discovered_has_zero_counts():
	channel = _channel(active=False)
	detail = svc.channel_detail(_session(channel, [], 0, 0, (None, None)), channel.channel_id)
	assert detail["counts"]["discovered"] == 0
	assert detail["status"] == "revoked"
	assert detail["last_discovered_at"] is None


def test_unknown_channel_is_404_for_detail_and_history():
	for call in (svc.channel_detail, svc.channel_history):
		with pytest.raises(APIError) as error:
			call(_session(None), "UC" + "b" * 22)
		assert error.value.status_code == 404


def test_history_returns_the_audit_rows_for_that_channel():
	channel = _channel()
	rows = [SimpleNamespace(id=uuid4(), actor_user_id=None, action="youtube.channel_trusted",
		created_at=datetime(2026, 11, 1), details={"channel_id": channel.channel_id})]
	assert svc.channel_history(_session(channel, rows), channel.channel_id) == rows
