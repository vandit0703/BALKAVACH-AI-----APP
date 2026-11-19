"""Up-next recommendations: ranking is pure, and the endpoint only ever draws on the eligible feed."""

from datetime import datetime, timedelta
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.api.v1 import videos as videos_api
from app.services.video_service import rank_next_videos

CAT_A, CAT_B = uuid4(), uuid4()
BASE = datetime(2026, 11, 1)


def vid(category=None, language="en", age_days=0, source="youtube", duration=300):
	return SimpleNamespace(
		id=uuid4(), category_id=category, language_code=language, created_at=BASE - timedelta(days=age_days),
		video_source=source, duration_seconds=duration, title="t", description=None, thumbnail_url=None,
		content_rating="educational", external_video_id="abcdefghi01",
	)


def test_same_category_comes_first_then_newest():
	current = vid(CAT_A)
	same_old = vid(CAT_A, age_days=30)
	same_new = vid(CAT_A, age_days=1)
	other = vid(CAT_B, age_days=0)
	ranked = rank_next_videos(current, [other, same_old, same_new], {}, 3)
	assert ranked == [same_new, same_old, other]


def test_the_current_video_is_never_suggested():
	current = vid(CAT_A)
	assert rank_next_videos(current, [current, vid(CAT_A)], {}, 5)[0] is not current
	assert current not in rank_next_videos(current, [current], {}, 5)


def test_same_channel_ranks_above_unrelated():
	current = vid(None)
	mine, stranger = vid(None, age_days=10), vid(None, age_days=0)
	channels = {current.id: "Kids", mine.id: "Kids", stranger.id: "Other"}
	assert rank_next_videos(current, [stranger, mine], channels, 2) == [mine, stranger]


def test_one_channel_cannot_fill_the_whole_list():
	current = vid(CAT_A)
	same_channel = [vid(CAT_A, age_days=i) for i in range(6)]
	different = [vid(CAT_B, age_days=100 + i) for i in range(3)]
	channels = {v.id: "Big" for v in same_channel}
	ranked = rank_next_videos(current, same_channel + different, channels, 6)
	assert len(ranked) == 6
	assert sum(1 for v in ranked if v in same_channel) == 3  # max(2, 6 // 2)


def test_limit_and_empty_pool():
	current = vid(CAT_A)
	assert rank_next_videos(current, [], {}, 5) == []
	assert len(rank_next_videos(current, [vid(CAT_A) for _ in range(10)], {}, 4)) == 4


def test_ordering_is_deterministic():
	current = vid(CAT_A)
	pool = [vid(CAT_A, age_days=i % 3) for i in range(8)]
	assert rank_next_videos(current, pool, {}, 8) == rank_next_videos(current, list(reversed(pool)), {}, 8)


# ---- endpoint -------------------------------------------------------------------------


@pytest.fixture
def child():
	return SimpleNamespace(id=uuid4(), family_id=uuid4(), user_id=uuid4())


def _session_with(current):
	session = MagicMock()
	session.query.return_value.filter.return_value.one_or_none.return_value = current
	return session


def test_exhausted_allowance_returns_nothing_and_never_queries(monkeypatch, child):
	monkeypatch.setattr(videos_api, "_allowance_exhausted", lambda s, c: True)
	monkeypatch.setattr(videos_api, "eligible_feed", lambda *a, **k: pytest.fail("must not query"))
	assert videos_api.next_videos(uuid4(), 6, child, MagicMock()) == []


def test_unknown_video_is_404(monkeypatch, child):
	monkeypatch.setattr(videos_api, "_allowance_exhausted", lambda s, c: False)
	monkeypatch.setattr(videos_api, "get_model", lambda name: MagicMock())
	with pytest.raises(HTTPException) as error:
		videos_api.next_videos(uuid4(), 6, child, _session_with(None))
	assert error.value.status_code == 404


def test_only_videos_from_the_eligible_feed_are_returned(monkeypatch, child):
	current = vid(CAT_A)
	eligible = [vid(CAT_A), vid(CAT_B)]
	asked = []

	def fake_feed(session, who, category, limit, offset, video_format=None):
		asked.append(video_format)
		return eligible if video_format == "regular" else []

	monkeypatch.setattr(videos_api, "_allowance_exhausted", lambda s, c: False)
	monkeypatch.setattr(videos_api, "get_model", lambda name: MagicMock())
	monkeypatch.setattr(videos_api, "eligible_feed", fake_feed)
	monkeypatch.setattr(videos_api, "_channel_names", lambda s, v: {})
	monkeypatch.setattr(videos_api, "_resume_positions", lambda s, c, v: {})
	result = videos_api.next_videos(uuid4(), 6, child, _session_with(current))
	assert {item.id for item in result} == {v.id for v in eligible}
	assert asked[0] == "regular", "a regular video is followed by regular ones first"
	assert result[0].id == eligible[0].id, "same category first"


def test_a_short_prefers_shorts_but_tops_up_from_regular(monkeypatch, child):
	current = vid(CAT_A, duration=30)
	shorts, regular = [vid(CAT_A, duration=30)], [vid(CAT_A, duration=300)]
	monkeypatch.setattr(videos_api, "_allowance_exhausted", lambda s, c: False)
	monkeypatch.setattr(videos_api, "get_model", lambda name: MagicMock())
	monkeypatch.setattr(
		videos_api, "eligible_feed",
		lambda s, c, cat, limit, offset, video_format=None: shorts if video_format == "short" else regular,
	)
	monkeypatch.setattr(videos_api, "_channel_names", lambda s, v: {})
	monkeypatch.setattr(videos_api, "_resume_positions", lambda s, c, v: {})
	ids = {item.id for item in videos_api.next_videos(uuid4(), 6, child, _session_with(current))}
	assert ids == {shorts[0].id, regular[0].id}
