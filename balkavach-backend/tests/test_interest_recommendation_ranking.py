"""Approved interests reorder the real feed query; pending requests never do.

Uses the SQLite feed world (tests/feed_world.py) and the production ``eligible_feed``. The child row's
``interests`` / ``pending_interest_requests`` are set as plain attributes: that is what the reflected
production model exposes after migration 0022 (JSONB columns), and all ranking reads is
``getattr(child, "interests")``.
"""

from app.services.video_service import eligible_feed
from tests.feed_world import (  # noqa: F401
	VideoCategory,
	add_youtube,
	feed_db,
	make_child,
)


def _world(session):
	science = VideoCategory(name="Science", slug="science", display_order=1)
	stories = VideoCategory(name="Stories", slug="stories", display_order=2)
	session.add_all([science, stories])
	session.commit()
	for index in range(3):
		add_youtube(session, title=f"Science {index}", category_id=science.id, display_order=index)
		add_youtube(session, title=f"Story {index}", category_id=stories.id, display_order=10 + index)
	return make_child(session)


def _first_three(session, child, seed):
	return {video.title.split()[0] for video in eligible_feed(session, child, None, 6, 0, video_format="regular", seed=seed)[:3]}


def test_approved_interest_categories_rank_first(feed_db):
	child = _world(feed_db)
	child.interests = ["stories"]
	child.pending_interest_requests = []
	for seed in ("a", "b", "c"):
		assert _first_three(feed_db, child, seed) == {"Story"}


def test_pending_interest_request_does_not_change_ranking(feed_db):
	child = _world(feed_db)
	child.interests = ["science"]
	child.pending_interest_requests = ["stories"]
	for seed in ("a", "b", "c"):
		assert _first_three(feed_db, child, seed) == {"Science"}


def test_parent_change_takes_effect_on_next_feed_request(feed_db):
	child = _world(feed_db)
	child.interests = ["science"]
	assert _first_three(feed_db, child, "s") == {"Science"}
	child.interests = ["stories"]  # what PUT /families/{f}/children/{c}/interests persists
	assert _first_three(feed_db, child, "s") == {"Story"}
