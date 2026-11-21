"""The standard mission reward (10 stars / 15 XP) as the API presents it and as new missions store it.

Runs on the in-memory SQLite world (``tests/sqlite_world.py``) and plain unit checks. It proves the service and
schema logic only: it is **not** a PostgreSQL integration test. Paying the reward (``review_submission``) uses
PostgreSQL ``ON CONFLICT`` and is covered by ``tests/test_api_mission_rewards.py`` against an isolated
PostgreSQL test database.
"""

from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4

from app.schemas.task import TaskPublic
from app.services.daily_mission_service import (
	_snapshot,
	ensure_daily_choices,
	public_assignment,
	select_assignment,
	start_assignment,
)
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from tests.sqlite_world import Task as WorldTask
from tests.sqlite_world import make_family, publish_templates, world_session  # noqa: F401  (fixture)

DAY = datetime(2026, 11, 19, 9, 0, tzinfo=timezone.utc)


def test_the_standard_reward_is_ten_stars_and_fifteen_xp():
	assert (MISSION_STAR_REWARD, MISSION_XP_REWARD) == (10, 15)


def _task_row(stars: int, xp: int):
	return SimpleNamespace(
		id=uuid4(),
		family_id=uuid4(),
		category_id=None,
		created_by=uuid4(),
		assigned_child_id=None,
		title="Make the bed",
		description=None,
		star_reward=stars,
		xp_reward=xp,
		due_at=None,
		is_active=True,
		created_at=DAY.replace(tzinfo=None),
	)


def test_a_task_shows_the_standard_reward_whatever_it_stored():
	for stored in [(0, 0), (1, 10), (5, 20), (500, 9000)]:
		public = TaskPublic.model_validate(_task_row(*stored))
		assert (public.star_reward, public.xp_reward) == (10, 15), stored


def _assignment_row(status: str, stars: int = 1, xp: int = 10):
	return SimpleNamespace(
		id=uuid4(),
		local_date=DAY.date(),
		choice_slot=1,
		age_band="4_6",
		status=status,
		task_id=None,
		selected_at=None,
		started_at=None,
		skipped_at=None,
		snapshot={"title": "Beat Builder (4 to 6)", "star_reward": stars, "xp_reward": xp},
	)


def test_a_mission_not_yet_approved_shows_what_an_approval_pays_now():
	for status in ["available", "selected", "in_progress", "pending_parent_approval", "rejected"]:
		content = public_assignment(_assignment_row(status))["content"]
		assert (content["star_reward"], content["xp_reward"]) == (10, 15), status
		assert content["title"] == "Beat Builder"


def test_an_approved_mission_keeps_the_reward_it_was_earned_with():
	content = public_assignment(_assignment_row("approved", stars=1, xp=10))["content"]
	assert (content["star_reward"], content["xp_reward"]) == (1, 10)


def test_public_assignment_does_not_change_the_stored_snapshot():
	row = _assignment_row("available", stars=1, xp=10)
	public_assignment(row)
	assert (row.snapshot["star_reward"], row.snapshot["xp_reward"]) == (1, 10)


def test_new_snapshots_store_the_standard_reward_not_the_templates():
	template = SimpleNamespace(mission_type="offline", theme="monday_sound_detective", star_reward=1, xp_reward=10, is_surprise=True, mystery_bonus={"type": "stars", "amount": 5})
	variation = SimpleNamespace(
		title="Sound Map",
		description="Listen.",
		instructions="1. Listen.",
		required_materials=["paper"],
		duration_minutes=10,
		safety_instructions="Stay inside.",
		completion_criteria="A map.",
		locale="en",
	)
	snapshot = _snapshot(template, variation)
	assert (snapshot["star_reward"], snapshot["xp_reward"]) == (10, 15)


def test_choosing_and_starting_a_daily_mission_creates_a_standard_task_and_pays_nothing(world_session):
	child = make_family(world_session)
	publish_templates(world_session, 8)  # the world's templates store 5 stars / 10 XP
	world_session.commit()
	_, _, rows = ensure_daily_choices(world_session, child, DAY)
	world_session.commit()

	picked = select_assignment(world_session, child, rows[0].id)
	world_session.commit()
	started = start_assignment(world_session, child, picked.id)
	world_session.commit()

	task = world_session.get(WorldTask, picked.task_id)
	assert (task.star_reward, task.xp_reward) == (10, 15)
	assert started.status == "in_progress"
	# Choosing and starting are not completions: nothing is written to a ledger (the SQLite world has no
	# ledger tables at all, so any attempt to pay here would fail this test).


def test_choosing_the_same_mission_again_does_not_create_a_second_task(world_session):
	child = make_family(world_session)
	publish_templates(world_session, 8)
	world_session.commit()
	_, _, rows = ensure_daily_choices(world_session, child, DAY)
	world_session.commit()
	first = select_assignment(world_session, child, rows[0].id)
	world_session.commit()
	task_id = first.task_id
	again = select_assignment(world_session, child, rows[0].id)
	world_session.commit()
	assert again.task_id == task_id
