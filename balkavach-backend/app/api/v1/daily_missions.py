from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.dependencies import require_admin_permission, require_child
from app.core.exceptions import APIError
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.daily_mission import (
    DailyMissionAssignmentPublic,
    DailyMissionChoicesPublic,
    DailyMissionHistoryPublic,
    DailyMissionSubmitPublic,
    DailyMissionTemplateCreate,
    DailyMissionTemplateUpdate,
    DailyMissionVariationCreate,
    DailyMissionVariationUpdate,
    WeeklyMissionSummary,
)
from app.schemas.task import TaskSubmissionCreate
from app.services.display_locale import resolve_display_locale
from app.services.mission_catalogue_service import assignment_counts, catalogue_health, missing_combinations
from app.services.mission_instructions import (
    AGE_BANDS,
    as_error_details,
    parse_numbered_steps,
    instruction_problems,
    instruction_status,
    render_task_text,
    structured_content,
    validate_content,
)
from app.services.daily_mission_service import (
    public_assignment as _public,
    unfinished_assignments,
    task_description,
    ensure_daily_choices,
    select_assignment,
    skip_assignment,
    start_assignment,
    has_complete_localized_variations,
    weekly_summary,
)
from app.services.child_age import child_age_band_or_none, ensure_assignment_eligible
from app.services.timezone_service import family_timezone_name
from app.services.task_service import submit_completion

router = APIRouter(prefix="/daily-missions", tags=["daily missions"])
admin_router = APIRouter(prefix="/admin/daily-missions", tags=["admin daily missions"])


def _commit(session: Session):
    try:
        session.commit()
    except IntegrityError as error:
        session.rollback()
        raise APIError(409, "daily_mission_conflict", "The daily mission changed; please retry") from error


def _child_display_locale(request: Request, session: Session, child) -> str:
    User = get_model("User")
    user = session.get(User, getattr(child, "user_id", None))
    return resolve_display_locale(request, user)


@router.get("/today", response_model=DailyMissionChoicesPublic)
def today_choices(request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    local_date, age_band, rows = ensure_daily_choices(session, child)
    session.commit()
    display_locale = _child_display_locale(request, session, child)
    selected = next((row.id for row in rows if row.status in {"selected", "in_progress", "pending_parent_approval", "approved", "rejected"}), None)
    return DailyMissionChoicesPublic(
        local_date=local_date,
        timezone=family_timezone_name(session, child.family_id),
        age_band=age_band,
        selected_assignment_id=selected,
        choices=[DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale)) for row in rows],
    )


@router.post("/{assignment_id}/select", response_model=DailyMissionAssignmentPublic)
def select_today_mission(assignment_id: UUID, request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    row = select_assignment(session, child, assignment_id)
    _commit(session)
    display_locale = _child_display_locale(request, session, child)
    return DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale))


@router.get("/active", response_model=DailyMissionAssignmentPublic | None)
def active_mission(request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    Assignment = get_model("DailyMissionAssignment")
    age_band = child_age_band_or_none(session, child)
    if age_band is None:
        return None
    row = (
        session.query(Assignment)
        .filter(
            Assignment.child_id == child.id,
            Assignment.is_current.is_(True),
            Assignment.age_band == age_band,
            Assignment.status.in_(["selected", "in_progress", "pending_parent_approval", "approved", "rejected"]),
        )
        .order_by(Assignment.local_date.desc())
        .first()
    )
    display_locale = _child_display_locale(request, session, child)
    return DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale)) if row else None


@router.get("/unfinished", response_model=list[DailyMissionAssignmentPublic])
def unfinished_missions(request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    """Missions the child chose on an earlier day and has not finished. Read-only: reopening one is the same
    Task and submission flow as today's mission, so nothing is duplicated or reset."""
    display_locale = _child_display_locale(request, session, child)
    return [DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale)) for row in unfinished_assignments(session, child)]


@router.post("/{assignment_id}/start", response_model=DailyMissionAssignmentPublic)
def start_today_mission(assignment_id: UUID, request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    row = start_assignment(session, child, assignment_id)
    _commit(session)
    display_locale = _child_display_locale(request, session, child)
    return DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale))


@router.post("/{assignment_id}/submit", response_model=DailyMissionSubmitPublic)
def submit_today_mission(
    assignment_id: UUID,
    request: TaskSubmissionCreate,
    child=Depends(require_child),
    session: Session = Depends(get_db),
):
    Assignment = get_model("DailyMissionAssignment")
    row = session.query(Assignment).filter(Assignment.id == assignment_id, Assignment.child_id == child.id, Assignment.is_current.is_(True)).one_or_none()
    if row is None or row.task_id is None:
        raise APIError(409, "daily_mission_not_selected", "Select a daily mission before submitting it")
    ensure_assignment_eligible(row, child_age_band_or_none(session, child))
    submission = submit_completion(session, row.task_id, child, request)
    row.status = "pending_parent_approval"
    _commit(session)
    return DailyMissionSubmitPublic(assignment_id=row.id, task_id=submission.task_id, status=row.status)


@router.post("/{assignment_id}/skip", response_model=list[DailyMissionAssignmentPublic])
def skip_today_mission(assignment_id: UUID, request: Request, child=Depends(require_child), session: Session = Depends(get_db)):
    _, choices = skip_assignment(session, child, assignment_id)
    _commit(session)
    display_locale = _child_display_locale(request, session, child)
    return [DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale)) for row in choices]


@router.get("/history", response_model=DailyMissionHistoryPublic)
def mission_history(
    request: Request,
    limit: int = Query(default=30, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    child=Depends(require_child),
    session: Session = Depends(get_db),
):
    Assignment = get_model("DailyMissionAssignment")
    rows = (
        session.query(Assignment)
        .filter(Assignment.child_id == child.id)
        .order_by(Assignment.local_date.desc(), Assignment.created_at.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    display_locale = _child_display_locale(request, session, child)
    return DailyMissionHistoryPublic(items=[DailyMissionAssignmentPublic(**_public(row, session=session, display_locale=display_locale)) for row in rows], limit=limit, offset=offset)


@router.get("/weekly", response_model=WeeklyMissionSummary)
def mission_weekly_summary(child=Depends(require_child), session: Session = Depends(get_db)):
    return WeeklyMissionSummary(**weekly_summary(session, child))


def _template_summary(row, variation_rows, assignment_count: int = 0) -> dict:
    missing = missing_combinations((age, locale) for age, locale in variation_rows)
    return {
        "id": row.id,
        "slug": row.slug,
        "theme": row.theme,
        "mission_type": row.mission_type,
        "is_surprise": row.is_surprise,
        "is_published": row.is_published,
        "star_reward": row.star_reward,
        "xp_reward": row.xp_reward,
        "mystery_bonus": row.mystery_bonus,
        "variation_count": len(variation_rows),
        "missing": missing,
        "is_complete": not missing,
        "assignment_count": assignment_count,
    }


@admin_router.get("/templates")
def list_daily_templates(admin=Depends(require_admin_permission("tasks:read")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    by_template: dict = {}
    for template_id, age_band, locale in session.query(Variation.template_id, Variation.age_band, Variation.locale).all():
        by_template.setdefault(template_id, set()).add((age_band, locale))
    counts = assignment_counts(session)
    return [
        _template_summary(row, by_template.get(row.id, set()), counts.get(row.id, 0))
        for row in session.query(Template).order_by(Template.theme, Template.slug).all()
    ]


@admin_router.get("/catalogue-health")
def catalogue_health_endpoint(admin=Depends(require_admin_permission("tasks:read")), session: Session = Depends(get_db)):
    """Rotation capacity per weekday theme (warns below 6 eligible templates), assignment counts, recent cooldown fallbacks."""
    return catalogue_health(session)


@admin_router.get("/templates/{template_id}")
def get_daily_template(template_id: UUID, admin=Depends(require_admin_permission("tasks:read")), session: Session = Depends(get_db)):
    """One template with every variation and the exact text a child (and the reviewing parent) will see."""
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    row = session.query(Template).filter(Template.id == template_id).one_or_none()
    if row is None:
        raise APIError(404, "daily_template_not_found", "Daily mission template not found")
    variations = session.query(Variation).filter(Variation.template_id == row.id).all()
    order = {"4_6": 0, "7_10": 1, "11_15": 2}
    locales = {"en": 0, "gu": 1, "hi": 2}
    variations.sort(key=lambda v: (order.get(v.age_band, 9), locales.get(v.locale, 9), v.variation_key or ""))
    return {
        **_template_summary(
            row, {(v.age_band, v.locale) for v in variations}, assignment_counts(session).get(row.id, 0)
        ),
        "variations": [
            {
                "id": v.id,
                "age_band": v.age_band,
                "locale": v.locale,
                "variation_key": v.variation_key,
                "title": v.title,
                "description": v.description,
                "instructions": v.instructions,
                "required_materials": v.required_materials or [],
                "duration_minutes": v.duration_minutes,
                "safety_instructions": v.safety_instructions,
                "completion_criteria": v.completion_criteria,
                "learning_objective": getattr(v, "learning_objective", None),
                "steps": structured_content(v)["steps"],
                "observation_guidance": getattr(v, "observation_guidance", None),
                "submission_requirements": getattr(v, "submission_requirements", None),
                "instruction_status": _issues(v)["instruction_status"],
                "issues": {"errors": _issues(v)["errors"], "warnings": _issues(v)["warnings"]},
                "preview": task_description(
                    {"description": v.description, "instructions": v.instructions, "completion_criteria": v.completion_criteria}
                ),
            }
            for v in variations
        ],
    }


_STRUCTURED_FIELDS = ("learning_objective", "steps", "observation_guidance", "submission_requirements")
_VARIATION_FIELDS = (
    "age_band", "locale", "title", "description", "instructions", "required_materials", "duration_minutes",
    "safety_instructions", "completion_criteria", "variation_key", *_STRUCTURED_FIELDS,
)


def _issues(v) -> dict:
    content = structured_content(v)
    issues = validate_content(content, age_band=v.age_band, description=v.description, instructions=v.instructions)
    return {
        "structured": content,
        "instruction_status": instruction_status(content),
        "errors": as_error_details(issues["errors"]),
        "warnings": as_error_details(issues["warnings"]),
    }


@admin_router.post("/variations/preview")
def preview_variation(request: DailyMissionVariationCreate, admin=Depends(require_admin_permission("tasks:read"))):
    """What a child will see for this variation, and what is still missing. Saves nothing."""
    content = structured_content({**request.model_dump(), "required_materials": request.required_materials})
    issues = validate_content(content, age_band=request.age_band, description=request.description, instructions=request.instructions)
    return {
        "content": {**content, "title": request.title, "description": request.description, "instruction_status": instruction_status(content)},
        "task_text": render_task_text(content),
        "errors": as_error_details(issues["errors"]),
        "warnings": as_error_details(issues["warnings"]),
        "publishable": not issues["errors"],
    }


@admin_router.post("/templates", status_code=status.HTTP_201_CREATED)
def create_daily_template(request: DailyMissionTemplateCreate, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    row = Template(**request.model_dump(), is_published=False)
    session.add(row)
    _commit(session)
    session.refresh(row)
    return {"id": row.id, **request.model_dump(), "is_published": row.is_published}


@admin_router.post("/templates/{template_id}/variations", status_code=status.HTTP_201_CREATED)
def create_daily_variation(template_id: UUID, request: DailyMissionVariationCreate, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    if session.query(Template.id).filter(Template.id == template_id).first() is None:
        raise APIError(404, "daily_template_not_found", "Daily mission template not found")
    values = {k: v for k, v in request.model_dump().items() if not (k in _STRUCTURED_FIELDS and v is None)}
    row = Variation(template_id=template_id, **values)
    session.add(row)
    _commit(session)
    session.refresh(row)
    return {"id": row.id, **request.model_dump(), "template_id": template_id}


@admin_router.patch("/templates/{template_id}")
def update_daily_template(template_id: UUID, request: DailyMissionTemplateUpdate, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    row = session.query(Template).filter(Template.id == template_id).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_template_not_found", "Daily mission template not found")
    for field, value in request.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    row.is_published = False
    _commit(session)
    return {"id": row.id, "is_published": row.is_published}


@admin_router.patch("/templates/{template_id}/variations/{variation_id}")
def update_daily_variation(template_id: UUID, variation_id: UUID, request: DailyMissionVariationUpdate, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    """Edit one age band x language version in place (its id, and every assignment, submission and approval that
    refers to it, never changes; assignments keep the snapshot they were made with).

    Publication follows the content, not the act of editing: editing one version used to unpublish the whole template
    (all nine versions vanished from rotation until someone republished). Now
    * an unpublished template stays unpublished;
    * a published template that is still publishable after the edit stays published;
    * an edit that would make a valid published template unpublishable is refused (422, nothing changes), so a child
      never sees a half-edited mission and the admin unpublishes first on purpose;
    * a published template that was already unpublishable is unpublished by the edit (the old protective behaviour)."""
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    template = session.query(Template).filter(Template.id == template_id).with_for_update().one_or_none()  # same lock order as publish
    row = session.query(Variation).filter(Variation.id == variation_id, Variation.template_id == template_id).with_for_update().one_or_none()
    if template is None or row is None:
        raise APIError(404, "daily_variation_not_found", "Daily mission variation not found")
    changes = request.model_dump(exclude_unset=True)
    if "steps" in changes and changes["steps"] is not None and "instructions" not in changes:
        # Keep the legacy ``instructions`` text in step with the steps (older clients and the Task text read it):
        # numbered steps first, then any un-numbered line the old text carried (e.g. 'Another way: ...').
        extras = [line for line in (row.instructions or "").splitlines() if line.strip() and not parse_numbered_steps(line)]
        changes["instructions"] = "\n".join([f"{n}. {step}" for n, step in enumerate(changes["steps"], start=1)] + extras)
    values = {**{field: getattr(row, field, None) for field in _VARIATION_FIELDS}, **changes}
    DailyMissionVariationCreate(**values)

    was_published = bool(template.is_published)
    problems_before = _publish_problems(session, template_id) if was_published else []
    for field, value in changes.items():
        setattr(row, field, value)
    if was_published:
        session.flush()
        problems_after = _publish_problems(session, template_id)
        if problems_after and not problems_before:
            session.rollback()
            raise APIError(
                422,
                "published_variation_edit_invalid",
                "This edit would leave a published mission incomplete. Unpublish the mission first, or fix the problems.",
                details={"problems": problems_after},
            )
        if problems_after:
            template.is_published = False
    _commit(session)
    return {"id": row.id, "template_id": row.template_id, "is_published": bool(template.is_published)}


def _publish_problems(session: Session, template_id: UUID) -> list[dict]:
    """What would stop this template being published right now (missing versions and instruction problems)."""
    Variation = get_model("DailyMissionVariation")
    rows = session.query(Variation).filter(Variation.template_id == template_id).all()
    problems = instruction_problems(rows)
    missing = missing_combinations((v.age_band, v.locale) for v in rows)
    if missing:
        problems.append({"age_band": None, "locale": None, "variation_id": None, "code": "versions_missing", "message": "Missing versions: " + ", ".join(missing)})
    return problems


@admin_router.patch("/templates/{template_id}/publish")
def publish_daily_template(template_id: UUID, publish: bool, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    row = session.query(Template).filter(Template.id == template_id).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_template_not_found", "Daily mission template not found")
    if publish:
        variations = session.query(Variation.age_band, Variation.locale).filter(Variation.template_id == row.id).all()
        if not has_complete_localized_variations(variations):
            raise APIError(
                422,
                "daily_template_incomplete",
                "Publish requires English, Gujarati, and Hindi content for all age bands",
                details={"missing": missing_combinations((a, loc) for a, loc in variations)},
            )
        problems = instruction_problems(session.query(Variation).filter(Variation.template_id == row.id).all())
        if problems:
            raise APIError(
                422,
                "daily_template_instructions_incomplete",
                "Publish requires real, age-specific steps and a clear submission requirement in every version",
                details={"problems": problems},
            )
    row.is_published = publish
    _commit(session)
    return {"id": row.id, "is_published": row.is_published}
