"""Panda conversation endpoint (child only, read-only, nothing persisted)."""

from collections import OrderedDict
import logging
from threading import Lock
from time import monotonic

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.core.dependencies import require_child
from app.core.rate_limit import FixedWindowLimiter, enforce
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.companion import CompanionChatReply, CompanionChatRequest
from app.services.companion_chat_service import ChildContext, compose_reply, safe_first_name

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/companion", tags=["companion"])

# 20 turns a minute per child is far above a real conversation and stops loops.
CHAT_RATE_LIMIT = 20
CHAT_RATE_WINDOW_SECONDS = 60
chat_limiter = FixedWindowLimiter()


class _TurnCache:
	"""Replies to recent turn ids, so a duplicate request is answered once."""

	def __init__(self, ttl_seconds: float = 120, capacity: int = 5000) -> None:
		self._items: OrderedDict[tuple[str, str], tuple[float, CompanionChatReply]] = OrderedDict()
		self._ttl = ttl_seconds
		self._capacity = capacity
		self._lock = Lock()

	def get(self, key: tuple[str, str]) -> CompanionChatReply | None:
		with self._lock:
			hit = self._items.get(key)
			if hit is None or monotonic() - hit[0] > self._ttl:
				self._items.pop(key, None)
				return None
			return hit[1]

	def put(self, key: tuple[str, str], reply: CompanionChatReply) -> None:
		with self._lock:
			self._items[key] = (monotonic(), reply)
			self._items.move_to_end(key)
			while len(self._items) > self._capacity:
				self._items.popitem(last=False)


turn_cache = _TurnCache()


def load_child_context(session: Session, child) -> tuple[ChildContext, str]:
	"""Read-only snapshot of what Panda may mention. Each part is optional: a
	failure leaves that part unknown rather than failing the conversation."""
	first_name = safe_first_name(getattr(child, "display_name", None))
	language = "en"
	try:
		User = get_model("User")
		language = session.query(User.preferred_language).filter(User.id == child.user_id).scalar() or "en"
	except Exception:  # noqa: BLE001 - optional context
		logger.warning("Companion: preferred language unavailable")

	video: dict = {}
	try:
		from app.services.video_entitlement_service import get_child_video_allowance_today

		video = get_child_video_allowance_today(session, child.id, child.family_id)
	except Exception:  # noqa: BLE001
		logger.warning("Companion: video allowance unavailable")
		session.rollback()

	mission_title = mission_status = None
	try:
		Assignment = get_model("DailyMissionAssignment")
		row = (
			session.query(Assignment)
			.filter(
				Assignment.child_id == child.id,
				Assignment.is_current.is_(True),
				Assignment.status.in_(["selected", "in_progress", "pending_parent_approval", "approved", "rejected"]),
			)
			.order_by(Assignment.local_date.desc())
			.first()
		)
		if row is not None:
			mission_title = (row.snapshot or {}).get("title")
			mission_status = row.status
	except Exception:  # noqa: BLE001
		logger.warning("Companion: active mission unavailable")
		session.rollback()

	streak_days = None
	try:
		from app.services.streak_service import compute_streak_state

		streak_days = int(compute_streak_state(session, child.id, child.family_id).get("current_streak") or 0)
	except Exception:  # noqa: BLE001
		logger.warning("Companion: streak unavailable")
		session.rollback()

	ctx = ChildContext(
		first_name=first_name,
		video_remaining_seconds=video.get("remaining_seconds"),
		video_exhausted=video.get("is_exhausted"),
		video_earned_today_seconds=video.get("total_earned_today_seconds"),
		mission_title=mission_title if isinstance(mission_title, str) else None,
		mission_status=mission_status,
		streak_days=streak_days,
	)
	return ctx, language


@router.post("/chat", response_model=CompanionChatReply)
def companion_chat(
	request: CompanionChatRequest,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> CompanionChatReply:
	key = (str(child.id), str(request.turn_id))
	cached = turn_cache.get(key)
	if cached is not None:
		return cached

	enforce(chat_limiter, f"companion:{child.id}", limit=CHAT_RATE_LIMIT, window_seconds=CHAT_RATE_WINDOW_SECONDS)

	ctx, preferred = load_child_context(session, child)
	locale = request.locale or (preferred if preferred in {"en", "hi", "gu"} else "en")
	reply = compose_reply(request.text, locale, ctx, context_intent=request.context_intent)
	# Intent and safety category only: the child's words are never logged.
	logger.info("Companion turn intent=%s safety=%s", reply.intent, reply.safety)

	public = CompanionChatReply(
		reply=reply.text,
		locale=locale,
		mood=reply.mood,
		intent=reply.intent,
		follow_up=reply.follow_up,
		safety=reply.safety,
		suggestions=reply.suggestions,
	)
	turn_cache.put(key, public)
	return public
