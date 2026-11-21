-- RECONSTRUCTED baseline for a DISPOSABLE LOCAL PostgreSQL. This is NOT a dump of production and NOT tests/schema/baseline.sql.
--
-- The real pre-migration tables are not in the repository (the app reflects them at runtime). This file re-creates, from what
-- the application code and the Alembic migrations require, the tables that existed before migration 0001, so the real
-- migrations and the real approval transaction can run on real PostgreSQL (row locks, ON CONFLICT, rollback, concurrency).
--
-- What it proves: application logic and the migrations' own SQL on PostgreSQL semantics.
-- What it CANNOT prove: which constraints, NOT NULLs, defaults and indexes the production database really has. Every
-- constraint below is an assumption; the ones that decide the approval outcome are listed in
-- docs/parent-approval-troubleshooting.md and are exercised both ways by tests/test_parent_approval_postgres.py.
--
-- Timestamps are naive UTC (timestamp without time zone): the application stores utc_naive() values everywhere.
--
-- Never run this against anything but a throwaway database whose name contains "test".


CREATE TABLE users (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	email text UNIQUE,
	password_hash text,
	full_name text NOT NULL DEFAULT '',
	role text NOT NULL DEFAULT 'parent',
	preferred_language text NOT NULL DEFAULT 'en',
	is_active boolean NOT NULL DEFAULT true,
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE families (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_name text NOT NULL DEFAULT 'Family',
	created_by uuid REFERENCES users(id),
	created_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE family_members (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
	user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	relationship text NOT NULL DEFAULT 'parent',
	is_primary_parent boolean NOT NULL DEFAULT false,
	is_active boolean NOT NULL DEFAULT true,
	created_at timestamp NOT NULL DEFAULT now(),
	UNIQUE (family_id, user_id)
);

CREATE TABLE levels (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	level_number integer NOT NULL UNIQUE,
	name text NOT NULL,
	minimum_xp integer NOT NULL DEFAULT 0
);

CREATE TABLE child_profiles (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
	display_name text NOT NULL,
	date_of_birth date,
	avatar_url text,
	current_level_id uuid REFERENCES levels(id),
	is_active boolean NOT NULL DEFAULT true,
	created_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE task_categories (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	name text NOT NULL,
	description text,
	icon_name text,
	is_default boolean NOT NULL DEFAULT false,
	is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE tasks (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
	category_id uuid REFERENCES task_categories(id) ON DELETE SET NULL,
	created_by uuid NOT NULL REFERENCES users(id),
	assigned_child_id uuid REFERENCES child_profiles(id) ON DELETE SET NULL,
	title text NOT NULL,
	description text,
	star_reward integer NOT NULL DEFAULT 0 CHECK (star_reward >= 0),
	xp_reward integer NOT NULL DEFAULT 0 CHECK (xp_reward >= 0),
	due_at timestamp,
	repeat_rule text,
	is_custom boolean NOT NULL DEFAULT true,
	is_active boolean NOT NULL DEFAULT true,
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE task_submissions (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	submission_number integer NOT NULL DEFAULT 1,
	proof_type text NOT NULL DEFAULT 'none',
	proof_url text,
	proof_note text,
	status text NOT NULL DEFAULT 'pending',
	submitted_at timestamp NOT NULL DEFAULT now(),
	reviewed_at timestamp,
	UNIQUE (task_id, child_id, submission_number)
);

CREATE TABLE task_reviews (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	submission_id uuid NOT NULL REFERENCES task_submissions(id) ON DELETE CASCADE,
	reviewed_by uuid NOT NULL REFERENCES users(id),
	decision text NOT NULL,
	review_note text,
	created_at timestamp NOT NULL DEFAULT now()
);

-- ASSUMPTION A: the idempotency keys carry a UNIQUE constraint. Production may or may not (see the troubleshooting doc).
CREATE TABLE star_transactions (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	amount integer NOT NULL,
	transaction_type text NOT NULL,
	submission_id uuid REFERENCES task_submissions(id) ON DELETE SET NULL,
	redemption_id uuid,
	idempotency_key text,
	description text,
	created_at timestamp NOT NULL DEFAULT now(),
	CONSTRAINT star_transactions_idempotency_key_key UNIQUE (idempotency_key)
);

CREATE TABLE xp_transactions (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	amount integer NOT NULL,
	submission_id uuid REFERENCES task_submissions(id) ON DELETE SET NULL,
	reason text NOT NULL,
	idempotency_key text,
	created_at timestamp NOT NULL DEFAULT now(),
	CONSTRAINT xp_transactions_idempotency_key_key UNIQUE (idempotency_key)
);

CREATE TABLE child_progress (
	child_id uuid PRIMARY KEY REFERENCES child_profiles(id) ON DELETE CASCADE,
	total_xp integer NOT NULL DEFAULT 0,
	current_level_id uuid REFERENCES levels(id),
	garden_progress jsonb NOT NULL DEFAULT '{}'::jsonb,
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE child_activity_days (
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	activity_date date NOT NULL,
	completed_tasks integer NOT NULL DEFAULT 0,
	stars_earned integer NOT NULL DEFAULT 0,
	xp_earned integer NOT NULL DEFAULT 0,
	created_at timestamp NOT NULL DEFAULT now(),
	PRIMARY KEY (child_id, activity_date)
);

CREATE TABLE child_streaks (
	child_id uuid PRIMARY KEY REFERENCES child_profiles(id) ON DELETE CASCADE,
	current_streak integer NOT NULL DEFAULT 0,
	longest_streak integer NOT NULL DEFAULT 0,
	last_activity_date date,
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE badges (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	name text NOT NULL UNIQUE,
	description text,
	icon_url text,
	criteria_type text NOT NULL,
	criteria_value jsonb NOT NULL DEFAULT '{}'::jsonb,
	is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE child_badges (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	badge_id uuid NOT NULL REFERENCES badges(id) ON DELETE CASCADE,
	unlocked_at timestamp NOT NULL DEFAULT now(),
	UNIQUE (child_id, badge_id)
);

CREATE TABLE notifications (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	recipient_user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	notification_type text NOT NULL,
	title text NOT NULL,
	message text NOT NULL,
	related_task_id uuid,
	related_submission_id uuid,
	related_redemption_id uuid,
	is_read boolean NOT NULL DEFAULT false,
	read_at timestamp,
	created_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE user_settings (
	user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
	language_code text NOT NULL DEFAULT 'en',
	push_enabled boolean NOT NULL DEFAULT true,
	email_notifications_enabled boolean NOT NULL DEFAULT true,
	updated_at timestamp
);

CREATE TABLE family_settings (
	family_id uuid PRIMARY KEY REFERENCES families(id) ON DELETE CASCADE,
	default_language text NOT NULL DEFAULT 'en',
	mission_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
	reward_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
	video_settings jsonb NOT NULL DEFAULT '{}'::jsonb,
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE video_categories (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	name text NOT NULL,
	slug text NOT NULL UNIQUE,
	description text,
	icon_url text,
	display_order integer NOT NULL DEFAULT 0,
	is_active boolean NOT NULL DEFAULT true
);

CREATE TABLE videos (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	title text NOT NULL,
	description text,
	video_source text NOT NULL DEFAULT 'hosted',
	video_url text NOT NULL DEFAULT 'https://example.test/v',
	external_video_id text,
	storage_key text,
	thumbnail_url text,
	duration_seconds integer NOT NULL DEFAULT 0,
	category_id uuid REFERENCES video_categories(id) ON DELETE SET NULL,
	language_code text NOT NULL DEFAULT 'en',
	age_min integer NOT NULL DEFAULT 3,
	age_max integer NOT NULL DEFAULT 15,
	content_rating text NOT NULL DEFAULT 'general',
	is_published boolean NOT NULL DEFAULT false,
	published_at timestamp,
	display_order integer NOT NULL DEFAULT 0,
	created_by uuid REFERENCES users(id),
	uploaded_by uuid REFERENCES users(id),
	created_at timestamp NOT NULL DEFAULT now(),
	updated_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE video_collections (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	title text NOT NULL DEFAULT 'Collection',
	is_published boolean NOT NULL DEFAULT false
);

CREATE TABLE rewards (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
	created_by uuid REFERENCES users(id),
	name text NOT NULL,
	description text,
	reward_type text NOT NULL,
	star_cost integer NOT NULL,
	image_url text,
	video_id uuid REFERENCES videos(id),
	video_collection_id uuid REFERENCES video_collections(id),
	access_duration_seconds integer,
	access_validity_seconds integer,
	max_uses integer,
	is_active boolean NOT NULL DEFAULT true,
	created_at timestamp NOT NULL DEFAULT now()
);

CREATE TABLE redemption_requests (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	reward_id uuid NOT NULL REFERENCES rewards(id),
	child_id uuid NOT NULL REFERENCES child_profiles(id),
	star_cost_at_request integer NOT NULL DEFAULT 0,
	status text NOT NULL DEFAULT 'pending',
	idempotency_key text,
	requested_at timestamp NOT NULL DEFAULT now(),
	reviewed_by uuid REFERENCES users(id),
	reviewed_at timestamp,
	review_note text,
	fulfilled_at timestamp,
	cancelled_at timestamp,
	created_at timestamp NOT NULL DEFAULT now()
);

-- The star-redemption entitlement table as migration 0013 found it. Star-redemption rows always have exactly one of
-- video_id / video_collection_id (reward_service.create_reward enforces it before the row is copied).
-- ASSUMPTION B (decides the approval outcome): here both targets are NULLABLE with no "exactly one target" rule. A strict
-- variant is applied by tests/test_parent_approval_postgres.py to show what happens if production has such a rule.
CREATE TABLE video_access_entitlements (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	child_id uuid NOT NULL REFERENCES child_profiles(id) ON DELETE CASCADE,
	redemption_id uuid REFERENCES redemption_requests(id) ON DELETE SET NULL,
	video_id uuid REFERENCES videos(id) ON DELETE CASCADE,
	video_collection_id uuid REFERENCES video_collections(id) ON DELETE CASCADE,
	granted_seconds integer NOT NULL DEFAULT 0 CHECK (granted_seconds >= 0),
	consumed_seconds integer NOT NULL DEFAULT 0 CHECK (consumed_seconds >= 0),
	granted_at timestamp NOT NULL DEFAULT now(),
	valid_from timestamp,
	expires_at timestamp,
	status text NOT NULL DEFAULT 'active'
);

CREATE TABLE consent_records (
	id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
	family_id uuid NOT NULL REFERENCES families(id) ON DELETE CASCADE,
	child_id uuid REFERENCES child_profiles(id) ON DELETE CASCADE,
	parent_user_id uuid NOT NULL REFERENCES users(id),
	consent_type text NOT NULL,
	document_version text NOT NULL,
	accepted boolean NOT NULL,
	accepted_at timestamp,
	revoked_at timestamp,
	created_at timestamp NOT NULL DEFAULT now()
);
