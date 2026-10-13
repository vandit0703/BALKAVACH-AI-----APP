"""Operator commands. Run from ``balkavach-backend``::

    python -m app.cli create-admin --email you@example.com --name "Your Name"

The password is read from the ``ADMIN_PASSWORD`` environment variable or prompted
for; it is never accepted as a command-line argument (shell history, process list).
"""

import argparse
import getpass
import os
import sys

from sqlalchemy.orm import Session

from app.core.security import hash_password
from app.db.base import get_model

MIN_PASSWORD_LENGTH = 12


def create_admin(session: Session, email: str, name: str, password: str, role_name: str = "super_admin"):
	"""Create (or promote nothing — refuse existing) an admin account with one admin role."""
	if len(password) < MIN_PASSWORD_LENGTH:
		raise ValueError(f"Password must be at least {MIN_PASSWORD_LENGTH} characters")
	User = get_model("User")
	AdminRole = get_model("AdminRole")
	UserAdminRole = get_model("UserAdminRole")
	email = email.strip().lower()
	if session.query(User.id).filter(User.email == email).first():
		raise ValueError("An account with that email already exists")
	role = session.query(AdminRole).filter(AdminRole.name == role_name).one_or_none()
	if role is None:
		raise ValueError(f"Unknown admin role: {role_name}")
	user = User(
		full_name=name.strip(),
		email=email,
		password_hash=hash_password(password),
		role="admin",
		preferred_language="en",
		is_active=True,
	)
	session.add(user)
	session.flush()
	session.add(UserAdminRole(user_id=user.id, admin_role_id=role.id))
	session.commit()
	return user


def main(argv: list[str] | None = None) -> int:
	parser = argparse.ArgumentParser(prog="python -m app.cli")
	commands = parser.add_subparsers(dest="command", required=True)
	admin = commands.add_parser("create-admin", help="Create an administrator account")
	admin.add_argument("--email", required=True)
	admin.add_argument("--name", required=True)
	admin.add_argument("--role", default="super_admin")
	args = parser.parse_args(argv)

	from app.db.session import SessionLocal

	if SessionLocal is None:
		print("DATABASE_URL is not configured", file=sys.stderr)
		return 2
	password = os.environ.get("ADMIN_PASSWORD") or getpass.getpass("Password: ")
	with SessionLocal() as session:
		try:
			user = create_admin(session, args.email, args.name, password, args.role)
		except ValueError as error:
			print(f"Error: {error}", file=sys.stderr)
			return 1
	print(f"Created administrator {user.email} with role {args.role}")
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
