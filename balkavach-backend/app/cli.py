"""Operator commands. Run from ``balkavach-backend`` with:

    python -m app.cli create-admin

Email, name, and password are entered interactively. Passwords are read with
getpass and are never accepted from arguments or environment variables.
"""

import argparse
import getpass
import sys

from pydantic import ValidationError
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


def _youtube_recheck(session_factory, limit: int) -> int:
	from app.core.exceptions import APIError
	from app.integrations.youtube import get_youtube_client
	from app.services.youtube_review_service import recheck

	try:
		with session_factory() as session:
			counts = recheck(session, get_youtube_client(), limit)
	except APIError as error:
		print(f"Error: {error.message}", file=sys.stderr)
		return 1
	except SQLAlchemyError:
		print("Database operation failed during YouTube recheck.", file=sys.stderr)
		return 2
	print(", ".join(f"{key}={value}" for key, value in counts.items()))
	return 0


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
				)
				for key in totals:
					if key in result:
						totals[key] += len(result["created"]) if key == "created" else result[key]
			trusted_totals = discover_trusted(session, actor, client, max_results)
			for key, value in trusted_totals.items():
				totals[key] += value
	except APIError as error:
		print(f"Error: {error.message}", file=sys.stderr)
		return 1
	except SQLAlchemyError:
		print("Database operation failed during YouTube discovery.", file=sys.stderr)
		return 2
	print(", ".join(f"{key}={value}" for key, value in totals.items()))
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
	args = parser.parse_args(argv)

	from app.db.session import SessionLocal

	if SessionLocal is None:
		print("DATABASE_URL is not configured", file=sys.stderr)
		return 2

	if args.command == "youtube-recheck":
		return _youtube_recheck(SessionLocal, args.limit)
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
