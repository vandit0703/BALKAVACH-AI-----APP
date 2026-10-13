"""Seed default levels and badges (production currently has none).

Revision ID: 0001_seed_progression
Revises:
Create Date: 2026-10-13

Data-only and idempotent: rows are inserted only when the level number or badge
name is missing. Existing rows are never changed. Downgrade deliberately removes
nothing, because children may already have earned the seeded rows.
"""

import sqlalchemy as sa
from alembic import op

from app.db.seed_data import BADGES, LEVELS

revision = "0001_seed_progression"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
	bind = op.get_bind()
	for number, name, minimum_xp in LEVELS:
		bind.execute(
			sa.text(
				"INSERT INTO levels (level_number, name, minimum_xp) VALUES (:n, :name, :xp) "
				"ON CONFLICT (level_number) DO NOTHING"
			),
			{"n": number, "name": name, "xp": minimum_xp},
		)
	for name, description, criteria_type, threshold in BADGES:
		bind.execute(
			sa.text(
				"INSERT INTO badges (name, description, criteria_type, criteria_value, is_active) "
				"VALUES (:name, :description, :ctype, CAST(:cval AS jsonb), true) ON CONFLICT (name) DO NOTHING"
			),
			{"name": name, "description": description, "ctype": criteria_type, "cval": '{"threshold": %d}' % int(threshold)},
		)


def downgrade() -> None:
	# Intentionally empty: removing levels/badges could orphan progress children already earned.
	pass
