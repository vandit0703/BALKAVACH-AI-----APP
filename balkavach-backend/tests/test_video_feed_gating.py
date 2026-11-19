"""Feeds withhold playable ids at zero allowance (mocked service layer, no database)."""

from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.api.v1 import videos as videos_api


@pytest.fixture
def child():
	return SimpleNamespace(id=uuid4(), family_id=uuid4(), user_id=uuid4())


def set_allowance(monkeypatch, exhausted: bool):
	monkeypatch.setattr(
		videos_api,
		"get_child_video_allowance_today",
		lambda session, child_id, family_id: {"is_exhausted": exhausted},
	)


def fail_if_called(*args, **kwargs):
	raise AssertionError("feed query must not run while the allowance is exhausted")


def test_regular_feed_is_empty_and_unqueried_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	monkeypatch.setattr(videos_api, "eligible_feed", fail_if_called)
	assert videos_api.video_feed(None, 20, 0, child, MagicMock()) == []


def test_shorts_feed_is_empty_and_unqueried_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	monkeypatch.setattr(videos_api, "eligible_feed", fail_if_called)
	assert videos_api.video_shorts(None, 20, 0, child, MagicMock()) == []


def test_continue_watching_is_empty_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	monkeypatch.setattr(videos_api.video_watch_history_service, "list_child_history", fail_if_called)
	assert videos_api.continue_watching(20, child, MagicMock()) == []


def test_feeds_still_query_when_time_remains(monkeypatch, child):
	set_allowance(monkeypatch, False)
	calls = []
	monkeypatch.setattr(videos_api, "eligible_feed", lambda *a, **k: calls.append(k.get("video_format")) or [])
	assert videos_api.video_feed(None, 20, 0, child, MagicMock()) == []
	assert videos_api.video_shorts(None, 20, 0, child, MagicMock()) == []
	assert calls == ["regular", "short"]


def test_history_hides_youtube_ids_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	row = {
		"video_id": uuid4(),
		"title": "Counting",
		"description": None,
		"thumbnail_url": None,
		"duration_seconds": 120,
		"category_id": None,
		"language_code": "en",
		"video_source": "youtube",
		"youtube_video_id": "abc123XYZ00",
		"video_format": "regular",
		"started_at": "2026-11-19T00:00:00Z",
		"last_watched_at": "2026-11-19T00:00:00Z",
		"last_position_seconds": 5,
		"watch_duration_seconds": 5,
		"completion_percentage": 4,
		"is_completed": False,
	}
	monkeypatch.setattr(videos_api.video_watch_history_service, "list_child_history", lambda *a, **k: [dict(row)])
	result = videos_api.child_video_history(100, child, MagicMock())
	assert [item.youtube_video_id for item in result] == [None]

	set_allowance(monkeypatch, False)
	result = videos_api.child_video_history(100, child, MagicMock())
	assert [item.youtube_video_id for item in result] == ["abc123XYZ00"]
