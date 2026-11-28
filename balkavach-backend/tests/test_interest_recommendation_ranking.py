"""Retired interests no longer influence video recommendation ranking or filtering.

Uses the SQLite feed world (tests/feed_world.py) and the production ``eligible_feed``.
Stored ``interests`` / ``pending_interest_requests`` on ``child`` are preserved but ignored,
while age suitability, safety filtering, and category filtering remain enforced.
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


def _feed_ids(session, child, seed, category_id=None):
	return [video.id for video in eligible_feed(session, child, category_id, 6, 0, video_format="regular", seed=seed)]


def test_stored_interests_do_not_change_recommendation_ranking(feed_db):
	child = _world(feed_db)
	child.interests = []
	child.pending_interest_requests = []
	baseline = _feed_ids(feed_db, child, "s")

	child.interests = ["stories"]
	child.pending_interest_requests = ["science"]
	with_stories = _feed_ids(feed_db, child, "s")

	child.interests = ["science"]
	child.pending_interest_requests = ["stories"]
	with_science = _feed_ids(feed_db, child, "s")

	assert with_stories == baseline
	assert with_science == baseline
	assert child.interests == ["science"]
	assert child.pending_interest_requests == ["stories"]


def test_age_suitability_and_safety_filters_remain_enforced(feed_db):
	child = _world(feed_db)
	child.interests = ["science", "stories"]
	add_youtube(feed_db, title="Too Old", age_min=14, age_max=15)
	add_youtube(feed_db, title="Unsafe Rating", content_rating="restricted")
	titles = [v.title for v in eligible_feed(feed_db, child, None, 20, 0, video_format="regular", seed="s")]
	assert "Too Old" not in titles
	assert "Unsafe Rating" not in titles
	assert len(titles) == 6


def test_explicit_category_filter_still_works(feed_db):
	child = _world(feed_db)
	child.interests = ["science"]
	stories = feed_db.query(VideoCategory).filter(VideoCategory.slug == "stories").one()
	titles = [v.title for v in eligible_feed(feed_db, child, stories.id, 10, 0, video_format="regular", seed="s")]
	assert set(titles) == {"Story 0", "Story 1", "Story 2"}
