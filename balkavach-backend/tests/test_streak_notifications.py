"""Tests for streak notification creation and deduplication."""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from unittest.mock import MagicMock, patch

import pytest


def _setup_mock_notification():
    mock_notification_cls = MagicMock()
    mock_notification_cls.recipient_user_id = MagicMock()
    mock_notification_cls.notification_type = MagicMock()
    mock_notification_cls.id = MagicMock()
    mock_notification_cls.created_at = MagicMock()
    mock_notification_cls.created_at.__gt__ = MagicMock(return_value=True)
    return mock_notification_cls


def test_streak_notification_deduplication():
    """
    Verify notify_streak_event does NOT create a second notification
    when one of the same type was sent in the last 20 hours.
    """
    from app.services import notification_service

    notify_streak_event = getattr(notification_service, "notify_streak_event", None)
    if notify_streak_event is None:
        pytest.skip("notify_streak_event not yet defined in notification_service")

    session = MagicMock()
    child_user_id = uuid.uuid4()
    event_type = "streak_at_risk"
    current_streak = 5
    now_utc = datetime(2026, 11, 10, 12, 0, tzinfo=timezone.utc)

    # Simulate existing recent notification found (within last 20 hours)
    recent_notification = MagicMock()
    recent_notification.created_at = now_utc - timedelta(hours=5)

    q = session.query.return_value
    q.filter.return_value = q
    q.first.return_value = (recent_notification,)

    mock_notification_cls = _setup_mock_notification()

    with patch("app.services.notification_service.create_notification") as mock_create, \
         patch("app.services.notification_service.get_model", return_value=mock_notification_cls):

        result = notify_streak_event(
            session, child_user_id, event_type, current_streak
        )

        mock_create.assert_not_called()
        assert result is None


def test_streak_notification_created_when_outside_dedup_window():
    """
    Verify notify_streak_event creates a notification when the previous one
    was sent more than 20 hours ago or does not exist.
    """
    from app.services import notification_service

    notify_streak_event = getattr(notification_service, "notify_streak_event", None)
    if notify_streak_event is None:
        pytest.skip("notify_streak_event not yet defined in notification_service")

    session = MagicMock()
    child_user_id = uuid.uuid4()
    event_type = "streak_continued"
    current_streak = 4

    # No recent notification found
    q = session.query.return_value
    q.filter.return_value = q
    q.first.return_value = None

    mock_notification_cls = _setup_mock_notification()

    with patch("app.services.notification_service.create_notification") as mock_create, \
         patch("app.services.notification_service.get_model", return_value=mock_notification_cls):
        mock_created_notification = MagicMock()
        mock_create.return_value = mock_created_notification

        result = notify_streak_event(
            session, child_user_id, event_type, current_streak
        )

        mock_create.assert_called_once()
        args, kwargs = mock_create.call_args
        assert args[0] is session
        assert args[1] == child_user_id
        assert args[2] == event_type
        assert result == mock_created_notification
