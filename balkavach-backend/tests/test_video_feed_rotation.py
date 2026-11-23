from datetime import datetime, timedelta, timezone

from app.services.video_service import eligible_feed
from app.utils import utc_naive
from tests.feed_world import (  # noqa: F401
    ChildVideoWatchHistory,
    add_youtube,
    feed_db,
    make_child,
)


def _titles(session, child, *, seed=None, offset=0, limit=50, video_format="regular"):
    return [
        video.title
        for video in eligible_feed(
            session, child, None, limit, offset, video_format=video_format, seed=seed
        )
    ]


def _mark_history(session, child, video, *, completed, last_watched_at, position=0):
    session.add(
        ChildVideoWatchHistory(
            child_id=child.id,
            video_id=video.id,
            video_format="regular" if (video.duration_seconds or 0) > 60 else "short",
            started_at=last_watched_at,
            last_watched_at=last_watched_at,
            last_position_seconds=position,
            watch_duration_seconds=position,
            completion_percentage=100 if completed else min(90, position),
            is_completed=completed,
            parent_replay_authorized=False,
        )
    )
    session.commit()


def test_unseen_videos_are_prioritized_over_in_progress_and_finished(feed_db):
    child = make_child(feed_db)
    finished = add_youtube(feed_db, title="Finished", display_order=0).video
    progress = add_youtube(feed_db, title="InProgress", display_order=1).video
    add_youtube(feed_db, title="UnseenA", display_order=2)
    add_youtube(feed_db, title="UnseenB", display_order=3)
    now = utc_naive(datetime.now(timezone.utc))
    _mark_history(feed_db, child, finished, completed=True, last_watched_at=now - timedelta(days=3))
    _mark_history(feed_db, child, progress, completed=False, last_watched_at=now - timedelta(hours=1), position=20)

    titles = _titles(feed_db, child, seed="session-a")
    assert set(titles[:2]) == {"UnseenA", "UnseenB"}
    assert titles[2] == "InProgress"
    assert titles[3] == "Finished"


def test_same_seed_keeps_feed_stable_but_different_sessions_rotate_unseen(feed_db):
    child = make_child(feed_db)
    for index in range(8):
        add_youtube(feed_db, title=f"U{index}", display_order=0)

    stable_a = _titles(feed_db, child, seed="open-1")
    stable_b = _titles(feed_db, child, seed="open-1")
    assert stable_a == stable_b

    orders = {_titles(feed_db, child, seed=f"open-{n}")[0] for n in range(1, 12)}
    assert len(orders) > 1, "different feed sessions should not always repeat the same unseen item first"


def test_pagination_with_seed_returns_no_duplicates_and_keeps_order(feed_db):
    child = make_child(feed_db)
    for index in range(7):
        add_youtube(feed_db, title=f"V{index}", display_order=0)

    seen = []
    first_page = None
    for offset in (0, 3, 6, 9):
        page = _titles(feed_db, child, seed="scroll-session", offset=offset, limit=3)
        if offset == 0:
            first_page = page
        seen.extend(page)

    assert len(seen) == 7
    assert len(set(seen)) == 7
    assert set(seen) == {f"V{i}" for i in range(7)}
    assert _titles(feed_db, child, seed="scroll-session", offset=0, limit=3) == first_page


def test_finished_videos_return_gradually_oldest_watched_first(feed_db):
    child = make_child(feed_db)
    add_youtube(feed_db, title="Unseen", display_order=0)
    recent = add_youtube(feed_db, title="WatchedRecent", display_order=1).video
    older = add_youtube(feed_db, title="WatchedOlder", display_order=2).video
    oldest = add_youtube(feed_db, title="WatchedOldest", display_order=3).video
    now = utc_naive(datetime.now(timezone.utc))
    _mark_history(feed_db, child, recent, completed=True, last_watched_at=now - timedelta(days=1))
    _mark_history(feed_db, child, older, completed=True, last_watched_at=now - timedelta(days=10))
    _mark_history(feed_db, child, oldest, completed=True, last_watched_at=now - timedelta(days=30))

    titles = _titles(feed_db, child, seed="session-x")
    assert titles[0] == "Unseen"
    assert titles[1:] == ["WatchedOldest", "WatchedOlder", "WatchedRecent"]


def test_shorts_use_same_unseen_priority_rotation_and_pagination_rules(feed_db):
    child = make_child(feed_db)
    finished = add_youtube(feed_db, title="ShortDone", display_order=0, duration_seconds=30).video
    for index in range(6):
        add_youtube(feed_db, title=f"S{index}", display_order=0, duration_seconds=30)
    _mark_history(feed_db, child, finished, completed=True, last_watched_at=utc_naive(datetime.now(timezone.utc)) - timedelta(days=5))

    first = _titles(feed_db, child, seed="short-a", video_format="short")
    assert first == _titles(feed_db, child, seed="short-a", video_format="short")
    assert "ShortDone" in first
    assert first.index("ShortDone") >= 6  # all unseen shorts come first

    orders = {_titles(feed_db, child, seed=f"short-{n}", video_format="short")[0] for n in range(1, 12)}
    assert len(orders) > 1

    seen = []
    for offset in (0, 3, 6, 9):
        seen.extend(_titles(feed_db, child, seed="short-scroll", offset=offset, limit=3, video_format="short"))
    assert len(seen) == 7
    assert len(set(seen)) == 7
    assert "ShortDone" in seen
