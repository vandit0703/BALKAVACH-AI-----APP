from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any
from uuid import UUID

import logging

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.services.child_age import (
    age_band_for_birth_date,  # noqa: F401  (re-exported: the name older callers and tests import)
    child_age_band,
    child_age_band_or_none,
    ensure_assignment_eligible,
)
from app.services.mission_instructions import instruction_status, structured_content
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from app.services.mission_rotation_service import POLICY, Candidate, load_child_history, rank_candidates
from app.services.mission_titles import child_facing_title
from app.services.timezone_service import family_timezone_name, local_today
from app.utils import utc_naive

logger = logging.getLogger(__name__)

THEMES_BY_WEEKDAY = {
    0: "monday_sound_detective",
    1: "tuesday_memory_master",
    2: "wednesday_magic_story_maker",
    3: "thursday_paper_architect",
    4: "friday_emotion_detective",
    5: "saturday_rhythm_rockstar",
    6: "sunday_future_inventor",
}
MAX_SKIPS_PER_DAY = 2  # roadmap Phase 2: a bounded re-roll, never an endless one
REQUIRED_AGE_BANDS = ("4_6", "7_10", "11_15")
REQUIRED_LOCALES = ("en", "gu", "hi")


def has_complete_localized_variations(rows) -> bool:
    required = {(age_band, locale) for age_band in REQUIRED_AGE_BANDS for locale in REQUIRED_LOCALES}
    return required.issubset(set(rows))


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _snapshot(template, variation) -> dict[str, Any]:
    return {
        "title": variation.title,
        "description": variation.description,
        "instructions": variation.instructions,
        "required_materials": variation.required_materials or [],
        "duration_minutes": variation.duration_minutes,
        "safety_instructions": variation.safety_instructions,
        "completion_criteria": variation.completion_criteria,
        "mission_type": template.mission_type,
        "theme": template.theme,
        # The standard reward (mission_rewards), not the template's own values.
        "star_reward": MISSION_STAR_REWARD,
        "xp_reward": MISSION_XP_REWARD,
        "is_surprise": bool(template.is_surprise),
        "mystery_bonus": template.mystery_bonus,
        "locale": variation.locale,
        # Structured instructions. getattr: the columns exist only after migration 0019 is applied.
        "learning_objective": getattr(variation, "learning_objective", None),
        "steps": getattr(variation, "steps", None),
        "observation_guidance": getattr(variation, "observation_guidance", None),
        "submission_requirements": getattr(variation, "submission_requirements", None),
    }


def _display_content_from_variation(row, variation) -> dict[str, Any]:
    """Localized display content from a variation, without mutating the stored snapshot."""
    snapshot = dict(row.snapshot or {})
    return {
        "title": variation.title,
        "description": variation.description,
        "instructions": variation.instructions,
        "required_materials": variation.required_materials or [],
        "duration_minutes": variation.duration_minutes,
        "safety_instructions": variation.safety_instructions,
        "completion_criteria": variation.completion_criteria,
        "mission_type": snapshot.get("mission_type"),
        "theme": snapshot.get("theme"),
        "star_reward": snapshot.get("star_reward", MISSION_STAR_REWARD),
        "xp_reward": snapshot.get("xp_reward", MISSION_XP_REWARD),
        "is_surprise": snapshot.get("is_surprise", False),
        "mystery_bonus": snapshot.get("mystery_bonus"),
        "locale": variation.locale,
        "learning_objective": getattr(variation, "learning_objective", None),
        "steps": getattr(variation, "steps", None),
        "observation_guidance": getattr(variation, "observation_guidance", None),
        "submission_requirements": getattr(variation, "submission_requirements", None),
    }


def _localized_display_content(session: Session | None, row, display_locale: str | None) -> dict[str, Any] | None:
    if session is None or not display_locale:
        return None
    template_id = getattr(row, "template_id", None)
    age_band = getattr(row, "age_band", None)
    if template_id is None or age_band is None:
        return None
    Variation = get_model("DailyMissionVariation")
    requested = (
        session.query(Variation)
        .filter(
            Variation.template_id == template_id,
            Variation.age_band == age_band,
            Variation.locale == display_locale,
        )
        .first()
    )
    if requested is not None:
        return _display_content_from_variation(row, requested)
    snapshot = row.snapshot or {}
    snapshot_locale = snapshot.get("locale") if isinstance(snapshot, dict) else None
    # If a translation for the requested locale does not exist, fall back truthfully
    # (prefer English content if available, else keep the original snapshot).
    if display_locale != "en":
        english = (
            session.query(Variation)
            .filter(
                Variation.template_id == template_id,
                Variation.age_band == age_band,
                Variation.locale == "en",
            )
            .first()
        )
        if english is not None and snapshot_locale != display_locale:
            return _display_content_from_variation(row, english)
    return None


def public_assignment(row, *, session: Session | None = None, display_locale: str | None = None) -> dict[str, Any]:
    """An assignment as the child API shows it.

    The title is shown without the age range some titles carry ("... (4 to 6)"); ``age_band`` and the stored
    snapshot are unchanged, so eligibility and history keep their metadata."""
    content = _localized_display_content(session, row, display_locale)
    if content is None:
        content = dict(row.snapshot or {})
    else:
        # Preserve original mission content/snapshot in DB; only display is localized.
        content = dict(content)
    if isinstance(content.get("title"), str):
        content["title"] = child_facing_title(content["title"])
    if row.status != "approved":
        # Not earned yet: show what an approval pays now. An approved row keeps the snapshot it was earned
        # with (history is shown as recorded).
        content["star_reward"] = MISSION_STAR_REWARD
        content["xp_reward"] = MISSION_XP_REWARD
    structured = structured_content(content)  # old snapshots: steps are extracted from the numbered lines
    content.update(
        learning_objective=structured["learning_objective"],
        steps=structured["steps"],
        materials=structured["materials"],
        observation_guidance=structured["observation_guidance"],
        submission_requirements=structured["submission_requirements"],
        instruction_status=instruction_status(structured),
    )
    return {
        "id": row.id,
        "local_date": row.local_date,
        "choice_slot": row.choice_slot,
        "age_band": row.age_band,
        "status": row.status,
        "task_id": row.task_id,
        "selected_at": row.selected_at,
        "started_at": row.started_at,
        "skipped_at": row.skipped_at,
        "content": content,
    }


_public = public_assignment  # the name older callers and tests import


def _child_language(session: Session, child) -> list[str]:
    User = get_model("User")
    language = session.query(User.preferred_language).filter(User.id == child.user_id).scalar() or "en"
    return [language] if language == "en" else [language, "en"]


def _pick_variation(session: Session, template_id: UUID, age_band: str, locales: list[str]):
    Variation = get_model("DailyMissionVariation")
    rows = (
        session.query(Variation)
        .filter(Variation.template_id == template_id, Variation.age_band == age_band, Variation.locale.in_(locales))
        .all()
    )
    return min(rows, key=lambda row: locales.index(row.locale)) if rows else None


def _eligible_templates(session: Session, age_band: str, locales: list[str]):
    """Published templates that have a variation for this age band in one of the child's languages.

    (A template missing the age band, or a translation, simply is not offered; the admin catalogue health view
    reports incomplete templates.)"""
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    with_variation = (
        session.query(Variation.template_id)
        .filter(Variation.age_band == age_band, Variation.locale.in_(locales))
        .distinct()
    )
    return (
        session.query(Template)
        .filter(Template.is_published.is_(True), Template.id.in_(with_variation))
        .all()
    )


def _choose_templates(session: Session, child, age_band: str, locales: list[str], local_date: date, current, needed: int):
    """The templates to fill ``needed`` free slots, with how each was chosen (see ``mission_rotation_service``)."""
    templates = {row.id: row for row in _eligible_templates(session, age_band, locales)}
    candidates = [Candidate(id=row.id, theme=row.theme, is_surprise=bool(row.is_surprise)) for row in templates.values()]
    history = load_child_history(session, child.id, local_date)
    picks = rank_candidates(
        candidates,
        history,
        local_date,
        None,
        f"{child.id}:{local_date.isoformat()}",
        used_themes={(row.snapshot or {}).get("theme") for row in current},
        limit=needed,
    )
    return [(templates[pick.candidate.id], pick) for pick in picks], len(candidates)


def _eligible(rows, age_band: str):
    return [row for row in rows if row.age_band == age_band]


# Today's rows for another age group that can be let go: nothing was sent to a parent and nothing was earned.
# (Pending and approved rows are progress or history and are never released.)
RELEASABLE_WHEN_AGE_CHANGES = ("available", "selected", "in_progress", "rejected")


def release_obsolete_choices(session: Session, current, age_band: str) -> int:
    """Hands back today's choice slots that were generated for a different age group than the child's current one.

    The row is **not deleted and not rewritten**: it keeps its status, snapshot, task and age group, stays in
    the child's history, and only stops being the *current* row of its slot (``is_current = false``, the same
    flag a skipped mission uses), so a fresh mission for the new group can take the slot. A task already created
    for it stays on record but can no longer be opened or submitted (``child_age.ineligible_daily_task_ids``).
    No skip is counted and nothing is paid or recalculated."""
    released = 0
    for row in current:
        if row.age_band != age_band and row.status in RELEASABLE_WHEN_AGE_CHANGES:
            row.is_current = False
            released += 1
    if released:
        session.flush()
        logger.info("daily missions: released %s obsolete slot(s) after an age group change (now %s)", released, age_band)
    return released


def ensure_daily_choices(session: Session, child, now_utc: datetime | None = None):
    """Today's choices for the child's **current** age group (``child_age``).

    If the age group changed today (the birth date was corrected, or today is a birthday that moved the child
    up), the obsolete rows are released (``release_obsolete_choices``) and the child immediately gets fresh
    choices for the new group. Obsolete rows already sent to a parent or approved keep their slot (they are
    progress); they are never returned, so the child may then see fewer than three, but never a wrong-age one."""
    now_utc = now_utc or _now()
    local_date, age_band = child_age_band(session, child, now_utc)

    ChildProfile = get_model("ChildProfile")
    locked_child = session.query(ChildProfile).filter(ChildProfile.id == child.id).with_for_update().one()
    Assignment = get_model("DailyMissionAssignment")
    # SessionLocal has autoflush off: make pending changes (e.g. a skipped row) visible to the queries below.
    session.flush()
    current = (
        session.query(Assignment)
        .filter(Assignment.child_id == locked_child.id, Assignment.local_date == local_date, Assignment.is_current.is_(True))
        .order_by(Assignment.choice_slot)
        .all()
    )
    if release_obsolete_choices(session, current, age_band):
        current = [row for row in current if row.is_current]
    if len(current) == 3:
        eligible = _eligible(current, age_band)
        if len(eligible) < 3:
            logger.warning(
                "daily missions: child=%s has %s current choice(s) for another age group today (now %s); not shown",
                locked_child.id,
                3 - len(eligible),
                age_band,
            )
        return local_date, age_band, eligible

    locales = _child_language(session, locked_child)
    free_slots = [slot for slot in (1, 2, 3) if slot not in {row.choice_slot for row in current}]
    chosen, eligible = _choose_templates(session, locked_child, age_band, locales, local_date, current, len(free_slots))
    for template, pick in chosen:
        variation = _pick_variation(session, template.id, age_band, locales)
        snapshot = _snapshot(template, variation)
        snapshot["rotation"] = {
            "policy": POLICY,
            "tier": "cooldown_fallback" if pick.tier else "fresh",
            "last_shown": pick.last_shown.isoformat() if pick.last_shown else None,
        }
        session.add(
            Assignment(
                child_id=locked_child.id,
                family_id=locked_child.family_id,
                local_date=local_date,
                choice_slot=free_slots.pop(0),
                age_band=age_band,
                template_id=template.id,
                variation_id=variation.id,
                status="available",
                is_current=True,
                snapshot=snapshot,
            )
        )
    session.flush()
    current = (
        session.query(Assignment)
        .filter(Assignment.child_id == locked_child.id, Assignment.local_date == local_date, Assignment.is_current.is_(True))
        .order_by(Assignment.choice_slot)
        .all()
    )
    if len(current) != 3:
        logger.error(
            "daily missions unavailable: child=%s age_band=%s eligible_published_templates=%s (publish more missions)",
            locked_child.id,
            age_band,
            eligible,
        )
        raise APIError(
            503,
            "daily_missions_unavailable",
            "There are not enough published missions for today. An administrator needs to publish more.",
            details={"eligible": eligible, "age_band": age_band},
        )
    return local_date, age_band, _eligible(current, age_band)


def task_description(snapshot: dict[str, Any]) -> str:
    """The text of the Task created when a mission is chosen (what the child reads and the parent reviews).

    The completion criteria, whose last line is the parent's check, are included so the approving parent
    sees what to verify; the admin preview uses the same function."""
    return "\n\n".join(
        part for part in (snapshot["description"], snapshot["instructions"], snapshot.get("completion_criteria")) if part
    )


def select_assignment(session: Session, child, assignment_id: UUID):
    Assignment = get_model("DailyMissionAssignment")
    assignment = (
        session.query(Assignment)
        .filter(Assignment.id == assignment_id, Assignment.child_id == child.id, Assignment.is_current.is_(True))
        .with_for_update()
        .one_or_none()
    )
    if assignment is None:
        raise APIError(404, "daily_assignment_not_found", "Daily mission choice not found")
    ensure_assignment_eligible(assignment, child_age_band(session, child, _now())[1])
    if assignment.status != "available":
        return assignment
    selected = (
        session.query(Assignment)
        .filter(
            Assignment.child_id == child.id,
            Assignment.local_date == assignment.local_date,
            Assignment.is_current.is_(True),
            Assignment.status.in_(["selected", "in_progress", "pending_parent_approval", "approved", "rejected"]),
        )
        .with_for_update()
        .first()
    )
    if selected is not None and selected.id != assignment.id:
        raise APIError(409, "daily_mission_already_selected", "Only one daily mission can be selected")
    Task = get_model("Task")
    now = utc_naive(_now())
    task = Task(
        family_id=child.family_id,
        created_by=child.user_id,
        assigned_child_id=child.id,
        title=child_facing_title(assignment.snapshot["title"]),
        description=task_description(assignment.snapshot),
        star_reward=MISSION_STAR_REWARD,
        xp_reward=MISSION_XP_REWARD,
        is_custom=False,
        is_active=True,
    )
    session.add(task)
    session.flush()
    assignment.task_id = task.id
    assignment.status = "selected"
    assignment.selected_at = now
    return assignment


# Statuses of a mission the child chose and has not finished: still theirs to do. "Pending parent approval" is
# not listed (nothing left for the child to do), nor "approved" / "skipped" (finished or given up), nor "available"
# (offered but never chosen: it was a menu, not a commitment).
UNFINISHED_STATUSES = ("selected", "in_progress", "rejected")
UNFINISHED_LIMIT = 20


def unfinished_assignments(session: Session, child, now_utc: datetime | None = None):
    """Missions the child chose on an earlier family-local day and has not finished, newest first.

    Read-only. It never creates an assignment, so listing or reopening one cannot duplicate or reset it: the
    mission keeps its Task, its submissions and its status, and is finished through the same submission and
    parent-approval flow as today's mission."""
    now_utc = now_utc or _now()
    today = local_today(session, child.family_id, now_utc)
    # Only missions for the child's current age group are carried forward; older ones stay in history.
    age_band = child_age_band_or_none(session, child, now_utc)
    if age_band is None:
        return []
    Assignment = get_model("DailyMissionAssignment")
    Task = get_model("Task")
    return (
        session.query(Assignment)
        .join(Task, Task.id == Assignment.task_id)
        .filter(
            Assignment.child_id == child.id,
            Assignment.is_current.is_(True),
            Assignment.local_date < today,
            Assignment.status.in_(UNFINISHED_STATUSES),
            Assignment.age_band == age_band,
            Task.is_active.is_(True),
        )
        .order_by(Assignment.local_date.desc(), Assignment.choice_slot)
        .limit(UNFINISHED_LIMIT)
        .all()
    )


def start_assignment(session: Session, child, assignment_id: UUID):
    Assignment = get_model("DailyMissionAssignment")
    row = session.query(Assignment).filter(Assignment.id == assignment_id, Assignment.child_id == child.id, Assignment.is_current.is_(True)).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_assignment_not_found", "Daily mission not found")
    ensure_assignment_eligible(row, child_age_band(session, child, _now())[1])
    if row.status == "selected":
        row.status = "in_progress"
        row.started_at = utc_naive(_now())
    elif row.status not in {"in_progress", "pending_parent_approval", "approved", "rejected"}:
        raise APIError(409, "daily_mission_not_selected", "Select this mission before starting it")
    return row


def skip_assignment(session: Session, child, assignment_id: UUID, now_utc: datetime | None = None):
    Assignment = get_model("DailyMissionAssignment")
    row = session.query(Assignment).filter(
        Assignment.id == assignment_id,
        Assignment.child_id == child.id,
        Assignment.is_current.is_(True),
        Assignment.status.in_(["available", "selected", "in_progress", "rejected"]),
    ).with_for_update().one_or_none()
    if row is None:
        raise APIError(409, "daily_mission_cannot_skip", "This mission cannot be skipped while it is awaiting review or already approved")
    ensure_assignment_eligible(row, child_age_band(session, child, now_utc or _now())[1])
    skipped_today = (
        session.query(Assignment.id)
        .filter(Assignment.child_id == child.id, Assignment.local_date == row.local_date, Assignment.status == "skipped")
        .count()
    )
    if skipped_today >= MAX_SKIPS_PER_DAY:
        raise APIError(409, "daily_skip_limit", "You have used all of today's skips")
    if row.task_id is not None:
        TaskSubmission = get_model("TaskSubmission")
        if session.query(TaskSubmission.id).filter(
            TaskSubmission.task_id == row.task_id,
            TaskSubmission.child_id == child.id,
            TaskSubmission.status == "pending",
        ).first() is not None:
            raise APIError(409, "daily_mission_cannot_skip", "A submitted mission must be reviewed before it can be skipped")
        Task = get_model("Task")
        session.query(Task).filter(Task.id == row.task_id).update({"is_active": False})
    row.status = "skipped"
    row.is_current = False
    row.skipped_at = utc_naive(now_utc or _now())
    session.flush()
    try:
        local_date, age_band, choices = ensure_daily_choices(session, child, now_utc)
    except APIError as error:
        if error.code == "daily_missions_unavailable":
            # The request is abandoned (nothing is committed), so the mission stays where it was.
            raise APIError(409, "daily_mission_no_replacement", "There is no other mission to swap in today") from error
        raise
    return row, choices


# How a day with several rows (a skipped mission and its replacement) is shown: the furthest-along one wins.
_DAY_STATUS_RANK = {
    "approved": 6,
    "pending_parent_approval": 5,
    "rejected": 4,
    "in_progress": 3,
    "selected": 2,
    "available": 1,
    "skipped": 0,
}


def _day_status(day_rows) -> str:
    current = [row for row in day_rows if row.is_current] or day_rows
    return max(current, key=lambda row: _DAY_STATUS_RANK.get(row.status, 0)).status


def weekly_summary(session: Session, child, now_utc: datetime | None = None):
    now_utc = now_utc or _now()
    today = local_today(session, child.family_id, now_utc)
    week_start = today - timedelta(days=today.weekday())
    Assignment = get_model("DailyMissionAssignment")
    rows = session.query(Assignment).filter(Assignment.child_id == child.id, Assignment.local_date >= week_start, Assignment.local_date <= today).order_by(Assignment.created_at.asc()).all()
    approved = [row for row in rows if row.status == "approved"]
    return {
        "week_start": week_start,
        "week_end": week_start + timedelta(days=6),
        "completed_count": len(approved),
        "approved_xp": sum(int(row.snapshot.get("xp_reward", 0)) for row in approved),
        "approved_stars": sum(int(row.snapshot.get("star_reward", 0)) for row in approved),
        "skipped_count": sum(row.status == "skipped" for row in rows),
        "daily_status": {day.isoformat(): _day_status([row for row in rows if row.local_date == day]) for day in {row.local_date for row in rows}},
    }


def _localized_variation(session: Session, template_id, age_band: str, display_locale: str):
    Variation = get_model("DailyMissionVariation")
    requested = (
        session.query(Variation)
        .filter(
            Variation.template_id == template_id,
            Variation.age_band == age_band,
            Variation.locale == display_locale,
        )
        .first()
    )
    if requested is not None:
        return requested
    if display_locale != "en":
        return (
            session.query(Variation)
            .filter(
                Variation.template_id == template_id,
                Variation.age_band == age_band,
                Variation.locale == "en",
            )
            .first()
        )
    return None


def localized_task_fields(session: Session, tasks, display_locale: str | None) -> dict[UUID, dict[str, str]]:
    """Read-only localized title/description for tasks created from daily missions.

    Returns a mapping of task_id -> {title, description}. Stored Task rows and
    assignment snapshots are never modified.
    """
    if not display_locale or not tasks:
        return {}
    task_ids = [getattr(task, "id", None) for task in tasks]
    task_ids = [task_id for task_id in task_ids if task_id is not None]
    if not task_ids:
        return {}
    Assignment = get_model("DailyMissionAssignment")
    rows = (
        session.query(Assignment)
        .filter(Assignment.task_id.in_(task_ids))
        .order_by(Assignment.created_at.desc())
        .all()
    )
    by_task: dict[UUID, Any] = {}
    for row in rows:
        if row.task_id is None or row.task_id in by_task:
            continue
        if getattr(row, "is_current", True) is False:
            continue
        by_task[row.task_id] = row
    result: dict[UUID, dict[str, str]] = {}
    for task_id, assignment in by_task.items():
        template_id = getattr(assignment, "template_id", None)
        age_band = getattr(assignment, "age_band", None)
        if template_id is None or age_band is None:
            continue
        variation = _localized_variation(session, template_id, age_band, display_locale)
        content_source = variation if variation is not None else (assignment.snapshot or {})
        content = {
            "title": getattr(content_source, "title", None) if variation is not None else content_source.get("title"),
            "description": getattr(content_source, "description", None) if variation is not None else content_source.get("description"),
            "instructions": getattr(content_source, "instructions", None) if variation is not None else content_source.get("instructions"),
            "completion_criteria": getattr(content_source, "completion_criteria", None) if variation is not None else content_source.get("completion_criteria"),
        }
        title = content.get("title")
        if not isinstance(title, str) or not title:
            continue
        result[task_id] = {
            "title": child_facing_title(title),
            "description": task_description(content),
        }
    return result
