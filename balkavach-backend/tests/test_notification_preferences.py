"""Phase 7: family notification preferences, quiet hours and push gating.

Runs on the in-memory SQLite world (``tests/sqlite_world.py``) with a fake push
provider. It proves the rules, not delivery: no PostgreSQL, no FCM, no phone.
"""

from __future__ import annotations

from datetime import datetime, timezone
from types import SimpleNamespace
from uuid import uuid4
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import app.api.v1.settings as settings_api
import app.services.notification_preferences_service as prefs
import app.services.notification_service as notification_service
import app.services.device_service as device_service
import app.services.push_service as push_service
import app.services.timezone_service as zones
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.main import app
from tests.sqlite_world import (
	ChildProfile,
	Family,
	DeviceToken,
	FamilyMember,
	FamilySetting,
	Notification,
	User,
	UserSetting,
	World,
	_get_model,
)

UTC = timezone.utc
KOLKATA = ZoneInfo("Asia/Kolkata")
NEW_YORK = ZoneInfo("America/New_York")


@pytest.fixture
def world(monkeypatch):
	"""Like ``world_session`` but on one shared connection, so TestClient's worker thread sees the same data."""
	for module in (prefs, push_service, settings_api, notification_service, zones, device_service):
		monkeypatch.setattr(module, "get_model", _get_model)
	engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
	World.metadata.create_all(engine)
	session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)()
	try:
		yield session
	finally:
		session.close()
		engine.dispose()


def _family(session, *, timezone_name: str | None = "Asia/Kolkata", stored: dict | None = None):
	family = Family()
	session.add(family)
	session.flush()
	family_id = family.id
	parent = User(role="parent", preferred_language="en")
	child_user = User(role="child", preferred_language="hi")
	session.add_all([parent, child_user])
	session.flush()
	session.add(FamilyMember(family_id=family_id, user_id=parent.id))
	session.add(ChildProfile(user_id=child_user.id, family_id=family_id))
	mission_settings = {}
	if timezone_name:
		mission_settings["timezone"] = timezone_name
	if stored is not None:
		mission_settings[prefs.PREFERENCES_KEY] = stored
	if mission_settings:
		session.add(FamilySetting(family_id=family_id, mission_settings=mission_settings))
	session.commit()
	return SimpleNamespace(id=family_id, parent=parent, child=child_user)


# --------------------------------------------------------------------- pure rules


def test_defaults_turn_every_category_on_and_quiet_hours_off():
	effective = prefs.effective_preferences(None)
	assert all(effective["categories"].values())
	assert set(effective["categories"]) == {c.key for c in prefs.CATEGORIES}
	assert effective["quiet_hours"] == {"enabled": False, "start": "21:00", "end": "07:00"}


def test_junk_in_storage_falls_back_to_defaults_and_cannot_unlock_safety():
	effective = prefs.effective_preferences(
		{
			"categories": {"streaks": "no", "rewards": False, "safety": False, "made_up": False},
			"quiet_hours": {"enabled": "yes", "start": "25:00", "end": "07:30"},
		}
	)
	assert effective["categories"]["streaks"] is True  # non-bool ignored
	assert effective["categories"]["rewards"] is False
	assert effective["categories"]["safety"] is True  # locked
	assert "made_up" not in effective["categories"]
	assert effective["quiet_hours"] == {"enabled": False, "start": "21:00", "end": "07:30"}


def test_every_push_template_type_has_a_category():
	# A new push type without a category would silently ignore the parent's switches.
	missing = [t for t in push_service.GENERIC_TEXT if prefs.category_of(t) is None]
	assert missing == []


@pytest.mark.parametrize(
	"local,expected",
	[("21:59", False), ("22:00", True), ("23:59", True), ("00:00", True), ("03:15", True), ("06:59", True), ("07:00", False), ("12:00", False)],
)
def test_overnight_quiet_hours_cross_midnight(local, expected):
	quiet = {"enabled": True, "start": "22:00", "end": "07:00"}
	hours, minutes = map(int, local.split(":"))
	moment = datetime(2026, 11, 19, hours, minutes, tzinfo=KOLKATA)
	assert prefs.is_quiet(quiet, KOLKATA, moment) is expected


def test_same_day_quiet_hours_window():
	quiet = {"enabled": True, "start": "13:00", "end": "15:00"}
	assert prefs.is_quiet(quiet, KOLKATA, datetime(2026, 11, 19, 14, 0, tzinfo=KOLKATA))
	assert not prefs.is_quiet(quiet, KOLKATA, datetime(2026, 11, 19, 15, 0, tzinfo=KOLKATA))
	assert not prefs.is_quiet({**quiet, "enabled": False}, KOLKATA, datetime(2026, 11, 19, 14, 0, tzinfo=KOLKATA))


def test_quiet_hours_use_the_family_zone_not_utc():
	quiet = {"enabled": True, "start": "22:00", "end": "07:00"}
	# 17:00 UTC is 22:30 in Kolkata (quiet) and 12:00 in New York (not quiet).
	moment = datetime(2026, 11, 19, 17, 0, tzinfo=UTC)
	assert prefs.is_quiet(quiet, KOLKATA, moment)
	assert not prefs.is_quiet(quiet, NEW_YORK, moment)
	# A naive timestamp is read as UTC, the way the database stores them.
	assert prefs.is_quiet(quiet, KOLKATA, moment.replace(tzinfo=None))


def test_quiet_hours_follow_local_wall_clock_across_daylight_saving():
	quiet = {"enabled": True, "start": "22:00", "end": "07:00"}
	# New York, 2026: DST ends 1 Nov (UTC-4 -> UTC-5), starts 8 Mar (UTC-5 -> UTC-4).
	# 11:30 UTC is 07:30 local in EDT (not quiet) but 06:30 local in EST (quiet).
	assert not prefs.is_quiet(quiet, NEW_YORK, datetime(2026, 10, 31, 11, 30, tzinfo=UTC))
	assert prefs.is_quiet(quiet, NEW_YORK, datetime(2026, 11, 2, 11, 30, tzinfo=UTC))
	# On the spring-forward night 02:00-03:00 does not exist; 06:59 local is still quiet, 07:00 is not.
	assert prefs.is_quiet(quiet, NEW_YORK, datetime(2026, 3, 8, 6, 59, tzinfo=NEW_YORK))
	assert not prefs.is_quiet(quiet, NEW_YORK, datetime(2026, 3, 8, 7, 0, tzinfo=NEW_YORK))


def test_decisions_mute_by_category_and_exempt_safety():
	effective = prefs.effective_preferences(
		{"categories": {"streaks": False}, "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"}}
	)
	day = datetime(2026, 11, 19, 12, 0, tzinfo=KOLKATA)
	night = datetime(2026, 11, 19, 23, 0, tzinfo=KOLKATA)
	assert prefs.push_decision(effective, KOLKATA, "streak_at_risk", day) == "muted"
	assert prefs.push_decision(effective, KOLKATA, "task_approved", day) == "send"
	assert prefs.push_decision(effective, KOLKATA, "task_approved", night) == "quiet_hours"
	assert prefs.push_decision(effective, KOLKATA, "parent_mode_locked", night) == "send"
	# Unknown types are never muted but do respect quiet hours.
	assert prefs.push_decision(effective, KOLKATA, "brand_new_type", day) == "send"
	assert prefs.push_decision(effective, KOLKATA, "brand_new_type", night) == "quiet_hours"


# --------------------------------------------------------------------- API


@pytest.fixture
def client(world):
	state = SimpleNamespace(user=None)

	def _db():
		yield world

	app.dependency_overrides[get_db] = _db
	app.dependency_overrides[get_current_user] = lambda: state.user
	try:
		with TestClient(app) as http:
			http.state = state
			yield http
	finally:
		app.dependency_overrides.pop(get_db, None)
		app.dependency_overrides.pop(get_current_user, None)


def _url(family_id):
	return f"/api/v1/settings/families/{family_id}/notification-preferences"


def test_parent_reads_defaults_with_family_timezone(client, world):
	family = _family(world)
	client.state.user = family.parent
	response = client.get(_url(family.id))
	assert response.status_code == 200
	body = response.json()
	assert body["timezone"] == "Asia/Kolkata"
	assert body["timezone_is_default"] is False
	assert body["locked_categories"] == ["safety"]
	assert body["quiet_hours_exempt_categories"] == ["safety"]
	assert all(body["categories"].values())
	assert body["updated_at"] is None


def test_missing_settings_row_reports_utc_as_a_default(client, world):
	family = _family(world, timezone_name=None)
	client.state.user = family.parent
	body = client.get(_url(family.id)).json()
	assert body["timezone"] == "UTC"
	assert body["timezone_is_default"] is True


def test_parent_update_persists_and_keeps_other_mission_settings(client, world):
	family = _family(world)
	client.state.user = family.parent
	response = client.patch(
		_url(family.id),
		json={"categories": {"streaks": False}, "quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"}},
	)
	assert response.status_code == 200, response.text
	body = response.json()
	assert body["categories"]["streaks"] is False
	assert body["categories"]["rewards"] is True
	assert body["quiet_hours"] == {"enabled": True, "start": "22:00", "end": "07:00"}
	assert body["updated_at"] is not None
	world.expire_all()
	stored = world.get(FamilySetting, family.id).mission_settings
	assert stored["timezone"] == "Asia/Kolkata"
	assert stored[prefs.PREFERENCES_KEY]["updated_by"] == str(family.parent.id)

	# A second, partial change merges instead of replacing.
	body = client.patch(_url(family.id), json={"quiet_hours": {"start": "21:30"}}).json()
	assert body["categories"]["streaks"] is False
	assert body["quiet_hours"] == {"enabled": True, "start": "21:30", "end": "07:00"}


def test_update_creates_the_settings_row_when_missing(client, world):
	family = _family(world, timezone_name=None)
	client.state.user = family.parent
	assert client.patch(_url(family.id), json={"categories": {"rewards": False}}).status_code == 200
	world.expire_all()
	assert world.get(FamilySetting, family.id).mission_settings[prefs.PREFERENCES_KEY]["categories"]["rewards"] is False


def test_child_accounts_cannot_read_or_change_preferences(client, world):
	family = _family(world)
	client.state.user = family.child
	assert client.get(_url(family.id)).status_code == 403
	assert client.patch(_url(family.id), json={"categories": {"streaks": False}}).status_code == 403


def test_a_parent_cannot_touch_another_familys_preferences(client, world):
	mine = _family(world)
	theirs = _family(world, stored={"categories": {"rewards": False}})
	client.state.user = mine.parent
	assert client.get(_url(theirs.id)).status_code == 404
	assert client.patch(_url(theirs.id), json={"categories": {"rewards": True}}).status_code == 404
	world.expire_all()
	assert world.get(FamilySetting, theirs.id).mission_settings[prefs.PREFERENCES_KEY]["categories"]["rewards"] is False


def test_inactive_membership_is_refused(client, world):
	family = _family(world)
	world.query(FamilyMember).filter(FamilyMember.user_id == family.parent.id).update({"is_active": False})
	world.commit()
	client.state.user = family.parent
	assert client.get(_url(family.id)).status_code == 404


@pytest.mark.parametrize(
	"payload",
	[
		{"categories": {"not_a_category": False}},
		{"categories": {"safety": False}},
		{"categories": {"streaks": "off"}},
		{"categories": None},
		{"quiet_hours": {"start": "24:00"}},
		{"quiet_hours": {"start": "7:00"}},
		{"quiet_hours": {"end": "07:60"}},
		{"quiet_hours": {"enabled": None}},
		{"quiet_hours": {"enabled": True, "start": "07:00", "end": "07:00"}},
		{"quiet_hours": {"surprise": True}},
		{"unknown_field": 1},
	],
)
def test_invalid_values_are_rejected_and_nothing_is_saved(client, world, payload):
	family = _family(world)
	client.state.user = family.parent
	assert client.patch(_url(family.id), json=payload).status_code == 422
	world.expire_all()
	assert prefs.PREFERENCES_KEY not in world.get(FamilySetting, family.id).mission_settings


def test_generic_family_settings_patch_cannot_overwrite_preferences(client, world):
	family = _family(world)
	client.state.user = family.parent
	client.patch(_url(family.id), json={"categories": {"streaks": False}})
	# The app saves the time zone by sending back an old copy of mission_settings.
	response = client.patch(
		f"/api/v1/settings/families/{family.id}",
		json={"mission_settings": {"timezone": "Europe/London", prefs.PREFERENCES_KEY: {"categories": {"streaks": True}}}},
	)
	assert response.status_code == 200, response.text
	world.expire_all()
	stored = world.get(FamilySetting, family.id).mission_settings
	assert stored["timezone"] == "Europe/London"
	assert stored[prefs.PREFERENCES_KEY]["categories"]["streaks"] is False


def test_get_one_notification_is_owner_scoped(client, world):
	family = _family(world)
	mine = Notification(recipient_user_id=family.child.id, notification_type="task_approved", related_task_id=uuid4())
	other = Notification(recipient_user_id=family.parent.id, notification_type="task_submitted")
	world.add_all([mine, other])
	world.commit()
	client.state.user = family.child
	response = client.get(f"/api/v1/notifications/{mine.id}")
	assert response.status_code == 200
	assert response.json()["related_task_id"] == str(mine.related_task_id)
	assert client.get(f"/api/v1/notifications/{other.id}").status_code == 404
	assert client.get(f"/api/v1/notifications/{uuid4()}").status_code == 404


# --------------------------------------------------------------------- push gating


class FakeProvider:
	def __init__(self, *results):
		self.results = list(results) or ["ok"]
		self.sent = []

	def send(self, token, title, body, data):
		self.sent.append({"token": token, "title": title, "data": data})
		return self.results.pop(0) if len(self.results) > 1 else self.results[0]


@pytest.fixture
def at(monkeypatch):
	def _set(moment: datetime):
		monkeypatch.setattr(push_service, "_now", lambda: moment)

	monkeypatch.setattr(push_service, "_sleep", lambda _seconds: None)
	return _set


def _device(session, user, token="t" * 40):
	session.add(DeviceToken(user_id=user.id, token=token, is_active=True))
	session.commit()


def test_muted_category_is_not_pushed_but_other_categories_are(world, at):
	family = _family(world, stored={"categories": {"streaks": False}})
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))  # 12:00 in Kolkata
	provider = FakeProvider()
	stats = push_service._deliver_with_session(
		world, provider, [(family.child.id, "streak_at_risk", uuid4()), (family.child.id, "task_approved", uuid4())]
	)
	assert [item["data"]["type"] for item in provider.sent] == ["task_approved"]
	assert stats["suppressed_muted"] == 1
	assert stats["provider_ok"] == 1


def test_quiet_hours_suppress_pushes_in_family_time_but_not_safety_alerts(world, at):
	family = _family(world, stored={"quiet_hours": {"enabled": True, "start": "22:00", "end": "07:00"}})
	_device(world, family.parent)
	at(datetime(2026, 11, 19, 18, 0, tzinfo=UTC))  # 23:30 in Kolkata
	provider = FakeProvider()
	stats = push_service._deliver_with_session(
		world, provider, [(family.parent.id, "task_submitted", uuid4()), (family.parent.id, "parent_mode_locked", uuid4())]
	)
	assert [item["data"]["type"] for item in provider.sent] == ["parent_mode_locked"]
	assert stats["suppressed_quiet_hours"] == 1

	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))  # 12:00 in Kolkata
	provider = FakeProvider()
	push_service._deliver_with_session(world, provider, [(family.parent.id, "task_submitted", uuid4())])
	assert len(provider.sent) == 1


def test_master_push_switch_still_wins(world, at):
	family = _family(world)
	_device(world, family.child)
	world.add(UserSetting(user_id=family.child.id, push_enabled=False))
	world.commit()
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	provider = FakeProvider()
	stats = push_service._deliver_with_session(world, provider, [(family.child.id, "task_approved", uuid4())])
	assert provider.sent == [] and stats["push_off"] == 1


def test_the_same_notification_is_never_sent_twice_in_one_run(world, at):
	family = _family(world)
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	notification_id = uuid4()
	provider = FakeProvider()
	stats = push_service._deliver_with_session(
		world, provider, [(family.child.id, "task_approved", notification_id)] * 3
	)
	assert len(provider.sent) == 1
	assert stats["duplicate_skipped"] == 2


def test_retry_is_bounded_and_counted(world, at):
	family = _family(world)
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	provider = FakeProvider("retry", "ok")
	stats = push_service._deliver_with_session(world, provider, [(family.child.id, "task_approved", uuid4())])
	assert len(provider.sent) == 2 and stats["provider_ok"] == 1

	provider = FakeProvider("retry")
	stats = push_service._deliver_with_session(world, provider, [(family.child.id, "task_approved", uuid4())])
	assert len(provider.sent) == push_service.MAX_ATTEMPTS
	assert stats["provider_retry_exhausted"] == 1


def test_invalid_token_is_deactivated_and_not_used_again(world, at):
	family = _family(world)
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	stats = push_service._deliver_with_session(world, FakeProvider("invalid_token"), [(family.child.id, "task_approved", uuid4())])
	assert stats["provider_invalid_token"] == 1
	world.expire_all()
	assert world.query(DeviceToken).one().is_active is False
	provider = FakeProvider()
	stats = push_service._deliver_with_session(world, provider, [(family.child.id, "task_approved", uuid4())])
	assert provider.sent == [] and stats["no_active_device"] == 1


def test_a_raising_provider_does_not_stop_the_run(world, at):
	family = _family(world)
	_device(world, family.child)
	_device(world, family.parent, token="p" * 40)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))

	class Boom:
		calls = 0

		def send(self, *args):
			Boom.calls += 1
			raise RuntimeError("provider down")

	stats = push_service._deliver_with_session(
		world, Boom(), [(family.child.id, "task_approved", uuid4()), (family.parent.id, "task_submitted", uuid4())]
	)
	assert Boom.calls == 2  # an exception is not retried
	assert stats["provider_error"] == 2


def test_unreadable_preferences_fail_open(world, at, monkeypatch):
	family = _family(world, stored={"categories": {"streaks": False}})
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))

	def broken(*_args, **_kwargs):
		raise RuntimeError("settings unavailable")

	monkeypatch.setattr(prefs, "load_family_preferences", broken)
	provider = FakeProvider()
	push_service._deliver_with_session(world, provider, [(family.child.id, "streak_at_risk", uuid4())])
	assert len(provider.sent) == 1


def test_push_payload_still_carries_no_content(world, at):
	family = _family(world)
	_device(world, family.child)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	provider = FakeProvider()
	push_service._deliver_with_session(world, provider, [(family.child.id, "task_approved", uuid4())])
	assert set(provider.sent[0]["data"]) == {"type", "notification_id"}
	# The child's language is Hindi: the generic text is localised.
	assert provider.sent[0]["title"] == push_service.GENERIC_TEXT["task_approved"]["hi"][0]


def test_unavailable_provider_never_breaks_the_request(world, monkeypatch):
	def unavailable():
		raise RuntimeError("no provider")

	monkeypatch.setattr(push_service, "get_push_notification_provider", unavailable)
	world.info["push_ready"] = [(uuid4(), "task_approved", uuid4())]
	push_service.deliver_ready(world)  # must not raise
	assert "push_ready" not in world.info


# --------------------------------------------------------------------- token lifecycle


def test_token_lifecycle_register_refresh_move_and_unregister(world, at):
	a = _family(world)
	b = _family(world)
	token = "x" * 60
	device_service.register_device(world, a.parent.id, token, "android", "1.0.0")
	device_service.register_device(world, a.parent.id, token, "android", "1.0.1")  # refresh, same phone
	rows = world.query(DeviceToken).all()
	assert len(rows) == 1 and rows[0].app_version == "1.0.1"

	# Another account signs in on the same phone: the token follows them.
	device_service.register_device(world, b.parent.id, token, "android", "1.0.1")
	world.expire_all()
	assert world.query(DeviceToken).one().user_id == b.parent.id
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	provider = FakeProvider()
	push_service._deliver_with_session(world, provider, [(a.parent.id, "task_submitted", uuid4())])
	assert provider.sent == []  # the previous user no longer receives pushes on that phone

	# Unregistering someone else's token is a silent no-op; your own removes it.
	device_service.unregister_device(world, a.parent.id, token)
	assert world.query(DeviceToken).count() == 1
	device_service.unregister_device(world, b.parent.id, token)
	assert world.query(DeviceToken).count() == 0


def test_a_deactivated_token_comes_back_when_the_app_registers_again(world, at):
	family = _family(world)
	token = "y" * 60
	device_service.register_device(world, family.child.id, token, "android", None)
	at(datetime(2026, 11, 19, 6, 30, tzinfo=UTC))
	push_service._deliver_with_session(world, FakeProvider("invalid_token"), [(family.child.id, "task_approved", uuid4())])
	world.expire_all()
	assert world.query(DeviceToken).one().is_active is False
	device_service.register_device(world, family.child.id, token, "android", None)
	world.expire_all()
	assert world.query(DeviceToken).one().is_active is True
