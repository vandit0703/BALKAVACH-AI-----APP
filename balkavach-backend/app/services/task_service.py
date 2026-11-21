import functools
import logging
from datetime import date, datetime, timezone
from uuid import UUID

from sqlalchemy import case, func
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.task import TaskReviewCreate, TaskSubmissionCreate
from app.services.child_age import ensure_task_age_eligible
from app.services.ledger_service import star_balance, xp_total
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from app.services.notification_service import create_notification, family_parent_ids
from app.services.progress_service import badge_qualifies
from app.services.timezone_service import local_date_of
from app.services.upload_service import claim_upload_for_submission, proof_url
from app.services.video_entitlement_service import missing_mission_allowance_columns
from app.utils import utc_naive

logger = logging.getLogger(__name__)


def submit_completion(session: Session, task_id: UUID, child, request: TaskSubmissionCreate):
	Task = get_model("Task")
	TaskSubmission = get_model("TaskSubmission")
	task = session.query(Task).filter(Task.id == task_id, Task.is_active.is_(True)).with_for_update().one_or_none()
	if task is None or task.family_id != child.family_id:
		raise APIError(404, "task_not_found", "Task not found")
	if task.assigned_child_id is not None and task.assigned_child_id != child.id:
		raise APIError(403, "task_not_assigned", "Task is assigned to another child")
	# A daily mission made for another age group (see child_age) cannot be completed as a current mission.
	ensure_task_age_eligible(session, child, task.id)

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
	DailyMissionAssignment = get_model("DailyMissionAssignment")
	daily_assignment = (
		session.query(DailyMissionAssignment)
		.filter(
			DailyMissionAssignment.task_id == task.id,
			DailyMissionAssignment.child_id == child.id,
			DailyMissionAssignment.is_current.is_(True),
		)
		.with_for_update()
		.one_or_none()
	)
	if daily_assignment is not None:
		daily_assignment.status = "pending_parent_approval"
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


def submission_activity_date(session: Session, family_id: UUID, submission, fallback: datetime) -> date:
	"""The family-local day the child *did* the mission: the day of the submission, never of the approval.

	Derived from the server-stamped ``submitted_at`` (the client never supplies a date), so a late parent
	approval cannot move the activity to another day and a child cannot backdate or forward-date it. A
	rejected mission that is resubmitted has a new submission, hence the day of the resubmission.
	"""
	return local_date_of(session, family_id, submission.submitted_at or fallback)


def _all_or_nothing(review):
	"""Run a review as one transaction: any failure rolls everything back and raises a named, safe error.

	The decision, the review row, stars, XP, the video allowance and the notifications commit together or
	not at all, so a mission is never left approved without its rewards (or rewarded without being approved).
	"""

	@functools.wraps(review)
	def run(session: Session, submission_id: UUID, reviewer, request: TaskReviewCreate):
		try:
			return review(session, submission_id, reviewer, request)
		except APIError:
			session.rollback()
			raise
		except Exception as error:  # noqa: BLE001 - nothing may be half written, whatever failed
			session.rollback()
			logger.exception(
				"Mission approval failed and was rolled back (submission %s, decision %s): %s",
				submission_id,
				request.decision,
				type(error).__name__,
			)
			raise APIError(
				500,
				"approval_failed",
				"The approval could not be saved. Nothing was awarded. Please try again.",
			) from error

	return run


@_all_or_nothing
def review_submission(session: Session, submission_id: UUID, reviewer, request: TaskReviewCreate):
	"""Approve, decline or ask to retry a submission (all-or-nothing, see ``_all_or_nothing``).

	Repeating a decision that was already applied returns that result unchanged: the parent's first
	response may have been lost, and a retry must not pay twice.
	"""
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
		if submission.status == request.decision:
			# Already applied (a retry after a lost response): report the existing result, change nothing.
			session.rollback()
			return submission
		raise APIError(409, "submission_already_reviewed", "This submission has already been reviewed")
	if request.decision == "approved":
		missing = missing_mission_allowance_columns()
		if missing:
			# Fail before writing anything: an approval must pay all three rewards or none.
			logger.critical(
				"Mission approval refused: the database lacks the video allowance schema (%s). "
				"Apply migration 0013_mission_video_entitlement.",
				", ".join(missing),
			)
			raise APIError(
				503,
				"video_allowance_unavailable",
				"Video time cannot be granted right now, so this mission was not approved. Nothing was awarded.",
			)

	approved_at = datetime.now(timezone.utc)  # one instant for every write this approval makes
	now = utc_naive(approved_at)
	submission.status = request.decision
	submission.reviewed_at = now  # the real approval time; the activity day is derived from submitted_at
	DailyMissionAssignment = get_model("DailyMissionAssignment")
	daily_assignment = (
		session.query(DailyMissionAssignment)
		.filter(
			DailyMissionAssignment.task_id == task.id,
			DailyMissionAssignment.child_id == submission.child_id,
			DailyMissionAssignment.is_current.is_(True),
		)
		.with_for_update()
		.one_or_none()
	)
	if daily_assignment is not None:
		daily_assignment.status = "approved" if request.decision == "approved" else "rejected"
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
		# One standard reward for every approved mission (see mission_rewards). The stored task values and any
		# template "mystery bonus" are not paid any more: a mission earns exactly these amounts, once per
		# approved submission (the submission was locked and is no longer pending after this transaction, and
		# the ledger idempotency keys are per submission).
		stars_awarded = MISSION_STAR_REWARD
		xp_awarded = MISSION_XP_REWARD
		StarTransaction = get_model("StarTransaction")
		session.add(
			StarTransaction(
				child_id=child.id,
				amount=stars_awarded,
				transaction_type="task_approved",
				submission_id=submission.id,
				idempotency_key=f"task-approved:{submission.id}:stars",
				description=f"Approved task: {task.title}",
			)
		)
		XPTransaction = get_model("XPTransaction")
		session.add(
			XPTransaction(
				child_id=child.id,
				amount=xp_awarded,
				submission_id=submission.id,
				reason="task_approved",
				idempotency_key=f"task-approved:{submission.id}:xp",
			)
		)
		ChildProgress = get_model("ChildProgress")
		progress_insert = pg_insert(ChildProgress).values(
			child_id=child.id,
			total_xp=xp_awarded,
			garden_progress={},
			updated_at=now,
		)
		session.execute(
			progress_insert.on_conflict_do_update(
				index_elements=[ChildProgress.child_id],
				set_={
					"total_xp": ChildProgress.total_xp + xp_awarded,
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

		activity_date = submission_activity_date(session, task.family_id, submission, now)
		ChildActivityDay = get_model("ChildActivityDay")
		activity_insert = pg_insert(ChildActivityDay).values(
			child_id=child.id,
			activity_date=activity_date,
			completed_tasks=1,
			stars_earned=stars_awarded,
			xp_earned=xp_awarded,
			created_at=now,
		)
		session.execute(
			activity_insert.on_conflict_do_update(
				index_elements=[ChildActivityDay.child_id, ChildActivityDay.activity_date],
				set_={
					"completed_tasks": ChildActivityDay.completed_tasks + 1,
					"stars_earned": ChildActivityDay.stars_earned + stars_awarded,
					"xp_earned": ChildActivityDay.xp_earned + xp_awarded,
				},
			)
		)
		session.flush()
		Badge = get_model("Badge")
		ChildBadge = get_model("ChildBadge")
		approved_tasks = session.query(func.count(TaskSubmission.id)).filter(
			TaskSubmission.child_id == child.id,
			TaskSubmission.status == "approved",
		).scalar()
		from app.services.streak_service import record_qualifying_activity
		from app.services.notification_service import notify_streak_event

		# The streak service is the only streak writer; badges read its result (no second calculation).
		streak_result = record_qualifying_activity(
			session, child.id, task.family_id, now_utc=approved_at, activity_date=activity_date
		)
		current_streak = streak_result["current_streak"]
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
		if streak_result.get("is_new_after_break"):
			notify_streak_event(
				session,
				child.user_id,
				"streak_new_after_break",
				streak_result["current_streak"],
			)
		elif streak_result.get("streak_extended"):
			c_streak = streak_result["current_streak"]
			if c_streak in {3, 7, 14, 30, 50, 100, 365} or (c_streak > 0 and c_streak % 100 == 0):
				notify_streak_event(
					session, child.user_id, "streak_milestone", c_streak
				)
			else:
				notify_streak_event(
					session, child.user_id, "streak_continued", c_streak
				)

		from app.services.video_entitlement_service import grant_mission_video_entitlement
		from app.services.notification_service import notify_video_entitlement_event

		entitlement = grant_mission_video_entitlement(
			session, child, task, submission, now_utc=approved_at
		)
		if entitlement and (entitlement.granted_seconds or 0) > 0:
			notify_video_entitlement_event(
				session,
				child.user_id,
				"mission_video_time_granted",
				minutes_granted=(entitlement.granted_seconds or 0) // 60,
				task_id=task.id,
				submission_id=submission.id,
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
