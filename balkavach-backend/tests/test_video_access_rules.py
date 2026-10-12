from datetime import datetime, timedelta, timezone

import pytest

from app.core.exceptions import APIError
from app.services.video_access_service import accepted_heartbeat_seconds


def test_heartbeat_time_is_server_capped_and_limited_by_entitlement() -> None:
    previous = datetime(2026, 10, 12, tzinfo=timezone.utc)

    assert accepted_heartbeat_seconds(previous, previous + timedelta(seconds=8), 100) == 8
    assert accepted_heartbeat_seconds(previous, previous + timedelta(seconds=90), 100) == 30
    assert accepted_heartbeat_seconds(previous, previous + timedelta(seconds=8), 3) == 3
    assert accepted_heartbeat_seconds(previous, previous + timedelta(seconds=8), 0) == 0


def test_heartbeat_rejects_time_reversal() -> None:
    now = datetime(2026, 10, 12, tzinfo=timezone.utc)

    with pytest.raises(APIError) as error:
        accepted_heartbeat_seconds(now, now - timedelta(seconds=1), 30)

    assert error.value.status_code == 409