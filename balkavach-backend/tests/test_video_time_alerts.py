"""Low-time / time-up alerts and the deduction path they ride on.

Runs the real ``record_progress`` against an in-memory SQLite database that
declares only the columns this path touches. SQLite has no row locks, so the
concurrent behaviour (two devices reporting at once) still needs the
PostgreSQL suite (TEST_DATABASE_URL); nothing here claims PostgreSQL coverage.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from app.core.exceptions import APIError
from app.services import video_time_alerts as alerts
from app.services.video_time_alerts import EXHAUSTED, NEARLY_EXHAUSTED, alert_text, crossed_event
from app.utils import utc_naive
from tests.video_world import (  # noqa: F401 - db is a fixture
	ChildVideoDailyUsage,
	ChildVideoWatchHistory,
	Notification,
	Video,
	VideoAccessEntitlement,
	alerts_of,
	db,
	grant,
	make_child,
	report,
	tick,
)


# --------------------------------------------------------------------------- thresholds


@pytest.mark.parametrize(
	"before,after,expected",
	[
		(150, 120, NEARLY_EXHAUSTED),
		(121, 91, NEARLY_EXHAUSTED),
		(120, 90, None),  # already below: the warning was for an earlier crossing
		(300, 270, None),
		(25, 0, EXHAUSTED),
		(0, 0, None),
		(100, 100, None),  # nothing charged
		(90, 900, None),  # time went up (a grant), never an alert
	],
)
def test_threshold_crossings(before, after, expected):
	assert crossed_event(before, after) == expected


@pytest.mark.parametrize("language", ["en", "hi", "gu", "fr", None])
def test_alert_text_is_localised_real_and_never_promises_time(language):
	title, message = alert_text(NEARLY_EXHAUSTED, language, 95)
	assert "2" in message  # 95 s is "about 2 min", rounded up from the server figure
	_, done = alert_text(EXHAUSTED, language, 0)
	approval = {"en": "approve", "hi": "मंज़ूरी", "gu": "મંજૂર"}[language if language in {"hi", "gu"} else "en"]
	assert approval in done  # a grown-up must approve; a mission alone unlocks nothing
	for text in (title, message, done):
		assert "earned" not in text.lower() and "unlocked" not in text.lower()


# --------------------------------------------------------------------------- end to end on record_progress


def test_record_progress_runs_against_a_real_allowance_calculation(db):
	"""Regression: record_progress passed a naive datetime to the allowance helpers, whose
	utc_naive() rejects it, so every progress report failed (hidden by mocked tests)."""
	child, video = make_child(db)
	result = report(db, child, video)
	assert result["accepted_seconds"] == 30
	assert result["remaining_allowance_seconds"] == 870


def test_warning_fires_once_when_crossing_two_minutes(db):
	child, video = make_child(db, free_left=140)
	result = report(db, child, video)
	assert result["accepted_seconds"] == 30
	assert result["remaining_allowance_seconds"] == 110
	[warning] = alerts_of(db, child, NEARLY_EXHAUSTED)
	assert "2 min" in warning.message

	for _ in range(2):  # more reports below the threshold, possibly from other videos
		tick(db, child)
		report(db, child, video)
	assert len(alerts_of(db, child, NEARLY_EXHAUSTED)) == 1


def test_time_up_alert_fires_once_and_further_reports_are_refused(db):
	child, video = make_child(db, free_left=25)
	result = report(db, child, video)
	assert result["accepted_seconds"] == 25  # never more than what is left
	assert result["is_exhausted"] is True
	assert len(alerts_of(db, child, EXHAUSTED)) == 1

	tick(db, child)
	with pytest.raises(APIError) as refused:
		report(db, child, video)
	assert refused.value.status_code == 403
	assert refused.value.code == "video_time_exhausted"
	assert len(alerts_of(db, child, EXHAUSTED)) == 1


def test_duplicate_report_charges_once_and_alerts_once(db):
	child, video = make_child(db, free_left=140)
	first = report(db, child, video)
	second = report(db, child, video)  # same instant: retry / double send
	assert first["accepted_seconds"] == 30
	assert second["accepted_seconds"] == 0
	assert second["remaining_allowance_seconds"] in (None, 110)
	usage = db.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	assert usage.free_watched_seconds == 900 - 110
	assert len(alerts_of(db, child)) == 1


def test_mission_time_is_charged_after_free_time_and_alerts_use_the_total(db):
	child, video = make_child(db, free_left=10)
	grant(db, child, 120)
	result = report(db, child, video)
	assert result["accepted_seconds"] == 30
	assert result["remaining_allowance_seconds"] == 100  # 10 free + 120 mission - 30
	entitlement = db.query(VideoAccessEntitlement).one()
	assert entitlement.consumed_seconds == 20
	assert len(alerts_of(db, child, NEARLY_EXHAUSTED)) == 1


def test_a_new_parent_approval_rearms_the_warnings(db):
	child, video = make_child(db, free_left=25)
	report(db, child, video)
	assert len(alerts_of(db, child, EXHAUSTED)) == 1

	grant(db, child, 140)  # a parent approved a mission (partial grant near the cap)
	tick(db, child)
	result = report(db, child, video, position=130)
	assert result["remaining_allowance_seconds"] == 110
	assert len(alerts_of(db, child, NEARLY_EXHAUSTED)) == 1

	for position in (160, 190, 220, 250):
		tick(db, child)
		try:
			report(db, child, video, position=position)
		except APIError:
			break
	assert len(alerts_of(db, child, EXHAUSTED)) == 2  # one per grant window, never repeated within it


def test_alert_is_not_sent_twice_for_the_same_window(db):
	child, _ = make_child(db)
	now = datetime.now(timezone.utc)
	first = alerts.emit_video_time_alert(db, child, before_seconds=150, after_seconds=110, now=now)
	db.commit()
	again = alerts.emit_video_time_alert(db, child, before_seconds=150, after_seconds=110, now=now + timedelta(seconds=5))
	assert first is not None
	assert again is None


def test_yesterdays_alert_does_not_silence_today(db):
	child, _ = make_child(db)
	now = datetime.now(timezone.utc)
	db.add(
		Notification(
			recipient_user_id=child.user_id, notification_type=NEARLY_EXHAUSTED, title="t", message="m",
			created_at=utc_naive(now) - timedelta(days=1, hours=1),
		)
	)
	db.commit()
	assert alerts.emit_video_time_alert(db, child, before_seconds=150, after_seconds=110, now=now) is not None


def test_alerts_are_in_the_childs_language(db):
	child, video = make_child(db, language="gu", free_left=140)
	report(db, child, video)
	[warning] = alerts_of(db, child)
	assert any("઀" <= ch <= "૿" for ch in warning.message)


def test_yesterdays_grant_has_expired(db):
	child, video = make_child(db, free_left=25)
	grant(db, child, 900, at=utc_naive(datetime.now(timezone.utc)) - timedelta(days=2))
	result = report(db, child, video)
	assert result["is_exhausted"] is True  # last day's mission time does not carry over


def test_an_alert_failure_never_undoes_the_charge(db, monkeypatch):
	import app.services.video_watch_history_service as history

	def broken(*args, **kwargs):
		raise RuntimeError("notification store down")

	monkeypatch.setattr(history, "emit_video_time_alert", broken)
	child, video = make_child(db, free_left=140)
	result = report(db, child, video)
	assert result["accepted_seconds"] == 30
	db.expire_all()
	usage = db.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	assert usage.free_watched_seconds == 900 - 110


def test_seeking_while_paused_is_not_charged_and_raises_no_alert(db):
	from app.services.video_watch_history_service import record_progress

	child, video = make_child(db, free_left=140)
	usage = db.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one()
	usage.is_playing = False
	db.commit()
	result = record_progress(db, child, video.id, 500, is_playing=False)  # a seek forward while paused
	assert result["accepted_seconds"] == 0
	assert alerts_of(db, child) == []
