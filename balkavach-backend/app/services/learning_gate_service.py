"""Today's learning-gate state for one child, derived from existing tables only.

The product intent is a daily workflow: a first video session unlocks today's
missions, completing them unlocks a second session, and the server enforces a
total daily viewing allowance.

Only part of that can be honoured against the current schema. There is no
per-child-per-day gate row, so a *durable* record of "the first session was
satisfied today" cannot be stored, and no video playback provider is configured
(`settings.video_playback_provider` is empty and no implementation ships in this
repository), so no eligible viewing time can be measured in the first place.

Rather than approximate either one, this service reports what it can prove and
marks the rest unavailable:

* Mission figures come from `tasks` and `task_submissions`.
* Viewing seconds come from `video_watch_sessions` rows that the server itself
  wrote through the heartbeat API, bounded to the family's local day.
* `video_gate_available` is false while no playback provider is configured, and
  callers must then leave missions reachable instead of locking them.

Nothing here grants, unlocks or mutates anything; it is a read-only view.
"""

from datetime import date, datetime, timezone
from typing import Any
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.db.base import get_model
from app.services.timezone_service import (
	family_timezone_name,
	local_day_bounds_utc_naive,
	local_today,
	parse_timezone,
)

# Product defaults, used when a family has set no override. Phase 2 of the brief
# asks for 10-15 minutes first and 15-20 minutes second; the lower bound is the
# default in both cases.
DEFAULT_FIRST_SESSION_SECONDS = 600
DEFAULT_SECOND_SESSION_SECONDS = 900

# A family may not configure a session shorter than this or a day longer than
# this, so a parent setting cannot trivially disable or weaponise the gate.
MIN_SESSION_SECONDS = 60
MAX_SESSION_SECONDS = 3600
MAX_DAILY_ALLOWANCE_SECONDS = 4 * 3600

# Watch-session rows in these states represent time the server accepted.
COUNTED_WATCH_STATUSES = ("active", "completed", "interrupted", "expired")

PHASE_FIRST_SESSION = "first_session"
PHASE_MISSIONS = "missions"
PHASE_AWAITING_APPROVAL = "awaiting_approval"
PHASE_SECOND_SESSION = "second_session"
PHASE_COMPLETE = "complete"
PHASE_UNAVAILABLE = "video_unavailable"


def _positive_int(raw: Any) -> int | None:
	"""Accept only a real whole number; JSON settings are parent-writable."""
	if isinstance(raw, bool) or not isinstance(raw, int):
		return None
	return raw if raw > 0 else None


def _clamped(raw: Any, default: int) -> int:
	value = _positive_int(raw)
	if value is None:
		return default
	return max(MIN_SESSION_SECONDS, min(MAX_SESSION_SECONDS, value))


def session_targets(session: Session, family_id: UUID) -> tuple[int, int, int]:
	"""(first, second, daily allowance) seconds from the family's video settings.

	`family_settings.video_settings` already exists and is parent-writable, so
	the configurable durations Phase 7 asks for need no new column. Unknown keys
	are ignored and out-of-range values are clamped rather than rejected: a bad
	setting must not make a child's day unreadable.
	"""
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting.video_settings).filter(
		FamilySetting.family_id == family_id
	).first()
	configured = (row[0] or {}) if row else {}
	if not isinstance(configured, dict):
		configured = {}

	first = _clamped(configured.get("first_session_seconds"), DEFAULT_FIRST_SESSION_SECONDS)
	second = _clamped(configured.get("second_session_seconds"), DEFAULT_SECOND_SESSION_SECONDS)

	allowance = _positive_int(configured.get("daily_limit_seconds"))
	if allowance is None:
		allowance = _positive_int(configured.get("default_daily_limit_seconds"))
	if allowance is None:
		allowance = first + second
	# Never advertise an allowance that cannot cover both required sessions.
	allowance = max(first + second, min(MAX_DAILY_ALLOWANCE_SECONDS, allowance))
	return first, second, allowance


def video_enabled(session: Session, family_id: UUID) -> bool:
	"""Parents may switch video off for the family; the key already exists."""
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting.video_settings).filter(
		FamilySetting.family_id == family_id
	).first()
	configured = (row[0] or {}) if row else {}
	if not isinstance(configured, dict):
		return True
	return configured.get("enabled", True) is not False


def playback_configured() -> bool:
	"""True only when a playback provider is actually configured.

	Loading the provider is deliberately not attempted here: this is a read-only
	status call and a broken provider should not make the gate unreadable.
	"""
	return bool(settings.video_playback_provider)


def watched_seconds_on(session: Session, child_id: UUID, family_id: UUID, day: date) -> int:
	"""Server-accepted viewing seconds for one local day.

	`watched_seconds` is only ever incremented by `record_heartbeat`, which caps
	each beat and clamps it to the remaining entitlement, so this sums time the
	server accepted rather than time a client claimed. Sessions are attributed to
	the day they started.
	"""
	zone = parse_timezone(family_timezone_name(session, family_id))
	start, end = local_day_bounds_utc_naive(zone, day, 1)
	VideoWatchSession = get_model("VideoWatchSession")
	total = session.query(func.coalesce(func.sum(VideoWatchSession.watched_seconds), 0)).filter(
		VideoWatchSession.child_id == child_id,
		VideoWatchSession.started_at >= start,
		VideoWatchSession.started_at < end,
		VideoWatchSession.status.in_(COUNTED_WATCH_STATUSES),
	).scalar()
	return int(total or 0)


def _mission_counts(session: Session, child, day: date) -> tuple[int, int, int]:
	"""(assigned, approved, pending) for today's missions.

	Assignment mirrors `GET /tasks` for a child exactly: active family tasks that
	are either unassigned or assigned to this child. Submission states are read
	for the local day so a mission approved yesterday does not satisfy today.
	"""
	Task = get_model("Task")
	task_rows = session.query(Task.id).filter(
		Task.is_active.is_(True),
		Task.family_id == child.family_id,
		(Task.assigned_child_id.is_(None)) | (Task.assigned_child_id == child.id),
	).all()
	task_ids = [row[0] for row in task_rows]
	if not task_ids:
		return 0, 0, 0

	zone = parse_timezone(family_timezone_name(session, child.family_id))
	start, end = local_day_bounds_utc_naive(zone, day, 1)
	TaskSubmission = get_model("TaskSubmission")
	submissions = session.query(TaskSubmission.task_id, TaskSubmission.status).filter(
		TaskSubmission.child_id == child.id,
		TaskSubmission.task_id.in_(task_ids),
		TaskSubmission.submitted_at >= start,
		TaskSubmission.submitted_at < end,
	).all()

	approved_ids = {task_id for task_id, status in submissions if status == "approved"}
	pending_ids = {
		task_id for task_id, status in submissions if status == "pending"
	} - approved_ids
	return len(task_ids), len(approved_ids), len(pending_ids)


def _phase(
	*,
	gate_available: bool,
	first_done: bool,
	assigned: int,
	approved: int,
	pending: int,
	second_done: bool,
) -> str:
	if not gate_available:
		return PHASE_UNAVAILABLE
	if not first_done:
		return PHASE_FIRST_SESSION
	if assigned == 0 or approved < assigned:
		# A submitted-but-unreviewed mission is a distinct state: the child has
		# done their part and is waiting on a parent, which the UI should say
		# plainly rather than showing the same "go do missions" prompt.
		if pending > 0 and approved + pending >= assigned:
			return PHASE_AWAITING_APPROVAL
		return PHASE_MISSIONS
	return PHASE_COMPLETE if second_done else PHASE_SECOND_SESSION


def today_state(session: Session, child) -> dict:
	"""Read-only snapshot of the child's daily learning workflow."""
	day = local_today(session, child.family_id)
	first_target, second_target, allowance = session_targets(session, child.family_id)
	enabled = video_enabled(session, child.family_id)
	configured = playback_configured()
	gate_available = enabled and configured

	watched = watched_seconds_on(session, child.id, child.family_id, day)
	assigned, approved, pending = _mission_counts(session, child, day)

	first_done = gate_available and watched >= first_target
	second_done = gate_available and watched >= first_target + second_target

	# The gate may only *restrict* missions when it can actually be satisfied.
	# With no playback provider there is no way to watch anything, so missions
	# stay reachable exactly as they are today instead of becoming unreachable.
	missions_unlocked = first_done if gate_available else True
	second_unlocked = gate_available and approved >= assigned > 0 and first_done

	blockers: list[str] = []
	if not enabled:
		blockers.append("video_disabled_by_parent")
	if not configured:
		blockers.append("playback_provider_not_configured")
	if gate_available and not first_done:
		blockers.append("first_session_incomplete")
	if gate_available and first_done and assigned == 0:
		blockers.append("no_missions_assigned")
	if gate_available and first_done and assigned > 0 and approved < assigned:
		blockers.append("missions_awaiting_approval" if pending > 0 else "missions_incomplete")

	return {
		"local_date": day,
		"timezone": family_timezone_name(session, child.family_id),
		"phase": _phase(
			gate_available=gate_available,
			first_done=first_done,
			assigned=assigned,
			approved=approved,
			pending=pending,
			second_done=second_done,
		),
		"video_gate_available": gate_available,
		"video_enabled": enabled,
		"playback_configured": configured,
		"first_session_target_seconds": first_target,
		"second_session_target_seconds": second_target,
		"daily_allowance_seconds": allowance,
		"watched_seconds_today": watched,
		"remaining_allowance_seconds": max(0, allowance - watched),
		"first_session_complete": first_done,
		"second_session_complete": second_done,
		"missions_unlocked": missions_unlocked,
		"second_session_unlocked": second_unlocked,
		"missions_assigned": assigned,
		"missions_approved": approved,
		"missions_pending_approval": pending,
		"requires_parent_approval": True,
		"blockers": blockers,
		"generated_at": datetime.now(timezone.utc),
	}
