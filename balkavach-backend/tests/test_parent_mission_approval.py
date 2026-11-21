"""Parent mission approval, driven through the REAL routes and the REAL ``review_submission`` (see approval_world).

Test type: in-memory SQLite. It runs the production service code unchanged (the PostgreSQL upserts compile on
SQLite) but it is NOT PostgreSQL: row locks are ignored, so truly simultaneous requests are not exercised, and the
live schema is not reflected. It touches no real database.
"""

from uuid import uuid4

import pytest

from app.services import task_service
from tests import sqlite_world as shared
from tests import video_world
from tests.approval_world import (
	ChildProgress, StarTransaction, TaskReview, TaskSubmission, XPTransaction, approval_db, make_family,
	make_submission,  # noqa: F401
)


@pytest.fixture
def client(approval_db):
	from fastapi.testclient import TestClient

	from app.core.dependencies import require_parent
	from app.db.session import get_db
	from app.main import app

	family = make_family(approval_db)
	app.dependency_overrides[require_parent] = lambda: family.parent
	app.dependency_overrides[get_db] = lambda: approval_db
	try:
		yield TestClient(app, raise_server_exceptions=False), family, approval_db
	finally:
		app.dependency_overrides.pop(require_parent, None)
		app.dependency_overrides.pop(get_db, None)


def review(http, submission, decision="approved", note=None):
	body = {"decision": decision, **({"review_note": note} if note else {})}
	return http.post(f"/api/v1/reviews/submissions/{submission.id}", json=body)


def paid(session):
	"""Everything an approval may pay: (star rows, XP rows, allowance seconds, review rows)."""
	return (
		[row.amount for row in session.query(StarTransaction)],
		[row.amount for row in session.query(XPTransaction)],
		[row.granted_seconds for row in session.query(video_world.VideoAccessEntitlement)],
		session.query(TaskReview).count(),
	)


Notification = shared.Notification
NOTHING = ([], [], [], 0)


def counts(http, family):
	out = {}
	for key, status in (("pending", "pending"), ("approved", "approved"), ("retry", "resubmission_requested")):
		response = http.get(f"/api/v1/reviews/submissions?family_id={family.family_id}&status={status}")
		assert response.status_code == 200, response.text
		out[key] = len(response.json())
	return out


def status_of(session, submission):
	session.expire_all()
	return session.query(TaskSubmission).filter_by(id=submission.id).one().status


def assignment_status(session):
	session.expire_all()
	return session.query(shared.DailyMissionAssignment).one().status


# ---- approve ---------------------------------------------------------------------------------------------------


def test_approving_pays_ten_stars_fifteen_xp_and_fifteen_minutes_exactly_once(client):
	http, family, session = client
	item = make_submission(session, family)
	assert counts(http, family) == {"pending": 1, "approved": 0, "retry": 0}

	response = review(http, item.submission)

	assert response.status_code == 200, response.text
	assert response.json()["status"] == "approved" and response.json()["id"] == str(item.submission.id)
	assert paid(session) == ([10], [15], [900], 1)
	assert assignment_status(session) == "approved"
	assert session.query(ChildProgress).one().total_xp == 15
	assert counts(http, family) == {"pending": 0, "approved": 1, "retry": 0}
	kinds = {row.notification_type for row in session.query(Notification)}
	assert {"task_approved", "mission_video_time_granted"} <= kinds


def test_the_queue_shows_what_an_approval_pays_from_the_backend(client):
	http, family, session = client
	make_submission(session, family)
	item = http.get(f"/api/v1/reviews/submissions?family_id={family.family_id}&status=pending").json()[0]
	assert (item["star_reward"], item["xp_reward"], item["video_minutes_reward"]) == (10, 15, 15)


def test_the_three_rewards_are_independent_a_full_daily_cap_still_pays_stars_and_xp(client):
	http, family, session = client
	row = session.query(shared.FamilySetting).one()
	row.video_settings = {"daily_limit_seconds": 900}
	session.commit()
	first = make_submission(session, family, title="First", daily=False)
	second = make_submission(session, family, title="Second", daily=False)

	assert review(http, first.submission).status_code == 200
	assert review(http, second.submission).status_code == 200

	stars, xp, seconds, reviews = paid(session)
	assert (stars, xp) == ([10, 10], [15, 15])
	assert seconds == [900], "the second mission found the daily cap full and unlocked no time"


# ---- reject and retry --------------------------------------------------------------------------------------------


@pytest.mark.parametrize(
	"decision,bucket", [("rejected", None), ("resubmission_requested", "retry")]
)
def test_a_declined_or_retried_mission_pays_nothing(client, decision, bucket):
	http, family, session = client
	item = make_submission(session, family)
	response = review(http, item.submission, decision, note="Try again with a drawing")
	assert response.status_code == 200, response.text
	assert response.json()["status"] == decision
	stars, xp, seconds, reviews = paid(session)
	assert (stars, xp, seconds, reviews) == ([], [], [], 1)
	assert assignment_status(session) == "rejected"
	expected = {"pending": 0, "approved": 0, "retry": 1 if bucket else 0}
	assert counts(http, family) == expected
	assert session.query(ChildProgress).count() == 0


# ---- repeats, lost responses, invalid and foreign requests ---------------------------------------------------------


def test_repeating_an_approval_returns_the_existing_result_and_pays_nothing_more(client):
	http, family, session = client
	item = make_submission(session, family)
	first = review(http, item.submission)
	again = review(http, item.submission)  # the first response was lost: the app retries
	third = review(http, item.submission)

	assert first.status_code == again.status_code == third.status_code == 200
	assert again.json() == first.json()
	assert paid(session) == ([10], [15], [900], 1)
	assert session.query(ChildProgress).one().total_xp == 15
	assert session.query(Notification).filter_by(notification_type="task_approved").count() == 1


def test_a_conflicting_second_decision_is_refused_and_changes_nothing(client):
	http, family, session = client
	item = make_submission(session, family)
	assert review(http, item.submission).status_code == 200
	response = review(http, item.submission, "rejected")
	assert response.status_code == 409
	assert response.json()["error"]["code"] == "submission_already_reviewed"
	assert paid(session) == ([10], [15], [900], 1)
	assert status_of(session, item.submission) == "approved"


def test_a_declined_mission_cannot_be_approved_afterwards(client):
	http, family, session = client
	item = make_submission(session, family)
	assert review(http, item.submission, "rejected").status_code == 200
	response = review(http, item.submission, "approved")
	assert response.status_code == 409
	assert paid(session) == ([], [], [], 1)


def test_an_unknown_submission_is_a_clear_404(client):
	http, family, session = client
	response = http.post(f"/api/v1/reviews/submissions/{uuid4()}", json={"decision": "approved"})
	assert response.status_code == 404
	assert response.json()["error"]["code"] == "submission_not_found"
	assert paid(session) == NOTHING


def test_another_familys_submission_cannot_be_approved(client):
	http, family, session = client
	other = make_family(session)
	foreign = make_submission(session, other)
	response = review(http, foreign.submission)
	assert response.status_code == 404
	assert response.json()["error"]["code"] == "submission_not_found"
	assert paid(session) == NOTHING
	assert status_of(session, foreign.submission) == "pending"


def test_only_a_pending_submission_can_be_reviewed(client):
	http, family, session = client
	item = make_submission(session, family)
	item.submission.status = "cancelled"
	session.commit()
	assert review(http, item.submission).status_code == 409
	assert paid(session) == NOTHING


def test_a_bad_decision_is_a_validation_error(client):
	http, family, session = client
	item = make_submission(session, family)
	response = http.post(f"/api/v1/reviews/submissions/{item.submission.id}", json={"decision": "maybe"})
	assert response.status_code == 422
	assert paid(session) == NOTHING


# ---- failures are atomic and named -----------------------------------------------------------------------------------


def test_a_failing_allowance_grant_rolls_everything_back_with_a_clear_error_and_the_retry_succeeds(client, monkeypatch):
	http, family, session = client
	item = make_submission(session, family)
	from app.services import video_entitlement_service as entitlements

	real = entitlements.grant_mission_video_entitlement

	def boom(*args, **kwargs):
		raise RuntimeError("entitlement table exploded")

	monkeypatch.setattr(entitlements, "grant_mission_video_entitlement", boom)
	response = review(http, item.submission)

	assert response.status_code == 500
	assert response.json()["error"]["code"] == "approval_failed"
	assert "Nothing was awarded" in response.json()["error"]["message"]
	assert paid(session) == NOTHING, "no star, XP, allowance or review row may survive a failed approval"
	assert status_of(session, item.submission) == "pending"
	assert assignment_status(session) == "pending_parent_approval"
	assert session.query(Notification).count() == 0
	assert session.query(ChildProgress).count() == 0
	assert counts(http, family) == {"pending": 1, "approved": 0, "retry": 0}

	monkeypatch.setattr(entitlements, "grant_mission_video_entitlement", real)
	retry = review(http, item.submission)
	assert retry.status_code == 200
	assert paid(session) == ([10], [15], [900], 1)


def test_a_duplicate_reward_row_fails_the_whole_approval_instead_of_half_paying(client):
	http, family, session = client
	item = make_submission(session, family)
	session.add(
		StarTransaction(
			child_id=family.child.id, amount=10, transaction_type="task_approved", submission_id=item.submission.id,
			idempotency_key=f"task-approved:{item.submission.id}:stars",
		)
	)
	session.commit()
	response = review(http, item.submission)
	assert response.status_code == 500
	assert response.json()["error"]["code"] == "approval_failed"
	assert paid(session)[1:] == ([], [], 0), "no XP, allowance or review row beside the unrelated duplicate"
	assert status_of(session, item.submission) == "pending"


def test_a_database_without_the_allowance_columns_is_refused_before_anything_is_written(client, monkeypatch):
	http, family, session = client
	item = make_submission(session, family)
	monkeypatch.setattr(task_service, "missing_mission_allowance_columns", lambda: ["submission_id", "source_type"])
	response = review(http, item.submission)
	assert response.status_code == 503
	body = response.json()["error"]
	assert body["code"] == "video_allowance_unavailable"
	assert "submission_id" not in body["message"], "column names go to the log, not to a parent's screen"
	assert paid(session) == NOTHING
	assert status_of(session, item.submission) == "pending"
	# Declining or asking for a retry pays nothing, so it does not depend on the allowance schema.
	assert review(http, item.submission, "rejected").status_code == 200


def test_the_schema_check_names_missing_columns(monkeypatch):
	from types import SimpleNamespace

	from app.services import video_entitlement_service as entitlements

	monkeypatch.setattr(entitlements, "has_model", lambda name: True)
	monkeypatch.setattr(entitlements, "get_model", lambda name: SimpleNamespace(child_id=1, granted_seconds=1))
	missing = entitlements.missing_mission_allowance_columns()
	assert {"submission_id", "task_id", "source_type"} <= set(missing) and "child_id" not in missing
	monkeypatch.setattr(entitlements, "has_model", lambda name: False)
	assert entitlements.missing_mission_allowance_columns() == ["video_access_entitlements (table)"]


def test_the_complete_schema_passes_the_check(approval_db):
	from app.services.video_entitlement_service import missing_mission_allowance_columns

	assert missing_mission_allowance_columns() == []


# ---- the server log names the failing rule (names only) ----------------------------------------------------------------


def test_a_database_error_is_logged_with_the_rule_it_broke_and_no_values():
	from types import SimpleNamespace

	from sqlalchemy.exc import IntegrityError

	from app.core.exceptions import database_error_details

	diag = SimpleNamespace(constraint_name="star_transactions_idempotency_key_key", table_name="star_transactions", column_name=None)
	error = IntegrityError("INSERT ... VALUES (%(secret)s)", {"secret": "child@example.test"}, SimpleNamespace(sqlstate="23505", diag=diag))
	text = database_error_details(error)
	assert "sqlstate=23505" in text and "constraint=star_transactions_idempotency_key_key" in text
	assert "table=star_transactions" in text
	assert "child@example.test" not in text and "secret" not in text
	assert database_error_details(RuntimeError("x")) == ""
