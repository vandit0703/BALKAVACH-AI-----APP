"""Which code path charges video time. Exactly one, always.

* ``record_progress`` (the shipped path) charges unless play tickets are active.
* Play-ticket heartbeats charge only when tickets are active.

Tickets are active only when **both** the setting ``VIDEO_PLAY_TICKETS_ENABLED``
is true **and** the ``video_play_tickets`` table exists in the reflected
database. The table is deferred (``docs/deferred-database-integration.md``), so
today tickets can never be active, whatever the setting says, and nothing about
charging changes. Turning the setting on also requires the PostgreSQL
concurrency suite to pass first (``docs/video-play-tickets.md`` §6-7).
"""

from __future__ import annotations

from app.core.config import settings
from app.db.base import has_model

TICKET_MODEL = "VideoPlayTicket"


def play_tickets_enabled_setting() -> bool:
	return bool(settings.video_play_tickets_enabled)


def play_ticket_storage_available() -> bool:
	try:
		return has_model(TICKET_MODEL)
	except Exception:  # noqa: BLE001 - no database configured: no storage
		return False


def play_tickets_active() -> bool:
	"""True only when ticket heartbeats are the charging path."""
	return play_tickets_enabled_setting() and play_ticket_storage_available()
