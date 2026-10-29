from threading import RLock
from typing import Any

from sqlalchemy import MetaData
from sqlalchemy.engine import Connection, Engine
from sqlalchemy.ext.automap import automap_base

Base = automap_base(
	metadata=MetaData(
		naming_convention={
			"ix": "ix_%(column_0_label)s",
			"uq": "uq_%(table_name)s_%(column_0_name)s",
			"ck": "ck_%(table_name)s_%(constraint_name)s",
			"fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
			"pk": "pk_%(table_name)s",
		}
	)
)

MODEL_TABLES = {
	"User": "users",
	"Family": "families",
	"FamilyMember": "family_members",
	"ChildProfile": "child_profiles",
	"Level": "levels",
	"Task": "tasks",
	"TaskCategory": "task_categories",
	"TaskSubmission": "task_submissions",
	"TaskReview": "task_reviews",
	"StarTransaction": "star_transactions",
	"XPTransaction": "xp_transactions",
	"ChildBadge": "child_badges",
	"Badge": "badges",
	"ChildProgress": "child_progress",
	"ChildActivityDay": "child_activity_days",
	"ChildStreak": "child_streaks",
	"VideoCategory": "video_categories",
	"Video": "videos",
	"VideoCollection": "video_collections",
	"VideoCollectionItem": "video_collection_items",
	"VideoWatchSession": "video_watch_sessions",
	"Reward": "rewards",
	"RedemptionRequest": "redemption_requests",
	"VideoAccessEntitlement": "video_access_entitlements",
	"EducationalContent": "educational_content",
	"Notification": "notifications",
	"UserSetting": "user_settings",
	"FamilySetting": "family_settings",
	"ConsentRecord": "consent_records",
	"UserAdminRole": "user_admin_roles",
	"AdminRole": "admin_roles",
	"AuditLog": "audit_logs",
	"AuthSession": "auth_sessions",
	"DeviceToken": "device_tokens",
	"ProofUpload": "proof_uploads",
	"PresetTask": "preset_tasks",
	"AppSetting": "app_settings",
	"YouTubeContentReview": "youtube_content_reviews",
	"YouTubeTrustedChannel": "youtube_trusted_channels",
	"ContentReport": "content_reports",
}

_prepare_lock = RLock()
_prepared = False


def prepare_models(bind: Engine | Connection | None = None) -> None:
	global _prepared
	if _prepared:
		return
	if bind is None:
		from app.db.session import engine

		bind = engine
	if bind is None:
		raise RuntimeError("DATABASE_URL must be configured before loading database models")
	with _prepare_lock:
		if not _prepared:
			Base.prepare(
				autoload_with=bind,
				schema="public",
				classname_for_table=lambda base, tablename, table: tablename,
			)
			_prepared = True


def get_model(name: str) -> Any:
	table_name = MODEL_TABLES.get(name, name)
	if table_name not in MODEL_TABLES.values():
		raise KeyError(f"Unknown BalKavach model: {name}")
	prepare_models()
	return getattr(Base.classes, table_name)


def has_model(name: str) -> bool:
	"""Whether the table behind ``name`` exists in the reflected database.

	Migration 0008 may not be applied yet; callers of its tables use this to
	degrade (fail closed) instead of crashing.
	"""
	table_name = MODEL_TABLES.get(name, name)
	if table_name not in MODEL_TABLES.values():
		return False
	prepare_models()
	return table_name in Base.classes
