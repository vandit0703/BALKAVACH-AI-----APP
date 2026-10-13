from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import case, func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.task import TaskReviewCreate, TaskSubmissionCreate
from app.services.ledger_service import star_balance, xp_total
from app.services.notification_service import create_notification, family_parent_ids
from app.services.progress_service import badge_qualifies
from app.services.timezone_service import local_today
from app.services.upload_service import claim_upload_for_submission, proof_url
from app.utils import utc_naive


def submit_completion(session: Session, task_id: UUID, child, request: TaskSubmissionCreate):
	Task = get_model("Task")
	TaskSubmission = get_model("TaskSubmission")
	task = session.query(Task).filter(Task.id == task_id, Task.is_active.is_(True)).with_for_update().one_or_none()
	if task is None or task.family_id != child.family_id:
		raise APIError(404, "task_not_found", "Task not found")
	if task.assigned_child_id is not None and task.assigned_child_id != child.id:
		raise APIError(403, "task_not_assigned", "Task is assigned to another child")

	existing_statuses = {
		row[0]
		for row in session.query(TaskSubmission.status)
		.filter(TaskSubmission.task_id == task_id, TaskSubmission.child_id == child.id)
		.all()
	}
	if "pending" in existing_statuses:
		raise APIError(409, "submission_pending", "This mission is already waiting for review")
	if "approved" in existing_statuses and task.repeat_rule is None:
		raise APIError(409, "task_already_completed", "This mission has already been completed")

	last_submission = (
		session.query(TaskSubmission.submission_number)
		.filter(TaskSubmission.task_id == task_id, TaskSubmission.child_id == child.id)
		.order_by(TaskSubmission.submission_number.desc())
		.first()
	)
	submission = TaskSubmission(
		task_id=task_id,
		child_id=child.id,
		submission_number=(last_submission[0] + 1) if last_submission else 1,
		proof_type=request.proof_type,
		proof_url=proof_url(request.proof_upload_id)
		if request.proof_upload_id
		else (str(request.proof_url) if request.proof_url else None),
		proof_note=request.proof_note,
		status="pending",
		submitted_at=utc_naive(datetime.now(timezone.utc)),
	)
	session.add(submission)
	session.flush()
	if request.proof_upload_id:
		claim_upload_for_submission(session, child, request.proof_upload_id, submission.id)
	for parent_id in family_parent_ids(session, task.family_id):
		create_notification(
			session,
			parent_id,
			"task_submitted",
			"Task submitted for review",
			f"{child.display_name} submitted {task.title}.",
			task_id=task.id,
			submission_id=submission.id,
		)
	try:
		session.commit()
		session.refresh(submission)
	except Exception:
		session.rollback()
		raise
	return submission


def review_submission(session: Session, submission_id: UUID, reviewer, request: TaskReviewCreate):
	TaskSubmission = get_model("TaskSubmission")
	Task = get_model("Task")
	FamilyMember = get_model("FamilyMember")
	TaskReview = get_model("TaskReview")
	submission = (
		session.query(TaskSubmission)
		.filter(TaskSubmission.id == submission_id)
		.with_for_update()
		.one_or_none()
	)
	if submission is None:
		raise APIError(404, "submission_not_found", "Task submission not found")
	task = session.query(Task).filter(Task.id == submission.task_id).with_for_update().one()
	authorized = (
		session.query(FamilyMember.id)
		.filter(
			FamilyMember.family_id == task.family_id,
			FamilyMember.user_id == reviewer.id,
			FamilyMember.is_active.is_(True),
		)
		.first()
	)
	if authorized is None:
		raise APIError(404, "submission_not_found", "Task submission not found")
	if submission.status != "pending":
		raise APIError(409, "submission_already_reviewed", "This submission has already been reviewed")

	now = utc_naive(datetime.now(timezone.utc))
	submission.status = request.decision
	submission.reviewed_at = now
	session.add(
		TaskReview(
			submission_id=submission.id,
			reviewed_by=reviewer.id,
			decision=request.decision,
			review_note=request.review_note,
			created_at=now,
		)
	)
	if request.decision == "approved":
		ChildProfile = get_model("ChildProfile")
		child = session.query(ChildProfile).filter(ChildProfile.id == submission.child_id).with_for_update().one()
		if task.star_reward:
			StarTransaction = get_model("StarTransaction")
			session.add(
				StarTransaction(
					child_id=child.id,
					amount=task.star_reward,
					transaction_type="task_approved",
					submission_id=submission.id,
					idempotency_key=f"task-approved:{submission.id}:stars",
					description=f"Approved task: {task.title}",
				)
			)
		if task.xp_reward:
			XPTransaction = get_model("XPTransaction")
			session.add(
				XPTransaction(
					child_id=child.id,
					amount=task.xp_reward,
					submission_id=submission.id,
					reason="task_approved",
					idempotency_key=f"task-approved:{submission.id}:xp",
				)
			)
			ChildProgress = get_model("ChildProgress")
			progress_insert = pg_insert(ChildProgress).values(
				child_id=child.id,
				total_xp=task.xp_reward,
				garden_progress={},
				updated_at=now,
			)
			session.execute(
				progress_insert.on_conflict_do_update(
					index_elements=[ChildProgress.child_id],
					set_={
						"total_xp": ChildProgress.total_xp + task.xp_reward,
						"updated_at": now,
					},
				)
			)
			total_xp = session.query(ChildProgress.total_xp).filter(ChildProgress.child_id == child.id).scalar()
			Level = get_model("Level")
			level = (
				session.query(Level)
				.filter(Level.minimum_xp <= total_xp)
				.order_by(Level.minimum_xp.desc())
				.first()
			)
			if level:
				session.query(ChildProgress).filter(ChildProgress.child_id == child.id).update(
					{ChildProgress.current_level_id: level.id}
				)
				child.current_level_id = level.id

		activity_date = local_today(session, task.family_id)
		ChildActivityDay = get_model("ChildActivityDay")
		activity_insert = pg_insert(ChildActivityDay).values(
			child_id=child.id,
			activity_date=activity_date,
			completed_tasks=1,
			stars_earned=task.star_reward,
			xp_earned=task.xp_reward,
			created_at=now,
		)
		session.execute(
			activity_insert.on_conflict_do_update(
				index_elements=[ChildActivityDay.child_id, ChildActivityDay.activity_date],
				set_={
					"completed_tasks": ChildActivityDay.completed_tasks + 1,
					"stars_earned": ChildActivityDay.stars_earned + task.star_reward,
					"xp_earned": ChildActivityDay.xp_earned + task.xp_reward,
				},
			)
		)
		session.flush()
		Badge = get_model("Badge")
		ChildBadge = get_model("ChildBadge")
		ChildStreak = get_model("ChildStreak")
		approved_tasks = session.query(func.count(TaskSubmission.id)).filter(
			TaskSubmission.child_id == child.id,
			TaskSubmission.status == "approved",
		).scalar()
		streak = session.query(ChildStreak).filter(ChildStreak.child_id == child.id).one_or_none()
		yesterday = activity_date - timedelta(days=1)
		if streak is None:
			current_streak = 1
		elif streak.last_activity_date == activity_date:
			current_streak = streak.current_streak
		elif streak.last_activity_date == yesterday:
			current_streak = streak.current_streak + 1
		else:
			current_streak = 1
		criteria_values = {
			"approved_tasks": int(approved_tasks or 0),
			"total_stars": star_balance(session, child.id),
			"total_xp": xp_total(session, child.id),
			"current_streak": current_streak,
		}
		unlocked_ids = {
			badge_id
			for (badge_id,) in session.query(ChildBadge.badge_id).filter(ChildBadge.child_id == child.id).all()
		}
		for badge in session.query(Badge).filter(Badge.is_active.is_(True)).all():
			if badge_qualifies(badge.criteria_type, badge.criteria_value, criteria_values) and badge.id not in unlocked_ids:
				session.add(ChildBadge(child_id=child.id, badge_id=badge.id, unlocked_at=now))
				create_notification(
					session,
					child.user_id,
					"badge_unlocked",
					"New badge unlocked",
					f"You earned {badge.name}.",
					now=now,
				)
		streak_insert = pg_insert(ChildStreak).values(
			child_id=child.id,
			current_streak=1,
			longest_streak=1,
			last_activity_date=activity_date,
			updated_at=now,
		)
		next_streak = case(
			(ChildStreak.last_activity_date == activity_date, ChildStreak.current_streak),
			(ChildStreak.last_activity_date == yesterday, ChildStreak.current_streak + 1),
			else_=1,
		)
		session.execute(
			streak_insert.on_conflict_do_update(
				index_elements=[ChildStreak.child_id],
				set_={
					"current_streak": next_streak,
					"longest_streak": func.greatest(ChildStreak.longest_streak, next_streak),
					"last_activity_date": activity_date,
					"updated_at": now,
				},
			)
		)

	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(ChildProfile.id == submission.child_id).one()
	create_notification(
		session,
		child.user_id,
		f"task_{request.decision}",
		"Task reviewed",
		request.review_note or f"Your task was {request.decision.replace('_', ' ')}.",
		task_id=task.id,
		submission_id=submission.id,
		now=now,
	)
	try:
		session.commit()
		session.refresh(submission)
	except Exception:
		session.rollback()
		raise
	return submission
