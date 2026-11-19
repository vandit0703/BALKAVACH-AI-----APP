"""Account-level failed-attempt tracking and lockout (parent-mode step-up).

Guessing is limited per **subject** (target account, family, child device
session), never per client IP, so rotating addresses gains an attacker nothing.

* ``parent_mode_max_failures`` wrong answers inside the failure window lock the
  subject for ``parent_mode_lock_seconds``;
* every further lock inside the strike window doubles the duration, capped at
  ``parent_mode_lock_max_seconds``;
* attempts made while locked are refused *without being evaluated* and neither
  extend nor escalate the lock;
* a correct answer clears the failure counter (it never lifts an active lock).

State lives in Redis (atomic Lua) because Redis is already mandatory for the
authentication limiters. If Redis is unavailable the step-up is refused (503):
it fails closed, like the other limiters.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from fastapi import HTTPException

from app.core.config import settings

logger = logging.getLogger(__name__)

_RECORD_FAILURE = """
local ttl = redis.call('TTL', KEYS[2])
if ttl > 0 then
  return {0, ttl, 0}
end
local failures = redis.call('INCR', KEYS[1])
if failures == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
if failures >= tonumber(ARGV[2]) then
  local strikes = redis.call('INCR', KEYS[3])
  redis.call('EXPIRE', KEYS[3], ARGV[3])
  local seconds = tonumber(ARGV[4])
  for _ = 2, strikes do seconds = seconds * 2 end
  if seconds > tonumber(ARGV[5]) then seconds = tonumber(ARGV[5]) end
  redis.call('SET', KEYS[2], '1', 'EX', seconds)
  redis.call('DEL', KEYS[1])
  return {failures, seconds, 1}
end
return {failures, 0, 0}
"""


@dataclass(frozen=True)
class FailureResult:
	locked_for: int
	attempts_remaining: int
	newly_locked: bool


class AttemptLockout:
	def __init__(self, client=None, scope: str = "parent-mode") -> None:
		self._client = client
		self._scope = scope
		self._script = None

	def _redis(self):
		if self._client is None:
			if not settings.redis_url:
				raise self._unavailable_error()
			import redis

			self._client = redis.Redis.from_url(
				settings.redis_url,
				decode_responses=True,
				socket_connect_timeout=1,
				socket_timeout=1,
			)
		return self._client

	def _key(self, kind: str, subject: str) -> str:
		return f"{settings.redis_rate_limit_prefix}:{self._scope}:{kind}:{subject}"

	@staticmethod
	def _unavailable_error() -> HTTPException:
		return HTTPException(
			status_code=503,
			detail="Authentication protection is temporarily unavailable.",
			headers={"Retry-After": "30"},
		)

	def _fail_closed(self, error: Exception) -> HTTPException:
		logger.error("Attempt lockout store failure", exc_info=error)
		return self._unavailable_error()

	def locked_for(self, subject: str) -> int:
		"""Seconds until this subject may try again; 0 when it is not locked."""
		try:
			ttl = int(self._redis().ttl(self._key("lock", subject)))
		except HTTPException:
			raise
		except Exception as error:
			raise self._fail_closed(error) from error
		return ttl if ttl > 0 else 0

	def record_failure(self, subject: str) -> FailureResult:
		try:
			client = self._redis()
			if self._script is None:
				self._script = client.register_script(_RECORD_FAILURE)
			failures, locked_for, newly = self._script(
				keys=[self._key("fail", subject), self._key("lock", subject), self._key("strikes", subject)],
				args=[
					settings.parent_mode_failure_window_seconds,
					settings.parent_mode_max_failures,
					settings.parent_mode_strike_window_seconds,
					settings.parent_mode_lock_seconds,
					settings.parent_mode_lock_max_seconds,
				],
			)
		except HTTPException:
			raise
		except Exception as error:
			raise self._fail_closed(error) from error
		locked_for = int(locked_for)
		remaining = 0 if locked_for else max(0, settings.parent_mode_max_failures - int(failures))
		return FailureResult(locked_for=locked_for, attempts_remaining=remaining, newly_locked=bool(int(newly)))

	def record_success(self, subject: str) -> None:
		try:
			self._redis().delete(self._key("fail", subject))
		except HTTPException:
			raise
		except Exception as error:
			raise self._fail_closed(error) from error

	def lift_lock_keep_history(self, subject: str) -> None:
		"""Operational/test helper: end the current lock but keep strike history."""
		self._redis().delete(self._key("lock", subject), self._key("fail", subject))


parent_mode_lockout = AttemptLockout()
