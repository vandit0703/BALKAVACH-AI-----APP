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


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(prog="python -m app.cli")
	commands = parser.add_subparsers(dest="command", required=True)
	admin = commands.add_parser("create-admin", help="Create a new super-administrator account")
	parser.parse_args(argv)

	from app.db.session import SessionLocal

	if SessionLocal is None:
		print("DATABASE_URL is not configured", file=sys.stderr)
		return 2

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
