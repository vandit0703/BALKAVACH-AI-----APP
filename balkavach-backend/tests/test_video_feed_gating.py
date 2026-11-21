"""Feeds keep listing videos at zero allowance but withhold playable ids (mocked service layer, no database)."""

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
	raise AssertionError("must not be called while the allowance is exhausted")


def fake_video(**fields):
	values = dict(
		id=uuid4(), title="Counting", description=None, thumbnail_url=None, duration_seconds=240, category_id=None,
		language_code="en", content_rating="educational", video_source="youtube", external_video_id="abc123XYZ00",
	)
	values.update(fields)
	return SimpleNamespace(**values)


def stub_queries(monkeypatch, videos):
	monkeypatch.setattr(videos_api, "eligible_feed", lambda *a, **k: list(videos))
	monkeypatch.setattr(videos_api, "_channel_names", lambda s, v: {})
	monkeypatch.setattr(videos_api, "_resume_positions", lambda s, c, v: {})


def test_regular_feed_still_lists_videos_but_locks_them_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	stub_queries(monkeypatch, [fake_video()])
	items = videos_api.video_feed(None, 20, 0, child, MagicMock())
	assert [item.title for item in items] == ["Counting"]
	assert items[0].playback_locked is True and items[0].youtube_video_id is None


def test_shorts_feed_still_lists_videos_but_locks_them_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	stub_queries(monkeypatch, [fake_video(duration_seconds=30)])
	items = videos_api.video_shorts(None, 20, 0, child, MagicMock())
	assert [item.title for item in items] == ["Counting"]
	assert items[0].playback_locked is True and items[0].youtube_video_id is None


def test_continue_watching_withholds_ids_when_exhausted(monkeypatch, child):
	set_allowance(monkeypatch, True)
	row = {
		"video_id": uuid4(), "title": "Counting", "description": None, "thumbnail_url": None, "duration_seconds": 120,
		"category_id": None, "language_code": "en", "video_source": "youtube", "youtube_video_id": "abc123XYZ00",
		"video_format": "regular", "started_at": "2026-11-19T00:00:00Z", "last_watched_at": "2026-11-19T00:00:00Z",
		"last_position_seconds": 5, "watch_duration_seconds": 5, "completion_percentage": 4, "is_completed": False,
	}
	monkeypatch.setattr(videos_api.video_watch_history_service, "list_child_history", lambda *a, **k: [dict(row)])
	result = videos_api.continue_watching(20, child, MagicMock())
	assert [item.youtube_video_id for item in result] == [None]


def test_feeds_query_and_unlock_when_time_remains(monkeypatch, child):
	set_allowance(monkeypatch, False)
	calls = []
	monkeypatch.setattr(videos_api, "eligible_feed", lambda *a, **k: calls.append(k.get("video_format")) or [fake_video()])
	monkeypatch.setattr(videos_api, "_channel_names", lambda s, v: {})
	monkeypatch.setattr(videos_api, "_resume_positions", lambda s, c, v: {})
	regular = videos_api.video_feed(None, 20, 0, child, MagicMock())
	shorts = videos_api.video_shorts(None, 20, 0, child, MagicMock())
	assert calls == ["regular", "short"]
	assert regular[0].playback_locked is False and regular[0].youtube_video_id == "abc123XYZ00"
	assert shorts[0].playback_locked is False


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
