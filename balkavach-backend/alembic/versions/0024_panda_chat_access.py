"""Allow child-authored Panda chat requests in existing consent records."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0024_panda_chat_access"
down_revision = "0023_parent_email_verification"
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	columns = {column["name"]: column for column in sa.inspect(bind).get_columns("consent_records")}
	if columns["parent_user_id"]["nullable"]:
		return
	op.alter_column(
		"consent_records",
		"parent_user_id",
		existing_type=postgresql.UUID(as_uuid=True),
		existing_nullable=False,
		nullable=True,
	)


def downgrade() -> None:
	bind = op.get_bind()
	pending = bind.execute(
		sa.text(
			"SELECT count(*) FROM consent_records "
			"WHERE consent_type = 'panda_chat_access' AND parent_user_id IS NULL"
		)
	).scalar_one()
	if pending:
		raise RuntimeError("Cannot downgrade while child Panda chat requests have no parent actor")
	op.alter_column(
		"consent_records",
		"parent_user_id",
		existing_type=postgresql.UUID(as_uuid=True),
		existing_nullable=True,
		nullable=False,
	)
