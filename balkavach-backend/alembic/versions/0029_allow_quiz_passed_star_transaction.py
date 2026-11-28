"""Allow quiz_passed in star transaction types."""

import os
import sqlalchemy as sa
from alembic import op

revision = "0029_allow_quiz_passed_star_transaction"
down_revision = "0028_task_repeat_rule_jsonb"
branch_labels = None
depends_on = None

CONSTRAINT = "star_transactions_transaction_type_check"

OLD_TYPES = (
    "'task_approved', 'reward_redemption', 'admin_adjustment', "
    "'refund', 'other'"
)

NEW_TYPES = OLD_TYPES + ", 'quiz_passed'"


def upgrade() -> None:
    if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
        raise RuntimeError("Schema migrations are disabled")

    op.execute(sa.text(
        f"ALTER TABLE public.star_transactions "
        f"DROP CONSTRAINT {CONSTRAINT}"
    ))

    op.execute(sa.text(
        f"ALTER TABLE public.star_transactions "
        f"ADD CONSTRAINT {CONSTRAINT} "
        f"CHECK (transaction_type IN ({NEW_TYPES}))"
    ))


def downgrade() -> None:
    bind = op.get_bind()

    existing = bind.execute(sa.text(
        "SELECT COUNT(*) FROM public.star_transactions "
        "WHERE transaction_type = 'quiz_passed'"
    )).scalar_one()

    if existing:
        raise RuntimeError(
            f"Cannot downgrade: {existing} quiz_passed transactions exist."
        )

    op.execute(sa.text(
        f"ALTER TABLE public.star_transactions "
        f"DROP CONSTRAINT {CONSTRAINT}"
    ))

    op.execute(sa.text(
        f"ALTER TABLE public.star_transactions "
        f"ADD CONSTRAINT {CONSTRAINT} "
        f"CHECK (transaction_type IN ({OLD_TYPES}))"
    ))
