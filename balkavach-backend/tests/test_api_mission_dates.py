"""Late parent approval, end to end on PostgreSQL (roadmap Phase 2, MIS-04/05; Testing Plan 3.2).

DB-backed: skipped without ``TEST_DATABASE_URL`` (see ``scripts/testenv.py``). **Written but not yet run**
against the complete schema because ``tests/schema/baseline.sql`` is not in the repository; the logic these
tests exercise is also covered without PostgreSQL in ``test_streak_activity_date.py`` and
``test_review_activity_date.py``. Family timezone is the default (UTC) so every date below is a UTC date.
"""

from datetime import datetime, timedelta, timezone
from uuid import UUID

from app.db.base import get_model


def _utc_naive(delta: timedelta = timedelta()) -> datetime:
	return (datetime.now(timezone.utc) + delta).replace(tzinfo=None)


def _submit(api, ctx, *, submitted_ago: timedelta):
	parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
	task = api.create_task(parent, family["id"], assigned_child_id=child["id"], star_reward=5, xp_reward=20)
	submission = api.submit(child["token"], task["id"]).json()
	Submission = get_model("TaskSubmission")
	row = api.session.get(Submission, UUID(submission["id"]))
	row.submitted_at = _utc_naive(-submitted_ago)  # the child did it earlier; the parent only now gets to it
	api.session.commit()
	return submission["id"], row


def test_late_approval_dates_the_activity_and_streak_by_the_submission_day(api):
	ctx = api.family_with_child()
	submission_id, row = _submit(api, ctx, submitted_ago=timedelta(days=2))
	submitted = row.submitted_at

	assert api.review(ctx["parent"]["token"], submission_id, "approved").status_code == 200

	api.session.refresh(row)
	assert row.submitted_at == submitted  # original submission time preserved
	assert row.reviewed_at > submitted + timedelta(days=1)  # real approval time kept separately

	ChildActivityDay = get_model("ChildActivityDay")
	days = api.session.query(ChildActivityDay.activity_date).filter(ChildActivityDay.child_id == UUID(ctx["child"]["id"])).all()
	assert [d[0] for d in days] == [submitted.date()]  # not the approval day

	ChildStreak = get_model("ChildStreak")
	streak = api.session.query(ChildStreak).filter(ChildStreak.child_id == UUID(ctx["child"]["id"])).one()
	assert streak.last_activity_date == submitted.date()
	assert streak.current_streak == 1


def test_approving_twice_credits_stars_xp_and_video_time_exactly_once(api):
	ctx = api.family_with_child()
	parent, child = ctx["parent"]["token"], ctx["child"]
	submission_id, _ = _submit(api, ctx, submitted_ago=timedelta(hours=1))

	assert api.review(parent, submission_id, "approved").status_code == 200
	assert api.review(parent, submission_id, "approved").status_code == 409
	assert api.review(parent, submission_id, "approved").status_code == 409

	progress = api.get(f"/progress/children/{child['id']}", child["token"]).json()
	assert (progress["star_balance"], progress["total_xp"]) == (10, 15)  # the standard mission reward, once
	Entitlement = get_model("VideoAccessEntitlement")
	grants = api.session.query(Entitlement).filter(Entitlement.submission_id == UUID(submission_id)).all()
	assert len(grants) == 1 and grants[0].granted_seconds == 900


def test_a_rejected_then_resubmitted_mission_counts_for_the_resubmission_day(api):
	ctx = api.family_with_child()
	parent, family, child = ctx["parent"]["token"], ctx["family"], ctx["child"]
	task = api.create_task(parent, family["id"], assigned_child_id=child["id"])
	first = api.submit(child["token"], task["id"]).json()
	assert api.review(parent, first["id"], "rejected", "Try again").status_code == 200
	second = api.submit(child["token"], task["id"]).json()
	assert api.review(parent, second["id"], "approved").status_code == 200

	ChildActivityDay = get_model("ChildActivityDay")
	days = api.session.query(ChildActivityDay).filter(ChildActivityDay.child_id == UUID(child["id"])).all()
	assert len(days) == 1 and days[0].completed_tasks == 1  # the rejection earned and counted nothing
