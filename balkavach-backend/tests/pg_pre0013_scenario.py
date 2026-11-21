"""Subprocess helper for tests/test_parent_approval_postgres.py: approval against a database WITHOUT migration 0013.

Run only with DATABASE_URL pointing at a throwaway database (the test builds it at revision 0012). It reflects that
schema, inserts one pending submission with raw SQL, runs the real ``review_submission`` for "approved" and then
"rejected", and prints one JSON line. Never run it against a real database.
"""

import json
import sys
from types import SimpleNamespace
from uuid import uuid4

from sqlalchemy import text

from app.core.exceptions import APIError
from app.db.base import get_model
from app.db.session import SessionLocal
from app.schemas.task import TaskReviewCreate
from app.services import video_entitlement_service as entitlements
from app.services.task_service import review_submission

if SessionLocal is None:
	sys.exit("DATABASE_URL is required")

with SessionLocal() as session:
	name = session.execute(text("select current_database()")).scalar_one()
	assert "test" in name, name
	parent, kid, family, child, task, submission = (uuid4() for _ in range(6))
	session.execute(text("insert into users (id, email, full_name, role, password_hash) values (:p, :e, 'P', 'parent', 'x')"), {"p": parent, "e": f"{parent}@example.test"})
	session.execute(text("insert into users (id, full_name, role, password_hash, username) values (:k, 'Kid', 'child', 'x', :n)"), {"k": kid, "n": f"k{kid.hex[:20]}"})
	session.execute(text("insert into families (id, family_name, created_by) values (:f, 'F', :p)"), {"f": family, "p": parent})
	session.execute(text("insert into family_members (family_id, user_id, relationship, is_primary_parent) values (:f, :p, 'parent', true)"), {"f": family, "p": parent})
	session.execute(text("insert into child_profiles (id, user_id, family_id, display_name, date_of_birth) values (:c, :k, :f, 'hshs', '2017-05-01')"), {"c": child, "k": kid, "f": family})
	session.execute(text("insert into tasks (id, family_id, created_by, assigned_child_id, title) values (:t, :f, :p, :c, 'Saturday Rhythm Rockstar')"), {"t": task, "f": family, "p": parent, "c": child})
	session.execute(text("insert into task_submissions (id, task_id, child_id) values (:s, :t, :c)"), {"s": submission, "t": task, "c": child})
	session.commit()

	report = {"missing_columns": entitlements.missing_mission_allowance_columns()}
	user = session.get(get_model("User"), parent)

	def counts():
		row = session.execute(
			text(
				"select (select count(*) from star_transactions where submission_id=:s) star_rows,"
				" (select coalesce(sum(amount),0) from star_transactions where submission_id=:s) stars,"
				" (select count(*) from xp_transactions where submission_id=:s) xp_rows,"
				" (select coalesce(sum(amount),0) from xp_transactions where submission_id=:s) xp,"
				" 0 as grants, 0 as seconds,"
				" (select count(*) from task_reviews where submission_id=:s) reviews,"
				" (select status from task_submissions where id=:s) status"
			),
			{"s": submission},
		).one()
		return dict(row._mapping)

	try:
		review_submission(session, submission, user, TaskReviewCreate(decision="approved"))
		report["approve"] = "approved"
	except APIError as error:
		report["approve"] = [error.status_code, error.code]
	except Exception as error:  # noqa: BLE001
		report["approve"] = ["exception", type(error).__name__]
	report["after_approve"] = counts()
	report["still_pending"] = report["after_approve"]["status"] == "pending"

	# What the grant does on this schema WITHOUT the up-front check (the behaviour before the fix).
	try:
		entitlements.grant_mission_video_entitlement(
			session, SimpleNamespace(id=child), SimpleNamespace(id=task, family_id=family), SimpleNamespace(id=uuid4())
		)
		report["grant_without_preflight"] = ["no error", ""]
	except Exception as error:  # noqa: BLE001
		report["grant_without_preflight"] = [type(error).__name__, str(error)[:200]]
	session.rollback()

	try:
		outcome = review_submission(session, submission, user, TaskReviewCreate(decision="rejected"))
		report["decline"] = outcome.status
	except APIError as error:
		report["decline"] = [error.status_code, error.code]

print(json.dumps(report))
