"""Operator commands. Run from ``balkavach-backend`` with:

    python -m app.cli create-admin

Email, name, and password are entered interactively. Passwords are read with
getpass and are never accepted from arguments or environment variables.
"""

import argparse
import getpass
import json
import sys
import uuid
from contextlib import contextmanager

from pydantic import ValidationError
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from app.core.permissions import expand_permissions
from app.core.security import hash_password
from app.db.base import get_model
from app.schemas.auth import RegistrationRequest

SUPER_ADMIN_ROLE = "super_admin"
REQUIRED_ADMIN_PERMISSIONS = frozenset(
	{
		"dashboard:read",
		"users:read",
		"users:write",
		"families:read",
		"families:write",
		"tasks:read",
		"tasks:write",
		"rewards:read",
		"rewards:write",
		"redemptions:read",
		"content:read",
		"content:write",
		"video:read",
		"video:write",
		"badges:read",
		"badges:write",
		"settings:read",
		"settings:write",
		"reports:read",
		"audit:read",
		"admin_roles:read",
		"admin_roles:write",
	}
)


def _validated_details(email: str, name: str, password: str) -> tuple[str, str, str]:
	try:
		request = RegistrationRequest(
			full_name=name.strip(),
			email=email.strip(),
			password=password,
		)
	except ValidationError as error:
		fields = {str(issue["loc"][0]) for issue in error.errors() if issue.get("loc")}
		if "email" in fields:
			raise ValueError("Enter a valid email address") from None
		if "full_name" in fields:
			raise ValueError("Name must be between 2 and 160 characters") from None
		raise ValueError("Password must be between 12 and 128 characters") from None
	return str(request.email).strip().lower(), request.full_name.strip(), request.password


def _missing_admin_permissions(role) -> set[str]:
	granted = expand_permissions(role.permissions)
	if "*" in granted:
		return set()
	return REQUIRED_ADMIN_PERMISSIONS - granted


def existing_admin_status(session: Session, email: str, role_name: str = SUPER_ADMIN_ROLE) -> str | None:
	"""Describe an existing account without changing it."""
	User = get_model("User")
	user = session.query(User).filter(User.email == email).one_or_none()
	if user is None:
		return None

	account_state = "active" if user.is_active else "inactive"
	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	role = session.query(AdminRole).filter(AdminRole.name == role_name).one_or_none()
	if role is None:
		return f"Account {email} already exists as {user.role} ({account_state}), but required role {role_name!r} is absent; no changes were made."

	assignment = (
		session.query(UserAdminRole.user_id)
		.filter(UserAdminRole.user_id == user.id, UserAdminRole.admin_role_id == role.id)
		.first()
	)
	if assignment is None:
		return f"Account {email} already exists as {user.role} ({account_state}) without role {role_name!r}; it was not changed."

	missing = _missing_admin_permissions(role)
	if missing:
		return (
			f"Account {email} already has role {role_name!r}, but that role lacks required permissions: "
			f"{', '.join(sorted(missing))}. No changes were made."
		)
	if user.role not in {"admin", "staff"}:
		return (
			f"Account {email} has role assignment {role_name!r}, but its account type is {user.role} "
			f"({account_state}) and cannot authenticate as an administrator; no changes were made."
		)
	return f"Account {email} already has full {role_name} access ({account_state}); no changes were made."


def create_admin(session: Session, email: str, name: str, password: str, role_name: str = SUPER_ADMIN_ROLE):
	"""Atomically create a new admin and assign an existing full-admin role."""
	email, name, password = _validated_details(email, name, password)

	try:
		User = get_model("User")
		AdminRole = get_model("AdminRole")
		UserAdminRole = get_model("UserAdminRole")
		if session.query(User.id).filter(User.email == email).first():
			raise ValueError("An account with that email already exists")

		role = session.query(AdminRole).filter(AdminRole.name == role_name).one_or_none()
		if role is None:
			raise ValueError(
				f"Required role {role_name!r} is absent. Have a database administrator provision the approved "
				"full-administration role; this command will not create roles or change the schema."
			)
		missing = _missing_admin_permissions(role)
		if missing:
			raise ValueError(
				f"Role {role_name!r} lacks required admin permissions: {', '.join(sorted(missing))}. "
				"No account was created; have a database administrator review the existing role."
			)

		user = User(
			full_name=name,
			email=email,
			password_hash=hash_password(password),
			role="admin",
			preferred_language="en",
			is_active=True,
		)
		session.add(user)
		session.flush()

		assignment_exists = (
			session.query(UserAdminRole.user_id)
			.filter(UserAdminRole.user_id == user.id, UserAdminRole.admin_role_id == role.id)
			.first()
		)
		if assignment_exists is not None:
			raise ValueError("The administrator role is already assigned; no duplicate assignment was created")
		session.add(UserAdminRole(user_id=user.id, admin_role_id=role.id))
		session.flush()
		session.commit()
		return user
	except Exception:
		session.rollback()
		raise


def _record_recheck_failure(session_factory, code: str) -> None:
	"""Leave a durable trace that a scheduled recheck ran and failed (best effort: never masks the failure)."""
	from app.services.admin_service import record_audit

	try:
		with session_factory() as session:
			record_audit(session, None, "youtube.recheck.failed", "youtube_pipeline", None, {"code": code})
			session.commit()
	except Exception:  # noqa: BLE001 - the original error is what the operator needs to see
		print("Could not record the recheck failure in the audit log.", file=sys.stderr)


@contextmanager
def _read_only(session: Session):
	"""Make this session unable to write, enforced by the database, for the read-only commands.

	PostgreSQL: ``SET TRANSACTION READ ONLY`` (any INSERT/UPDATE/DELETE then fails). SQLite (tests):
	``PRAGMA query_only``. The transaction is rolled back on exit, which also ends the read-only mode.
	"""
	dialect = session.get_bind().dialect.name
	if dialect == "postgresql":
		session.execute(text("SET TRANSACTION READ ONLY"))
	elif dialect == "sqlite":
		session.execute(text("PRAGMA query_only = ON"))
	try:
		yield session
	finally:
		session.rollback()
		if dialect == "sqlite":
			session.execute(text("PRAGMA query_only = OFF"))


def _youtube_recheck(session_factory, limit: int) -> int:
	"""Re-verify approved videos. Idempotent and safe to repeat or to overlap (``FOR UPDATE SKIP LOCKED``).

	Prints one summary line on success (``checked=N, verified=N, ...``). On failure the error goes to
	stderr, a ``youtube.recheck.failed`` audit row is written, and the exit code is non-zero so the
	scheduler marks the run failed; work already committed (videos re-verified before the failure) is kept
	and the next run continues with the oldest remaining.
	"""
	from app.core.exceptions import APIError
	from app.integrations.youtube import get_youtube_client
	from app.services.youtube_review_service import recheck

	try:
		with session_factory() as session:
			counts = recheck(session, get_youtube_client(), limit)
	except APIError as error:
		print(f"Error: {error.message} ({error.code})", file=sys.stderr)
		_record_recheck_failure(session_factory, error.code)
		return 1
	except SQLAlchemyError:
		print("Database operation failed during YouTube recheck.", file=sys.stderr)
		return 2
	print(", ".join(f"{key}={value}" for key, value in counts.items()))
	return 0


def _recheck_health(session_factory, max_age_hours: float) -> int:
	"""Read-only monitor for the recheck job: exit 0 healthy, 3 unhealthy, 2 database error.

	Unhealthy means approved videos have no recent completed recheck run on record or the latest recheck failed.
	Old verification age alone does not hide approved feed videos, but recheck should still run regularly to refresh
	metadata and availability. Point a scheduler or uptime monitor at it so a job that stopped running is noticed.
	"""
	from datetime import datetime, timezone

	from app.services.youtube_review_service import diagnostics

	try:
		with session_factory() as session, _read_only(session):
			info = diagnostics(session)
			session.rollback()
	except SQLAlchemyError:
		print("Database read failed.", file=sys.stderr)
		return 2
	problems: list[str] = []
	last_run = info.get("last_recheck_run")
	age_hours = None if last_run is None else (datetime.now(timezone.utc) - last_run).total_seconds() / 3600
	if info["approved_stale"]:
		problems.append(f"{info['approved_stale']} approved video(s) are past the {info['reverify_hours']} h window")
	if info["approved"] and (age_hours is None or age_hours > max_age_hours):
		problems.append(
			"no completed recheck on record"
			if age_hours is None
			else f"last completed recheck was {age_hours:.1f} h ago (limit {max_age_hours:g} h)"
		)
	if info.get("last_recheck_failure") and (last_run is None or info["last_recheck_failure"] > last_run):
		problems.append(f"the last recheck failed ({info.get('last_recheck_failure_code')})")
	print(
		json.dumps(
			{
				"healthy": not problems,
				"problems": problems,
				"approved": info["approved"],
				"approved_not_recently_verified": info.get("approved_stale", 0),
				"approved_stale": info.get("approved_stale", 0),
				"last_recheck_run": last_run,
				"oldest_approved_verification": info["oldest_approved_verification"],
			},
			sort_keys=True,
			default=str,
		)
	)
	return 0 if not problems else 3


def _video_feed_diagnose(session_factory, *, child_id, age, language: str) -> int:
	"""Read-only: which feed rule removes the videos, for one child or for an age and language."""
	from app.services.video_feed_diagnostics import diagnose

	try:
		with session_factory() as session, _read_only(session):
			report = diagnose(session, child_id=child_id, age=age, language=language)
			session.rollback()  # nothing was written; make that explicit
	except SQLAlchemyError:
		print("Database read failed.", file=sys.stderr)
		return 2
	print(json.dumps(report, indent=2, sort_keys=True, default=str))
	return 1 if report.get("error") else 0


def _youtube_discover(session_factory, max_results: int) -> int:
	from app.core.config import settings
	from app.core.exceptions import APIError
	from app.integrations.youtube import DISCOVERY_TOPICS, get_youtube_client
	from app.schemas.video import YouTubeDiscoverRequest
	from app.services.youtube_review_service import discover, discover_trusted

	topics = list(dict.fromkeys(settings.youtube_discovery_topics))
	unknown = sorted(set(topics) - DISCOVERY_TOPICS.keys())
	if unknown:
		print(f"Unknown YOUTUBE_DISCOVERY_TOPICS entries: {', '.join(unknown)}", file=sys.stderr)
		return 1
	if not topics:
		print("YOUTUBE_DISCOVERY_TOPICS must include at least one curated topic.", file=sys.stderr)
		return 1
	if settings.youtube_discovery_actor_id is None:
		print("YOUTUBE_DISCOVERY_ACTOR_ID must identify an active administrator.", file=sys.stderr)
		return 1
	try:
		with session_factory() as session:
			actor = _youtube_discovery_actor(session, settings.youtube_discovery_actor_id)
			if actor is None:
				print(
					"YOUTUBE_DISCOVERY_ACTOR_ID must identify an active administrator with video:write permission.",
					file=sys.stderr,
				)
				return 1
			client = get_youtube_client()
			totals = {
				"created": 0,
				"skipped_existing": 0,
				"skipped_unplayable": 0,
				"automatically_published": 0,
				"quarantined": 0,
			}
			for topic in topics:
				result = discover(
					session,
					actor,
					client,
					YouTubeDiscoverRequest(
						topic=topic,
						region_code=settings.youtube_region_code,
						max_results=max_results,
					),
					auto_publish=True,
				)
				for key in totals:
					if key in result:
						totals[key] += len(result["created"]) if key == "created" else result[key]
			trusted_totals = discover_trusted(session, actor, client, max_results)
			for key, value in trusted_totals.items():
				totals[key] += value
			from app.services.youtube_review_service import auto_review

			reviewed = auto_review(session, actor, client, limit=200)
			totals["auto_approved"] = reviewed["auto_approved"]
			totals["needs_manual_review"] = reviewed["needs_manual_review"]
			totals["quarantined"] += reviewed["newly_quarantined"]
			from app.services.admin_service import record_audit
			record_audit(session, actor.id, "youtube.discovery.completed", "youtube_pipeline", None, totals)
			session.commit()
	except APIError as error:
		print(f"Error: {error.message}", file=sys.stderr)
		return 1
	except SQLAlchemyError:
		print("Database operation failed during YouTube discovery.", file=sys.stderr)
		return 2
	print(", ".join(f"{key}={value}" for key, value in totals.items()))
	return 0


def _streak_check(session_factory) -> int:
	"""Check and update daily streak states and deliver grace period notifications."""
	import logging
	from datetime import datetime, timezone
	from app.db.base import get_model
	from app.services.notification_service import notify_streak_event
	from app.services.streak_service import check_and_update_streak_states
	from app.utils import utc_aware

	logger = logging.getLogger("app.cli.streak_check")
	try:
		with session_factory() as session:
			changes = check_and_update_streak_states(session, child_ids=None)
			logger.info("check_and_update_streak_states found %d changed row(s)", len(changes))

			ChildProfile = get_model("ChildProfile")
			ChildStreak = get_model("ChildStreak")
			now = datetime.now(timezone.utc)

			notifications_sent = 0
			for change in changes:
				child_id = change["child_id"]
				old_state = change["old_state"]
				new_state = change["new_state"]

				# at_risk -> broken: no notification (streak already gone)
				if new_state == "broken":
					continue

				child = session.query(ChildProfile).filter(ChildProfile.id == child_id).first()
				if not child:
					continue
				streak = session.query(ChildStreak).filter(ChildStreak.child_id == child_id).first()
				current_streak = streak.current_streak if streak else 1

				if old_state == "active" and new_state == "at_risk":
					is_one_day_left = False
					if streak and streak.grace_deadline:
						seconds_left = (utc_aware(streak.grace_deadline) - now).total_seconds()
						if 0 < seconds_left <= 86400:
							is_one_day_left = True

					event = "streak_one_day_left" if is_one_day_left else "streak_at_risk"
					notif = notify_streak_event(session, child.user_id, event, current_streak)
					if notif:
						notifications_sent += 1

			# Also check already at_risk streaks with <= 1 day left
			at_risk_streaks = (
				session.query(ChildStreak)
				.filter(
					ChildStreak.streak_state == "at_risk",
					ChildStreak.grace_deadline.isnot(None),
				)
				.all()
			)
			for streak in at_risk_streaks:
				seconds_left = (utc_aware(streak.grace_deadline) - now).total_seconds()
				if 0 < seconds_left <= 86400:
					child = session.query(ChildProfile).filter(ChildProfile.id == streak.child_id).first()
					if child:
						notif = notify_streak_event(
							session,
							child.user_id,
							"streak_one_day_left",
							streak.current_streak or 1,
						)
						if notif:
							notifications_sent += 1

			session.commit()
			from app.services import push_service

			push_service.deliver_ready(session)
			print(
				f"Streak check complete: {len(changes)} state change(s), {notifications_sent} notification(s) sent."
			)
			return 0
	except SQLAlchemyError:
		print("Database operation failed during streak check.", file=sys.stderr)
		return 2
	except Exception as err:
		print(f"Error during streak check: {err}", file=sys.stderr)
		return 1


def _daily_missions_notify(session_factory, *, from_hour: int, to_hour: int) -> int:
	"""Once per family-local day, tell each active child that new missions are ready.

	Only runs for families whose local time is within [from_hour, to_hour), so nobody is notified at night.
	Re-running is safe: ``notify_daily_missions_ready`` skips a child who already has today's notification."""
	from datetime import datetime, timezone

	from app.db.base import get_model
	from app.services import push_service
	from app.services.notification_service import notify_daily_missions_ready
	from app.services.timezone_service import family_timezone_name, parse_timezone

	try:
		with session_factory() as session:
			ChildProfile = get_model("ChildProfile")
			User = get_model("User")
			now = datetime.now(timezone.utc)
			children = (
				session.query(ChildProfile)
				.join(User, User.id == ChildProfile.user_id)
				.filter(User.is_active.is_(True))
				.all()
			)
			zones: dict = {}
			sent = skipped = 0
			for child in children:
				if child.family_id not in zones:
					zones[child.family_id] = parse_timezone(family_timezone_name(session, child.family_id))
				if not from_hour <= now.astimezone(zones[child.family_id]).hour < to_hour:
					skipped += 1
					continue
				if notify_daily_missions_ready(session, child, now) is not None:
					sent += 1
			session.commit()
			push_service.deliver_ready(session)
			print(f"Daily missions notify complete: {sent} sent, {skipped} outside the daytime window.")
			return 0
	except SQLAlchemyError:
		print("Database operation failed during daily missions notify.", file=sys.stderr)
		return 2


def _youtube_auto_review(session_factory, limit: int) -> int:
	from app.core.config import settings
	from app.core.exceptions import APIError
	from app.integrations.youtube import get_youtube_client
	from app.services.youtube_review_service import auto_review

	if settings.youtube_discovery_actor_id is None:
		print("YOUTUBE_DISCOVERY_ACTOR_ID must identify an active administrator.", file=sys.stderr)
		return 1
	try:
		with session_factory() as session:
			actor = _youtube_discovery_actor(session, settings.youtube_discovery_actor_id)
			if actor is None:
				print("YOUTUBE_DISCOVERY_ACTOR_ID must identify an active administrator with video:write permission.", file=sys.stderr)
				return 1
			result = auto_review(session, actor, get_youtube_client(), limit)
	except APIError as error:
		print(f"Error: {error.message}", file=sys.stderr)
		return 1
	except SQLAlchemyError:
		print("Database operation failed during YouTube auto-review.", file=sys.stderr)
		return 2
	print(json.dumps(result, indent=2, sort_keys=True))
	return 1 if result["error"] else 0


def _youtube_report(session_factory) -> int:
	"""Read-only: status counts and the reason each unapproved video is waiting."""
	from app.db.base import get_model as model
	from app.services.youtube_review_service import diagnostics

	try:
		with session_factory() as session, _read_only(session):
			summary = diagnostics(session)
			Review, Video = model("YouTubeContentReview"), model("Video")
			rows = (
				session.query(Review, Video)
				.join(Video, Video.id == Review.video_id)
				.filter(Review.status.in_(["pending_review", "quarantined", "unavailable", "rejected", "revoked"]))
				.order_by(Review.status, Review.discovered_at)
				.all()
			)
			waiting = [
				{
					"youtube_video_id": review.youtube_video_id,
					"status": review.status,
					"flags": list(review.screening_flags or []),
					"made_for_kids": review.made_for_kids,
					"duration_seconds": video.duration_seconds,
					"reviewed_by_admin": review.reviewed_by is not None,
					"reason": review.publication_reason or review.review_notes or review.revoked_reason,
				}
				for review, video in rows
			]
			session.rollback()
	except SQLAlchemyError:
		print("Database read failed.", file=sys.stderr)
		return 2
	print(json.dumps({"summary": summary, "waiting": waiting}, indent=2, sort_keys=True, default=str))
	return 0


def _youtube_discovery_actor(session: Session, actor_id):
	User = get_model("User")
	actor = session.query(User).filter(
		User.id == actor_id,
		User.role.in_(["admin", "staff"]),
		User.is_active.is_(True),
	).one_or_none()
	if actor is None:
		return None

	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	assignments = (
		session.query(AdminRole.permissions)
		.join(UserAdminRole, UserAdminRole.admin_role_id == AdminRole.id)
		.filter(UserAdminRole.user_id == actor.id)
		.all()
	)
	granted: set[str] = set()
	for (permissions,) in assignments:
		granted |= expand_permissions(permissions)
	if "video:write" not in granted and "*" not in granted:
		return None
	return actor


def _catalogue_missions():
	from app.content.daily_missions import MISSIONS

	return list(MISSIONS)


def _seed_daily_missions(session_factory, *, apply: bool, publish: bool, retire: bool) -> int:
	"""Validate the localized catalogue and, only with ``apply``, add what is missing (never edits or deletes)."""
	from app.services.mission_catalogue_service import (
		apply_catalogue,
		catalogue_summary,
		retire_placeholders,
		validate_catalogue,
	)

	missions = _catalogue_missions()
	problems = validate_catalogue(missions)
	if problems:
		print("Catalogue is invalid; nothing was written:", file=sys.stderr)
		for problem in problems[:20]:
			print(f"  - {problem}", file=sys.stderr)
		return 1
	summary = catalogue_summary(missions)
	print(f"Catalogue valid: {summary['templates']} templates, {summary['variations']} variations (en/gu/hi x 3 age bands).")
	if not apply:
		print("Dry run: nothing was written. Re-run with --apply to add missing rows (unpublished unless --publish).")
		return 0
	try:
		with session_factory() as session:
			report = apply_catalogue(session, missions, publish=publish)
			if retire:
				retired = retire_placeholders(session)
				report["unpublished"] = len(retired["unpublished"])
				report["kept_edited"] = len(retired["kept_edited"])
			session.commit()
	except SQLAlchemyError:
		print("Database operation failed; nothing was committed.", file=sys.stderr)
		return 2
	differing = report.pop("variations_differing")
	print(", ".join(f"{key}={value}" for key, value in report.items()))
	if differing:
		print(f"{len(differing)} existing variations differ from the catalogue and were left unchanged: {', '.join(differing[:5])}")
	return 0


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(prog="python -m app.cli")
	commands = parser.add_subparsers(dest="command", required=True)
	admin = commands.add_parser("create-admin", help="Create a new super-administrator account")
	recheck = commands.add_parser(
		"youtube-recheck",
		help="Re-verify approved YouTube videos against YouTube (run from cron, e.g. hourly)",
	)
	recheck.add_argument("--limit", type=int, default=200, choices=range(1, 1001), metavar="1-1000")
	discover = commands.add_parser(
		"youtube-discover",
		help="Discover reviewed-only YouTube candidates for configured topics",
	)
	discover.add_argument(
		"--max-results",
		type=int,
		default=None,
		choices=range(1, 51),
		metavar="1-50",
	)
	auto = commands.add_parser(
		"youtube-auto-review",
		help="Re-verify waiting YouTube videos and approve those that pass every automatic rule",
	)
	auto.add_argument("--limit", type=int, default=100, choices=range(1, 201), metavar="1-200")
	commands.add_parser("youtube-report", help="Read-only report of YouTube review statuses and reasons")
	health = commands.add_parser(
		"youtube-recheck-health",
		help="Read-only monitor: exit 3 if approved videos are stale or recheck has not completed recently",
	)
	health.add_argument("--max-age-hours", type=float, default=3.0, help="Longest acceptable gap between rechecks")
	diagnose = commands.add_parser(
		"video-feed-diagnose",
		help="Read-only: explain why a child's Home and Shorts feeds are empty (which rule removes the videos)",
	)
	diagnose.add_argument("--child-id", type=uuid.UUID, help="Use this child's real age, language and allowance")
	diagnose.add_argument("--age", type=int, choices=range(0, 19), metavar="0-18", help="Without --child-id")
	diagnose.add_argument("--language", default="en", choices=["en", "hi", "gu"], help="Without --child-id")
	commands.add_parser("streak-check", help="Check and update daily streak states and deliver notifications")
	notify = commands.add_parser(
		"daily-missions-notify", help="Notify children once per local day that new missions are ready"
	)
	notify.add_argument("--from-hour", type=int, default=8, choices=range(0, 24), metavar="0-23")
	notify.add_argument("--to-hour", type=int, default=19, choices=range(1, 25), metavar="1-24")
	seed = commands.add_parser(
		"seed-daily-missions",
		help="Validate the localized daily-mission catalogue; with --apply, add missing templates/variations",
	)
	seed.add_argument("--apply", action="store_true", help="Write to the configured database (default: dry run)")
	seed.add_argument("--publish", action="store_true", help="Publish the templates created by this run (needs --apply)")
	seed.add_argument(
		"--retire-placeholders",
		action="store_true",
		help="Unpublish the original placeholder templates that were never edited (needs --apply; deletes nothing)",
	)
	args = parser.parse_args(argv)

	if args.command == "daily-missions-notify":
		from app.db.session import SessionLocal as notify_factory

		if notify_factory is None:
			print("DATABASE_URL is not configured", file=sys.stderr)
			return 2
		return _daily_missions_notify(notify_factory, from_hour=args.from_hour, to_hour=args.to_hour)

	if args.command == "seed-daily-missions":
		if (args.publish or args.retire_placeholders) and not args.apply:
			parser.error("--publish and --retire-placeholders need --apply")
		factory = None
		if args.apply:
			from app.db.session import SessionLocal as factory

			if factory is None:
				print("DATABASE_URL is not configured", file=sys.stderr)
				return 2
		return _seed_daily_missions(
			factory, apply=args.apply, publish=args.publish, retire=args.retire_placeholders
		)

	from app.db.session import SessionLocal

	if SessionLocal is None:
		print("DATABASE_URL is not configured", file=sys.stderr)
		return 2

	if args.command == "streak-check":
		return _streak_check(SessionLocal)
	if args.command == "youtube-recheck":
		return _youtube_recheck(SessionLocal, args.limit)
	if args.command == "youtube-auto-review":
		return _youtube_auto_review(SessionLocal, args.limit)
	if args.command == "youtube-report":
		return _youtube_report(SessionLocal)
	if args.command == "youtube-recheck-health":
		return _recheck_health(SessionLocal, args.max_age_hours)
	if args.command == "video-feed-diagnose":
		if args.child_id is None and args.age is None:
			parser.error("give --child-id, or --age (and optionally --language)")
		return _video_feed_diagnose(SessionLocal, child_id=args.child_id, age=args.age, language=args.language)
	if args.command == "youtube-discover":
		from app.core.config import settings

		return _youtube_discover(
			SessionLocal,
			args.max_results or settings.youtube_discovery_max_results,
		)

	try:
		email = input("Administrator email: ")
		name = input("Administrator name: ")
		password = getpass.getpass("Administrator password: ")
		password_confirmation = getpass.getpass("Confirm password: ")
		if password != password_confirmation:
			print("Passwords do not match; no account was created.", file=sys.stderr)
			return 1
		email, name, password = _validated_details(email, name, password)
	except (EOFError, KeyboardInterrupt):
		print("Cancelled; no account was created.", file=sys.stderr)
		return 130
	except ValueError as error:
		print(f"Error: {error}", file=sys.stderr)
		return 1

	try:
		with SessionLocal() as session:
			status = existing_admin_status(session, email)
			if status is not None:
				print(status, file=sys.stderr)
				return 1
			user = create_admin(session, email, name, password)
	except ValueError as error:
		print(f"Error: {error}", file=sys.stderr)
		return 1
	except SQLAlchemyError:
		print("Database operation failed; no account was created.", file=sys.stderr)
		return 2

	print(f"Created administrator {user.email} with role {SUPER_ADMIN_ROLE}.")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
