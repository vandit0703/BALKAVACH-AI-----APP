"""Per-subject lockout used by parent-mode entry. Pure tests: no database, in-process Redis stand-in."""

import fakeredis
import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.services.attempt_lockout import AttemptLockout


@pytest.fixture
def lockout(monkeypatch):
	monkeypatch.setattr(settings, "parent_mode_max_failures", 3)
	monkeypatch.setattr(settings, "parent_mode_lock_seconds", 60)
	monkeypatch.setattr(settings, "parent_mode_lock_max_seconds", 600)
	return AttemptLockout(client=fakeredis.FakeRedis(decode_responses=True))


def test_failures_below_the_limit_do_not_lock(lockout):
	first = lockout.record_failure("email:a")
	second = lockout.record_failure("email:a")
	assert (first.locked_for, first.attempts_remaining) == (0, 2)
	assert (second.locked_for, second.attempts_remaining) == (0, 1)
	assert lockout.locked_for("email:a") == 0


def test_limit_locks_the_subject_with_no_ip_involved(lockout):
	for _ in range(2):
		lockout.record_failure("email:a")
	locked = lockout.record_failure("email:a")
	assert locked.locked_for == 60 and locked.newly_locked is True
	assert 0 < lockout.locked_for("email:a") <= 60


def test_other_subjects_are_unaffected(lockout):
	for _ in range(3):
		lockout.record_failure("email:victim")
	assert lockout.locked_for("email:victim") > 0
	assert lockout.locked_for("email:other") == 0


def test_attempts_while_locked_do_not_extend_or_escalate(lockout):
	for _ in range(3):
		lockout.record_failure("s")
	again = lockout.record_failure("s")
	assert 0 < again.locked_for <= 60
	assert again.newly_locked is False


def test_repeat_locks_double_and_are_capped(lockout):
	for _ in range(3):
		lockout.record_failure("s")
	for expected in (120, 240, 480, 600, 600):
		lockout.lift_lock_keep_history("s")
		for _ in range(2):
			lockout.record_failure("s")
		assert lockout.record_failure("s").locked_for == expected


def test_success_clears_failures_but_never_an_active_lock(lockout):
	lockout.record_failure("s")
	lockout.record_failure("s")
	lockout.record_success("s")
	assert lockout.record_failure("s").attempts_remaining == 2
	for _ in range(2):
		lockout.record_failure("s")
	assert lockout.locked_for("s") > 0
	lockout.record_success("s")
	assert lockout.locked_for("s") > 0


def test_redis_failure_fails_closed():
	class Broken:
		def ttl(self, *_):
			raise ConnectionError("down")

		def register_script(self, *_):
			raise ConnectionError("down")

	guard = AttemptLockout(client=Broken())
	with pytest.raises(HTTPException) as error:
		guard.locked_for("s")
	assert error.value.status_code == 503
	with pytest.raises(HTTPException) as error:
		guard.record_failure("s")
	assert error.value.status_code == 503


def test_missing_redis_configuration_fails_closed(monkeypatch):
	monkeypatch.setattr(settings, "redis_url", None)
	with pytest.raises(HTTPException) as error:
		AttemptLockout().locked_for("s")
	assert error.value.status_code == 503
