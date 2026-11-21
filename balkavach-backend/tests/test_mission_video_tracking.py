"""Mission watch time is isolated, server-timed, and replay-safe (SQLite test world)."""

from datetime import datetime, timedelta, timezone
import pytest

from app.core.exceptions import APIError
from app.services.mission_video_service import (
    get_mission_video_progress,
    interrupt_mission_video_watch,
    record_mission_video_heartbeat,
    require_video_requirement_complete,
    start_mission_video_watch,
)
from app.services.video_entitlement_service import get_child_video_allowance_today
from app.utils import utc_naive
from tests import feed_world
from tests.feed_world import ChildVideoDailyUsage, add_youtube, feed_db, make_child  # noqa: F401


def make_task(session, child, required=900):
    Task = feed_world._get_model("Task")
    task = Task(
        family_id=child.family_id,
        assigned_child_id=child.id,
        required_video_seconds=required,
        title="Watch educational videos",
    )
    session.add(task)
    session.commit()
    return task


def heartbeat(session, child, watch, sequence, position, *, playing=True, elapsed=30):
    watch.last_heartbeat_at = utc_naive(datetime.now(timezone.utc)) - timedelta(seconds=elapsed)
    session.flush()
    return record_mission_video_heartbeat(
        session, watch.id, child, sequence, position, playing
    )


def test_five_verified_minutes_are_not_enough(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    video = add_youtube(feed_db, duration_seconds=1800).video
    started = start_mission_video_watch(feed_db, task.id, child, video.id, "a" * 32)
    Watch = feed_world._get_model("MissionVideoWatchSession")
    watch = feed_db.query(Watch).filter_by(id=started["session_id"]).one()

    for sequence in range(10):
        heartbeat(feed_db, child, watch, sequence, (sequence + 1) * 30)

    progress = get_mission_video_progress(feed_db, task.id, child)
    assert progress["verified_video_seconds"] == 300
    assert progress["remaining_video_seconds"] == 600
    assert not progress["is_complete"]
    with pytest.raises(APIError) as error:
        require_video_requirement_complete(feed_db, task, child)
    assert error.value.code == "mission_video_incomplete"


def test_missions_without_a_video_requirement_keep_the_existing_submission_path(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child, required=None)
    require_video_requirement_complete(feed_db, task, child)


def test_retried_session_start_returns_the_existing_session(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    video = add_youtube(feed_db, duration_seconds=1800).video
    first = start_mission_video_watch(feed_db, task.id, child, video.id, "f" * 32)
    retry = start_mission_video_watch(feed_db, task.id, child, video.id, "f" * 32)

    assert retry["session_id"] == first["session_id"]
    assert feed_db.query(feed_world._get_model("MissionVideoWatchSession")).count() == 1


def test_verified_requirement_completes_and_duplicate_heartbeat_does_not_count_twice(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    video = add_youtube(feed_db, duration_seconds=1800).video
    started = start_mission_video_watch(feed_db, task.id, child, video.id, "b" * 32)
    Watch = feed_world._get_model("MissionVideoWatchSession")
    watch = feed_db.query(Watch).filter_by(id=started["session_id"]).one()

    first = heartbeat(feed_db, child, watch, 0, 30)
    duplicate = record_mission_video_heartbeat(feed_db, watch.id, child, 0, 60, True)
    assert first["accepted_seconds"] == 30
    assert duplicate["accepted_seconds"] == 0
    assert duplicate["verified_video_seconds"] == 30

    for sequence in range(1, 30):
        result = heartbeat(feed_db, child, watch, sequence, (sequence + 1) * 30)
    assert result["verified_video_seconds"] == 900
    assert result["remaining_video_seconds"] == 0
    assert result["is_complete"]
    assert result["status"] == "completed"
    require_video_requirement_complete(feed_db, task, child)


def test_daily_free_allowance_does_not_satisfy_mission_requirement(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    DailyUsage = feed_world._get_model("ChildVideoDailyUsage")
    today = get_child_video_allowance_today(feed_db, child.id, child.family_id)["local_date"]
    feed_db.add(ChildVideoDailyUsage(child_id=child.id, local_date=today, free_watched_seconds=900))
    feed_db.commit()

    assert get_child_video_allowance_today(feed_db, child.id, child.family_id)["remaining_seconds"] == 0
    progress = get_mission_video_progress(feed_db, task.id, child)
    assert progress["verified_video_seconds"] == 0
    assert not progress["is_complete"]


def test_interruption_preserves_only_server_verified_progress(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    video = add_youtube(feed_db, duration_seconds=1800).video
    started = start_mission_video_watch(feed_db, task.id, child, video.id, "c" * 32)
    Watch = feed_world._get_model("MissionVideoWatchSession")
    watch = feed_db.query(Watch).filter_by(id=started["session_id"]).one()
    heartbeat(feed_db, child, watch, 0, 30)

    interrupted = interrupt_mission_video_watch(feed_db, watch.id, child)
    assert interrupted["status"] == "interrupted"
    assert interrupted["verified_video_seconds"] == 30
    assert get_mission_video_progress(feed_db, task.id, child)["verified_video_seconds"] == 30
    with pytest.raises(APIError) as error:
        record_mission_video_heartbeat(feed_db, watch.id, child, 1, 60, True)
    assert error.value.code == "mission_video_session_inactive"


def test_a_long_heartbeat_gap_interrupts_without_earning_time(feed_db):
    child = make_child(feed_db)
    task = make_task(feed_db, child)
    video = add_youtube(feed_db, duration_seconds=1800).video
    started = start_mission_video_watch(feed_db, task.id, child, video.id, "d" * 32)
    Watch = feed_world._get_model("MissionVideoWatchSession")
    watch = feed_db.query(Watch).filter_by(id=started["session_id"]).one()

    result = heartbeat(feed_db, child, watch, 0, 1800, elapsed=3600)
    assert result["accepted_seconds"] == 0
    assert result["verified_video_seconds"] == 0
    assert result["status"] == "interrupted"
