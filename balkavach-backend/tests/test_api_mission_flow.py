"""HTTP-level tests for the mission workflow (isolated test database only)."""

from tests.harness import in_days


def _types(api, token):
    response = api.get("/notifications", token)
    assert response.status_code == 200, response.text
    return [item["notification_type"] for item in response.json()]


def test_full_mission_flow_awards_once_and_notifies(api):
    ctx = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"], assigned_child_id=child["id"], star_reward=5, xp_reward=20)

    submission = api.submit(child["token"], task["id"])
    assert submission.status_code == 201, submission.text
    assert submission.json()["status"] == "pending"
    assert "task_submitted" in _types(api, parent)

    reviewed = api.review(parent, submission.json()["id"], "approved", "Great job")
    assert reviewed.status_code == 200, reviewed.text
    assert api.review(parent, submission.json()["id"], "approved").status_code == 409

    progress = api.get(f"/progress/children/{child['id']}", child["token"]).json()
    assert progress["star_balance"] == 5
    assert progress["total_xp"] == 20
    assert progress["current_streak"] == 1
    assert "task_approved" in _types(api, child["token"])


def test_rejected_submission_awards_nothing_and_allows_resubmission(api):
    ctx = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"])
    first = api.submit(child["token"], task["id"]).json()
    assert api.review(parent, first["id"], "rejected", "Try again").status_code == 200
    assert api.get(f"/progress/children/{child['id']}", child["token"]).json()["star_balance"] == 0

    second = api.submit(child["token"], task["id"])
    assert second.status_code == 201, second.text
    assert second.json()["submission_number"] == 2


def test_duplicate_pending_submission_is_rejected(api):
    ctx = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"])
    assert api.submit(child["token"], task["id"]).status_code == 201
    again = api.submit(child["token"], task["id"])
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "submission_pending"


def test_approved_one_time_task_cannot_be_submitted_again(api):
    ctx = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"])
    sub = api.submit(child["token"], task["id"]).json()
    api.review(parent, sub["id"], "approved")
    again = api.submit(child["token"], task["id"])
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "task_already_completed"


def test_child_can_list_only_own_submissions(api):
    ctx = api.family_with_child("Asha")
    parent, family, asha = ctx["parent"]["token"], ctx["family"], ctx["child"]
    ravi = api.create_child(parent, family["id"], "Ravi")
    task = api.create_task(parent, family["id"])
    api.submit(asha["token"], task["id"])
    api.submit(ravi["token"], task["id"])

    mine = api.get("/tasks/submissions/mine", asha["token"])
    assert mine.status_code == 200, mine.text
    assert [s["child_id"] for s in mine.json()] == [asha["id"]]
    assert api.get("/tasks/submissions/mine?status=approved", asha["token"]).json() == []
    assert api.get("/tasks/submissions/mine", parent).status_code == 403


def test_pending_review_queue_is_family_scoped_and_joined(api):
    ctx = api.family_with_child("Asha")
    other = api.family_with_child("Stranger")
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"], title="Read a book")
    api.submit(child["token"], task["id"])
    other_task = api.create_task(other["parent"]["token"], other["family"]["id"], title="Other")
    api.submit(other["child"]["token"], other_task["id"])

    queue = api.get(f"/reviews/pending?family_id={family['id']}", parent)
    assert queue.status_code == 200, queue.text
    rows = queue.json()
    assert len(rows) == 1
    assert rows[0]["task_title"] == "Read a book"
    assert rows[0]["child_name"] == "Asha"
    assert rows[0]["status"] == "pending"
    assert api.get(f"/reviews/pending?family_id={family['id']}", other["parent"]["token"]).status_code == 404
    assert api.get(f"/reviews/pending?family_id={family['id']}", child["token"]).status_code == 403


def test_assignment_notifies_the_child_and_unassigned_notifies_family_children(api):
    ctx = api.family_with_child("Asha")
    parent, family, asha = ctx["parent"]["token"], ctx["family"], ctx["child"]
    ravi = api.create_child(parent, family["id"], "Ravi")
    api.create_task(parent, family["id"], assigned_child_id=asha["id"], title="Only Asha")
    assert "task_assigned" in _types(api, asha["token"])
    assert "task_assigned" not in _types(api, ravi["token"])

    api.create_task(parent, family["id"], title="For everyone")
    assert _types(api, ravi["token"]).count("task_assigned") == 1


def test_mission_due_date_and_validation(api):
    ctx = api.family_with_child()
    parent, family = ctx["parent"]["token"], ctx["family"]
    ok = api.post("/tasks", parent, {"family_id": family["id"], "title": "Due soon", "due_at": in_days(2)})
    assert ok.status_code == 201, ok.text
    naive = api.post("/tasks", parent, {"family_id": family["id"], "title": "Naive", "due_at": "2030-01-01T10:00:00"})
    assert naive.status_code == 422
    short = api.post("/tasks", parent, {"family_id": family["id"], "title": "x"})
    assert short.status_code == 422


def test_parent_cannot_touch_another_familys_tasks(api):
    a = api.family_with_child()
    b = api.family_with_child()
    task = api.create_task(a["parent"]["token"], a["family"]["id"])
    assert api.patch(f"/tasks/{task['id']}", b["parent"]["token"], {"title": "Hijack"}).status_code == 404
    assert api.delete(f"/tasks/{task['id']}", b["parent"]["token"]).status_code == 404
    assert api.get(f"/tasks/{task['id']}/submissions", b["parent"]["token"]).status_code == 404
    assert api.submit(b["child"]["token"], task["id"]).status_code == 404


def test_child_cannot_submit_a_task_assigned_to_a_sibling(api):
    ctx = api.family_with_child("Asha")
    parent, family, asha = ctx["parent"]["token"], ctx["family"], ctx["child"]
    ravi = api.create_child(parent, family["id"], "Ravi")
    task = api.create_task(parent, family["id"], assigned_child_id=asha["id"])
    denied = api.submit(ravi["token"], task["id"])
    assert denied.status_code == 403
    assert denied.json()["error"]["code"] == "task_not_assigned"


def test_my_submissions_include_title_and_parent_feedback(api):
    ctx = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    task = api.create_task(parent, family["id"], title="Tidy the shelf")
    first = api.submit(child["token"], task["id"]).json()
    api.review(parent, first["id"], "rejected", "Please also dust it")
    second = api.submit(child["token"], task["id"]).json()

    rows = api.get("/tasks/submissions/mine", child["token"]).json()
    assert [r["submission_number"] for r in rows] == [2, 1]
    assert {r["task_title"] for r in rows} == {"Tidy the shelf"}
    by_id = {r["id"]: r for r in rows}
    assert by_id[first["id"]]["review_note"] == "Please also dust it"
    assert by_id[second["id"]]["review_note"] is None
    assert by_id[first["id"]]["status"] == "rejected" and by_id[second["id"]]["status"] == "pending"


def test_family_submission_history_filters_by_status_and_is_scoped(api):
    ctx = api.family_with_child("Asha")
    other = api.family_with_child()
    parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
    approved_task = api.create_task(parent, family["id"], title="Approve me")
    rejected_task = api.create_task(parent, family["id"], title="Reject me")
    waiting_task = api.create_task(parent, family["id"], title="Wait for me")
    for task, decision in [(approved_task, "approved"), (rejected_task, "rejected"), (waiting_task, None)]:
        sub = api.submit(child["token"], task["id"]).json()
        if decision:
            api.review(parent, sub["id"], decision)

    base = f"/reviews/submissions?family_id={family['id']}"
    everything = api.get(base, parent).json()
    assert {r["task_title"] for r in everything} == {"Approve me", "Reject me", "Wait for me"}
    assert [r["status"] for r in api.get(base + "&status=pending", parent).json()] == ["pending"]
    combined = api.get(base + "&status=rejected&status=resubmission_requested", parent).json()
    assert [r["task_title"] for r in combined] == ["Reject me"]
    assert {r["status"] for r in api.get(base + "&status=approved", parent).json()} == {"approved"}
    assert api.get(base + "&status=bogus", parent).status_code == 422
    assert api.get(base, other["parent"]["token"]).status_code == 404
    assert api.get(base, child["token"]).status_code == 403
    # the original pending endpoint keeps working
    assert len(api.get(f"/reviews/pending?family_id={family['id']}", parent).json()) == 1
