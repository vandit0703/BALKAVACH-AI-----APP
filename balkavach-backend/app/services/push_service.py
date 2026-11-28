"""Push delivery for stored notifications.

Flow: ``create_notification`` stages a push in ``session.info``; a successful
commit promotes it to "ready" and a rolled-back transaction discards it; the
request wrapper (``get_db``) delivers the ready pushes after the endpoint
returns. Delivery never raises into the request, never carries names or task
titles (only a generic localised sentence plus the notification id), and honours
``user_settings.push_enabled`` plus the family's per-category preferences and
quiet hours (``notification_preferences_service``).

Three different things, never to be confused:

* **created** - the ``notifications`` row exists (in-app centre). Always happens.
* **accepted** - the provider (FCM) answered ``ok`` for a device token.
* **delivered** - the phone showed it. The server cannot observe this.

A ``retry`` answer is retried a few times inside the same worker with a short
backoff. There is no durable queue (``notification_deliveries`` is deferred), so
a push still failing after the last attempt, or lost in a process restart, is
dropped and only counted in the log.
"""

import logging
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import event
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.integrations import get_push_notification_provider
from app.services import notification_preferences_service as preferences
from app.services.timezone_service import family_timezone_name, parse_timezone

logger = logging.getLogger(__name__)

_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="push")

GENERIC_TEXT: dict[str, dict[str, tuple[str, str]]] = {
	"panda_chat_access_requested": {
		"en": ("Panda chat request", "Your child asked to chat with Panda."),
		"hi": ("पांडा चैट का अनुरोध", "आपके बच्चे ने पांडा से चैट करने की अनुमति माँगी है।"),
		"gu": ("પાંડા ચેટની વિનંતી", "તમારા બાળકે પાંડા સાથે ચેટ કરવાની પરવાનગી માગી છે."),
	},
	"parent_mode_locked": {
		"en": ("Parent sign-in locked", "Several incorrect parent sign-in attempts were made on a child's device."),
		"hi": ("पैरेंट साइन-इन लॉक", "बच्चे के डिवाइस पर पैरेंट साइन-इन के कई गलत प्रयास हुए।"),
		"gu": ("પેરેન્ટ સાઇન-ઇન લૉક", "બાળકના ડિવાઇસ પર પેરેન્ટ સાઇન-ઇનના ઘણા ખોટા પ્રયાસો થયા."),
	},
	"task_assigned": {
		"en": ("New mission", "You have a new mission."),
		"hi": ("नया मिशन", "आपके लिए एक नया मिशन है।"),
		"gu": ("નવું મિશન", "તમારા માટે એક નવું મિશન છે."),
	},
	"daily_missions_ready": {
		"en": ("New Missions Are Ready!", "Your learning adventure is waiting!"),
		"hi": ("नए मिशन तैयार हैं!", "आपकी सीखने की यात्रा आपका इंतज़ार कर रही है!"),
		"gu": ("નવા મિશન તૈયાર છે!", "તમારી શીખવાની સફર તમારી રાહ જોઈ રહી છે!"),
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
	"interest_requested": {
		"en": ("New topic request", "Your child asked to watch new topics."),
		"hi": ("नए विषय का अनुरोध", "आपके बच्चे ने नए विषय देखने का अनुरोध किया है।"),
		"gu": ("નવા વિષયની વિનંતી", "તમારા બાળકે નવા વિષયો જોવાની વિનંતી કરી છે."),
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
	"mission_video_time_granted": {
		"en": ("Video time unlocked", "You earned 15 minutes of video time."),
		"hi": ("वीडियो समय खुला", "आपने 15 मिनट का वीडियो समय कमाया।"),
		"gu": ("વીડિયો સમય ખુલ્યો", "તમે 15 મિનિટનો વીડિયો સમય મેળવ્યો."),
	},
	# Push text cannot carry the exact minutes, so it says "a little"; the in-app
	# notification (video_time_alerts.py) has the server's real figure.
	"video_time_nearly_exhausted": {
		"en": ("A little video time left", "Just a little video time left today. Time to finish up your video!"),
		"hi": ("थोड़ा सा वीडियो टाइम बचा है", "आज बस थोड़ा सा वीडियो टाइम बचा है। अब अपना वीडियो पूरा कर लो!"),
		"gu": ("થોડો વિડિયો સમય બાકી છે", "આજે થોડો જ વિડિયો સમય બાકી છે. હવે તમારો વિડિયો પૂરો કરો!"),
	},
	"video_time_exhausted": {
		"en": (
			"Video time is done for today",
			"Finish a mission and ask your grown-up to approve it to earn more video time.",
		),
		"hi": (
			"आज का वीडियो टाइम पूरा हुआ",
			"एक मिशन पूरा करो और अपने बड़ों से मंज़ूरी लो, तब और वीडियो टाइम मिलेगा।",
		),
		"gu": (
			"આજનો વિડિયો સમય પૂરો થયો",
			"એક મિશન પૂરું કરો અને તમારા વડીલ મંજૂર કરે ત્યારે વધુ વિડિયો સમય મળશે.",
		),
	},
}

# Body for an approval that earned something. The numbers are read from the star and XP
# ledgers (what the server actually recorded), never computed or guessed here.
REWARD_TEXT: dict[str, dict[str, str]] = {
	"stars_xp": {
		"en": "Your mission was approved! You earned {stars} Stars and {xp} XP.",
		"hi": "आपका मिशन स्वीकृत हो गया! आपने {stars} स्टार और {xp} XP कमाए।",
		"gu": "તમારું મિશન મંજૂર થયું! તમે {stars} સ્ટાર અને {xp} XP મેળવ્યા.",
	},
	"stars": {
		"en": "Your mission was approved! You earned {stars} Stars.",
		"hi": "आपका मिशन स्वीकृत हो गया! आपने {stars} स्टार कमाए।",
		"gu": "તમારું મિશન મંજૂર થયું! તમે {stars} સ્ટાર મેળવ્યા.",
	},
	"xp": {
		"en": "Your mission was approved! You earned {xp} XP.",
		"hi": "आपका मिशन स्वीकृत हो गया! आपने {xp} XP कमाए।",
		"gu": "તમારું મિશન મંજૂર થયું! તમે {xp} XP મેળવ્યા.",
	},
}

# Replaced by tests so delivery is synchronous and uses the test transaction.
_runner = _executor.submit

MAX_ATTEMPTS = 3
RETRY_DELAYS_SECONDS = (0.5, 2.0)
# Replaced by tests (no real sleeping, fixed clock).
_sleep = time.sleep


def _now() -> datetime:
	return datetime.now(timezone.utc)


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


def _preference_decision(session: Session, user_id: UUID, role: str | None, notification_type: str) -> str:
	"""``send`` / ``muted`` / ``quiet_hours`` under the recipient's family settings.

	A parent in more than one family gets the push if any of them allows it. If the
	settings cannot be read the push is sent (fail open) and a warning is logged:
	the in-app notification exists either way.
	"""
	try:
		family_ids = preferences.family_ids_for_user(session, user_id, role)
		if not family_ids:
			return "send"
		now = _now()
		decisions = []
		for family_id in family_ids:
			effective, _ = preferences.load_family_preferences(session, family_id)
			zone = parse_timezone(family_timezone_name(session, family_id))
			decisions.append(preferences.push_decision(effective, zone, notification_type, now))
	except Exception:
		logger.warning("Push preferences unreadable for a %s notification; sending", notification_type)
		return "send"
	return "send" if "send" in decisions else decisions[0]


def _send_with_retry(provider, token: str, title: str, body: str, data: dict[str, str]) -> str:
	"""Final provider answer for one token; a persistent ``retry`` becomes ``retry_exhausted``."""
	for attempt in range(MAX_ATTEMPTS):
		try:
			result = provider.send(token, title, body, data)
		except Exception:
			logger.exception("Push provider raised")
			return "error"
		if result != "retry":
			return result if result in {"ok", "invalid_token", "error"} else "error"
		if attempt < MAX_ATTEMPTS - 1:
			_sleep(RETRY_DELAYS_SECONDS[min(attempt, len(RETRY_DELAYS_SECONDS) - 1)])
	return "retry_exhausted"


def _approval_body(session: Session, notification_id: UUID, language: str) -> str | None:
	"""The reward sentence for an approved mission, or ``None`` when nothing was earned or it cannot be read."""
	try:
		from app.services.ledger_service import awarded_by_submission

		Notification = get_model("Notification")
		row = session.query(Notification.related_submission_id).filter(Notification.id == notification_id).first()
		if row is None or row[0] is None:
			return None
		stars, xp = awarded_by_submission(session, [row[0]]).get(row[0], (0, 0))
	except Exception:
		logger.warning("Reward amounts unreadable for push; sending the generic text")
		return None
	key = "stars_xp" if stars > 0 and xp > 0 else "stars" if stars > 0 else "xp" if xp > 0 else None
	if key is None:
		return None
	return (REWARD_TEXT[key].get(language) or REWARD_TEXT[key]["en"]).format(stars=stars, xp=xp)


def _deliver_with_session(session: Session, provider, items) -> Counter:
	"""Send each staged push once. Returns the outcome counts (also logged; no names or tokens)."""
	DeviceToken = get_model("DeviceToken")
	UserSetting = get_model("UserSetting")
	User = get_model("User")
	stats: Counter = Counter()
	seen: set[tuple[UUID, UUID]] = set()
	for user_id, notification_type, notification_id in items:
		if (user_id, notification_id) in seen:
			stats["duplicate_skipped"] += 1
			continue
		seen.add((user_id, notification_id))
		setting = session.query(UserSetting.push_enabled).filter(UserSetting.user_id == user_id).first()
		if setting is not None and setting[0] is False:
			stats["push_off"] += 1
			continue
		texts = GENERIC_TEXT.get(notification_type)
		if texts is None:
			stats["no_template"] += 1
			continue
		user_row = session.query(User.preferred_language, User.role).filter(User.id == user_id).first()
		language = (user_row[0] if user_row else None) or "en"
		role = user_row[1] if user_row else None
		decision = _preference_decision(session, user_id, role, notification_type)
		if decision != "send":
			stats[f"suppressed_{decision}"] += 1
			logger.info("Push suppressed (%s): type=%s notification=%s", decision, notification_type, notification_id)
			continue
		title, body = texts.get(language) or texts["en"]
		if notification_type == "task_approved":
			body = _approval_body(session, notification_id, language) or body
		devices = session.query(DeviceToken).filter(DeviceToken.user_id == user_id, DeviceToken.is_active.is_(True)).all()
		if not devices:
			stats["no_active_device"] += 1
		tokens_sent: set[str] = set()
		for device in devices:
			if device.token in tokens_sent:
				continue
			tokens_sent.add(device.token)
			result = _send_with_retry(
				provider, device.token, title, body, {"type": notification_type, "notification_id": str(notification_id)}
			)
			stats[f"provider_{result}"] += 1
			if result == "invalid_token":
				device.is_active = False
			elif result in {"error", "retry_exhausted"}:
				logger.warning("Push not accepted (%s): type=%s notification=%s", result, notification_type, notification_id)
		session.commit()
	logger.info("Push run finished: %s", dict(sorted(stats.items())))
	return stats
