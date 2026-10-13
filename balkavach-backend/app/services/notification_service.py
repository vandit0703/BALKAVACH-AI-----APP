from datetime import datetime, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.push_service import stage_push
from app.utils import utc_naive


def create_notification(
	session: Session,
	recipient_user_id: UUID,
	notification_type: str,
	title: str,
	message: str,
	*,
	task_id: UUID | None = None,
	submission_id: UUID | None = None,
	redemption_id: UUID | None = None,
	now: datetime | None = None,
):
	"""Stage an in-app notification in the caller's transaction (the caller commits)."""
	Notification = get_model("Notification")
	notification = Notification(
		recipient_user_id=recipient_user_id,
		notification_type=notification_type,
		title=title,
		message=message,
		related_task_id=task_id,
		related_submission_id=submission_id,
		related_redemption_id=redemption_id,
		is_read=False,
		created_at=now or utc_naive(datetime.now(timezone.utc)),
	)
	session.add(notification)
	stage_push(session, notification)
	return notification


def family_parent_ids(session: Session, family_id: UUID) -> list[UUID]:
	FamilyMember = get_model("FamilyMember")
	User = get_model("User")
	rows = (
		session.query(User.id)
		.join(FamilyMember, FamilyMember.user_id == User.id)
		.filter(
			FamilyMember.family_id == family_id,
			FamilyMember.is_active.is_(True),
			User.role == "parent",
			User.is_active.is_(True),
		)
		.all()
	)
	return [row[0] for row in rows]


def notify_task_assigned(session: Session, task) -> None:
	"""Tell the assigned child, or every active child of the family for an open mission."""
	ChildProfile = get_model("ChildProfile")
	query = session.query(ChildProfile.user_id).filter(
		ChildProfile.family_id == task.family_id,
		ChildProfile.is_active.is_(True),
	)
	if task.assigned_child_id is not None:
		query = query.filter(ChildProfile.id == task.assigned_child_id)
	for (user_id,) in query.all():
		create_notification(
			session,
			user_id,
			"task_assigned",
			"New mission",
			f"You have a new mission: {task.title}.",
			task_id=task.id,
		)


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
