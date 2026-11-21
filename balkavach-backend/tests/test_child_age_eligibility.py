"""A child only ever gets daily missions for their own, current age group.

Runs on the in-memory SQLite world (``tests/sqlite_world.py``) with the **real** localized catalogue
(42 templates x 3 age groups x en/gu/hi) and the real service code. It proves the service logic: it is **not**
a PostgreSQL integration test (no row locks, no real schema). The HTTP checks for ``/tasks`` and submitting
live in ``tests/test_api_mission_age_eligibility.py`` (PostgreSQL).
"""

from datetime import date, datetime, timedelta, timezone
from uuid import uuid4

import pytest
from pydantic import ValidationError

import app.services.daily_mission_service as missions
from app.core.exceptions import APIError
from app.schemas.daily_mission import DailyMissionVariationCreate
from app.services.child_age import (
	AGE_GROUPS,
	age_band_for_birth_date,
	age_on,
	child_age_band,
	child_age_band_or_none,
	ensure_task_age_eligible,
	ineligible_daily_task_ids,
)
from app.services.daily_mission_service import (
	ensure_daily_choices,
	select_assignment,
	skip_assignment,
	start_assignment,
	unfinished_assignments,
)
from app.services.mission_catalogue_service import apply_catalogue
from tests.sqlite_world import (
	ChildProfile,
	DailyMissionAssignment,
	DailyMissionVariation,
	Task,
	User,
	make_family,
	world_session,  # noqa: F401  (fixture)
)

TODAY = date(2026, 11, 19)
NOW = datetime(2026, 11, 19, 9, 0, tzinfo=timezone.utc)


def _born(years: int, today: date = TODAY, days_after_birthday: int = 30) -> date:
	"""A birth date making the child exactly ``years`` old on ``today`` (birthday ``days_after_birthday`` ago)."""
	birthday_this_year = today - timedelta(days=days_after_birthday)
	return birthday_this_year.replace(year=birthday_this_year.year - years)


@pytest.fixture
def catalogue(world_session, monkeypatch):
	apply_catalogue(world_session, publish=True)
	world_session.commit()
	clock = {"now": NOW}
	monkeypatch.setattr(missions, "_now", lambda: clock["now"])
	return clock


def _variation_band(session, row) -> str:
	return session.get(DailyMissionVariation, row.variation_id).age_band


# ---- the age rule ---------------------------------------------------------------------------------------


def test_the_configured_groups_are_the_catalogues_three_bands():
	assert AGE_GROUPS == (("4_6", 4, 6), ("7_10", 7, 10), ("11_15", 11, 15))


@pytest.mark.parametrize(
	"age, band",
	[(3, None), (4, "4_6"), (6, "4_6"), (7, "7_10"), (10, "7_10"), (11, "11_15"), (15, "11_15"), (16, None)],
)
def test_every_group_boundary(age, band):
	assert age_band_for_birth_date(_born(age), TODAY) == band


@pytest.mark.parametrize("years, before, on", [(7, "4_6", "7_10"), (11, "7_10", "11_15"), (4, None, "4_6"), (16, "11_15", None)])
def test_the_group_changes_on_the_birthday_not_a_day_early(years, before, on):
	birthday = date(2026, 3, 10)
	birth = birthday.replace(year=birthday.year - years)
	assert age_band_for_birth_date(birth, birthday - timedelta(days=1)) == before
	assert age_band_for_birth_date(birth, birthday) == on


def test_a_leap_day_birthday_counts_from_march_first_in_other_years():
	birth = date(2016, 2, 29)
	assert age_on(birth, date(2023, 2, 28)) == 6
	assert age_on(birth, date(2023, 3, 1)) == 7
	assert age_band_for_birth_date(birth, date(2023, 2, 28)) == "4_6"
	assert age_band_for_birth_date(birth, date(2023, 3, 1)) == "7_10"


def test_a_future_birth_date_has_no_group():
	assert age_band_for_birth_date(TODAY + timedelta(days=1), TODAY) is None


def test_missing_birth_date_is_an_error_never_a_default_group(world_session):
	child = make_family(world_session)
	child.date_of_birth = None
	with pytest.raises(APIError) as error:
		child_age_band(world_session, child, NOW)
	assert (error.value.status_code, error.value.code) == (422, "birth_date_required")
	assert child_age_band_or_none(world_session, child, NOW) is None


def test_invalid_and_out_of_range_birth_dates_are_clear_errors(world_session):
	child = make_family(world_session, birth=TODAY + timedelta(days=3))
	with pytest.raises(APIError) as error:
		child_age_band(world_session, child, NOW)
	assert error.value.code == "birth_date_invalid"
	child.date_of_birth = _born(2)
	with pytest.raises(APIError) as error:
		child_age_band(world_session, child, NOW)
	assert error.value.code == "daily_missions_age_range"


def test_the_group_uses_the_family_local_date(world_session):
	# Turns 7 on 2026-11-20. At 20:00 UTC on the 19th it is already the 20th in Kolkata (+5:30), not in UTC.
	birth = date(2019, 11, 20)
	evening = datetime(2026, 11, 19, 20, 0, tzinfo=timezone.utc)
	in_utc = make_family(world_session, birth=birth)
	in_kolkata = make_family(world_session, birth=birth, timezone_name="Asia/Kolkata")
	assert child_age_band(world_session, in_utc, evening)[1] == "4_6"
	assert child_age_band(world_session, in_kolkata, evening)[1] == "7_10"


def test_admin_variations_only_accept_the_real_groups():
	base = dict(
		locale="en",
		title="Sound Hunt",
		description="Listen for safe sounds.",
		instructions="Listen beside a trusted grown-up.",
		safety_instructions="Use safe household objects only.",
		completion_criteria="Tell a grown-up one sound you noticed.",
		duration_minutes=8,
	)
	for wrong in ("4-6", "3_5", "4_7", "all", ""):
		with pytest.raises(ValidationError):
			DailyMissionVariationCreate(age_band=wrong, **base)
	assert DailyMissionVariationCreate(age_band="11_15", **base).age_band == "11_15"


# ---- assignment: each group gets only its own missions ------------------------------------------------


@pytest.mark.parametrize("years", list(range(4, 16)))
def test_a_child_of_every_age_gets_only_missions_for_their_group(world_session, catalogue, years):
	child = make_family(world_session, birth=_born(years))
	expected = age_band_for_birth_date(child.date_of_birth, TODAY)
	_, band, rows = ensure_daily_choices(world_session, child, NOW)
	world_session.commit()
	assert band == expected
	assert len(rows) == 3
	assert {row.age_band for row in rows} == {expected}
	assert {_variation_band(world_session, row) for row in rows} == {expected}


@pytest.mark.parametrize("years", list(range(7, 16)))
def test_a_child_outside_4_to_6_never_receives_a_4_to_6_mission_over_a_month(world_session, catalogue, years):
	child = make_family(world_session, birth=_born(years, days_after_birthday=200))
	for day in range(30):
		catalogue["now"] = NOW + timedelta(days=day)
		_, _, rows = ensure_daily_choices(world_session, child, catalogue["now"])
		world_session.commit()
		assert rows and all(row.age_band != "4_6" for row in rows)
		assert all(_variation_band(world_session, row) != "4_6" for row in rows)
	stored = world_session.query(DailyMissionAssignment).filter(DailyMissionAssignment.child_id == child.id).all()
	assert stored and all(row.age_band != "4_6" for row in stored)


def test_two_children_of_one_family_each_get_their_own_group(world_session, catalogue):
	young = make_family(world_session, birth=_born(5))
	user = User(preferred_language="en")
	world_session.add(user)
	world_session.flush()
	older = ChildProfile(user_id=user.id, family_id=young.family_id, date_of_birth=_born(12))
	world_session.add(older)
	world_session.flush()
	young_rows = ensure_daily_choices(world_session, young, NOW)[2]
	older_rows = ensure_daily_choices(world_session, older, NOW)[2]
	world_session.commit()
	assert {r.age_band for r in young_rows} == {"4_6"}
	assert {r.age_band for r in older_rows} == {"11_15"}
	assert {r.child_id for r in older_rows} == {older.id}


# ---- existing assignments for another group --------------------------------------------------------------


def _rows(session, child):
	return session.query(DailyMissionAssignment).filter(DailyMissionAssignment.child_id == child.id).all()


def test_a_same_day_move_from_4_6_to_7_10_gives_fresh_choices_at_once(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))  # entered wrongly as a 5-year-old
	before = ensure_daily_choices(world_session, child, NOW)[2]
	world_session.commit()
	old_ids = {r.id for r in before}
	assert {r.age_band for r in before} == {"4_6"}

	child.date_of_birth = _born(9)  # the parent corrects it the same day
	world_session.commit()
	_, band, after = ensure_daily_choices(world_session, child, NOW)
	world_session.commit()

	assert band == "7_10"
	assert len(after) == 3 and {r.age_band for r in after} == {"7_10"}
	assert {_variation_band(world_session, r) for r in after} == {"7_10"}
	assert not old_ids & {r.id for r in after}, "new rows, not the old ones"
	assert sorted(r.choice_slot for r in after) == [1, 2, 3]

	stored = {r.id: r for r in _rows(world_session, child)}
	assert old_ids <= set(stored), "old assignments are kept for history, not deleted"
	assert len(stored) == 6, "exactly three new rows: no duplicates"
	for old in (stored[i] for i in old_ids):
		assert (old.age_band, old.status, old.is_current) == ("4_6", "available", False)
		assert old.snapshot and old.task_id is None


def test_asking_again_after_the_move_changes_nothing(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))
	ensure_daily_choices(world_session, child, NOW)
	world_session.commit()
	child.date_of_birth = _born(9)
	world_session.commit()
	first = [r.id for r in ensure_daily_choices(world_session, child, NOW)[2]]
	world_session.commit()
	again = [r.id for r in ensure_daily_choices(world_session, child, NOW)[2]]
	world_session.commit()
	assert first == again and len(_rows(world_session, child)) == 6


def test_a_birthday_during_the_day_moves_the_child_up_at_once(world_session, catalogue):
	# Turns 7 on the 20th; 7pm UTC on the 19th is already the 20th in Kolkata (+5:30).
	child = make_family(world_session, birth=date(2019, 11, 20), timezone_name="Asia/Kolkata")
	early = datetime(2026, 11, 19, 12, 0, tzinfo=timezone.utc)  # still the 19th in Kolkata: age 6
	assert {r.age_band for r in ensure_daily_choices(world_session, child, early)[2]} == {"4_6"}
	world_session.commit()
	evening = datetime(2026, 11, 19, 19, 0, tzinfo=timezone.utc)  # the 20th in Kolkata
	catalogue["now"] = evening
	_, band, rows = ensure_daily_choices(world_session, child, evening)
	assert band == "7_10" and len(rows) == 3 and {r.age_band for r in rows} == {"7_10"}


def test_a_chosen_old_group_mission_is_released_and_its_task_kept_but_closed(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))
	rows = ensure_daily_choices(world_session, child, NOW)[2]
	picked = select_assignment(world_session, child, rows[0].id)
	start_assignment(world_session, child, picked.id)
	world_session.commit()
	task_id = picked.task_id

	child.date_of_birth = _born(9)
	world_session.commit()
	_, band, after = ensure_daily_choices(world_session, child, NOW)
	world_session.commit()

	assert band == "7_10" and len(after) == 3 and {r.age_band for r in after} == {"7_10"}
	old = world_session.get(DailyMissionAssignment, picked.id)
	assert (old.status, old.is_current, old.task_id, old.age_band) == ("in_progress", False, task_id, "4_6")
	assert world_session.get(Task, task_id).is_active, "the task and any submissions stay on record"
	with pytest.raises(APIError) as error:
		ensure_task_age_eligible(world_session, child, task_id, NOW)
	assert error.value.code == "mission_not_age_eligible"
	# The child can now choose one of the new group's missions (the one-a-day slot was freed).
	assert select_assignment(world_session, child, after[0].id).status == "selected"


@pytest.mark.parametrize("status", ["pending_parent_approval", "approved"])
def test_progress_is_never_released_when_the_group_changes(world_session, catalogue, status):
	child = make_family(world_session, birth=_born(5))
	rows = ensure_daily_choices(world_session, child, NOW)[2]
	picked = select_assignment(world_session, child, rows[0].id)
	picked.status = status  # what submitting / approving records
	world_session.commit()

	child.date_of_birth = _born(9)
	world_session.commit()
	_, band, after = ensure_daily_choices(world_session, child, NOW)
	world_session.commit()

	kept = world_session.get(DailyMissionAssignment, picked.id)
	assert (kept.status, kept.is_current, kept.age_band) == (status, True, "4_6")
	assert band == "7_10" and after and {r.age_band for r in after} == {"7_10"}
	assert picked.id not in {r.id for r in after}, "never shown as a current mission"
	assert len(after) <= 2, "its slot stays held: progress is not discarded"


def test_a_rejected_old_group_mission_is_released_with_its_history(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))
	rows = ensure_daily_choices(world_session, child, NOW)[2]
	picked = select_assignment(world_session, child, rows[0].id)
	picked.status = "rejected"
	world_session.commit()
	child.date_of_birth = _born(9)
	world_session.commit()
	after = ensure_daily_choices(world_session, child, NOW)[2]
	world_session.commit()
	old = world_session.get(DailyMissionAssignment, picked.id)
	assert (old.status, old.is_current) == ("rejected", False)
	assert len(after) == 3 and {r.age_band for r in after} == {"7_10"}


def test_the_move_is_not_a_skip_and_uses_no_skips(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))
	ensure_daily_choices(world_session, child, NOW)
	world_session.commit()
	child.date_of_birth = _born(9)
	world_session.commit()
	after = ensure_daily_choices(world_session, child, NOW)[2]
	world_session.commit()
	assert not [r for r in _rows(world_session, child) if r.status == "skipped"]
	skipped, replacement = skip_assignment(world_session, child, after[0].id, NOW)
	world_session.commit()
	assert skipped.status == "skipped" and {r.age_band for r in replacement} == {"7_10"}


def test_the_move_pays_nothing_and_touches_no_ledger(world_session, catalogue):
	# The SQLite world has no ledger tables: any attempt to pay or recalculate would fail here.
	child = make_family(world_session, birth=_born(5))
	rows = ensure_daily_choices(world_session, child, NOW)[2]
	select_assignment(world_session, child, rows[0].id)
	world_session.commit()
	child.date_of_birth = _born(9)
	world_session.commit()
	ensure_daily_choices(world_session, child, NOW)
	world_session.commit()


def test_an_ineligible_choice_cannot_be_chosen_started_or_skipped_by_id(world_session, catalogue):
	child = make_family(world_session, birth=_born(5))
	rows = ensure_daily_choices(world_session, child, NOW)[2]
	picked = select_assignment(world_session, child, rows[0].id)
	world_session.commit()
	other = rows[1]
	child.date_of_birth = _born(8)
	world_session.commit()

	for action in (
		lambda: select_assignment(world_session, child, other.id),
		lambda: start_assignment(world_session, child, picked.id),
		lambda: skip_assignment(world_session, child, other.id, NOW),
	):
		with pytest.raises(APIError) as error:
			action()
		assert (error.value.status_code, error.value.code) == (409, "mission_not_age_eligible")
	world_session.rollback()
	assert world_session.get(DailyMissionAssignment, picked.id).status == "selected"


def test_an_unfinished_mission_from_the_old_group_is_not_carried_forward(world_session, catalogue):
	birth = date(2019, 11, 20)  # 6 on the 19th, 7 from the 20th
	child = make_family(world_session, birth=birth)
	day1 = ensure_daily_choices(world_session, child, NOW)[2]
	assert {r.age_band for r in day1} == {"4_6"}
	picked = select_assignment(world_session, child, day1[0].id)
	world_session.commit()

	day2 = NOW + timedelta(days=1)
	catalogue["now"] = day2
	assert unfinished_assignments(world_session, child, day2) == []
	_, band, today = ensure_daily_choices(world_session, child, day2)
	world_session.commit()
	assert band == "7_10" and {r.age_band for r in today} == {"7_10"}

	# Still on record, with its task: history, not a current mission.
	row = world_session.get(DailyMissionAssignment, picked.id)
	assert (row.status, row.is_current, row.task_id) == ("selected", True, picked.task_id)
	blocked = {task_id for (task_id,) in ineligible_daily_task_ids(world_session, child, band).all()}
	assert blocked == {picked.task_id}
	with pytest.raises(APIError) as error:
		ensure_task_age_eligible(world_session, child, picked.task_id, day2)
	assert error.value.code == "mission_not_age_eligible"


def test_an_unfinished_mission_in_the_same_group_is_still_carried_forward(world_session, catalogue):
	child = make_family(world_session, birth=_born(8))
	picked = select_assignment(world_session, child, ensure_daily_choices(world_session, child, NOW)[2][0].id)
	world_session.commit()
	day2 = NOW + timedelta(days=1)
	catalogue["now"] = day2
	assert [r.id for r in unfinished_assignments(world_session, child, day2)] == [picked.id]
	assert ineligible_daily_task_ids(world_session, child, "7_10").all() == []
	ensure_task_age_eligible(world_session, child, picked.task_id, day2)  # no error


def test_without_a_birth_date_nothing_is_carried_forward_or_offered(world_session, catalogue):
	child = make_family(world_session, birth=_born(8))
	picked = select_assignment(world_session, child, ensure_daily_choices(world_session, child, NOW)[2][0].id)
	world_session.commit()
	child.date_of_birth = None
	world_session.commit()
	assert unfinished_assignments(world_session, child, NOW + timedelta(days=1)) == []
	with pytest.raises(APIError) as error:
		ensure_daily_choices(world_session, child, NOW)
	assert error.value.code == "birth_date_required"
	blocked = {task_id for (task_id,) in ineligible_daily_task_ids(world_session, child, None).all()}
	assert blocked == {picked.task_id}


def test_family_missions_from_a_parent_have_no_age_group_and_stay_eligible(world_session, catalogue):
	child = make_family(world_session, birth=_born(12))
	task = Task(family_id=child.family_id, created_by=uuid4(), title="Water the plants", description="")
	world_session.add(task)
	world_session.commit()
	ensure_task_age_eligible(world_session, child, task.id, NOW)  # no error
