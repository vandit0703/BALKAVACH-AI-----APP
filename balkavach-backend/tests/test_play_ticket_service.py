"""D6 play-ticket service and API.

LABELS
* **SQLite service tests** (most of this file): the real ``play_ticket_service``
  and the real ``SqlPlayTicketRepository`` against an in-memory SQLite copy of
  the *proposed* ``video_play_tickets`` table (``tests/video_world.py``), with
  the real allowance ledgers and alerts. Not PostgreSQL.
* **Test doubles**: SQLite has no partial unique index, so
  ``OneActiveRepository`` emulates PostgreSQL's one-active-ticket index, and
  ``RacingRepository`` simulates another device inserting between our check
  and our insert. Real concurrent starts still need the PostgreSQL suite.
* **API tests**: FastAPI routes with dependency overrides (child + SQLite
  session); no network, no real database.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
import logging
from types import SimpleNamespace
from unittest.mock import MagicMock
from uuid import uuid4

import pytest

from app.core.config import settings
from app.core.exceptions import APIError
from app.services import charging_path
from app.services import play_ticket_service as svc
from app.services.play_ticket_service import ActiveTicketConflict, SqlPlayTicketRepository
from app.utils import utc_naive
from tests.video_world import (  # noqa: F401 - db is a fixture
	MODELS,
	ChildVideoDailyUsage,
	Notification,
	Video,
	VideoAccessEntitlement,
	VideoPlayTicket,
	db,
	grant,
	make_child,
)

SECRET = "ticket-test-secret-that-is-long-enough"
DEVICE = "device-aaaa1111"


@pytest.fixture
def tickets_on(monkeypatch):
	"""Tickets active: setting on and the (test) table present."""
	monkeypatch.setattr(settings, "jwt_secret_key", SECRET)
	monkeypatch.setattr(settings, "video_play_tickets_enabled", True)
	monkeypatch.setattr(charging_path, "has_model", lambda name: name in MODELS)


class OneActiveRepository(SqlPlayTicketRepository):
	"""Test double: the real SQL repository plus the PostgreSQL partial unique
	index ``(child_id) WHERE state IN (issued, playing, paused)`` that SQLite lacks."""

	def add(self, **fields):
		if self.active_count(fields["child_id"]):
			raise ActiveTicketConflict
		return super().add(**fields)

	def active_count(self, child_id):
		return (
			self._session.query(VideoPlayTicket)
			.filter(VideoPlayTicket.child_id == child_id, VideoPlayTicket.state.in_(["issued", "playing", "paused"]))
			.count()
		)


class RacingRepository(OneActiveRepository):
	"""Test double: the first check misses a ticket another device inserts just before our insert."""

	def __init__(self, session, rival):
		super().__init__(session)
		self._rival = rival
		self._raced = False

	def active_for_child(self, child_id):
		if not self._raced:
			self._raced = True
			self._rival()
			return None  # our check ran before the rival's insert was visible
		return super().active_for_child(child_id)


def now_utc():
	return datetime.now(timezone.utc)


def start(db, child, video, *, repo=None, at=None):
	repo = repo or OneActiveRepository(db)
	return repo, svc.issue_ticket(db, repo, child, video_id=video.id, device_session_id=DEVICE, now_aware=at or now_utc())


def beat(db, repo, child, issued, *, seq, at, playing=True, position=10, token=None):
	return svc.ticket_heartbeat(
		db, repo, child, ticket_id=issued.ticket_id, token=token or issued.ticket_token, sequence=seq,
		is_playing=playing, position_seconds=position, now_aware=at,
	)


def ticket_row(db, issued):
	db.expire_all()
	return db.get(VideoPlayTicket, issued.ticket_id)


def free_used(db, child):
	db.expire_all()
	return db.query(ChildVideoDailyUsage).filter_by(child_id=child.id).one().free_watched_seconds


# --------------------------------------------------------------------------- issuing


def test_issue_stores_only_a_hash_and_returns_the_video(db, tickets_on):
	child, video = make_child(db)
	repo, issued = start(db, child, video)
	row = ticket_row(db, issued)
	assert row.state == "issued"
	assert row.token_hash != issued.ticket_token and issued.ticket_token not in row.token_hash
	assert issued.youtube_video_id == video.external_video_id
	assert issued.heartbeat_interval_seconds == 10
	assert utc_naive(issued.expires_at) <= utc_naive(now_utc()) + timedelta(seconds=61)


def test_no_ticket_without_allowance(db, tickets_on):
	child, video = make_child(db, free_left=0)
	with pytest.raises(APIError) as refused:
		start(db, child, video)
	assert refused.value.code == "video_time_exhausted"
	assert db.query(VideoPlayTicket).count() == 0


def test_a_new_start_supersedes_the_old_ticket(db, tickets_on):
	child, video = make_child(db)
	repo, first = start(db, child, video)
	_, second = start(db, child, video, repo=repo)
	old = ticket_row(db, first)
	assert old.state == "superseded" and old.superseded_by == second.ticket_id
	assert repo.active_count(child.id) == 1
	with pytest.raises(APIError) as moved:
		beat(db, repo, child, first, seq=0, at=now_utc())
	assert moved.value.code == "ticket_superseded"


def test_concurrent_start_race_leaves_exactly_one_active_ticket(db, tickets_on):
	"""Double: simulates the race the PostgreSQL index and child row lock prevent."""
	child, video = make_child(db)

	def rival():
		other = OneActiveRepository(db)
		svc.issue_ticket(db, other, child, video_id=video.id, device_session_id="device-bbbb2222", now_aware=now_utc())

	repo = RacingRepository(db, rival)
	issued = svc.issue_ticket(db, repo, child, video_id=video.id, device_session_id=DEVICE, now_aware=now_utc())
	assert repo.active_count(child.id) == 1
	assert ticket_row(db, issued).state == "issued"
	assert db.query(VideoPlayTicket).filter_by(state="superseded").count() == 1


# --------------------------------------------------------------------------- ownership and tokens


def test_another_childs_ticket_is_not_found(db, tickets_on):
	child, video = make_child(db)
	stranger, _ = make_child(db)
	repo, issued = start(db, child, video)
	with pytest.raises(Exception) as missing:
		beat(db, repo, stranger, issued, seq=0, at=now_utc())
	assert getattr(missing.value, "status_code", None) == 404


def test_a_wrong_token_is_refused_without_charging(db, tickets_on):
	child, video = make_child(db)
	repo, issued = start(db, child, video)
	with pytest.raises(APIError) as invalid:
		beat(db, repo, child, issued, seq=0, at=now_utc(), token="x" * 43)
	assert invalid.value.code == "ticket_invalid"
	assert ticket_row(db, issued).last_sequence == -1


# --------------------------------------------------------------------------- heartbeats


def test_nothing_is_charged_before_playback_starts(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	before = free_used(db, child)
	first = beat(db, repo, child, issued, seq=0, at=t0 + timedelta(seconds=3))
	assert first.accepted_seconds == 0 and first.state == "playing"
	second = beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=13))
	assert second.accepted_seconds == 10
	assert free_used(db, child) == before + 10
	assert ticket_row(db, issued).charged_seconds == 10


def test_duplicate_and_out_of_order_heartbeats(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	for seq in range(6):
		beat(db, repo, child, issued, seq=seq, at=t0 + timedelta(seconds=2 + 10 * seq))
	charged = ticket_row(db, issued).charged_seconds
	again = beat(db, repo, child, issued, seq=5, at=t0 + timedelta(seconds=60))
	late = beat(db, repo, child, issued, seq=4, at=t0 + timedelta(seconds=61))
	assert again.duplicate and late.duplicate
	assert ticket_row(db, issued).charged_seconds == charged
	with pytest.raises(APIError) as replay:
		beat(db, repo, child, issued, seq=0, at=t0 + timedelta(seconds=62))
	assert replay.value.code == "ticket_sequence_invalid"


def test_paused_time_is_free(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0, playing=False)
	paused = beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=30), playing=True)
	assert paused.accepted_seconds == 0
	playing = beat(db, repo, child, issued, seq=2, at=t0 + timedelta(seconds=40), playing=False)
	assert playing.accepted_seconds == 10


def test_delayed_heartbeats_are_charged_in_full_and_silence_lapses(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0)
	assert beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=40)).accepted_seconds == 40
	# Network gone / app killed / device asleep for 5 minutes:
	lapsed = beat(db, repo, child, issued, seq=2, at=t0 + timedelta(seconds=340))
	assert lapsed.state == "expired" and lapsed.accepted_seconds == 10
	assert ticket_row(db, issued).end_reason == "missed_heartbeats"
	with pytest.raises(APIError) as dead:
		beat(db, repo, child, issued, seq=3, at=t0 + timedelta(seconds=350))
	assert dead.value.code == "ticket_expired"
	# After the interruption the app simply asks for a new ticket.
	_, fresh = start(db, child, video, repo=repo, at=t0 + timedelta(seconds=360))
	assert ticket_row(db, fresh).state == "issued"


def test_an_unused_ticket_expires(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	late = beat(db, repo, child, issued, seq=0, at=t0 + timedelta(seconds=90))
	assert late.state == "expired" and late.accepted_seconds == 0
	assert ticket_row(db, issued).end_reason == "not_started"


def test_parent_approval_during_playback_extends_the_session(db, tickets_on):
	child, video = make_child(db, free_left=25)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0)
	assert beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=10)).remaining_seconds == 15
	grant(db, child, 900)  # a parent approved a mission on their phone
	after = beat(db, repo, child, issued, seq=2, at=t0 + timedelta(seconds=20))
	assert after.state == "playing"
	assert after.remaining_seconds == 15 + 900 - 10
	db.expire_all()
	assert db.query(VideoAccessEntitlement).one().consumed_seconds == 0  # free time went first


def test_exhaustion_ends_the_ticket_and_raises_the_alert_once(db, tickets_on):
	child, video = make_child(db, free_left=15)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0)
	done = beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=20))
	assert done.accepted_seconds == 15 and done.is_exhausted and done.state == "exhausted"
	assert db.query(Notification).filter_by(notification_type="video_time_exhausted").count() == 1
	with pytest.raises(APIError) as refused:
		beat(db, repo, child, issued, seq=2, at=t0 + timedelta(seconds=30))
	assert refused.value.code == "ticket_exhausted"


def test_local_midnight_charges_only_the_old_day_and_ends_the_ticket(db, tickets_on):
	from app.services.timezone_service import local_day_bounds_utc_naive, local_today, parse_timezone

	child, video = make_child(db)
	today = local_today(db, child.family_id)
	midnight = local_day_bounds_utc_naive(parse_timezone("Asia/Kolkata"), today, 1)[1].replace(tzinfo=timezone.utc)
	t0 = midnight - timedelta(seconds=30)
	repo, issued = start(db, child, video, at=t0)
	assert utc_naive(issued.expires_at) <= utc_naive(midnight)
	beat(db, repo, child, issued, seq=0, at=t0 + timedelta(seconds=5))
	before = free_used(db, child)
	after_midnight = beat(db, repo, child, issued, seq=1, at=midnight + timedelta(seconds=10))
	assert after_midnight.state == "expired"
	assert ticket_row(db, issued).end_reason == "midnight"
	assert free_used(db, child) == before + 25  # the 25 s before midnight, nothing after


def test_unpublished_video_revokes_the_ticket(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0)
	video.title = "UNPUBLISHED"
	db.commit()
	with pytest.raises(APIError) as revoked:
		beat(db, repo, child, issued, seq=1, at=t0 + timedelta(seconds=10))
	assert revoked.value.code == "ticket_revoked"
	assert ticket_row(db, issued).state == "revoked"


def test_end_charges_the_last_interval_and_is_idempotent(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	beat(db, repo, child, issued, seq=0, at=t0)
	ended = svc.end_ticket(db, repo, child, ticket_id=issued.ticket_id, token=issued.ticket_token, sequence=1,
		position_seconds=42, now_aware=t0 + timedelta(seconds=7))
	assert ended.state == "ended" and ended.accepted_seconds == 7
	again = svc.end_ticket(db, repo, child, ticket_id=issued.ticket_id, token=issued.ticket_token, sequence=2,
		position_seconds=42, now_aware=t0 + timedelta(seconds=9))
	assert again.duplicate and again.accepted_seconds == 0
	with pytest.raises(APIError) as closed:
		beat(db, repo, child, issued, seq=3, at=t0 + timedelta(seconds=10))
	assert closed.value.code == "ticket_ended"


def test_revocation_stops_further_heartbeats(db, tickets_on):
	child, video = make_child(db)
	t0 = now_utc()
	repo, issued = start(db, child, video, at=t0)
	assert svc.revoke_child_tickets(db, repo, child.id, "parent_revoked") is True
	db.commit()
	with pytest.raises(APIError) as revoked:
		beat(db, repo, child, issued, seq=0, at=t0 + timedelta(seconds=1))
	assert revoked.value.code == "ticket_revoked"


# --------------------------------------------------------------------------- exactly one charging path


def test_default_settings_keep_tickets_off_and_record_progress_charging(db, monkeypatch):
	from app.services.video_watch_history_service import record_progress

	monkeypatch.setattr(charging_path, "has_model", lambda name: name in MODELS)
	assert settings.video_play_tickets_enabled is False
	assert charging_path.play_tickets_active() is False
	with pytest.raises(APIError) as off:
		svc.require_play_tickets(db)
	assert off.value.code == "play_tickets_unavailable"
	child, video = make_child(db)
	assert record_progress(db, child, video.id, 100)["accepted_seconds"] == 30


def test_setting_on_without_the_table_changes_nothing(db, monkeypatch):
	from app.services.video_watch_history_service import record_progress

	monkeypatch.setattr(settings, "video_play_tickets_enabled", True)
	monkeypatch.setattr(charging_path, "has_model", lambda name: False)  # the real situation today
	assert charging_path.play_tickets_active() is False
	with pytest.raises(APIError):
		svc.require_play_tickets(db)
	child, video = make_child(db)
	assert record_progress(db, child, video.id, 100)["accepted_seconds"] == 30


def test_with_tickets_active_record_progress_refuses_to_charge(db, tickets_on):
	from app.services.video_watch_history_service import record_progress

	child, video = make_child(db)
	before = free_used(db, child)
	with pytest.raises(APIError) as refused:
		record_progress(db, child, video.id, 10)
	assert refused.value.code == "play_ticket_required"
	assert free_used(db, child) == before


def test_without_a_database_storage_is_unavailable(monkeypatch):
	def no_db(name):
		raise RuntimeError("DATABASE_URL must be configured")

	monkeypatch.setattr(settings, "video_play_tickets_enabled", True)
	monkeypatch.setattr(charging_path, "has_model", no_db)
	assert charging_path.play_tickets_active() is False


# --------------------------------------------------------------------------- API


@pytest.fixture
def api(db):
	from fastapi.testclient import TestClient

	from app.core.dependencies import require_child
	from app.db.session import get_db
	from app.main import app

	holder = SimpleNamespace(child=None)
	app.dependency_overrides[require_child] = lambda: holder.child
	app.dependency_overrides[get_db] = lambda: db
	try:
		with TestClient(app) as client:
			yield client, holder
	finally:
		app.dependency_overrides.pop(require_child, None)
		app.dependency_overrides.pop(get_db, None)


def test_api_refuses_while_tickets_are_off(api, db):
	client, holder = api
	holder.child, video = make_child(db)
	response = client.post("/api/v1/video-access/tickets", json={"video_id": str(video.id), "device_session_id": DEVICE})
	assert response.status_code == 503
	assert response.json()["error"]["code"] == "play_tickets_unavailable"


def test_api_requires_a_child_token():
	from fastapi.testclient import TestClient

	from app.db.session import get_db
	from app.main import app

	app.dependency_overrides[get_db] = lambda: MagicMock()
	try:
		with TestClient(app) as client:
			response = client.post(
				"/api/v1/video-access/tickets", json={"video_id": str(uuid4()), "device_session_id": DEVICE}
			)
	finally:
		app.dependency_overrides.pop(get_db, None)
	assert response.status_code == 401


def test_api_flow_and_tokens_never_logged(api, db, tickets_on, monkeypatch, caplog):
	client, holder = api
	holder.child, video = make_child(db)
	monkeypatch.setattr(svc, "SqlPlayTicketRepository", OneActiveRepository)
	with caplog.at_level(logging.DEBUG):
		created = client.post(
			"/api/v1/video-access/tickets", json={"video_id": str(video.id), "device_session_id": DEVICE}
		)
		assert created.status_code == 201, created.text
		body = created.json()
		token, ticket_id = body["ticket_token"], body["ticket_id"]
		beat = client.post(
			f"/api/v1/video-access/tickets/{ticket_id}/heartbeat",
			json={"ticket_token": token, "sequence": 0, "is_playing": True, "position_seconds": 0},
		)
		assert beat.status_code == 200 and beat.json()["state"] == "playing"
		ended = client.post(
			f"/api/v1/video-access/tickets/{ticket_id}/end",
			json={"ticket_token": token, "sequence": 1, "position_seconds": 3},
		)
		assert ended.status_code == 200 and ended.json()["state"] == "ended"
	assert token not in caplog.text


@pytest.mark.parametrize(
	"payload",
	[
		{"ticket_token": "short", "sequence": 0, "is_playing": True, "position_seconds": 0},
		{"ticket_token": "x" * 43, "sequence": -1, "is_playing": True, "position_seconds": 0},
		{"ticket_token": "x" * 43, "sequence": 0, "is_playing": True},
	],
)
def test_api_validates_heartbeats(api, db, payload):
	client, holder = api
	holder.child, _ = make_child(db)
	assert client.post(f"/api/v1/video-access/tickets/{uuid4()}/heartbeat", json=payload).status_code == 422
