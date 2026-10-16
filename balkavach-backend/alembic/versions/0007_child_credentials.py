"""Add usernames and encrypted child credentials to existing user accounts.

Revision ID: 0007_child_credentials
Revises: 0006_app_settings
"""

import sqlalchemy as sa
from alembic import op

revision = "0007_child_credentials"
down_revision = "0006_app_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	inspector = sa.inspect(bind)
	if not inspector.has_table("users", schema="public"):
		raise RuntimeError("The existing users table must be provisioned before child credential migration")
	columns = {column["name"] for column in inspector.get_columns("users", schema="public")}
	if "username" not in columns:
		op.add_column("users", sa.Column("username", sa.String(length=32), nullable=True))
	if "password_encrypted" not in columns:
		op.add_column("users", sa.Column("password_encrypted", sa.Text(), nullable=True))
	indexes = {index["name"] for index in sa.inspect(bind).get_indexes("users", schema="public")}
	if "uq_users_username" not in indexes:
		op.create_index("uq_users_username", "users", [sa.text("lower(username)")], unique=True)


def downgrade() -> None:
	raise RuntimeError("Downgrade is disabled to preserve stored child credentials and existing user data")