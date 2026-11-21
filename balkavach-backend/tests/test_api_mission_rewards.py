"""Every approved mission pays exactly 10 stars and 15 XP, once (isolated PostgreSQL test database only).

These are HTTP-level integration tests: they need ``TEST_DATABASE_URL`` pointing at a disposable PostgreSQL
database whose name contains "test" and are skipped without it (see ``tests/conftest.py``).
"""


def _progress(api, child):
	response = api.get(f"/progress/children/{child['id']}", child["token"])
	assert response.status_code == 200, response.text
	body = response.json()
	return body["star_balance"], body["total_xp"]


def test_an_approved_mission_pays_exactly_ten_stars_and_fifteen_xp_once(api):
	ctx = api.family_with_child()
	parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
	task = api.create_task(parent, family["id"], star_reward=50, xp_reward=500)

	# The app shows what the backend will pay, to the child and to the parent.
	assert (task["star_reward"], task["xp_reward"]) == (10, 15)
	listed = [t for t in api.get("/tasks", child["token"]).json() if t["id"] == task["id"]]
	assert [(t["star_reward"], t["xp_reward"]) for t in listed] == [(10, 15)]

	# Opening (listing) and submitting pay nothing.
	submission = api.submit(child["token"], task["id"])
	assert submission.status_code == 201, submission.text
	assert _progress(api, child) == (0, 0)
	queue = api.get(f"/reviews/pending?family_id={family['id']}", parent).json()
	assert [(q["star_reward"], q["xp_reward"]) for q in queue] == [(10, 15)]

	# Approval pays once; retries and refreshes never pay again.
	assert api.review(parent, submission.json()["id"], "approved").status_code == 200
	assert _progress(api, child) == (10, 15)
	assert api.review(parent, submission.json()["id"], "approved").status_code == 409
	assert api.review(parent, submission.json()["id"], "rejected").status_code == 409
	assert _progress(api, child) == (10, 15)
	assert _progress(api, child) == (10, 15)

	mine = api.get("/tasks/submissions/mine", child["token"]).json()
	assert [(s["status"], s["stars_awarded"], s["xp_awarded"]) for s in mine] == [("approved", 10, 15)]

	# A one-time mission cannot be completed (and paid) again.
	again = api.submit(child["token"], task["id"])
	assert again.status_code == 409
	assert again.json()["error"]["code"] == "task_already_completed"
	assert _progress(api, child) == (10, 15)


def test_a_rejected_attempt_pays_nothing_and_the_approved_retry_pays_once(api):
	ctx = api.family_with_child()
	parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
	task = api.create_task(parent, family["id"])
	first = api.submit(child["token"], task["id"]).json()
	assert api.review(parent, first["id"], "rejected", "Try again").status_code == 200
	assert _progress(api, child) == (0, 0)

	second = api.submit(child["token"], task["id"]).json()
	assert api.review(parent, second["id"], "approved").status_code == 200
	assert _progress(api, child) == (10, 15)

	mine = {s["submission_number"]: s for s in api.get("/tasks/submissions/mine", child["token"]).json()}
	assert (mine[1]["status"], mine[1]["stars_awarded"], mine[1]["xp_awarded"]) == ("rejected", 0, 0)
	assert (mine[2]["status"], mine[2]["stars_awarded"], mine[2]["xp_awarded"]) == ("approved", 10, 15)


def test_each_approved_mission_pays_and_the_day_totals_match(api):
	ctx = api.family_with_child()
	parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
	for title in ("Read", "Run"):
		task = api.create_task(parent, family["id"], title=title, star_reward=1, xp_reward=1)
		sub = api.submit(child["token"], task["id"]).json()
		assert api.review(parent, sub["id"], "approved").status_code == 200
	assert _progress(api, child) == (20, 30)
	day = api.get(f"/progress/children/{child['id']}", child["token"]).json()["activity_days"][0]
	assert (day["completed_tasks"], day["stars_earned"], day["xp_earned"]) == (2, 20, 30)


def test_a_parent_cannot_change_a_missions_reward(api):
	ctx = api.family_with_child()
	parent, family = ctx["parent"]["token"], ctx["family"]
	task = api.create_task(parent, family["id"])
	edited = api.patch(f"/tasks/{task['id']}", parent, {"star_reward": 99, "xp_reward": 999, "title": "Make the bed well"})
	assert edited.status_code == 200, edited.text
	assert (edited.json()["title"], edited.json()["star_reward"], edited.json()["xp_reward"]) == ("Make the bed well", 10, 15)
