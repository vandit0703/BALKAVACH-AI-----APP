from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.utils import utc_naive


def list_notifications(session: Session, user_id: UUID, limit: int, offset: int):
	Notification = get_model("Notification")
	return (
		session.query(Notification)
		.filter(Notification.recipient_user_id == user_id)
		.order_by(Notification.created_at.desc(), Notification.id)
		.offset(offset)
		.limit(limit)
		.all()
	)


def mark_notification_read(session: Session, user_id: UUID, notification_id: UUID):
	Notification = get_model("Notification")
	notification = session.query(Notification).filter(
		Notification.id == notification_id,
		Notification.recipient_user_id == user_id,
	).with_for_update().one_or_none()
	if notification is None:
		raise HTTPException(status_code=404, detail="Notification not found")
	if not notification.is_read:
		notification.is_read = True
		notification.read_at = utc_naive(datetime.now(timezone.utc))
		session.commit()
		session.refresh(notification)
	return notification
