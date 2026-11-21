"""Older unfinished daily missions stay reachable, and age ranges never show in child-facing titles.

Runs on the in-memory SQLite world (``tests/sqlite_world.py``). This proves the service logic only: it is
**not** a PostgreSQL integration test (no row locks, no real schema).
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

import pytest

from app.core.exceptions import APIError
from app.services.daily_mission_service import (
	ensure_daily_choices,
	select_assignment,
	skip_assignment,
	unfinished_assignments,
)
from app.services.mission_titles import child_facing_title
from tests.sqlite_world import make_family, publish_templates, world_session  # noqa: F401  (fixture)

DAY1 = datetime(2026, 11, 19, 9, 0, tzinfo=timezone.utc)  # a Thursday
DAY2 = DAY1 + timedelta(days=2)  # the Saturday after


@pytest.mark.parametrize(
	"raw, shown",
	[
		("Saturday Rhythm Rockstar 2 (4 to 6)", "Saturday Rhythm Rockstar 2"),
		("Thursday Paper Architect 3 (7 to 10)", "Thursday Paper Architect 3"),
		("Beat Builder (11 to 15)", "Beat Builder"),
		("Beat Builder (Ages 4-6)", "Beat Builder"),
		("Beat Builder [4–6]", "Beat Builder"),
		("Beat Builder (4 to 6) ", "Beat Builder"),
		("Clap the Rhythm", "Clap the Rhythm"),
		("Draw a Cat (and a dog)", "Draw a Cat (and a dog)"),
		("Plan for 3 (kids)", "Plan for 3 (kids)"),
		("Level (2)", "Level (2)"),
		("(4 to 6)", "(4 to 6)"),
		("", ""),
	],
)
def test_child_facing_title_removes_only_a_trailing_age_range(raw, shown):
	assert child_facing_title(raw) == shown


def _setup(session):
	child = make_family(session)
	publish_templates(session, 8)
	session.commit()
	return child


def _day(session, child, when):
	_, _, rows = ensure_daily_choices(session, child, when)
	session.commit()
	return rows


def test_a_selected_mission_from_an_earlier_day_is_listed_after_its_day_passes(world_session):
	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	picked = select_assignment(world_session, child, day1[0].id)
	world_session.commit()

	_day(world_session, child, DAY2)
	older = unfinished_assignments(world_session, child, DAY2)

	assert [row.id for row in older] == [picked.id]
	assert older[0].task_id == picked.task_id and older[0].task_id is not None


def test_in_progress_and_rejected_missions_are_also_unfinished(world_session):
	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	first = select_assignment(world_session, child, day1[0].id)
	first.status = "in_progress"
	world_session.commit()
	day2 = _day(world_session, child, DAY1 + timedelta(days=1))
	second = select_assignment(world_session, child, day2[0].id)
	second.status = "rejected"
	world_session.commit()

	_day(world_session, child, DAY2)
	older = unfinished_assignments(world_session, child, DAY2)

	assert {row.id for row in older} == {first.id, second.id}
	assert [row.local_date for row in older] == sorted((row.local_date for row in older), reverse=True)


@pytest.mark.parametrize("status", ["approved", "pending_parent_approval", "skipped", "available"])
def test_finished_waiting_skipped_or_never_chosen_missions_are_not_unfinished(world_session, status):
	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	picked = select_assignment(world_session, child, day1[0].id)
	picked.status = status
	world_session.commit()

	_day(world_session, child, DAY2)

	assert picked.id not in {row.id for row in unfinished_assignments(world_session, child, DAY2)}


def test_todays_own_choices_are_not_repeated_in_the_unfinished_list(world_session):
	child = _setup(world_session)
	today = _day(world_session, child, DAY2)
	select_assignment(world_session, child, today[0].id)
	world_session.commit()

	assert unfinished_assignments(world_session, child, DAY2) == []


def test_a_deactivated_task_is_no_longer_unfinished(world_session):
	from tests.sqlite_world import Task

	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	picked = select_assignment(world_session, child, day1[0].id)
	world_session.commit()
	world_session.query(Task).filter(Task.id == picked.task_id).update({"is_active": False})
	world_session.commit()

	assert unfinished_assignments(world_session, child, DAY2) == []


def test_listing_and_revisiting_never_creates_or_resets_assignments(world_session):
	from tests.sqlite_world import DailyMissionAssignment, Task

	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	picked = select_assignment(world_session, child, day1[0].id)
	world_session.commit()
	_day(world_session, child, DAY2)
	rows_before = world_session.query(DailyMissionAssignment).count()
	tasks_before = world_session.query(Task).count()
	task_id, status, selected_at = picked.task_id, picked.status, picked.selected_at

	for _ in range(3):
		assert [row.id for row in unfinished_assignments(world_session, child, DAY2)] == [picked.id]
		_day(world_session, child, DAY2)
	# Opening the mission again is just a re-select of the same assignment: nothing is created or reset.
	again = select_assignment(world_session, child, picked.id)
	world_session.commit()

	assert again.id == picked.id and again.status == status and again.selected_at == selected_at
	assert again.task_id == task_id
	assert world_session.query(DailyMissionAssignment).count() == rows_before
	assert world_session.query(Task).count() == tasks_before


def test_choosing_a_new_mission_today_keeps_the_older_unfinished_one(world_session):
	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	older = select_assignment(world_session, child, day1[0].id)
	world_session.commit()

	day2 = _day(world_session, child, DAY2)
	todays = select_assignment(world_session, child, day2[0].id)
	world_session.commit()

	assert todays.id != older.id and todays.task_id != older.task_id
	assert [row.id for row in unfinished_assignments(world_session, child, DAY2)] == [older.id]


def test_unfinished_list_is_scoped_to_the_child(world_session):
	child = _setup(world_session)
	other = make_family(world_session)
	day1 = _day(world_session, child, DAY1)
	select_assignment(world_session, child, day1[0].id)
	world_session.commit()

	assert unfinished_assignments(world_session, other, DAY2) == []


def test_the_chosen_task_is_titled_without_the_age_range_but_keeps_the_age_band(world_session):
	from tests.sqlite_world import DailyMissionVariation, Task

	child = _setup(world_session)
	world_session.query(DailyMissionVariation).update({"title": "Saturday Rhythm Rockstar 2 (4 to 6)"})
	world_session.commit()
	choices = _day(world_session, child, DAY1)

	picked = select_assignment(world_session, child, choices[0].id)
	world_session.commit()

	task = world_session.query(Task).filter(Task.id == picked.task_id).one()
	assert task.title == "Saturday Rhythm Rockstar 2"
	# Age metadata is untouched: eligibility and the stored snapshot still carry it.
	assert picked.age_band == child_band(child, DAY1)
	assert picked.snapshot["title"] == "Saturday Rhythm Rockstar 2 (4 to 6)"


def child_band(child, when):
	from app.services.daily_mission_service import age_band_for_birth_date

	return age_band_for_birth_date(child.date_of_birth, when.date())


def test_the_public_content_title_has_no_age_range(world_session):
	from app.services.daily_mission_service import public_assignment
	from tests.sqlite_world import DailyMissionVariation

	child = _setup(world_session)
	world_session.query(DailyMissionVariation).update({"title": "Thursday Paper Architect 3 (4 to 6)"})
	world_session.commit()
	choices = _day(world_session, child, DAY1)

	shown = public_assignment(choices[0])

	assert shown["content"]["title"] == "Thursday Paper Architect 3"
	assert shown["age_band"] == choices[0].age_band  # metadata kept
	assert choices[0].snapshot["title"].endswith("(4 to 6)")  # stored value unchanged


def test_skipping_still_works_and_selecting_a_skipped_choice_is_rejected(world_session):
	child = _setup(world_session)
	day1 = _day(world_session, child, DAY1)
	skipped_id = day1[0].id
	skip_assignment(world_session, child, skipped_id, DAY1)
	world_session.commit()
	with pytest.raises(APIError) as error:
		select_assignment(world_session, child, skipped_id)
	assert error.value.code == "daily_assignment_not_found"


# ---- HTTP layer (real routes, SQLite world; auth and DB dependencies overridden) -------------------------


@pytest.fixture
def threaded_world(monkeypatch):
	"""Like ``world_session`` but usable from the TestClient's worker thread (shared in-memory connection)."""
	from sqlalchemy import create_engine
	from sqlalchemy.orm import sessionmaker
	from sqlalchemy.pool import StaticPool

	import app.api.v1.daily_missions as missions_api
	import app.services.daily_mission_service as missions
	import app.services.mission_rotation_service as rotation
	import app.services.timezone_service as zones
	from tests.sqlite_world import World, _get_model

	for module in (missions, zones, missions_api, rotation):
		monkeypatch.setattr(module, "get_model", _get_model)
	engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
	World.metadata.create_all(engine)
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


@pytest.fixture
def client(threaded_world, monkeypatch):
	from fastapi.testclient import TestClient

	import app.api.v1.daily_missions as missions_api
	from app.core.dependencies import require_child
	from app.db.session import get_db
	from app.main import app

	from tests.sqlite_world import DailyMissionTemplate

	world_session = threaded_world
	child = _setup(world_session)
	# the API schema only accepts the real mission types (the shared helper uses a free-text one)
	world_session.query(DailyMissionTemplate).update({"mission_type": "offline"})
	world_session.commit()
	clock = {"now": DAY1}
	monkeypatch.setattr("app.services.daily_mission_service._now", lambda: clock["now"])
	app.dependency_overrides[require_child] = lambda: child
	app.dependency_overrides[get_db] = lambda: world_session
	monkeypatch.setattr(missions_api, "family_timezone_name", lambda *_: "UTC")
	try:
		yield TestClient(app), clock, world_session
	finally:
		app.dependency_overrides.pop(require_child, None)
		app.dependency_overrides.pop(get_db, None)


def test_api_titles_have_no_age_range_and_unfinished_stays_after_the_day(client):
	from tests.sqlite_world import DailyMissionVariation

	http, clock, session = client
	session.query(DailyMissionVariation).update({"title": "Thursday Paper Architect 3 (4 to 6)"})
	session.commit()

	today = http.get("/api/v1/daily-missions/today").json()
	assert all(c["content"]["title"] == "Thursday Paper Architect 3" for c in today["choices"])
	assert all(c["age_band"] == "7_10" for c in today["choices"])  # eligibility metadata untouched
	picked = today["choices"][0]
	selected = http.post(f"/api/v1/daily-missions/{picked['id']}/select").json()
	assert selected["status"] == "selected" and selected["task_id"]

	clock["now"] = DAY2  # the day passes without finishing
	new_today = http.get("/api/v1/daily-missions/today").json()
	assert picked["id"] not in {c["id"] for c in new_today["choices"]}
	older = http.get("/api/v1/daily-missions/unfinished").json()
	assert [row["id"] for row in older] == [picked["id"]]
	assert older[0]["task_id"] == selected["task_id"]
	assert older[0]["content"]["title"] == "Thursday Paper Architect 3"
	assert older[0]["local_date"] == DAY1.date().isoformat()

	# Asking again changes nothing (no duplicate assignment, same task, same status).
	again = http.get("/api/v1/daily-missions/unfinished").json()
	assert again == older
	reselect = http.post(f"/api/v1/daily-missions/{picked['id']}/select").json()
	assert reselect["task_id"] == selected["task_id"] and reselect["status"] == "selected"


def test_api_a_finished_mission_leaves_the_unfinished_list(client):
	from tests.sqlite_world import DailyMissionAssignment

	http, clock, session = client
	picked = http.get("/api/v1/daily-missions/today").json()["choices"][0]
	http.post(f"/api/v1/daily-missions/{picked['id']}/select")
	clock["now"] = DAY2
	assert [r["id"] for r in http.get("/api/v1/daily-missions/unfinished").json()] == [picked["id"]]

	row = session.query(DailyMissionAssignment).filter(DailyMissionAssignment.id == UUID(picked["id"])).one()
	row.status = "approved"  # what review_submission records on parent approval
	session.commit()

	assert http.get("/api/v1/daily-missions/unfinished").json() == []
