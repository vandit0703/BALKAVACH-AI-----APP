from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from hashlib import sha256
from typing import Any
from uuid import UUID

from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.services.timezone_service import family_timezone_name, local_today
from app.utils import utc_naive

THEMES_BY_WEEKDAY = {
    0: "monday_sound_detective",
    1: "tuesday_memory_master",
    2: "wednesday_magic_story_maker",
    3: "thursday_paper_architect",
    4: "friday_emotion_detective",
    5: "saturday_rhythm_rockstar",
    6: "sunday_future_inventor",
}


def age_band_for_birth_date(birth_date: date, today: date) -> str | None:
    age = today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))
    if 4 <= age <= 6:
        return "4_6"
    if 7 <= age <= 10:
        return "7_10"
    if 11 <= age <= 15:
        return "11_15"
    return None


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
        "star_reward": template.star_reward,
        "xp_reward": template.xp_reward,
        "is_surprise": bool(template.is_surprise),
        "mystery_bonus": template.mystery_bonus,
        "locale": variation.locale,
    }


def _public(row) -> dict[str, Any]:
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
        "content": row.snapshot,
    }


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


def _candidate_templates(session: Session, child, age_band: str, local_date: date):
    Template = get_model("DailyMissionTemplate")
    Assignment = get_model("DailyMissionAssignment")
    completed_ids = {
        template_id
        for (template_id,) in session.query(Assignment.template_id)
        .filter(Assignment.child_id == child.id, Assignment.status == "approved")
        .all()
    }
    theme = THEMES_BY_WEEKDAY[local_date.weekday()]
    rows = (
        session.query(Template)
        .filter(Template.is_published.is_(True), ~Template.id.in_(completed_ids or {UUID(int=0)}))
        .all()
    )
    theme_rows = [row for row in rows if row.theme == theme]
    surprise = [row for row in rows if row.is_surprise]
    seed = f"{child.id}:{local_date.isoformat()}".encode()
    rows.sort(key=lambda row: sha256(seed + str(row.id).encode()).hexdigest())
    theme_rows.sort(key=lambda row: sha256(seed + str(row.id).encode()).hexdigest())
    choices = []
    if surprise:
        choices.append(surprise[0])
    for row in theme_rows + rows:
        if row not in choices:
            choices.append(row)
        if len(choices) == 3:
            break
    return choices[:3]


def ensure_daily_choices(session: Session, child, now_utc: datetime | None = None):
    now_utc = now_utc or _now()
    local_date = local_today(session, child.family_id, now_utc)
    if child.date_of_birth is None:
        raise APIError(422, "birth_date_required", "A birth date is required for daily missions")
    age_band = age_band_for_birth_date(child.date_of_birth, local_date)
    if age_band is None:
        raise APIError(422, "daily_missions_age_range", "Daily missions are available for ages 4 through 15")

    ChildProfile = get_model("ChildProfile")
    locked_child = session.query(ChildProfile).filter(ChildProfile.id == child.id).with_for_update().one()
    Assignment = get_model("DailyMissionAssignment")
    current = (
        session.query(Assignment)
        .filter(Assignment.child_id == locked_child.id, Assignment.local_date == local_date, Assignment.is_current.is_(True))
        .order_by(Assignment.choice_slot)
        .all()
    )
    if len(current) == 3:
        return local_date, age_band, current

    locales = _child_language(session, locked_child)
    issued_template_ids = {
        template_id
        for (template_id,) in session.query(Assignment.template_id).filter(
            Assignment.child_id == locked_child.id,
            Assignment.local_date == local_date,
        ).all()
    }
    existing_template_ids = set(issued_template_ids)
    for slot, template in enumerate(_candidate_templates(session, locked_child, age_band, local_date), start=1):
        if slot in {row.choice_slot for row in current} or template.id in existing_template_ids:
            continue
        variation = _pick_variation(session, template.id, age_band, locales)
        if variation is None:
            continue
        session.add(
            Assignment(
                child_id=locked_child.id,
                family_id=locked_child.family_id,
                local_date=local_date,
                choice_slot=slot,
                age_band=age_band,
                template_id=template.id,
                variation_id=variation.id,
                status="available",
                is_current=True,
                snapshot=_snapshot(template, variation),
            )
        )
        existing_template_ids.add(template.id)
    session.flush()
    current = (
        session.query(Assignment)
        .filter(Assignment.child_id == locked_child.id, Assignment.local_date == local_date, Assignment.is_current.is_(True))
        .order_by(Assignment.choice_slot)
        .all()
    )
    if len(current) != 3:
        raise APIError(503, "daily_missions_unavailable", "No complete daily mission set is published")
    return local_date, age_band, current


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
        title=assignment.snapshot["title"],
        description=(assignment.snapshot["description"] + "\n\n" + assignment.snapshot["instructions"]),
        star_reward=assignment.snapshot["star_reward"],
        xp_reward=assignment.snapshot["xp_reward"],
        is_custom=False,
        is_active=True,
    )
    session.add(task)
    session.flush()
    assignment.task_id = task.id
    assignment.status = "selected"
    assignment.selected_at = now
    return assignment


def start_assignment(session: Session, child, assignment_id: UUID):
    Assignment = get_model("DailyMissionAssignment")
    row = session.query(Assignment).filter(Assignment.id == assignment_id, Assignment.child_id == child.id, Assignment.is_current.is_(True)).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_assignment_not_found", "Daily mission not found")
    if row.status == "selected":
        row.status = "in_progress"
        row.started_at = utc_naive(_now())
    elif row.status not in {"in_progress", "pending_parent_approval", "approved", "rejected"}:
        raise APIError(409, "daily_mission_not_selected", "Select this mission before starting it")
    return row


def skip_assignment(session: Session, child, assignment_id: UUID):
    Assignment = get_model("DailyMissionAssignment")
    row = session.query(Assignment).filter(Assignment.id == assignment_id, Assignment.child_id == child.id, Assignment.is_current.is_(True), Assignment.status == "available").with_for_update().one_or_none()
    if row is None:
        raise APIError(409, "daily_mission_cannot_skip", "Only an unselected mission can be skipped")
    row.status = "skipped"
    row.is_current = False
    row.skipped_at = utc_naive(_now())
    local_date, age_band, choices = ensure_daily_choices(session, child)
    return row, choices


def weekly_summary(session: Session, child, now_utc: datetime | None = None):
    now_utc = now_utc or _now()
    today = local_today(session, child.family_id, now_utc)
    week_start = today - timedelta(days=today.weekday())
    Assignment = get_model("DailyMissionAssignment")
    rows = session.query(Assignment).filter(Assignment.child_id == child.id, Assignment.local_date >= week_start, Assignment.local_date <= today).all()
    approved = [row for row in rows if row.status == "approved"]
    return {
        "week_start": week_start,
        "week_end": week_start + timedelta(days=6),
        "completed_count": len(approved),
        "approved_xp": sum(int(row.snapshot.get("xp_reward", 0)) for row in approved),
        "approved_stars": sum(int(row.snapshot.get("star_reward", 0)) for row in approved),
        "skipped_count": sum(row.status == "skipped" for row in rows),
        "daily_status": {row.local_date.isoformat(): row.status for row in rows if row.is_current},
    }
