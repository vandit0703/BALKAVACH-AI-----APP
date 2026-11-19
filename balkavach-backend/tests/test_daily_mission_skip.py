"""Skip + replacement of today's daily mission choices (roadmap Phase 2, MIS-03).

Runs on the in-memory SQLite world (``tests/sqlite_world.py``): production uses ``autoflush=False`` and a
partial unique index on the current slot, and both are reproduced there. PostgreSQL row locking is not.
"""

import pytest

from app.core.exceptions import APIError
from app.services.daily_mission_service import (
	MAX_SKIPS_PER_DAY,
	ensure_daily_choices,
	select_assignment,
	skip_assignment,
	weekly_summary,
)
from tests.sqlite_world import make_family, publish_templates, world_session  # noqa: F401  (fixture)


def _setup(session, templates: int = 8):
	child = make_family(session)
	publish_templates(session, templates)
	_, _, choices = ensure_daily_choices(session, child)
	session.commit()
	return child, choices


def test_skip_returns_a_replacement_in_the_same_response(world_session):
	child, choices = _setup(world_session)
	skipped_id = choices[0].id

	skipped, current = skip_assignment(world_session, child, skipped_id)

	assert skipped.status == "skipped" and skipped.is_current is False
	assert len(current) == 3
	assert skipped_id not in {row.id for row in current}
	assert skipped.template_id not in {row.template_id for row in current}
	assert {row.choice_slot for row in current} == {1, 2, 3}
	assert all(row.status == "available" and row.is_current for row in current)


def test_a_skipped_mission_is_not_offered_again_the_same_day(world_session):
	child, choices = _setup(world_session)
	skipped_template = choices[1].template_id
	skip_assignment(world_session, child, choices[1].id)
	world_session.commit()

	for _ in range(2):  # the next GET /today, twice
		_, _, today = ensure_daily_choices(world_session, child)
		assert skipped_template not in {row.template_id for row in today}


def test_repeated_skips_stop_at_the_daily_limit(world_session):
	child, choices = _setup(world_session)
	current = choices
	for _ in range(MAX_SKIPS_PER_DAY):
		_, current = skip_assignment(world_session, child, current[0].id)
		world_session.commit()
	with pytest.raises(APIError) as error:
		skip_assignment(world_session, child, current[0].id)
	assert error.value.status_code == 409 and error.value.code == "daily_skip_limit"
	assert len({row.template_id for row in ensure_daily_choices(world_session, child)[2]}) == 3


def test_resending_the_same_skip_cannot_produce_another_choice(world_session):
	child, choices = _setup(world_session)
	skipped_id = choices[0].id
	_, first = skip_assignment(world_session, child, skipped_id)
	world_session.commit()
	with pytest.raises(APIError) as error:
		skip_assignment(world_session, child, skipped_id)
	assert error.value.code == "daily_mission_cannot_skip"
	assert [row.id for row in ensure_daily_choices(world_session, child)[2]] == [row.id for row in first]


def test_a_mission_awaiting_review_cannot_be_skipped(world_session):
	child, choices = _setup(world_session)
	picked = select_assignment(world_session, child, choices[0].id)
	picked.status = "pending_parent_approval"
	world_session.commit()
	with pytest.raises(APIError) as error:
		skip_assignment(world_session, child, picked.id)
	assert error.value.status_code == 409 and error.value.code == "daily_mission_cannot_skip"


def test_an_approved_mission_cannot_be_skipped(world_session):
	child, choices = _setup(world_session)
	picked = select_assignment(world_session, child, choices[0].id)
	picked.status = "approved"
	world_session.commit()
	with pytest.raises(APIError) as error:
		skip_assignment(world_session, child, picked.id)
	assert error.value.code == "daily_mission_cannot_skip"


def test_skipping_a_selected_mission_deactivates_its_task_and_frees_the_day(world_session):
	child, choices = _setup(world_session)
	picked = select_assignment(world_session, child, choices[0].id)
	world_session.commit()
	_, current = skip_assignment(world_session, child, picked.id)
	world_session.commit()
	assert len(current) == 3 and all(row.status == "available" for row in current)
	# another mission can now be chosen
	again = select_assignment(world_session, child, current[0].id)
	assert again.status == "selected"


def test_a_thin_catalogue_gives_a_clear_error_instead_of_a_server_error(world_session):
	child, choices = _setup(world_session, templates=3)  # nothing left to replace with
	with pytest.raises(APIError) as error:
		skip_assignment(world_session, child, choices[0].id)
	assert error.value.status_code == 409 and error.value.code == "daily_mission_no_replacement"


def test_weekly_summary_reports_the_day_by_its_current_state_not_by_row_order(world_session):
	child, choices = _setup(world_session)
	_, current = skip_assignment(world_session, child, choices[0].id)
	picked = select_assignment(world_session, child, current[0].id)
	picked.status = "approved"
	world_session.commit()

	summary = weekly_summary(world_session, child)

	assert summary["skipped_count"] == 1
	assert summary["completed_count"] == 1
	assert list(summary["daily_status"].values()) == ["approved"]
