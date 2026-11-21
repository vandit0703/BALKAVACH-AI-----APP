"""HTTP-level: a child never gets, opens or completes a daily mission made for another age group.

Isolated PostgreSQL test database only (``TEST_DATABASE_URL``; skipped without it, see ``tests/conftest.py``).
The same rules are proven on SQLite with the real catalogue in ``tests/test_child_age_eligibility.py``.
"""

from datetime import date, timedelta

from app.services.mission_catalogue_service import apply_catalogue


def _years_ago(years: int) -> str:
	today = date.today()
	# Birthday 60 days ago, so the test does not straddle a birthday.
	birthday = today - timedelta(days=60)
	return birthday.replace(year=birthday.year - years).isoformat()


def _set_birth_date(api, ctx, years: int) -> None:
	response = api.patch(
		f"/families/{ctx['family']['id']}/children/{ctx['child']['id']}",
		ctx["parent"]["token"],
		{"date_of_birth": _years_ago(years)},
	)
	assert response.status_code == 200, response.text


def _ready(api, years: int):
	apply_catalogue(api.session, publish=True)
	api.session.commit()
	ctx = api.family_with_child()
	_set_birth_date(api, ctx, years)
	return ctx


def test_each_age_group_gets_only_its_own_daily_missions(api):
	for years, band in [(4, "4_6"), (6, "4_6"), (7, "7_10"), (10, "7_10"), (11, "11_15"), (15, "11_15")]:
		ctx = _ready(api, years)
		today = api.get("/daily-missions/today", ctx["child"]["token"])
		assert today.status_code == 200, today.text
		body = today.json()
		assert body["age_band"] == band
		assert body["choices"] and {c["age_band"] for c in body["choices"]} == {band}


def test_missing_birth_date_is_a_clear_error_not_a_default_group(api):
	apply_catalogue(api.session, publish=True)
	api.session.commit()
	ctx = api.family_with_child()
	response = api.get("/daily-missions/today", ctx["child"]["token"])
	assert response.status_code == 422
	assert response.json()["error"]["code"] == "birth_date_required"
	assert api.get("/daily-missions/unfinished", ctx["child"]["token"]).json() == []


def test_after_a_birth_date_correction_old_group_missions_are_history_only(api):
	ctx = _ready(api, 5)
	kid = ctx["child"]["token"]
	choices = api.get("/daily-missions/today", kid).json()["choices"]
	assert {c["age_band"] for c in choices} == {"4_6"}
	picked = api.post(f"/daily-missions/{choices[0]['id']}/select", kid).json()
	task_id = picked["task_id"]
	assert task_id in {t["id"] for t in api.get("/tasks", kid).json()}

	_set_birth_date(api, ctx, 9)

	# At once: three fresh choices for the new group; the old ones are not offered, listed or carried forward.
	today = api.get("/daily-missions/today", kid).json()
	assert today["age_band"] == "7_10"
	assert len(today["choices"]) == 3 and all(c["age_band"] == "7_10" for c in today["choices"])
	assert task_id not in {t["id"] for t in api.get("/tasks", kid).json()}
	assert api.get("/daily-missions/unfinished", kid).json() == []
	active = api.get("/daily-missions/active", kid).json()
	assert active is None or active["age_band"] == "7_10"

	# Cannot be opened for action or completed by id.
	for path in (f"/daily-missions/{choices[1]['id']}/select", f"/daily-missions/{picked['id']}/start"):
		# Released rows are no longer current (404); any still-current wrong-group row is refused (409).
		refused = api.post(path, kid)
		assert refused.status_code in (404, 409), path
		assert refused.json()["error"]["code"] in {"daily_assignment_not_found", "mission_not_age_eligible"}
	submitted = api.submit(kid, task_id)
	assert submitted.status_code == 409
	assert submitted.json()["error"]["code"] == "mission_not_age_eligible"

	# History keeps every record, unchanged.
	history = api.get("/daily-missions/history", kid).json()["items"]
	assert picked["id"] in {item["id"] for item in history}
	assert {item["status"] for item in history if item["id"] == picked["id"]} == {"selected"}


def test_a_family_mission_from_a_parent_has_no_age_group(api):
	ctx = _ready(api, 12)
	task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], title="Water the plants")
	assert task["id"] in {t["id"] for t in api.get("/tasks", ctx["child"]["token"]).json()}
	assert api.submit(ctx["child"]["token"], task["id"]).status_code == 201
