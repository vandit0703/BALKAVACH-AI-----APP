"""Parent mission approval on REAL PostgreSQL: transactions, rollback, row locks, concurrency, constraints, pushes.

Needs ``TEST_DATABASE_URL`` (a disposable database whose name contains "test") and ``REDIS_URL``; otherwise every
test skips. Never point it at production or staging (``conftest.isolated_test_engine`` refuses the app database).

Scenarios that need several simultaneous connections create COMMITTED rows with a unique tag and delete them
afterwards; everything else runs inside the rolled-back transaction of the ``api`` fixture.

What this proves depends on the schema loaded into the test database: with ``tests/schema/reconstructed_baseline.sql``
the constraints are the ones written there, which are assumptions about production (see
docs/parent-approval-troubleshooting.md). With the real ``baseline.sql`` in CI the same tests check the real schema.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import threading
import time
import warnings
from datetime import date, datetime, timezone
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import sessionmaker

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.task import TaskReviewCreate
from app.services import push_service, task_service
from app.services import video_entitlement_service as entitlements
from app.services.task_service import review_submission
from app.utils import utc_naive

BACKEND = Path(__file__).resolve().parent.parent


# ---- helpers ---------------------------------------------------------------------------------------------------------


def _counts(session, submission_id: str) -> dict:
	"""What one submission has been paid, read straight from the ledgers."""
	sid = UUID(str(submission_id))
	row = session.execute(
		text(
			"""
			select
				(select count(*) from star_transactions where submission_id = :s) as star_rows,
				(select coalesce(sum(amount), 0) from star_transactions where submission_id = :s) as stars,
				(select count(*) from xp_transactions where submission_id = :s) as xp_rows,
				(select coalesce(sum(amount), 0) from xp_transactions where submission_id = :s) as xp,
				(select count(*) from video_access_entitlements where submission_id = :s) as grants,
				(select coalesce(sum(granted_seconds), 0) from video_access_entitlements where submission_id = :s) as seconds,
				(select count(*) from task_reviews where submission_id = :s) as reviews,
				(select status from task_submissions where id = :s) as status
			"""
		),
		{"s": sid},
	).one()
	return dict(row._mapping)


NOTHING = {"star_rows": 0, "stars": 0, "xp_rows": 0, "xp": 0, "grants": 0, "seconds": 0, "reviews": 0, "status": "pending"}
PAID = {"star_rows": 1, "stars": 10, "xp_rows": 1, "xp": 15, "grants": 1, "seconds": 900, "reviews": 1, "status": "approved"}


def _notifications(session, recipient_user_id, kind: str) -> int:
	return session.execute(
		text("select count(*) from notifications where recipient_user_id = :u and notification_type = :t"),
		{"u": UUID(str(recipient_user_id)), "t": kind},
	).scalar_one()


def _pending(api, *, title="Saturday Rhythm Rockstar"):
	ctx = api.family_with_child("hshs")
	task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"], assigned_child_id=ctx["child"]["id"], title=title)
	submission = api.submit(ctx["child"]["token"], task["id"])
	assert submission.status_code == 201, submission.text
	return ctx, submission.json()["id"]


def _queue_counts(api, ctx) -> dict:
	out = {}
	for key, status in (("pending", "pending"), ("approved", "approved"), ("retry", "resubmission_requested")):
		response = api.get(f"/reviews/submissions?family_id={ctx['family']['id']}&status={status}", ctx["parent"]["token"])
		assert response.status_code == 200, response.text
		out[key] = len(response.json())
	return out


# ---- 1. success, counts, repeats, conflicts, foreign family (real auth, real routes) -------------------------------------


def test_a_successful_approval_pays_exactly_ten_stars_fifteen_xp_and_900_seconds(api):
	ctx, sid = _pending(api)
	assert _queue_counts(api, ctx) == {"pending": 1, "approved": 0, "retry": 0}
	response = api.review(ctx["parent"]["token"], sid, "approved")
	assert response.status_code == 200, response.text
	assert _counts(api.session, sid) == PAID
	assert _queue_counts(api, ctx) == {"pending": 0, "approved": 1, "retry": 0}
	assert _notifications(api.session, ctx["child"]["user_id"], "task_approved") == 1
	assert _notifications(api.session, ctx["child"]["user_id"], "mission_video_time_granted") == 1


def test_declined_and_retry_decisions_pay_nothing_and_move_the_counts(api):
	ctx, sid = _pending(api)
	assert api.review(ctx["parent"]["token"], sid, "resubmission_requested", "again").status_code == 200
	assert _counts(api.session, sid) == {**NOTHING, "reviews": 1, "status": "resubmission_requested"}
	assert _queue_counts(api, ctx) == {"pending": 0, "approved": 0, "retry": 1}
	task_id = api.get(f"/reviews/submissions?family_id={ctx['family']['id']}&status=resubmission_requested", ctx["parent"]["token"]).json()[0]["task_id"]
	second = api.submit(ctx["child"]["token"], task_id).json()["id"]
	assert api.review(ctx["parent"]["token"], second, "rejected").status_code == 200
	assert _counts(api.session, second) == {**NOTHING, "reviews": 1, "status": "rejected"}


def test_a_repeated_approval_after_a_lost_response_returns_the_existing_result_and_pays_nothing_more(api):
	ctx, sid = _pending(api)
	first = api.review(ctx["parent"]["token"], sid, "approved")
	again = api.review(ctx["parent"]["token"], sid, "approved")
	third = api.review(ctx["parent"]["token"], sid, "approved")
	assert first.status_code == again.status_code == third.status_code == 200
	assert again.json() == first.json()
	assert _counts(api.session, sid) == PAID
	assert _notifications(api.session, ctx["child"]["user_id"], "task_approved") == 1


def test_a_conflicting_second_decision_is_refused(api):
	ctx, sid = _pending(api)
	assert api.review(ctx["parent"]["token"], sid, "approved").status_code == 200
	conflict = api.review(ctx["parent"]["token"], sid, "rejected")
	assert conflict.status_code == 409 and conflict.json()["error"]["code"] == "submission_already_reviewed"
	assert _counts(api.session, sid) == PAID


def test_another_familys_parent_cannot_approve_and_nothing_changes(api):
	ctx, sid = _pending(api)
	stranger = api.register_parent("Stranger")
	response = api.review(stranger["token"], sid, "approved")
	assert response.status_code == 404 and response.json()["error"]["code"] == "submission_not_found"
	assert _counts(api.session, sid) == NOTHING


# ---- 2. rollback when stars, XP, allowance, streak or notifications fail ---------------------------------------------------


@pytest.mark.parametrize("stage", ["stars", "xp", "allowance", "streak"])
def test_a_failure_in_any_reward_step_rolls_everything_back_and_a_retry_then_succeeds(api, monkeypatch, stage):
	ctx, sid = _pending(api)
	child_user = ctx["child"]["user_id"]
	notes_before = api.session.execute(text("select count(*) from notifications")).scalar_one()
	restore = None
	if stage == "stars":
		# A pre-existing row with this submission's star key: the star insert collides on the database's own key.
		api.session.execute(
			text(
				"insert into star_transactions (child_id, amount, transaction_type, idempotency_key) "
				"values (:c, 1, 'admin_adjustment', :k)"
			),
			{"c": UUID(ctx["child"]["id"]), "k": f"task-approved:{sid}:stars"},
		)
		api.session.commit()
		if not _has_unique(api.session, "star_transactions"):
			pytest.skip("this schema has no unique key on star_transactions.idempotency_key (see the uniqueness test)")
	elif stage == "xp":
		api.session.execute(
			text(
				"insert into xp_transactions (child_id, amount, reason, idempotency_key) values (:c, 1, 'admin_adjustment', :k)"
			),
			{"c": UUID(ctx["child"]["id"]), "k": f"task-approved:{sid}:xp"},
		)
		api.session.commit()
		if not _has_unique(api.session, "xp_transactions"):
			pytest.skip("this schema has no unique key on xp_transactions.idempotency_key (see the uniqueness test)")
	elif stage == "allowance":
		original = entitlements.grant_mission_video_entitlement
		monkeypatch.setattr(entitlements, "grant_mission_video_entitlement", _boom)
		restore = lambda: monkeypatch.setattr(entitlements, "grant_mission_video_entitlement", original)  # noqa: E731
	else:
		import app.services.streak_service as streaks

		original = streaks.record_qualifying_activity
		monkeypatch.setattr(streaks, "record_qualifying_activity", _boom)
		restore = lambda: monkeypatch.setattr(streaks, "record_qualifying_activity", original)  # noqa: E731

	response = api.review(ctx["parent"]["token"], sid, "approved")

	assert response.status_code == 500, response.text
	assert response.json()["error"]["code"] == "approval_failed"
	counts = _counts(api.session, sid)
	assert counts["status"] == "pending" and counts["reviews"] == 0 and counts["grants"] == 0
	assert (counts["star_rows"], counts["xp_rows"]) == (0, 0) or stage in {"stars", "xp"}
	assert api.session.execute(text("select count(*) from notifications")).scalar_one() == notes_before
	assert _queue_counts(api, ctx) == {"pending": 1, "approved": 0, "retry": 0}

	if stage in {"stars", "xp"}:
		api.session.execute(text("delete from star_transactions where idempotency_key like :k"), {"k": f"task-approved:{sid}:%"})
		api.session.execute(text("delete from xp_transactions where idempotency_key like :k"), {"k": f"task-approved:{sid}:%"})
		api.session.commit()
	if restore:
		restore()
	retry = api.review(ctx["parent"]["token"], sid, "approved")
	assert retry.status_code == 200, retry.text
	assert _counts(api.session, sid) == PAID


def _boom(*args, **kwargs):
	raise RuntimeError("injected failure")


def _has_unique(session, table: str) -> bool:
	return bool(
		session.execute(
			text(
				"""
				select exists (
					select 1 from pg_index i join pg_class c on c.oid = i.indrelid
					join pg_attribute a on a.attrelid = c.oid and a.attnum = any(i.indkey)
					where c.relname = :t and i.indisunique and a.attname = 'idempotency_key' and i.indnatts = 1
				)
				"""
			),
			{"t": table},
		).scalar()
	)


# ---- 3. schema variants production might have (the live schema is unknown) ----------------------------------------------------


@pytest.mark.parametrize(
	"ddl",
	[
		"ALTER TABLE video_access_entitlements ADD CONSTRAINT assumed_one_target CHECK "
		"((video_id IS NOT NULL)::int + (video_collection_id IS NOT NULL)::int = 1)",
		"ALTER TABLE video_access_entitlements ALTER COLUMN video_id SET NOT NULL",
	],
	ids=["exactly-one-target-check", "video_id-not-null"],
)
def test_if_the_entitlement_table_requires_a_video_target_every_mission_approval_fails_cleanly(api, ddl):
	"""Migration 0013 does not relax a baseline rule like this. If production has one, NO mission can be approved."""
	ctx, sid = _pending(api)
	api.session.execute(text(ddl))  # transactional DDL: rolled back with the test
	response = api.review(ctx["parent"]["token"], sid, "approved")
	assert response.status_code == 500 and response.json()["error"]["code"] == "approval_failed"
	assert _counts(api.session, sid) == NOTHING


# Which production rule broke approvals? Each candidate leaves a distinct signature in the server log line
# "Mission approval failed and was rolled back (... error_type=..., sqlstate=..., constraint=..., table=..., column=...)".
# One such line from production (2026-11-26 device report) identifies the cause; these map signature -> rule.
@pytest.mark.parametrize(
	("ddl", "signature"),
	[
		(
			"ALTER TABLE video_access_entitlements ADD CONSTRAINT assumed_one_target CHECK "
			"((video_id IS NOT NULL)::int + (video_collection_id IS NOT NULL)::int = 1)",
			"sqlstate=23514 constraint=assumed_one_target table=video_access_entitlements",
		),
		(
			"ALTER TABLE video_access_entitlements ALTER COLUMN video_id SET NOT NULL",
			"sqlstate=23502 table=video_access_entitlements column=video_id",
		),
		(
			"ALTER TABLE video_access_entitlements ALTER COLUMN redemption_id SET NOT NULL",
			"sqlstate=23502 table=video_access_entitlements column=redemption_id",
		),
		(
			"ALTER TABLE video_access_entitlements ALTER COLUMN expires_at SET NOT NULL",
			"sqlstate=23502 table=video_access_entitlements column=expires_at",
		),
		(
			"ALTER TABLE notifications ADD CONSTRAINT assumed_notification_types CHECK "
			"(notification_type IN ('task_submitted','task_approved','task_rejected','task_resubmission_requested',"
			"'badge_unlocked','streak_continued','streak_milestone','streak_new_after_break')) NOT VALID",
			"sqlstate=23514 constraint=assumed_notification_types table=notifications",
		),
	],
	ids=["one-target-check", "video_id-not-null", "redemption_id-not-null", "expires_at-not-null", "notification-type-check"],
)
def test_each_candidate_production_rule_leaves_a_distinct_log_signature(api, caplog, ddl, signature):
	ctx, sid = _pending(api)
	api.session.execute(text(ddl))  # transactional DDL: rolled back with the test
	with caplog.at_level("ERROR", logger="app.services.task_service"):
		response = api.review(ctx["parent"]["token"], sid, "approved")
	assert response.status_code == 500 and response.json()["error"]["code"] == "approval_failed"
	assert _counts(api.session, sid) == NOTHING
	logged = " ".join(r.getMessage() for r in caplog.records if "rolled back" in r.getMessage())
	assert "error_type=IntegrityError" in logged, logged
	assert signature in logged, logged


# ---- 4. concurrency on committed data, separate connections ------------------------------------------------------------------


@pytest.fixture
def committed_world(isolated_test_engine):
	"""Factory of committed pending submissions for threads; deletes everything it created."""
	factory = sessionmaker(bind=isolated_test_engine, expire_on_commit=False)
	created: list[tuple[UUID, list[UUID]]] = []

	def make(title="Saturday Rhythm Rockstar"):
		tag = uuid4().hex
		User, Family, Member = get_model("User"), get_model("Family"), get_model("FamilyMember")
		Child, Task, Submission = get_model("ChildProfile"), get_model("Task"), get_model("TaskSubmission")
		with factory() as s:
			parent = User(full_name="Parent", email=f"p-{tag}@example.test", password_hash="x", role="parent", preferred_language="en", is_active=True)
			kid = User(full_name="hshs", username=f"k{tag[:20]}", password_hash="x", role="child", preferred_language="en", is_active=True)
			s.add_all([parent, kid])
			s.flush()
			family = Family(family_name="F", created_by=parent.id)
			s.add(family)
			s.flush()
			s.add(Member(family_id=family.id, user_id=parent.id, relationship="parent", is_primary_parent=True, is_active=True))
			child = Child(user_id=kid.id, family_id=family.id, display_name="hshs", date_of_birth=date(2017, 5, 1), is_active=True)
			s.add(child)
			s.flush()
			task = Task(family_id=family.id, created_by=parent.id, assigned_child_id=child.id, title=title, description="d", star_reward=5, xp_reward=10, is_custom=True, is_active=True)
			s.add(task)
			s.flush()
			sub = Submission(task_id=task.id, child_id=child.id, submission_number=1, proof_type="none", status="pending", submitted_at=utc_naive(datetime.now(timezone.utc)))
			s.add(sub)
			s.commit()
			ids = SimpleNamespace_(parent=parent.id, kid=kid.id, family=family.id, child=child.id, submission=sub.id)
		created.append((family.id, [parent.id, kid.id]))
		return ids

	yield factory, make

	with isolated_test_engine.begin() as connection:
		for family_id, user_ids in created:
			for statement in (
				"delete from notifications where recipient_user_id = any(:u)",
				"delete from families where id = :f",
				"delete from users where id = any(:u)",
			):
				try:
					with connection.begin_nested():
						connection.execute(text(statement), {"f": family_id, "u": user_ids})
				except Exception:  # noqa: BLE001 - cleanup of a disposable database
					pass


class SimpleNamespace_:
	def __init__(self, **values):
		self.__dict__.update(values)


def _race(factory, ids, decisions, *, hold_seconds=0.8):
	"""Run one review per decision on its own connection at the same moment; the first to start is slowed inside its
	transaction so the others reach the submission row while it is locked."""
	User = get_model("User")
	barrier = threading.Barrier(len(decisions))
	results: list = [None] * len(decisions)
	real_grant = entitlements.grant_mission_video_entitlement
	started = threading.Event()

	def slow_grant(*args, **kwargs):
		if not started.is_set():
			started.set()
			time.sleep(hold_seconds)
		return real_grant(*args, **kwargs)

	def work(index, decision):
		with factory() as session:
			parent = session.get(User, ids.parent)
			barrier.wait()
			try:
				outcome = review_submission(session, ids.submission, parent, TaskReviewCreate(decision=decision))
				results[index] = ("ok", outcome.status)
			except APIError as error:
				results[index] = ("api_error", error.status_code, error.code)
			except Exception as error:  # noqa: BLE001
				results[index] = ("exception", type(error).__name__)

	entitlements.grant_mission_video_entitlement = slow_grant
	try:
		threads = [threading.Thread(target=work, args=(i, d)) for i, d in enumerate(decisions)]
		for thread in threads:
			thread.start()
		for thread in threads:
			thread.join(timeout=60)
	finally:
		entitlements.grant_mission_video_entitlement = real_grant
	return results


def test_two_simultaneous_approvals_of_one_submission_pay_once(committed_world):
	factory, make = committed_world
	ids = make()
	results = _race(factory, ids, ["approved", "approved"])
	assert results == [("ok", "approved"), ("ok", "approved")], results
	with factory() as s:
		assert _counts(s, ids.submission) == PAID


def test_simultaneous_approve_and_decline_have_exactly_one_winner(committed_world):
	factory, make = committed_world
	ids = make()
	results = _race(factory, ids, ["approved", "rejected"])
	oks = [r for r in results if r[0] == "ok"]
	conflicts = [r for r in results if r == ("api_error", 409, "submission_already_reviewed")]
	assert len(oks) == 1 and len(conflicts) == 1, results
	with factory() as s:
		counts = _counts(s, ids.submission)
	assert counts["reviews"] == 1 and counts["status"] == oks[0][1]
	if counts["status"] == "approved":
		assert counts == PAID
	else:
		assert (counts["star_rows"], counts["xp_rows"], counts["grants"]) == (0, 0, 0)


def test_ten_simultaneous_approvals_still_pay_once(committed_world):
	factory, make = committed_world
	ids = make()
	results = _race(factory, ids, ["approved"] * 10, hold_seconds=0.5)
	assert all(r == ("ok", "approved") for r in results), results
	with factory() as s:
		assert _counts(s, ids.submission) == PAID


def _idempotency_uniques(engine) -> list[tuple[str, str]]:
	"""(table, DDL to recreate) for each single-column unique key on the two idempotency columns."""
	found = []
	with engine.connect() as connection:
		rows = connection.execute(
			text(
				"""
				select c.relname, ic.relname as index_name, i.indisprimary, pg_get_indexdef(i.indexrelid) as definition,
					(select conname from pg_constraint k where k.conindid = i.indexrelid and k.contype = 'u') as constraint_name
				from pg_index i join pg_class c on c.oid = i.indrelid join pg_class ic on ic.oid = i.indexrelid
				join pg_attribute a on a.attrelid = c.oid and a.attnum = any(i.indkey)
				where c.relname in ('star_transactions', 'xp_transactions') and i.indisunique and not i.indisprimary
					and a.attname = 'idempotency_key' and i.indnatts = 1
				"""
			)
		).all()
	for table, index_name, _primary, definition, constraint_name in rows:
		found.append((table, index_name, definition, constraint_name))
	return found


def test_without_a_database_unique_key_the_row_lock_still_prevents_double_payment(committed_world, isolated_test_engine):
	"""Drops the star/XP idempotency unique keys for this test (committed), races ten approvals, restores them.

	Shows duplicate prevention does not depend on a constraint the live schema may not have: the submission row is
	locked FOR UPDATE and re-checked as pending."""
	factory, make = committed_world
	uniques = _idempotency_uniques(isolated_test_engine)
	with isolated_test_engine.begin() as connection:
		for table, index_name, _definition, constraint_name in uniques:
			if constraint_name:
				connection.execute(text(f'ALTER TABLE {table} DROP CONSTRAINT "{constraint_name}"'))
			else:
				connection.execute(text(f'DROP INDEX "{index_name}"'))
	try:
		ids = make()
		results = _race(factory, ids, ["approved"] * 10, hold_seconds=0.5)
		assert all(r == ("ok", "approved") for r in results), results
		with factory() as s:
			assert _counts(s, ids.submission) == PAID
	finally:
		with isolated_test_engine.begin() as connection:
			for table, _index_name, definition, constraint_name in uniques:
				connection.execute(text(definition))


def test_report_whether_the_idempotency_keys_are_unique_in_this_database(isolated_test_engine):
	uniques = {table for table, *_ in _idempotency_uniques(isolated_test_engine)}
	missing = {"star_transactions", "xp_transactions"} - uniques
	if missing:
		warnings.warn(f"No unique key on idempotency_key in: {sorted(missing)}. Duplicate prevention relies on the row lock.")
	print(f"IDEMPOTENCY_UNIQUE star={'star_transactions' in uniques} xp={'xp_transactions' in uniques}")


# ---- 5. a database that has not applied migration 0013 -------------------------------------------------------------------------


def _admin_url(test_url: str, database: str) -> str:
	return make_url(test_url).set(drivername="postgresql+psycopg", database=database).render_as_string(hide_password=False)


def test_a_database_without_migration_0013_refuses_approval_before_writing_anything(isolated_test_engine):
	"""Builds a throwaway database at head, removes exactly what migration 0013 added, then runs the real approval code
	against it in a subprocess (so reflection sees that schema)."""
	import psycopg

	test_url = os.environ["TEST_DATABASE_URL"]
	name = (make_url(test_url).database or "balkavach_test") + "_pre0013"
	assert "test" in name
	baseline = BACKEND / "tests" / "schema" / "baseline.sql"
	if not baseline.exists() or baseline.stat().st_size == 0:
		baseline = BACKEND / "tests" / "schema" / "reconstructed_baseline.sql"
	plain = _admin_url(test_url, "postgres").replace("postgresql+psycopg", "postgresql")
	with psycopg.connect(plain, autocommit=True) as admin:
		admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')
		admin.execute(f'CREATE DATABASE "{name}"')
	target = _admin_url(test_url, name)
	try:
		with psycopg.connect(target.replace("postgresql+psycopg", "postgresql"), autocommit=True) as conn:
			conn.execute(baseline.read_text(encoding="utf-8"))
			conn.execute("create table if not exists alembic_version (version_num varchar(64) not null primary key)")
		env = {**os.environ, "DATABASE_URL": target, "ALLOW_SCHEMA_MIGRATIONS": "true", "PYTHONPATH": str(BACKEND)}
		# Migration 0015 seeds JSONB columns through an untyped bulk_insert, which psycopg 3 cannot adapt; this test
		# registers a dict/list -> JSONB adapter for the alembic subprocess only (the migration file is not changed).
		wrapper = (
			"import sys, psycopg; from psycopg.types.json import JsonbDumper; "
			"psycopg.adapters.register_dumper(dict, JsonbDumper); psycopg.adapters.register_dumper(list, JsonbDumper); "
			"from alembic.config import main; main(argv=sys.argv[1:])"
		)
		upgrade = subprocess.run(
			[sys.executable, "-c", wrapper, "upgrade", "head"], cwd=BACKEND, env=env, capture_output=True, text=True, timeout=600,
		)
		assert upgrade.returncode == 0, upgrade.stderr[-800:]
		with psycopg.connect(target.replace("postgresql+psycopg", "postgresql"), autocommit=True) as conn:
			# Exactly what migration 0013's downgrade() removes, and nothing else: "0013 was never applied".
			conn.execute("DROP INDEX IF EXISTS ix_video_access_entitlements_child_source")
			conn.execute("ALTER TABLE video_access_entitlements DROP CONSTRAINT IF EXISTS source_type_check")
			conn.execute("ALTER TABLE video_access_entitlements DROP COLUMN submission_id, DROP COLUMN task_id, DROP COLUMN source_type")
		script = (BACKEND / "tests" / "pg_pre0013_scenario.py")
		run = subprocess.run([sys.executable, str(script)], cwd=BACKEND, env=env, capture_output=True, text=True, timeout=300)
		assert run.returncode == 0, run.stderr[-1500:]
		report = json.loads(run.stdout.strip().splitlines()[-1])
	finally:
		with psycopg.connect(plain, autocommit=True) as admin:
			admin.execute(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)')

	assert {"submission_id", "task_id", "source_type"} <= set(report["missing_columns"])
	assert report["approve"] == [503, "video_allowance_unavailable"]
	assert report["after_approve"] == NOTHING and report["still_pending"] is True
	assert report["decline"] == "rejected", "declining pays nothing and needs no allowance schema"
	assert report["grant_without_preflight"][0] == "AttributeError", "this is what production would show without the check"
	assert "submission_id" in report["grant_without_preflight"][1]


# ---- 6. notifications: transactional rows, push only after commit, a failing FCM never undoes an approval --------------------------


class _Provider:
	def __init__(self, behaviour="ok"):
		self.behaviour = behaviour
		self.calls = 0

	def send(self, token, title, body, data):
		self.calls += 1
		if self.behaviour == "raise":
			raise RuntimeError("FCM is down")
		return self.behaviour


@pytest.fixture
def push(monkeypatch, isolated_test_session):
	state = {"provider": _Provider("ok")}
	monkeypatch.setattr(push_service, "get_push_notification_provider", lambda: state["provider"])
	monkeypatch.setattr(push_service, "_runner", lambda fn: fn())
	monkeypatch.setattr(push_service, "_sleep", lambda seconds: None)

	class _Factory:
		def __enter__(self):
			return isolated_test_session

		def __exit__(self, *exc):
			return False

	monkeypatch.setattr(push_service, "_session_factory", lambda: _Factory())
	return state


def _notification_ids(session, user_id) -> set:
	return {row[0] for row in session.execute(text("select id from notifications where recipient_user_id = :u"), {"u": UUID(str(user_id))})}


def _register_device(api, ctx):
	response = api.client.put(
		"/api/v1/notifications/devices", headers=api.auth(ctx["child"]["token"]),
		json={"token": "d" * 48, "platform": "android", "app_version": "1.0.0"},
	)
	assert response.status_code == 204, response.text


@pytest.mark.parametrize("behaviour,attempts", [("ok", 1), ("raise", 1), ("error", 1), ("retry", push_service.MAX_ATTEMPTS)])
def test_a_failing_push_never_undoes_a_committed_approval(api, push, behaviour, attempts):
	push["provider"] = _Provider(behaviour)
	ctx, sid = _pending(api)
	_register_device(api, ctx)
	before = _notification_ids(api.session, ctx["child"]["user_id"])

	response = api.review(ctx["parent"]["token"], sid, "approved")

	assert response.status_code == 200, response.text
	assert _counts(api.session, sid) == PAID
	assert _notifications(api.session, ctx["child"]["user_id"], "task_approved") == 1
	created = _notification_ids(api.session, ctx["child"]["user_id"]) - before
	pushable = [
		kind
		for (kind,) in api.session.execute(
			text("select notification_type from notifications where id = any(:ids)"), {"ids": list(created)}
		)
		if kind in push_service.GENERIC_TEXT
	]
	assert "task_approved" in pushable
	# Every pushable notification is tried once (an exception or a hard error is not retried) or MAX_ATTEMPTS times
	# (a transient "retry"), and then given up on: the approval itself is untouched.
	assert push["provider"].calls == len(pushable) * attempts


def test_a_rolled_back_approval_sends_no_push_and_leaves_no_notification(api, push, monkeypatch):
	ctx, sid = _pending(api)
	_register_device(api, ctx)
	monkeypatch.setattr(entitlements, "grant_mission_video_entitlement", _boom)
	response = api.review(ctx["parent"]["token"], sid, "approved")
	assert response.status_code == 500
	assert push["provider"].calls == 0
	assert _notifications(api.session, ctx["child"]["user_id"], "task_approved") == 0


def test_repeating_an_approval_creates_no_second_notification_and_no_second_push(api, push):
	ctx, sid = _pending(api)
	_register_device(api, ctx)
	assert api.review(ctx["parent"]["token"], sid, "approved").status_code == 200
	calls = push["provider"].calls
	assert api.review(ctx["parent"]["token"], sid, "approved").status_code == 200
	assert push["provider"].calls == calls
	assert _notifications(api.session, ctx["child"]["user_id"], "task_approved") == 1
