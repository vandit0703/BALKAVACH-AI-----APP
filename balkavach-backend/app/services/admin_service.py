from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy.orm import Session

from app.db.base import get_model
from app.utils import utc_naive


def record_audit(
    session: Session,
    actor_id: UUID,
    action: str,
    entity_type: str,
    entity_id: UUID | None,
    details: dict,
) -> None:
    AuditLog = get_model("AuditLog")
    session.add(
        AuditLog(
            actor_user_id=actor_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
            created_at=utc_naive(datetime.now(timezone.utc)),
        )
    )