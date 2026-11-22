# Structured mission instructions (migration 0019)

> Second-pass update: the revision id is now `0019_mission_instruction_fields` (31 characters; the first draft's 36-character id could not be written to a `varchar(32)` `alembic_version.version_num`). The sections after "Content gap" describe the second pass.

Status: **written, not executed against any database.** Applying it, seeding and publishing need separate approval.

## Why

Missions showed text like "A creative learning adventure for ages 11 to 15" / "Try the steps, notice what you
discover…". That text is the placeholder data inserted by migration `0015_daily_mission_engine` (22 templates x 3 ages x
3 languages). The curated catalogue in `balkavach-backend/app/content/daily_missions/` (42 missions, 126 age-specific
missions, 378 localized versions) has real steps, but they were stored only as numbered lines inside one `instructions`
text column, and there was no place for "what you will learn", "what to observe" or "what to submit".

## Migration `0019_mission_instruction_fields`

* Revision chain: `0018_mission_video_requirements` -> `0019_mission_instruction_fields` (single head).
* Adds four **nullable** columns to `daily_mission_variations`; nothing else changes:

| Column | Type | Meaning |
|---|---|---|
| `learning_objective` | `TEXT` | "What you will learn" (one sentence) |
| `steps` | `JSONB` | ordered list of step strings |
| `observation_guidance` | `TEXT` | "What to observe" |
| `submission_requirements` | `TEXT` | "What to submit" |

* Reused (no new column): materials (`required_materials`), time (`duration_minutes`), safety (`safety_instructions`),
  completion criteria (`completion_criteria`).
* PostgreSQL: `ADD COLUMN` with no default and NULL allowed is a catalogue-only change (no table rewrite, short lock).
  Rendered DDL (generated with Alembic's PostgreSQL dialect, no database connection):

```sql
ALTER TABLE daily_mission_variations ADD COLUMN learning_objective TEXT;
ALTER TABLE daily_mission_variations ADD COLUMN steps JSONB;
ALTER TABLE daily_mission_variations ADD COLUMN observation_guidance TEXT;
ALTER TABLE daily_mission_variations ADD COLUMN submission_requirements TEXT;
```

* Downgrade drops exactly those four columns, in reverse order. It loses only content written into them.
* Variation ids, assignments (and their `snapshot`), submissions, approvals and rewards are untouched. No data is
  rewritten or backfilled by the migration.
* Naming: matches existing migrations (`NNNN_snake_case`, plain `op.add_column`).
* The ORM is reflected from the live schema (`app/db/base.py`), so the code reads the new columns with `getattr(...)`
  and the API works (with `steps` extracted from the numbered lines) before the migration is applied. **Writing**
  structured fields (admin editor, `seed-daily-missions --backfill-structured`) requires the migration first.

## Deployment order (when approved)

1. Back up / snapshot the database.
2. `alembic upgrade head` (applies 0019).
3. Deploy the backend, then the admin panel, then the app.
4. Read-only checks: `python -m app.cli seed-daily-missions --compare-db` and `python -m app.cli audit-daily-missions --database`.
5. Separately approved, each its own command: `seed-daily-missions --apply [--backfill-structured]`, then `--publish`,
   then `--retire-placeholders`. None of them runs automatically; dry run is the default.

## API contract

Child (`/daily-missions/*`) `content` keeps every old field and adds:
`learning_objective`, `steps[]`, `materials[]` (same items as `required_materials`), `observation_guidance`,
`submission_requirements`, `instruction_status` (`ready` | `incomplete`). Missing text is `null`/`[]`, never filler.
Old assignment snapshots are read by extracting their numbered lines; placeholder text yields no steps and `incomplete`.

Admin: variation detail adds the same fields plus `issues.errors` / `issues.warnings`; `POST /admin/daily-missions/variations/preview`
(no write) returns the child content, rendered text and publish blockers; create accepts `steps` (and derives numbered
`instructions`); update keeps `instructions` in step with `steps`; publish returns
`422 daily_template_instructions_incomplete` with `details.problems` unless every variation has real steps, materials
(or "Nothing needed"), a submission requirement, safety and completion text, no placeholder text, and each age band in a
language has its own steps.

## Content gap (not fabricated)

The catalogue has steps, materials, safety, a "what the child shows" line (used as `submission_requirements`) and a
parent check, but **no authored "what you will learn" or "what to observe" text**. Those stay NULL (the app omits the
sections) and the audit reports them as `NEEDS IMPROVEMENT` (warnings, not publish blockers). Authors can add optional
`objective` / `observe` keys to a catalogue entry's locale text, or edit them in the admin panel. Gujarati and Hindi
text, including the new interface strings, has not had native-speaker review.

## Second pass

### Audit classes (what blocks, what only enriches)
* **INCOMPLETE**: the child cannot act (no steps, one step, malformed steps, or placeholder text).
* **NEEDS IMPROVEMENT**: the child can follow the steps, but an essential field is missing (materials, child-facing
  submission, safety text, completion criteria, distinct age bands), or a quality problem exists (steps too long for
  ages 4-6, repeated steps, steps of different count between languages, a reviewer-voiced submission). Essential
  fields also block publishing.
* **SAFETY REVIEW**: the activity text asks for something on the restricted list (always wins).
* **COMPLETE**: no blockers or quality problems. Missing learning objective / observation guidance (enrichment) and the
  step-count guideline (advisory) never change the class and never block publishing.
Each variation also reports: actionable, steps ok, materials clear, duration present, safety guidance present,
submission clear to the child, completion clear to the reviewer, objective missing, observation missing, needs native
review (every Gujarati/Hindi row: no review record exists), needs safety review.

### Child submission text
See [mission-child-submission-examples.md](mission-child-submission-examples.md). The reviewer-facing `show` line is no
longer copied to the child; `submit` is the child's own text.

### Editing and publication
Editing one version used to unpublish the whole template (all nine versions vanished from rotation). Existing
assignments keep their immutable snapshot and task text, and submissions/approvals reference the task, so history was
never affected, but availability was. Now:
* unpublished template: stays unpublished, any edit allowed;
* published and still publishable after the edit: stays published;
* published, valid before, invalid after: edit refused with `422 published_variation_edit_invalid` (nothing changes);
* published but already invalid before the edit: unpublished by the edit.
Template-level edits (`PATCH /templates/{id}`) still unpublish, unchanged.

### Seeder
Dry run is the default and contacts no database. `--compare-db` is a read-only comparison. `--apply` creates what is
missing. `--backfill-structured`, `--publish` and `--retire-placeholders` each need `--apply` and are independent.
`--publish` now runs the same instruction checks as the admin endpoint and reports `publish_blocked` instead of
publishing an incomplete mission. Re-running is idempotent.

### PostgreSQL verification plan (disposable database only)
1. Provide a **disposable** PostgreSQL database whose name contains "test" (the `isolated_test_engine` fixture refuses
   anything else and refuses the application database). Load `tests/schema/reconstructed_baseline.sql`
   (a reconstruction, not production) or a schema-only dump, and widen `alembic_version.version_num` to `varchar(64)`.
2. `pytest tests/test_mission_structured_postgres.py` with `TEST_DATABASE_URL` set. It builds a scratch schema, copies
   the 0015 `daily_mission_variations` table there, runs 0019 upgrade and downgrade, checks `jsonb`/`text` types,
   NULL-ability, no defaults, intact ids and legacy values, and rolls everything back. It never touches real tables.
3. Optionally, on the same disposable database: `alembic upgrade head`, then
   `python -m app.cli audit-daily-missions --database` and `seed-daily-missions --compare-db` (read-only).
4. Before production: confirm `alembic_version.version_num` is at least `varchar(64)` or the shortest ids still fit
   (existing ids `0015_trusted_channel_upload_discovery` (37) and `0009_youtube_discovery_provenance` (33) already
   exceed 32, see docs/parent-approval-troubleshooting.md section 6).
Status: **not executed**; no verified disposable database was available (see the report).
