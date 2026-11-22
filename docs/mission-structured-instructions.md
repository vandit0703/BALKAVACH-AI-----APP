# Structured mission instructions (migration 0019)

Status: **written, not executed against any database.** Applying it, seeding and publishing need separate approval.

## Why

Missions showed text like "A creative learning adventure for ages 11 to 15" / "Try the steps, notice what you
discover…". That text is the placeholder data inserted by migration `0015_daily_mission_engine` (22 templates x 3 ages x
3 languages). The curated catalogue in `balkavach-backend/app/content/daily_missions/` (42 missions, 126 age-specific
missions, 378 localized versions) has real steps, but they were stored only as numbered lines inside one `instructions`
text column, and there was no place for "what you will learn", "what to observe" or "what to submit".

## Migration `0019_mission_structured_instructions`

* Revision chain: `0018_mission_video_requirements` -> `0019_mission_structured_instructions` (single head).
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
