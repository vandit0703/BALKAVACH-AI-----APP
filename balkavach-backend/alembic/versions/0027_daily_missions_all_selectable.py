"""Let a child choose and complete all three of the day's offered daily missions.

Migration 0015 added the partial unique index ``uq_daily_assignment_selected_day`` (one selected / in-progress /
submitted / approved / rejected current assignment per child per local day), which made the three offered missions
a one-completion limit. The product rule is now that each of the three can be completed, so the index is dropped.
What still holds: one current row per slot (``uq_daily_assignment_current_slot``), at most three slots, and each
chosen slot gets its own Task (``select_assignment`` locks the row). ``ix_daily_assignment_history`` keeps the
(child_id, local_date, status) lookups indexed.

Downgrade recreates the index. It fails if a child already has more than one chosen mission on a day; those rows
must be resolved first (nothing is deleted automatically).
"""

import os

import sqlalchemy as sa
from alembic import op

revision = "0027_daily_missions_all_selectable"
down_revision = "0026_custom_mission_video_reward"
branch_labels = None
depends_on = None

INDEX = "uq_daily_assignment_selected_day"
CHOSEN = "is_current AND status IN ('selected', 'in_progress', 'pending_parent_approval', 'approved', 'rejected')"


def upgrade() -> None:
	if os.getenv("ALLOW_SCHEMA_MIGRATIONS", "true").lower() in ("false", "0"):
		raise RuntimeError("Schema migrations are disabled; set ALLOW_SCHEMA_MIGRATIONS=true")
	op.execute(sa.text(f"DROP INDEX IF EXISTS {INDEX}"))


def downgrade() -> None:
	op.create_index(
		INDEX,
		"daily_mission_assignments",
		["child_id", "local_date"],
		unique=True,
		postgresql_where=sa.text(CHOSEN),
	)
