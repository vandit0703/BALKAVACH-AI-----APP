"""The scheduled recheck job and the read-only feed diagnosis, run through the real CLI functions.

Test type: in-memory SQLite (``tests/feed_world.py``) with a fake YouTube client. Not PostgreSQL, no network.
"""

import json
from contextlib import contextmanager
from datetime import datetime, timezone

import pytest

from app import cli
from app.integrations.youtube import YouTubeQuotaError, YouTubeUnavailableError
from app.services.video_service import eligible_feed
from app.services.youtube_review_service import diagnostics
from tests.feed_world import (
	AuditLog,
	FakeYouTube,
	Video,
	YouTubeContentReview,
	add_youtube,
	feed_db,  # noqa: F401  (fixture)
	good_item,
	make_child,
)


@pytest.fixture
def factory(feed_db):
	"""A session factory whose sessions are the shared test session."""

	@contextmanager
	def make():
		yield feed_db

	return make


def feed_titles(session, child):
	return {v.title for v in eligible_feed(session, child, None, 50, 0, video_format="regular")}


def test_the_recheck_job_refreshes_old_approved_videos_and_exits_zero(feed_db, factory, monkeypatch, capsys):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Stale", verified_hours_ago=300, youtube_id="aaaaaaaaaaa")
	add_youtube(feed_db, title="Older stale", verified_hours_ago=500, youtube_id="bbbbbbbbbbb")
	assert feed_titles(feed_db, child) == {"Stale", "Older stale"}
	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client",
		lambda: FakeYouTube(
			{"aaaaaaaaaaa": good_item("aaaaaaaaaaa", title="Stale"), "bbbbbbbbbbb": good_item("bbbbbbbbbbb", title="Older stale")}
		),
	)

	assert cli._youtube_recheck(factory, 200) == 0

	assert "checked=2, verified=2" in capsys.readouterr().out
	assert feed_titles(feed_db, child) == {"Stale", "Older stale"}


def test_running_the_job_twice_changes_nothing_the_second_time(feed_db, factory, monkeypatch, capsys):
	make_child(feed_db)
	add_youtube(feed_db, title="Stale", verified_hours_ago=300, youtube_id="ccccccccccc")
	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube({"ccccccccccc": good_item("ccccccccccc")})
	)
	assert cli._youtube_recheck(factory, 200) == 0
	status_after_first = feed_db.query(YouTubeContentReview.status).scalar()
	assert cli._youtube_recheck(factory, 200) == 0
	assert feed_db.query(YouTubeContentReview.status).scalar() == status_after_first == "approved"
	assert feed_db.query(Video).count() == 1


def test_a_failed_run_exits_non_zero_names_the_cause_and_leaves_an_audit_row(feed_db, factory, monkeypatch, capsys):
	add_youtube(feed_db, verified_hours_ago=300, youtube_id="ddddddddddd")
	monkeypatch.setattr("app.integrations.youtube.get_youtube_client", lambda: FakeYouTube(error=YouTubeQuotaError("q")))

	assert cli._youtube_recheck(factory, 200) == 1

	assert "youtube_quota_exhausted" in capsys.readouterr().err
	row = feed_db.query(AuditLog).filter(AuditLog.action == "youtube.recheck.failed").one()
	assert row.details == {"code": "youtube_quota_exhausted"}


def test_an_unreachable_youtube_is_a_handled_failure_not_a_crash(feed_db, factory, monkeypatch, capsys):
	add_youtube(feed_db, verified_hours_ago=300, youtube_id="eeeeeeeeeee")
	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube(error=YouTubeUnavailableError("down"))
	)
	assert cli._youtube_recheck(factory, 200) == 1
	assert feed_db.query(AuditLog).filter(AuditLog.action == "youtube.recheck.failed").count() == 1


def test_a_missing_api_key_fails_loudly_instead_of_silently_skipping(feed_db, factory, monkeypatch, capsys):
	from app.core.config import settings

	monkeypatch.setattr(settings, "youtube_api_key", None)
	assert cli._youtube_recheck(factory, 200) == 1
	assert "youtube_not_configured" in capsys.readouterr().err


def test_diagnostics_show_when_recheck_last_ran_and_old_verification_is_informational(feed_db, factory, monkeypatch):
	add_youtube(feed_db, verified_hours_ago=300, youtube_id="fffffffffff")
	before = diagnostics(feed_db)
	assert before["last_recheck_run"] is None and before["approved_stale"] == 1

	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube(error=YouTubeQuotaError("q"))
	)
	cli._youtube_recheck(factory, 200)
	failed = diagnostics(feed_db)
	assert failed["last_recheck_failure_code"] == "youtube_quota_exhausted" and failed["last_recheck_run"] is None

	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube({"fffffffffff": good_item("fffffffffff")})
	)
	cli._youtube_recheck(factory, 200)
	ok = diagnostics(feed_db)
	assert ok["approved_stale"] == 0
	assert ok["last_recheck_result"]["verified"] == 1
	assert ok["last_recheck_run"] is not None and ok["last_recheck_run"] <= datetime.now(timezone.utc)


def test_feed_diagnose_is_read_only_and_names_the_cause(feed_db, factory, capsys):
	child = make_child(feed_db)
	add_youtube(feed_db, title="Not approved", status="pending_review", is_published=True)
	audit_rows = feed_db.query(AuditLog).count()
	reviews = [(r.status, r.last_verified_at) for r in feed_db.query(YouTubeContentReview).all()]

	code = cli._video_feed_diagnose(factory, child_id=child.id, age=None, language="en")

	report = json.loads(capsys.readouterr().out)
	assert code == 0
	assert report["feeds"]["regular"]["limiting_stage"] == "youtube_approved"
	assert any("not approved, rights-cleared, made for kids" in line for line in report["findings"])
	assert feed_db.query(AuditLog).count() == audit_rows
	assert [(r.status, r.last_verified_at) for r in feed_db.query(YouTubeContentReview).all()] == reviews


def test_feed_diagnose_by_age_and_language_needs_no_child(feed_db, factory, capsys):
	add_youtube(feed_db, title="Fine", duration_seconds=30)
	assert cli._video_feed_diagnose(factory, child_id=None, age=8, language="en") == 0
	report = json.loads(capsys.readouterr().out)
	assert report["feeds"]["short"]["eligible"] == 1 and report["feeds"]["regular"]["eligible"] == 0
	assert report["feeds"]["regular"]["limiting_stage"] == "format_regular"


def test_feed_diagnose_reports_an_unknown_child(feed_db, factory, capsys):
	from uuid import uuid4

	assert cli._video_feed_diagnose(factory, child_id=uuid4(), age=None, language="en") == 1
	assert json.loads(capsys.readouterr().out) == {"error": "child_not_found"}


def test_the_command_requires_a_child_or_an_age(monkeypatch, capsys):
	import app.db.session as db_session

	monkeypatch.setattr(db_session, "SessionLocal", lambda: None)
	with pytest.raises(SystemExit) as exit_info:
		cli.main(["video-feed-diagnose"])
	assert exit_info.value.code == 2


# ---- recheck health monitor ---------------------------------------------------------------------------------------


def _health(factory, capsys, hours=3.0):
	code = cli._recheck_health(factory, hours)
	return code, json.loads(capsys.readouterr().out)


def test_health_is_ok_when_there_is_nothing_to_verify(feed_db, factory, capsys):
	code, report = _health(factory, capsys)
	assert code == 0 and report["healthy"] is True


def test_health_fails_when_approved_videos_are_stale(feed_db, factory, capsys):
	add_youtube(feed_db, verified_hours_ago=300)
	code, report = _health(factory, capsys)
	# Old verification age no longer hides feed videos, but lack of a completed recheck run is still unhealthy.
	assert code == 3 and report["healthy"] is False
	assert any("no completed recheck on record" in problem for problem in report["problems"])


def test_health_fails_when_no_recheck_is_on_record_even_if_videos_are_fresh(feed_db, factory, capsys):
	add_youtube(feed_db, verified_hours_ago=1)
	code, report = _health(factory, capsys)
	assert code == 3 and "no completed recheck on record" in report["problems"]


def test_health_passes_after_a_successful_recheck_and_fails_when_it_goes_quiet(feed_db, factory, monkeypatch, capsys):
	add_youtube(feed_db, verified_hours_ago=300, youtube_id="ggggggggggg")
	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube({"ggggggggggg": good_item("ggggggggggg")})
	)
	cli._youtube_recheck(factory, 200)
	capsys.readouterr()
	code, report = _health(factory, capsys)
	assert code == 0 and report["problems"] == []

	# Four hours later the job has gone quiet.
	row = feed_db.query(AuditLog).filter(AuditLog.action == "youtube.recheck.completed").one()
	from datetime import timedelta

	row.created_at = row.created_at - timedelta(hours=4)
	feed_db.commit()
	code, report = _health(factory, capsys)
	assert code == 3 and any("last completed recheck was" in problem for problem in report["problems"])


def test_health_reports_a_failed_latest_run(feed_db, factory, monkeypatch, capsys):
	add_youtube(feed_db, verified_hours_ago=1, youtube_id="hhhhhhhhhhh")
	monkeypatch.setattr("app.integrations.youtube.get_youtube_client", lambda: FakeYouTube(error=YouTubeQuotaError("q")))
	cli._youtube_recheck(factory, 200)
	capsys.readouterr()
	code, report = _health(factory, capsys)
	assert code == 3 and any("last recheck failed (youtube_quota_exhausted)" in p for p in report["problems"])


# ---- read-only is enforced by the database session, not just by reading the code ------------------------------------


def _sneaky_write(session):
	session.add(AuditLog(action="should.not.exist", entity_type="x", details={}, created_at=datetime.now(timezone.utc)))
	session.flush()


def test_the_read_only_helper_blocks_writes_and_releases_afterwards(feed_db):
	from sqlalchemy.exc import OperationalError

	with cli._read_only(feed_db):
		with pytest.raises(OperationalError):
			_sneaky_write(feed_db)
		feed_db.rollback()
	_sneaky_write(feed_db)  # writable again once the command is over
	feed_db.rollback()


def test_the_read_only_helper_asks_postgresql_for_a_read_only_transaction():
	from types import SimpleNamespace
	from unittest.mock import MagicMock

	session = MagicMock()
	session.get_bind.return_value = SimpleNamespace(dialect=SimpleNamespace(name="postgresql"))
	with cli._read_only(session):
		pass
	statements = [str(call.args[0]) for call in session.execute.call_args_list]
	assert statements == ["SET TRANSACTION READ ONLY"]
	session.rollback.assert_called_once()


@pytest.mark.parametrize(
	"command, patch_target",
	[
		("report", "app.services.youtube_review_service.diagnostics"),
		("diagnose", "app.services.video_feed_diagnostics.diagnose"),
		("health", "app.services.youtube_review_service.diagnostics"),
	],
)
def test_a_read_only_command_cannot_write_even_if_its_code_tried_to(feed_db, factory, monkeypatch, capsys, command, patch_target):
	def writes_then_returns(session, *args, **kwargs):
		_sneaky_write(session)
		return {}

	monkeypatch.setattr(patch_target, writes_then_returns)
	code = {
		"report": lambda: cli._youtube_report(factory),
		"diagnose": lambda: cli._video_feed_diagnose(factory, child_id=None, age=8, language="en"),
		"health": lambda: cli._recheck_health(factory, 3.0),
	}[command]()
	assert code == 2  # "database read failed", never a silent write
	assert feed_db.query(AuditLog).filter(AuditLog.action == "should.not.exist").count() == 0


def test_the_mutating_commands_are_not_read_only(feed_db, factory, monkeypatch):
	"""Documented contract: only recheck, discover, auto-review (and seed/streak) write."""
	add_youtube(feed_db, verified_hours_ago=300, youtube_id="mutatingxxx")
	monkeypatch.setattr(
		"app.integrations.youtube.get_youtube_client", lambda: FakeYouTube({"mutatingxxx": good_item("mutatingxxx")})
	)
	before = feed_db.query(YouTubeContentReview.last_verified_at).scalar()
	assert cli._youtube_recheck(factory, 10) == 0
	assert feed_db.query(YouTubeContentReview.last_verified_at).scalar() > before


# ---- exit codes through the real entry point (no database configured; nothing can connect) ----------------------------


@pytest.mark.parametrize(
	"argv",
	[
		["youtube-recheck-health"],
		["youtube-report"],
		["youtube-recheck", "--limit", "5"],
		["video-feed-diagnose", "--age", "8"],
		["youtube-discover"],
		["youtube-auto-review"],
	],
)
def test_without_a_database_every_command_exits_2_and_says_why(monkeypatch, capsys, argv):
	import app.db.session as db_session

	monkeypatch.setattr(db_session, "SessionLocal", None)
	assert cli.main(argv) == 2
	assert "DATABASE_URL is not configured" in capsys.readouterr().err


@pytest.mark.parametrize(
	"argv",
	[
		["video-feed-diagnose"],  # needs --child-id or --age
		["video-feed-diagnose", "--age", "99"],
		["video-feed-diagnose", "--age", "8", "--language", "fr"],
		["youtube-recheck", "--limit", "0"],
		["youtube-recheck", "--limit", "1001"],
		["youtube-recheck-health", "--max-age-hours", "abc"],
		["unknown-command"],
	],
)
def test_bad_arguments_are_refused_before_any_database_work(monkeypatch, capsys, argv):
	import app.db.session as db_session

	monkeypatch.setattr(db_session, "SessionLocal", lambda: pytest.fail("must not open a session"))
	with pytest.raises(SystemExit) as exit_info:
		cli.main(argv)
	assert exit_info.value.code == 2


def test_database_errors_in_the_read_only_commands_exit_2(monkeypatch, capsys):
	from sqlalchemy.exc import OperationalError

	def broken():
		raise OperationalError("select 1", {}, Exception("connection refused"))

	for call in (
		lambda: cli._youtube_report(broken),
		lambda: cli._video_feed_diagnose(broken, child_id=None, age=8, language="en"),
		lambda: cli._recheck_health(broken, 3.0),
		lambda: cli._youtube_recheck(broken, 5),
	):
		monkeypatch.setattr("app.integrations.youtube.get_youtube_client", lambda: FakeYouTube())
		assert call() == 2
	assert "connection refused" not in capsys.readouterr().err  # no driver detail, no connection string


def test_youtube_discover_aggregates_unexpected_and_trusted_counters(feed_db, factory, monkeypatch, capsys):
	from types import SimpleNamespace

	from app.core.config import settings

	monkeypatch.setattr(settings, "youtube_discovery_topics", ["stories", "music"] if False else ["stories", "math"])
	monkeypatch.setattr(settings, "youtube_discovery_actor_id", "actor-1")
	monkeypatch.setattr(settings, "youtube_region_code", "IN")
	monkeypatch.setattr(cli, "_youtube_discovery_actor", lambda session, actor_id: SimpleNamespace(id=actor_id))
	monkeypatch.setattr("app.integrations.youtube.get_youtube_client", lambda: object())

	topic_results = [
		{
			"created": [{"id": "a"}, {"id": "b"}],
			"skipped_existing": 3,
			"skipped_unplayable": 1,
			"automatically_published": 2,
			"quarantined": 1,
			"next_page_token": "token-1",
			"channels_checked": 4,  # unexpected for topic result
			"new_counter": 7,
		},
		{
			"created": [{"id": "c"}],
			"skipped_existing": 5,
			"skipped_unplayable": 0,
			"automatically_published": 1,
			"quarantined": 0,
			"next_page_token": None,
			"new_counter": 2,
		},
	]
	trusted_result = {
		"channels_checked": 3,
		"created": 5,
		"skipped_existing": 8,
		"automatically_published": 4,
		"pending_review": 2,
		"quarantined": 1,
		"unavailable": 6,
		"channels_unavailable": 1,
		"pages_checked": 9,
		"channels_pending_initial_scan": 2,
		"channels_pending_upload_scan": 1,
	}
	recorded = {}

	def fake_discover(session, actor, client, request, auto_publish=True):
		assert auto_publish is True
		return topic_results.pop(0)

	monkeypatch.setattr("app.services.youtube_review_service.discover", fake_discover)
	monkeypatch.setattr("app.services.youtube_review_service.discover_trusted", lambda *a, **k: trusted_result)
	monkeypatch.setattr(
		"app.services.youtube_review_service.auto_review",
		lambda session, actor, client, limit=200: {"auto_approved": 11, "needs_manual_review": 4, "newly_quarantined": 2},
	)
	monkeypatch.setattr("app.services.admin_service.record_audit", lambda session, actor_id, action, entity, entity_id, details: recorded.update(details or {}))

	assert cli._youtube_discover(factory, 25) == 0

	output = capsys.readouterr().out
	assert "created=8" in output  # 2 + 1 list items + 5 trusted
	assert "skipped_existing=16" in output  # 3 + 5 + 8
	assert "skipped_unplayable=1" in output
	assert "automatically_published=7" in output  # 2 + 1 + 4
	assert "quarantined=4" in output  # 1 + 0 + 1 + 2 newly_quarantined
	assert "channels_checked=7" in output  # 4 topic + 3 trusted
	assert "new_counter=9" in output  # 7 + 2
	assert "pending_review=2" in output
	assert "unavailable=6" in output
	assert "channels_unavailable=1" in output
	assert "pages_checked=9" in output
	assert "channels_pending_initial_scan=2" in output
	assert "channels_pending_upload_scan=1" in output
	assert "auto_approved=11" in output
	assert "needs_manual_review=4" in output
	assert "next_page_token" not in output
	assert recorded["channels_checked"] == 7
	assert recorded["created"] == 8


def test_youtube_discover_aggregates_trusted_discovery_without_preseeded_keys(feed_db, factory, monkeypatch, capsys):
	from types import SimpleNamespace

	from app.core.config import settings

	monkeypatch.setattr(settings, "youtube_discovery_topics", ["stories"])
	monkeypatch.setattr(settings, "youtube_discovery_actor_id", "actor-1")
	monkeypatch.setattr(settings, "youtube_region_code", "IN")
	monkeypatch.setattr(cli, "_youtube_discovery_actor", lambda session, actor_id: SimpleNamespace(id=actor_id))
	monkeypatch.setattr("app.integrations.youtube.get_youtube_client", lambda: object())
	monkeypatch.setattr(
		"app.services.youtube_review_service.discover",
		lambda session, actor, client, request, auto_publish=True: {
			"created": [],
			"skipped_existing": 0,
			"skipped_unplayable": 0,
			"automatically_published": 0,
			"quarantined": 0,
			"next_page_token": None,
		},
	)
	monkeypatch.setattr(
		"app.services.youtube_review_service.discover_trusted",
		lambda *a, **k: {"channels_checked": 2, "created": 3, "skipped_existing": 1, "automatically_published": 1, "pending_review": 0, "quarantined": 0, "unavailable": 0, "channels_unavailable": 0, "pages_checked": 2, "channels_pending_initial_scan": 0, "channels_pending_upload_scan": 0},
	)
	monkeypatch.setattr(
		"app.services.youtube_review_service.auto_review",
		lambda session, actor, client, limit=200: {"auto_approved": 0, "needs_manual_review": 0, "newly_quarantined": 0},
	)
	monkeypatch.setattr("app.services.admin_service.record_audit", lambda *a, **k: None)

	assert cli._youtube_discover(factory, 10) == 0
	output = capsys.readouterr().out
	assert "channels_checked=2" in output
	assert "created=3" in output
	assert "pages_checked=2" in output
	assert "channels_pending_initial_scan=0" in output
	assert "channels_pending_upload_scan=0" in output
