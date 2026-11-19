"""Which published missions a child is offered today: rotation and repeat prevention (milestone C2).

It replaces "an approved mission is excluded for ever", which exhausted the catalogue, with a cooldown built from
the child's real assignment history (``daily_mission_assignments``; no schema change). A *mission* is a template:
the same template in English, Gujarati or Hindi, or for another age band, is the same mission, so changing the
language never bypasses repeat prevention.

Policy (all dates are family-local dates):

* **Cooldown 42 days** after a mission the child engaged with: chose it (selected / in progress / pending review /
  approved) or skipped it. Skips count on purpose: a skipped mission was shown and declined.
* **Rejected** missions cool down for only 7 days: the parent said "try again", so the child may retry it soon.
* **Offered but never chosen** missions are *not* on cooldown (the child sees 3 a day and picks 1; a 42-day cooldown
  on everything shown would need 126 missions). They are discouraged instead: anything shown on either of the two
  most recent offer days ranks lower, and less-often-shown missions rank higher.
* **Never assigned**, in any tier: a template already issued today (including skipped), and a mission that is
  still active (selected / in progress / waiting for parent review) within the cooldown window.
* **Ranking** (lower is better): fresh before cooldown; among fresh: a surprise mission that was not shown
  recently, the weekday theme, not shown recently, least often shown, then a stable hash of child + date so a retry
  returns the same answer. Among cooldown fallbacks: shown longest ago, then least often shown.
* **Variety**: the three choices come from different themes when there are enough themes to do so.
* **Fallback** never turns into an error while any eligible published mission exists; each assignment records
  ``rotation.tier`` (``fresh`` or ``cooldown_fallback``) in its snapshot so administrators can see it.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from datetime import date, timedelta
from hashlib import sha256
from typing import Iterable
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.base import get_model

COOLDOWN_DAYS = 42
REJECTED_COOLDOWN_DAYS = 7
RECENT_OFFER_DAYS = 2  # "the previous two": the two most recent earlier days on which the child was offered missions
MIN_ELIGIBLE_PER_THEME = 6
POLICY = "rotation-v1"

ENGAGED = frozenset({"selected", "in_progress", "pending_parent_approval", "approved", "skipped"})
ACTIVE = frozenset({"selected", "in_progress", "pending_parent_approval"})


@dataclass(frozen=True)
class Candidate:
	id: UUID
	theme: str
	is_surprise: bool = False


@dataclass
class ChildHistory:
	"""What a child's recent assignments say about each template (built by :func:`load_child_history`)."""

	last_engaged: dict[UUID, date] = field(default_factory=dict)
	last_rejected: dict[UUID, date] = field(default_factory=dict)
	offered_count: dict[UUID, int] = field(default_factory=dict)
	active: set[UUID] = field(default_factory=set)
	issued_today: set[UUID] = field(default_factory=set)
	recent_offered: set[UUID] = field(default_factory=set)


@dataclass(frozen=True)
class Pick:
	candidate: Candidate
	tier: int  # 0 = fresh, 1 = cooldown fallback
	last_shown: date | None


def cooldown_end(history: ChildHistory, template_id: UUID) -> date | None:
	ends = []
	if template_id in history.last_engaged:
		ends.append(history.last_engaged[template_id] + timedelta(days=COOLDOWN_DAYS))
	if template_id in history.last_rejected:
		ends.append(history.last_rejected[template_id] + timedelta(days=REJECTED_COOLDOWN_DAYS))
	return max(ends) if ends else None


def _last_shown(history: ChildHistory, template_id: UUID) -> date | None:
	dates = [d for d in (history.last_engaged.get(template_id), history.last_rejected.get(template_id)) if d]
	return max(dates) if dates else None


def _tiebreak(seed: str, template_id: UUID) -> str:
	return sha256(f"{seed}:{template_id}".encode()).hexdigest()


def rank_candidates(
	candidates: Iterable[Candidate],
	history: ChildHistory,
	today: date,
	weekday_theme: str,
	seed: str,
	*,
	used_themes: Iterable[str] = (),
	limit: int = 3,
) -> list[Pick]:
	"""The best ``limit`` candidates in offer order. Pure: no database, no clock."""
	blocked = history.issued_today | history.active
	fresh: list[tuple[tuple, Candidate]] = []
	cooling: list[tuple[tuple, Candidate]] = []
	for candidate in candidates:
		if candidate.id in blocked:
			continue
		recent = candidate.id in history.recent_offered
		shown = history.offered_count.get(candidate.id, 0)
		end = cooldown_end(history, candidate.id)
		tie = _tiebreak(seed, candidate.id)
		if end is not None and today < end:
			cooling.append(((_last_shown(history, candidate.id) or date.min, shown, recent, tie), candidate))
		else:
			surprise_first = 0 if candidate.is_surprise and not recent else 1
			theme_first = 0 if candidate.theme == weekday_theme else 1
			fresh.append(((surprise_first, theme_first, recent, shown, tie), candidate))

	picks: list[Pick] = []
	themes = set(used_themes)
	for tier, group in ((0, fresh), (1, cooling)):
		group.sort(key=lambda pair: pair[0])
		ordered = [candidate for _, candidate in group]
		# Variety first: one per not-yet-used theme, then whatever is left in rank order.
		chosen = [c for c in ordered if c.theme not in themes]
		first_of_theme: list[Candidate] = []
		seen: set[str] = set()
		for c in chosen:
			if c.theme not in seen:
				seen.add(c.theme)
				first_of_theme.append(c)
		rest = [c for c in ordered if c not in first_of_theme]
		for candidate in [*first_of_theme, *rest]:
			if len(picks) >= limit:
				break
			picks.append(Pick(candidate, tier, _last_shown(history, candidate.id) if tier else None))
			themes.add(candidate.theme)
		if len(picks) >= limit:
			break
	return picks


def load_child_history(session: Session, child_id: UUID, today: date) -> ChildHistory:
	"""One windowed query (uses ``ix_daily_assignment_history``) plus one grouped count per child."""
	Assignment = get_model("DailyMissionAssignment")
	window_start = today - timedelta(days=COOLDOWN_DAYS)
	history = ChildHistory()
	offered_dates: dict[date, set[UUID]] = defaultdict(set)
	rows = (
		session.query(Assignment.template_id, Assignment.local_date, Assignment.status, Assignment.is_current)
		.filter(Assignment.child_id == child_id, Assignment.local_date >= window_start)
		.all()
	)
	for template_id, local_date, status, is_current in rows:
		if local_date == today:
			history.issued_today.add(template_id)
		else:
			offered_dates[local_date].add(template_id)
		if status in ENGAGED:
			previous = history.last_engaged.get(template_id)
			if previous is None or local_date > previous:
				history.last_engaged[template_id] = local_date
		elif status == "rejected":
			previous = history.last_rejected.get(template_id)
			if previous is None or local_date > previous:
				history.last_rejected[template_id] = local_date
		if status in ACTIVE and is_current:
			history.active.add(template_id)
	for local_date in sorted(offered_dates, reverse=True)[:RECENT_OFFER_DAYS]:
		history.recent_offered |= offered_dates[local_date]
	history.offered_count = {
		template_id: int(count)
		for template_id, count in session.query(Assignment.template_id, func.count(Assignment.id))
		.filter(Assignment.child_id == child_id)
		.group_by(Assignment.template_id)
		.all()
	}
	return history
