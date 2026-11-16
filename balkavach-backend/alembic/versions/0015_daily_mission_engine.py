"""Daily mission catalog, age-band variations, and child assignments."""

from datetime import datetime, timezone
from uuid import NAMESPACE_URL, uuid5

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0015_daily_mission_engine"
down_revision = "0014_auth_security_controls"
branch_labels = None
depends_on = None

_THEMES = [
    ("monday_sound_detective", "Sound Detective", "offline"),
    ("monday_sound_detective_2", "Sound Detective: Echo Hunt", "interactive"),
    ("monday_sound_detective_3", "Sound Detective: Rhythm Clues", "creative"),
    ("tuesday_memory_master", "Memory Master", "interactive"),
    ("tuesday_memory_master_2", "Memory Master: Pattern Path", "offline"),
    ("tuesday_memory_master_3", "Memory Master: Story Chain", "creative"),
    ("wednesday_magic_story_maker", "Magic Story Maker", "creative"),
    ("wednesday_magic_story_maker_2", "Magic Story Maker: Tiny World", "offline"),
    ("wednesday_magic_story_maker_3", "Magic Story Maker: Character Quest", "interactive"),
    ("thursday_paper_architect", "Paper Architect", "creative"),
    ("thursday_paper_architect_2", "Paper Architect: Strong Shapes", "offline"),
    ("thursday_paper_architect_3", "Paper Architect: Folded Future", "interactive"),
    ("friday_emotion_detective", "Emotion Detective", "interactive"),
    ("friday_emotion_detective_2", "Emotion Detective: Kind Clues", "creative"),
    ("friday_emotion_detective_3", "Emotion Detective: Calm Kit", "offline"),
    ("saturday_rhythm_rockstar", "Rhythm Rockstar", "creative"),
    ("saturday_rhythm_rockstar_2", "Rhythm Rockstar: Beat Builder", "interactive"),
    ("saturday_rhythm_rockstar_3", "Rhythm Rockstar: Tabletop Band", "offline"),
    ("sunday_future_inventor", "Future Inventor", "creative"),
    ("sunday_future_inventor_2", "Future Inventor: Helpful Gadget", "offline"),
    ("sunday_future_inventor_3", "Future Inventor: Mission Control", "interactive"),
    ("daily_surprise_spark", "Surprise Spark", "creative"),
]
_AGE_BANDS = ("4_6", "7_10", "11_15")


def _id(value: str):
    return uuid5(NAMESPACE_URL, f"balkavach.daily-mission:{value}")


def upgrade() -> None:
    op.create_table(
        "daily_mission_templates",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("slug", sa.String(100), nullable=False, unique=True),
        sa.Column("theme", sa.String(40), nullable=False),
        sa.Column("mission_type", sa.String(16), nullable=False),
        sa.Column("is_surprise", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("is_published", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("star_reward", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("xp_reward", sa.Integer(), nullable=False, server_default="10"),
        sa.Column("mystery_bonus", postgresql.JSONB(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("mission_type IN ('offline', 'interactive', 'creative')", name="daily_template_type_check"),
        sa.CheckConstraint("star_reward >= 0 AND xp_reward >= 0", name="daily_template_reward_check"),
    )
    op.create_table(
        "daily_mission_variations",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("template_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("age_band", sa.String(8), nullable=False),
        sa.Column("locale", sa.String(10), nullable=False),
        sa.Column("title", sa.String(180), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("instructions", sa.Text(), nullable=False),
        sa.Column("required_materials", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("duration_minutes", sa.Integer(), nullable=False),
        sa.Column("safety_instructions", sa.Text(), nullable=False),
        sa.Column("completion_criteria", sa.Text(), nullable=False),
        sa.Column("variation_key", sa.String(40), nullable=False, server_default="v1"),
        sa.ForeignKeyConstraint(["template_id"], ["daily_mission_templates.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("template_id", "age_band", "locale", "variation_key", name="uq_daily_variation_version"),
        sa.CheckConstraint("age_band IN ('4_6', '7_10', '11_15')", name="daily_variation_age_check"),
        sa.CheckConstraint("duration_minutes BETWEEN 1 AND 180", name="daily_variation_duration_check"),
    )
    op.create_index("ix_daily_variations_lookup", "daily_mission_variations", ["template_id", "age_band", "locale"])
    op.create_table(
        "daily_mission_assignments",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("child_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("family_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("local_date", sa.Date(), nullable=False),
        sa.Column("choice_slot", sa.Integer(), nullable=False),
        sa.Column("age_band", sa.String(8), nullable=False),
        sa.Column("template_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("variation_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("task_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("status", sa.String(32), nullable=False, server_default="available"),
        sa.Column("is_current", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("snapshot", postgresql.JSONB(), nullable=False),
        sa.Column("selected_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("skipped_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.ForeignKeyConstraint(["child_id"], ["child_profiles.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["family_id"], ["families.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["template_id"], ["daily_mission_templates.id"]),
        sa.ForeignKeyConstraint(["variation_id"], ["daily_mission_variations.id"]),
        sa.ForeignKeyConstraint(["task_id"], ["tasks.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("child_id", "local_date", "choice_slot", "id", name="uq_daily_assignment_history"),
        sa.CheckConstraint("choice_slot BETWEEN 1 AND 3", name="daily_assignment_slot_check"),
        sa.CheckConstraint("status IN ('available', 'selected', 'in_progress', 'pending_parent_approval', 'approved', 'rejected', 'skipped')", name="daily_assignment_status_check"),
    )
    op.create_index("uq_daily_assignment_current_slot", "daily_mission_assignments", ["child_id", "local_date", "choice_slot"], unique=True, postgresql_where=sa.text("is_current"))
    op.create_index("uq_daily_assignment_selected_day", "daily_mission_assignments", ["child_id", "local_date"], unique=True, postgresql_where=sa.text("is_current AND status IN ('selected', 'in_progress', 'pending_parent_approval', 'approved', 'rejected')"))
    op.create_index("ix_daily_assignment_history", "daily_mission_assignments", ["child_id", "local_date", "status"])

    templates = []
    for index, (slug, title, mission_type) in enumerate(_THEMES):
        theme = slug.rsplit("_", 1)[0] if slug.rsplit("_", 1)[-1].isdigit() else slug
        templates.append({"id": _id(slug), "slug": slug, "theme": theme, "mission_type": mission_type, "is_surprise": slug == "daily_surprise_spark", "is_published": True, "star_reward": 2 if slug == "daily_surprise_spark" else 1, "xp_reward": 20 if slug == "daily_surprise_spark" else 10, "mystery_bonus": {"type": "stars", "amount": 2} if slug == "daily_surprise_spark" else None})
    op.bulk_insert(sa.table("daily_mission_templates", *[sa.column(c) for c in ("id", "slug", "theme", "mission_type", "is_surprise", "is_published", "star_reward", "xp_reward", "mystery_bonus")]), templates)

    variations = []
    for template in templates:
        for age_band in _AGE_BANDS:
            age_label = {"4_6": "4 to 6", "7_10": "7 to 10", "11_15": "11 to 15"}[age_band]
            variation_id = _id(f"{template['slug']}:{age_band}:en:v1")
            variations.append({"id": variation_id, "template_id": template["id"], "age_band": age_band, "locale": "en", "title": f"{template['slug'].replace('_', ' ').title()} ({age_label})", "description": f"A {template['mission_type']} learning adventure for ages {age_label}.", "instructions": "Try the steps, notice what you discover, and tell a trusted grown-up what you learned.", "required_materials": ["safe household objects"], "duration_minutes": 10 if age_band == "4_6" else 15 if age_band == "7_10" else 20, "safety_instructions": "Use only safe objects with a trusted grown-up nearby. Never share personal information.", "completion_criteria": "Complete the steps and share one thing you discovered.", "variation_key": "v1"})
            variations.append({**variations[-1], "id": _id(f"{template['slug']}:{age_band}:gu:v1"), "locale": "gu", "title": f"{template['slug'].replace('_', ' ').title()} ({age_label})", "description": f"{age_label} umar mate ek maja nu shikshan sahas.", "instructions": "Pagala ajmavo, shu malyu te dhyanthi juo ane vishvasu mota vyaktine kaho.", "safety_instructions": "Fakta surakshit vastu vapro ane mota vyakti pase raho. Vyaktigat mahiti share na karo.", "completion_criteria": "Pagala purna karo ane ek navi vaat kaho."})
            variations.append({**variations[-1], "id": _id(f"{template['slug']}:{age_band}:hi:v1"), "locale": "hi", "title": f"{template['slug'].replace('_', ' ').title()} ({age_label})", "description": f"{age_label} saal ke bachchon ke liye ek mazedaar seekhne ka sahas.", "instructions": "Kadam aazmaiye, jo dekha use dhyan se samajhiye aur kisi bharosemand bade ko batayiye.", "safety_instructions": "Sirf surakshit cheezen istemal karein aur bade ke paas rahen. Niji jaankari share na karein.", "completion_criteria": "Kadam poore karke ek nayi baat batayiye."})
    op.bulk_insert(sa.table("daily_mission_variations", *[sa.column(c) for c in ("id", "template_id", "age_band", "locale", "title", "description", "instructions", "required_materials", "duration_minutes", "safety_instructions", "completion_criteria", "variation_key")]), variations)


def downgrade() -> None:
    op.drop_index("ix_daily_assignment_history", table_name="daily_mission_assignments")
    op.drop_index("uq_daily_assignment_selected_day", table_name="daily_mission_assignments")
    op.drop_index("uq_daily_assignment_current_slot", table_name="daily_mission_assignments")
    op.drop_table("daily_mission_assignments")
    op.drop_index("ix_daily_variations_lookup", table_name="daily_mission_variations")
    op.drop_table("daily_mission_variations")
    op.drop_table("daily_mission_templates")
