import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.core.rate_limit import FixedWindowLimiter, RedisRateLimiter, enforce


def test_fixed_window_limiter_blocks_after_limit_and_reports_retry() -> None:
	limiter = FixedWindowLimiter()
	assert limiter.check("ip:user", limit=2, window_seconds=60) is None
	assert limiter.check("ip:user", limit=2, window_seconds=60) is None
	retry_after = limiter.check("ip:user", limit=2, window_seconds=60)
	assert retry_after is not None and retry_after >= 1


def test_rate_limit_keys_are_independent() -> None:
	limiter = FixedWindowLimiter()
	assert limiter.check("first", limit=1, window_seconds=60) is None
	assert limiter.check("second", limit=1, window_seconds=60) is None


def test_enforce_raises_http_429() -> None:
	limiter = FixedWindowLimiter()
	enforce(limiter, "ip", limit=1, window_seconds=60)
	with pytest.raises(Exception) as error:
		enforce(limiter, "ip", limit=1, window_seconds=60)
	assert error.value.status_code == 429


def test_redis_limiter_fails_closed_when_not_configured(monkeypatch) -> None:
	monkeypatch.setattr(settings, "redis_url", None)
	with pytest.raises(HTTPException) as error:
		RedisRateLimiter("test").check("ip", limit=1, window_seconds=60)
	assert error.value.status_code == 503