"""Playback accounting and provider-boundary rules that need no database.

`record_heartbeat` and `start_playback` need a reflected schema, so their full
behaviour is covered by the integration suite (which requires
TEST_DATABASE_URL). What is checked here is the arithmetic that decides how much
viewing time a heartbeat may add, and the refusal to play anything when no
playback provider is configured — the two places where a mistake would either
hand out free viewing time or expose unauthorised media.
"""

from datetime import datetime, timedelta, timezone

import pytest

from app.core.exceptions import APIError
from app.integrations import get_video_playback_provider
from app.services.video_access_service import (
	MAX_HEARTBEAT_ELAPSED_SECONDS,
	accepted_heartbeat_seconds,
)

NOW = datetime(2026, 10, 22, 12, 0, 0, tzinfo=timezone.utc)


def accepted(elapsed_seconds: float, remaining: int = 10_000) -> int:
	previous = NOW - timedelta(seconds=elapsed_seconds)
	return accepted_heartbeat_seconds(previous, NOW, remaining)


class TestAcceptedHeartbeatSeconds:
	def test_credits_the_elapsed_time(self):
		assert accepted(10) == 10

	def test_rounds_down_so_time_is_never_over_credited(self):
		assert accepted(9.9) == 9

	def test_caps_a_long_gap_at_the_maximum(self):
		"""A client that goes quiet for an hour cannot bank an hour of viewing."""
		assert accepted(3600) == MAX_HEARTBEAT_ELAPSED_SECONDS

	def test_never_exceeds_the_remaining_allowance(self):
		assert accepted(30, remaining=4) == 4

	def test_an_exhausted_allowance_accepts_nothing(self):
		assert accepted(30, remaining=0) == 0

	def test_a_negative_remaining_allowance_accepts_nothing(self):
		assert accepted(30, remaining=-5) == 0

	def test_a_duplicate_heartbeat_adds_no_time(self):
		"""Two beats at the same instant: the second must be worth nothing."""
		assert accepted_heartbeat_seconds(NOW, NOW, 600) == 0

	def test_a_backwards_clock_is_rejected(self):
		"""Replaying an older timestamp must not mint viewing time."""
		with pytest.raises(APIError) as error:
			accepted_heartbeat_seconds(NOW + timedelta(seconds=5), NOW, 600)
		assert error.value.status_code == 409
		assert error.value.code == "invalid_heartbeat"

	@pytest.mark.parametrize("elapsed", [0, 1, 29, 30, 31, 600])
	def test_accepted_time_is_never_more_than_elapsed_or_the_cap(self, elapsed):
		result = accepted(elapsed)
		assert 0 <= result <= min(elapsed, MAX_HEARTBEAT_ELAPSED_SECONDS)


class TestPlaybackProviderBoundary:
	def test_unconfigured_provider_refuses_to_issue_playback(self, monkeypatch):
		"""With no provider, authorised playback must fail closed, not open."""
		monkeypatch.setattr("app.integrations.settings.video_playback_provider", None)
		with pytest.raises(APIError) as error:
			get_video_playback_provider()
		assert error.value.status_code == 503
		assert error.value.code == "playback_unavailable"

	def test_an_unimportable_provider_is_refused(self, monkeypatch):
		monkeypatch.setattr(
			"app.integrations.settings.video_playback_provider",
			"app.does_not_exist:provider",
		)
		with pytest.raises(APIError) as error:
			get_video_playback_provider()
		assert error.value.status_code == 503

	def test_a_provider_missing_required_methods_is_refused(self, monkeypatch):
		"""A half-built provider must not be accepted as if it could revoke."""
		monkeypatch.setattr(
			"app.integrations.settings.video_playback_provider",
			f"{__name__}:_incomplete_provider",
		)
		with pytest.raises(APIError) as error:
			get_video_playback_provider()
		assert error.value.code == "playback_unavailable"


class _Incomplete:
	def issue_playback_url(self, video, session_id, expires_at):
		return "https://media.example.test/x"

	# revoke_playback deliberately missing.


def _incomplete_provider():
	return _Incomplete()
