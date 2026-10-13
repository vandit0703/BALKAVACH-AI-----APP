from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.services.timezone_service import (
	family_timezone_name,
	local_day_bounds_utc_naive,
	parse_timezone,
)
from app.utils import utc_aware


def weekly_report(session: Session, child, weeks_back: int = 0) -> dict:
	"""Monday-to-Sunday report in the family's timezone, built only from approved reviews."""
	zone_name = family_timezone_name(session, child.family_id)
	zone = parse_timezone(zone_name)
	today = datetime.now(timezone.utc).astimezone(zone).date()
	week_start = today - timedelta(days=today.weekday()) - timedelta(weeks=weeks_back)
	week_end = week_start + timedelta(days=6)
	start_utc, end_utc = local_day_bounds_utc_naive(zone, week_start, 7)

	TaskSubmission = get_model("TaskSubmission")
	Task = get_model("Task")
	TaskCategory = get_model("TaskCategory")
	approved = (
		session.query(TaskSubmission.reviewed_at, Task.title, Task.star_reward, Task.xp_reward, TaskCategory.id, TaskCategory.name)
		.join(Task, Task.id == TaskSubmission.task_id)
		.outerjoin(TaskCategory, TaskCategory.id == Task.category_id)
		.filter(
			TaskSubmission.child_id == child.id,
			TaskSubmission.status == "approved",
			TaskSubmission.reviewed_at >= start_utc,
			TaskSubmission.reviewed_at < end_utc,
		)
		.order_by(TaskSubmission.reviewed_at.desc())
		.all()
	)

	days = {week_start + timedelta(days=i): {"completed_tasks": 0, "stars_earned": 0, "xp_earned": 0} for i in range(7)}
	categories: dict[str, dict] = {}
	recent = []
	for reviewed_at, title, stars, xp, category_id, category_name in approved:
		local_day = utc_aware(reviewed_at).astimezone(zone).date()
		bucket = days[local_day]
		bucket["completed_tasks"] += 1
		bucket["stars_earned"] += stars
		bucket["xp_earned"] += xp
		key = str(category_id) if category_id else "uncategorised"
		entry = categories.setdefault(
			key,
			{
				"category_id": category_id,
				"name": category_name or "Uncategorised",
				"completed_tasks": 0,
				"stars_earned": 0,
				"xp_earned": 0,
			},
		)
		entry["completed_tasks"] += 1
		entry["stars_earned"] += stars
		entry["xp_earned"] += xp
		if len(recent) < 10:
			recent.append({"title": title, "reviewed_at": utc_aware(reviewed_at), "stars_earned": stars, "xp_earned": xp})

	counts = dict(
		session.query(TaskSubmission.status, func.count(TaskSubmission.id))
		.filter(
			TaskSubmission.child_id == child.id,
			TaskSubmission.status.in_(["pending", "rejected", "resubmission_requested"]),
			TaskSubmission.submitted_at >= start_utc,
			TaskSubmission.submitted_at < end_utc,
		)
		.group_by(TaskSubmission.status)
		.all()
	)
	pending_now = (
		session.query(func.count(TaskSubmission.id))
		.filter(TaskSubmission.child_id == child.id, TaskSubmission.status == "pending")
		.scalar()
	)
	ChildStreak = get_model("ChildStreak")
	streak = session.query(ChildStreak).filter(ChildStreak.child_id == child.id).one_or_none()
	return {
		"child_id": child.id,
		"timezone": zone_name,
		"period_start": week_start,
		"period_end": week_end,
		"totals": {
			"completed_tasks": sum(d["completed_tasks"] for d in days.values()),
			"stars_earned": sum(d["stars_earned"] for d in days.values()),
			"xp_earned": sum(d["xp_earned"] for d in days.values()),
		},
		"days": [{"date": day, **values} for day, values in days.items()],
		"categories": sorted(categories.values(), key=lambda c: (-c["completed_tasks"], c["name"])),
		"pending_submissions": int(pending_now or 0),
		"rejected_submissions": int(counts.get("rejected", 0) + counts.get("resubmission_requested", 0)),
		"current_streak": streak.current_streak if streak else 0,
		"longest_streak": streak.longest_streak if streak else 0,
		"recent_approved": recent,
	}
