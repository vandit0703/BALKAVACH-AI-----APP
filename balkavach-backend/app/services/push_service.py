"""Push delivery for stored notifications.

Flow: ``create_notification`` stages a push in ``session.info``; a successful
commit promotes it to "ready" and a rolled-back transaction discards it; the
request wrapper (``get_db``) delivers the ready pushes after the endpoint
returns. Delivery never raises into the request, never carries names or task
titles (only a generic localised sentence plus the notification id), and honours
``user_settings.push_enabled``.
"""

import logging
from concurrent.futures import ThreadPoolExecutor
from uuid import UUID

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.integrations import get_push_notification_provider

logger = logging.getLogger(__name__)

_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="push")

GENERIC_TEXT: dict[str, dict[str, tuple[str, str]]] = {
	"task_assigned": {
		"en": ("New mission", "You have a new mission."),
		"hi": ("नया मिशन", "आपके लिए एक नया मिशन है।"),
		"gu": ("નવું મિશન", "તમારા માટે એક નવું મિશન છે."),
	},
	"task_submitted": {
		"en": ("Mission submitted", "A mission is waiting for your review."),
		"hi": ("मिशन समीक्षा के लिए भेजा गया", "समीक्षा के लिए एक मिशन इंतज़ार कर रहा है।"),
		"gu": ("મિશન સમીક્ષા માટે મોકલ્યું", "સમીક્ષા માટે એક મિશન રાહ જોઈ રહ્યું છે."),
	},
	"task_approved": {
		"en": ("Mission approved", "Well done! Your mission was approved."),
		"hi": ("मिशन स्वीकृत", "शाबाश! आपका मिशन स्वीकृत हो गया।"),
		"gu": ("મિશન મંજૂર", "શાબાશ! તમારું મિશન મંજૂર થયું."),
	},
	"task_rejected": {
		"en": ("Mission reviewed", "Your mission has been reviewed."),
		"hi": ("मिशन की समीक्षा हुई", "आपके मिशन की समीक्षा हो गई है।"),
		"gu": ("મિશનની સમીક્ષા થઈ", "તમારા મિશનની સમીક્ષા થઈ ગઈ છે."),
	},
	"task_resubmission_requested": {
		"en": ("Please send again", "Your mission needs another try."),
		"hi": ("फिर से भेजें", "आपका मिशन दोबारा भेजने के लिए कहा गया है।"),
		"gu": ("ફરી મોકલો", "તમારું મિશન ફરીથી મોકલવા કહ્યું છે."),
	},
	"reward_requested": {
		"en": ("Reward requested", "A reward request is waiting for you."),
		"hi": ("इनाम का अनुरोध", "एक इनाम अनुरोध स्वीकृति की प्रतीक्षा में है।"),
		"gu": ("ઇનામની વિનંતી", "એક ઇનામની વિનંતી મંજૂરીની રાહ જોઈ રહી છે."),
	},
	"reward_approved": {
		"en": ("Reward approved", "Your reward request was approved."),
		"hi": ("इनाम स्वीकृत", "आपका इनाम अनुरोध स्वीकृत हो गया।"),
		"gu": ("ઇનામ મંજૂર", "તમારી ઇનામની વિનંતી મંજૂર થઈ."),
	},
	"reward_rejected": {
		"en": ("Reward request reviewed", "Your reward request has been reviewed."),
		"hi": ("इनाम अनुरोध पर निर्णय", "आपके इनाम अनुरोध की समीक्षा हो गई है।"),
		"gu": ("ઇનામની વિનંતી પર નિર્ણય", "તમારી ઇનામની વિનંતીની સમીક્ષા થઈ ગઈ છે."),
	},
	"reward_fulfilled": {
		"en": ("Reward ready", "Your reward is ready."),
		"hi": ("इनाम तैयार", "आपका इनाम तैयार है।"),
		"gu": ("ઇનામ તૈયાર", "તમારું ઇનામ તૈયાર છે."),
	},
	"badge_unlocked": {
		"en": ("New badge", "You earned a new badge!"),
		"hi": ("नया बैज", "आपने एक नया बैज जीता!"),
		"gu": ("નવો બેજ", "તમે નવો બેજ જીત્યો!"),
	},
	"streak_at_risk": {
		"en": ("Streak at risk", "Complete a mission today to keep your streak going."),
		"hi": ("स्ट्राइक खतरे में", "अपनी स्ट्राइक जारी रखने के लिए आज एक मिशन पूरा करें।"),
		"gu": ("સ્ટ્રીક જોખમમાં", "તમારી સ્ટ્રીક ચાલુ રાખવા માટે આજે એક મિશન પૂર્ણ કરો."),
	},
	"streak_one_day_left": {
		"en": ("One day left", "Only one day left to save your streak!"),
		"hi": ("एक दिन बचा है", "अपनी स्ट्राइक बचाने के लिए सिर्फ एक दिन बचा है!"),
		"gu": ("એક દિવસ બાકી", "તમારી સ્ટ્રીક બચાવવા માટે ફક્ત એક દિવસ બાકી છે!"),
	},
	"streak_continued": {
		"en": ("Streak continued", "Great work keeping your daily streak alive!"),
		"hi": ("स्ट्राइक जारी रही", "अपनी दैनिक स्ट्राइक जारी रखने के लिए बहुत बढ़िया!"),
		"gu": ("સ્ટ્રીક ચાલુ રહી", "તમારી દૈનિક સ્ટ્રીક ચાલુ રાખવા બદલ ખૂબ સરસ!"),
	},
	"streak_milestone": {
		"en": ("Streak milestone", "Congratulations on reaching a streak milestone!"),
		"hi": ("स्ट्राइक मील का पत्थर", "स्ट्राइक मील का पत्थर हासिल करने पर बधाई!"),
		"gu": ("સ્ટ્રીક માઇલસ્ટોન", "સ્ટ્રીક માઇલસ્ટોન હાંસલ કરવા બદલ અભિનંદન!"),
	},
	"streak_new_after_break": {
		"en": ("New streak started", "Welcome back! You've started a new streak."),
		"hi": ("नई स्ट्राइक शुरू", "वापसी पर स्वागत है! आपने एक नई स्ट्राइक शुरू की है।"),
		"gu": ("નવી સ્ટ્રીક શરૂ થઈ", "પાછા આવવા બદલ સ્વાગત છે! તમે નવી સ્ટ્રીક શરૂ કરી છે."),
	},
}

# Replaced by tests so delivery is synchronous and uses the test transaction.
_runner = _executor.submit


def _default_session_factory():
	from app.db import session as db_session

	if db_session.SessionLocal is None:
		raise RuntimeError("Database is not configured")
	return db_session.SessionLocal()


_session_factory = _default_session_factory


def stage_push(session: Session, notification) -> None:
	session.info.setdefault("push_queue", []).append(notification)


@event.listens_for(Session, "after_commit")
def _promote_staged(session: Session) -> None:
	staged = session.info.pop("push_queue", [])
	if staged:
		session.info.setdefault("push_ready", []).extend(
			(item.recipient_user_id, item.notification_type, item.id) for item in staged
		)


@event.listens_for(Session, "after_rollback")
def _discard_staged(session: Session) -> None:
	session.info.pop("push_queue", None)


def deliver_ready(session: Session) -> None:
	"""Send pushes promoted by committed transactions. Safe to call after every request."""
	items = session.info.pop("push_ready", [])
	if not items:
		return
	try:
		provider = get_push_notification_provider()
	except Exception:
		logger.warning("Push provider unavailable; skipping %d push(es)", len(items))
		return
	if provider is None:
		return
	try:
		_runner(lambda: _deliver(provider, items))
	except Exception:
		logger.exception("Could not schedule push delivery")


def _deliver(provider, items: list[tuple[UUID, str, UUID]]) -> None:
	try:
		with _session_factory() as session:
			_deliver_with_session(session, provider, items)
	except Exception:
		logger.exception("Push delivery failed")


def _deliver_with_session(session: Session, provider, items) -> None:
	DeviceToken = get_model("DeviceToken")
	UserSetting = get_model("UserSetting")
	User = get_model("User")
	for user_id, notification_type, notification_id in items:
		setting = session.query(UserSetting.push_enabled).filter(UserSetting.user_id == user_id).first()
		if setting is not None and setting[0] is False:
			continue
		language = session.query(User.preferred_language).filter(User.id == user_id).scalar() or "en"
		texts = GENERIC_TEXT.get(notification_type)
		if texts is None:
			continue
		title, body = texts.get(language) or texts["en"]
		devices = session.query(DeviceToken).filter(DeviceToken.user_id == user_id, DeviceToken.is_active.is_(True)).all()
		for device in devices:
			try:
				result = provider.send(
					device.token, title, body, {"type": notification_type, "notification_id": str(notification_id)}
				)
			except Exception:
				logger.exception("Push provider raised")
				continue
			if result == "invalid_token":
				device.is_active = False
		session.commit()
