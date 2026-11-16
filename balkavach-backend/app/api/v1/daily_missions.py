from uuid import UUID

from fastapi import APIRouter, Depends, Query, status
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
from app.services.daily_mission_service import (
    _public,
    ensure_daily_choices,
    select_assignment,
    skip_assignment,
    start_assignment,
    weekly_summary,
)
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


@router.get("/today", response_model=DailyMissionChoicesPublic)
def today_choices(child=Depends(require_child), session: Session = Depends(get_db)):
    local_date, age_band, rows = ensure_daily_choices(session, child)
    session.commit()
    selected = next((row.id for row in rows if row.status in {"selected", "in_progress", "pending_parent_approval", "approved", "rejected"}), None)
    return DailyMissionChoicesPublic(
        local_date=local_date,
        timezone=family_timezone_name(session, child.family_id),
        age_band=age_band,
        selected_assignment_id=selected,
        choices=[DailyMissionAssignmentPublic(**_public(row)) for row in rows],
    )


@router.post("/{assignment_id}/select", response_model=DailyMissionAssignmentPublic)
def select_today_mission(assignment_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
    row = select_assignment(session, child, assignment_id)
    _commit(session)
    return DailyMissionAssignmentPublic(**_public(row))


@router.get("/active", response_model=DailyMissionAssignmentPublic | None)
def active_mission(child=Depends(require_child), session: Session = Depends(get_db)):
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
    return DailyMissionAssignmentPublic(**_public(row)) if row else None


@router.post("/{assignment_id}/start", response_model=DailyMissionAssignmentPublic)
def start_today_mission(assignment_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
    row = start_assignment(session, child, assignment_id)
    _commit(session)
    return DailyMissionAssignmentPublic(**_public(row))


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
    submission = submit_completion(session, row.task_id, child, request)
    row.status = "pending_parent_approval"
    _commit(session)
    return DailyMissionSubmitPublic(assignment_id=row.id, task_id=submission.task_id, status=row.status)


@router.post("/{assignment_id}/skip", response_model=list[DailyMissionAssignmentPublic])
def skip_today_mission(assignment_id: UUID, child=Depends(require_child), session: Session = Depends(get_db)):
    _, choices = skip_assignment(session, child, assignment_id)
    _commit(session)
    return [DailyMissionAssignmentPublic(**_public(row)) for row in choices]


@router.get("/history", response_model=DailyMissionHistoryPublic)
def mission_history(
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
    return DailyMissionHistoryPublic(items=[DailyMissionAssignmentPublic(**_public(row)) for row in rows], limit=limit, offset=offset)


@router.get("/weekly", response_model=WeeklyMissionSummary)
def mission_weekly_summary(child=Depends(require_child), session: Session = Depends(get_db)):
    return WeeklyMissionSummary(**weekly_summary(session, child))


@admin_router.get("/templates")
def list_daily_templates(admin=Depends(require_admin_permission("tasks:read")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    return [
        {
            "id": row.id,
            "slug": row.slug,
            "theme": row.theme,
            "mission_type": row.mission_type,
            "is_surprise": row.is_surprise,
            "is_published": row.is_published,
            "star_reward": row.star_reward,
            "xp_reward": row.xp_reward,
            "mystery_bonus": row.mystery_bonus,
        }
        for row in session.query(Template).order_by(Template.theme, Template.slug).all()
    ]


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
    row = Variation(template_id=template_id, **request.model_dump())
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
    Variation = get_model("DailyMissionVariation")
    row = session.query(Variation).filter(Variation.id == variation_id, Variation.template_id == template_id).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_variation_not_found", "Daily mission variation not found")
    values = {**{field: getattr(row, field) for field in ("age_band", "locale", "title", "description", "instructions", "required_materials", "duration_minutes", "safety_instructions", "completion_criteria", "variation_key")}, **request.model_dump(exclude_unset=True)}
    DailyMissionVariationCreate(**values)
    for field, value in request.model_dump(exclude_unset=True).items():
        setattr(row, field, value)
    Template = get_model("DailyMissionTemplate")
    session.query(Template).filter(Template.id == template_id).update({"is_published": False})
    _commit(session)
    return {"id": row.id, "template_id": row.template_id}


@admin_router.patch("/templates/{template_id}/publish")
def publish_daily_template(template_id: UUID, publish: bool, admin=Depends(require_admin_permission("tasks:write")), session: Session = Depends(get_db)):
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    row = session.query(Template).filter(Template.id == template_id).with_for_update().one_or_none()
    if row is None:
        raise APIError(404, "daily_template_not_found", "Daily mission template not found")
    if publish:
        count = session.query(Variation.id).filter(Variation.template_id == row.id).count()
        if count < 3:
            raise APIError(422, "daily_template_incomplete", "Publish requires all three age-band variations")
    row.is_published = publish
    _commit(session)
    return {"id": row.id, "is_published": row.is_published}
