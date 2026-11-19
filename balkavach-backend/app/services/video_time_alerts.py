"""Low-time and time-up notifications for the child's video allowance.

Called only from ``record_progress`` (the single deduction path) after it has
charged time, with the server's own before/after figures. Rules (roadmap
Phase 3, item 5; documented in ``docs/video-allowance-policy.md``):

* ``video_time_nearly_exhausted`` when the remaining time falls from above
  :data:`LOW_TIME_THRESHOLD_SECONDS` (2 minutes) to at most that, but above 0.
* ``video_time_exhausted`` when the remaining time reaches 0.
* Each fires at most once per family-local day, re-armed only by a new
  parent-approved grant later that day, so the same threshold never repeats.
* The text is in the child's language and never says that a mission alone
  unlocks time: a grown-up must approve it.

Nothing here grants, restores or changes allowance.
"""

from __future__ import annotations

from datetime import datetime
import logging
import math
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.notification_service import create_notification
from app.services.timezone_service import family_timezone_name, local_day_bounds_utc_naive, local_today, parse_timezone
from app.utils import utc_naive

logger = logging.getLogger(__name__)

LOW_TIME_THRESHOLD_SECONDS = 120
NEARLY_EXHAUSTED = "video_time_nearly_exhausted"
EXHAUSTED = "video_time_exhausted"

_TEXT: dict[str, dict[str, tuple[str, str]]] = {
	NEARLY_EXHAUSTED: {
		"en": ("A little video time left", "About {minutes} min of video time left today. Time to finish up your video!"),
		"hi": ("थोड़ा सा वीडियो टाइम बचा है", "आज लगभग {minutes} मिनट का वीडियो टाइम बचा है। अब अपना वीडियो पूरा कर लो!"),
		"gu": ("થોડો વિડિયો સમય બાકી છે", "આજે લગભગ {minutes} મિનિટનો વિડિયો સમય બાકી છે. હવે તમારો વિડિયો પૂરો કરો!"),
	},
	EXHAUSTED: {
		"en": (
			"Video time is done for today",
			"Time for a break! Finish a mission and ask your grown-up to approve it to earn more video time.",
		),
		"hi": (
			"आज का वीडियो टाइम पूरा हुआ",
			"थोड़ा आराम करो! एक मिशन पूरा करो और अपने बड़ों से मंज़ूरी लो, तब और वीडियो टाइम मिलेगा।",
		),
		"gu": (
			"આજનો વિડિયો સમય પૂરો થયો",
			"થોડો આરામ કરો! એક મિશન પૂરું કરો અને તમારા વડીલ મંજૂર કરે ત્યારે વધુ વિડિયો સમય મળશે.",
		),
	},
}


def crossed_event(before_seconds: int, after_seconds: int) -> str | None:
	"""The alert a single charge from ``before`` to ``after`` crosses, if any."""
	if after_seconds >= before_seconds:
		return None
	if after_seconds <= 0 < before_seconds:
		return EXHAUSTED
	if 0 < after_seconds <= LOW_TIME_THRESHOLD_SECONDS < before_seconds:
		return NEARLY_EXHAUSTED
	return None


def alert_text(event: str, language: str | None, remaining_seconds: int) -> tuple[str, str]:
	by_language = _TEXT[event]
	title, message = by_language.get(language or "en", by_language["en"])
	minutes = max(1, math.ceil(max(0, remaining_seconds) / 60))
	return title, message.format(minutes=minutes)


def _window_start(session: Session, child_id: UUID, family_id: UUID, now: datetime) -> datetime:
	"""Start of the family-local day, or the latest grant today if later."""
	zone = parse_timezone(family_timezone_name(session, family_id))
	start, end = local_day_bounds_utc_naive(zone, local_today(session, family_id, now), 1)
	Entitlement = get_model("VideoAccessEntitlement")
	latest_grant = (
		session.query(func.max(Entitlement.granted_at))
		.filter(
			Entitlement.child_id == child_id,
			Entitlement.source_type == "mission_reward",
			Entitlement.granted_at >= start,
			Entitlement.granted_at < end,
		)
		.scalar()
	)
	return max(start, latest_grant) if latest_grant else start


def emit_video_time_alert(
	session: Session,
	child,
	*,
	before_seconds: int,
	after_seconds: int,
	now: datetime,
):
	"""Stage at most one alert for this charge, in the caller's transaction.

	``now`` must be timezone-aware. Returns the notification, or ``None`` when
	no threshold was crossed or the alert was already sent for this window."""
	event = crossed_event(before_seconds, after_seconds)
	if event is None:
		return None
	now_naive = utc_naive(now)
	Notification = get_model("Notification")
	if (
		session.query(Notification.id)
		.filter(
			Notification.recipient_user_id == child.user_id,
			Notification.notification_type == event,
			Notification.created_at >= _window_start(session, child.id, child.family_id, now),
		)
		.first()
		is not None
	):
		return None
	User = get_model("User")
	language = session.query(User.preferred_language).filter(User.id == child.user_id).scalar()
	title, message = alert_text(event, language, after_seconds)
	logger.info("Video time alert %s for child %s", event, child.id)
	return create_notification(session, child.user_id, event, title, message, now=now_naive)
