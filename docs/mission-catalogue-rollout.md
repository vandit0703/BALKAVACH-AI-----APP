# Mission catalogue rollout (seed and publish), exact commands

Run from `balkavach-backend` with `DATABASE_URL` set to the intended project database and migration 0019
(`0019_mission_instruction_fields`) applied. Every step except `--apply` is read-only. Flags verified against
`app/cli.py`.

1. Offline checks (no database): `python -m app.cli seed-daily-missions` (validates 42 templates / 378 versions) and
   `python -m app.cli audit-daily-missions` (expect 378 publish-ready, 0 INCOMPLETE, 0 SAFETY REVIEW).
2. Read-only comparison: `python -m app.cli seed-daily-missions --compare-db`
   (reports missing templates, conflicts with admin edits, rows that can be backfilled, published placeholders)
   and `python -m app.cli audit-daily-missions --database`.
3. Create missing rows and backfill empty structured fields on unedited rows (never overwrites an edit, publishes nothing):
   `python -m app.cli seed-daily-missions --apply --backfill-structured`
4. Publish, with the same validation as the admin endpoint (templates that fail are reported, not published):
   `python -m app.cli seed-daily-missions --apply --publish-existing`
   (`--publish` publishes only templates created by that run; `--publish-existing` also publishes pre-existing unedited ones.)
5. Verify: rerun step 2 (conflicts and backfillable should be 0 apart from admin edits) and `GET /api/v1/daily-missions/today`
   for a child of each age band and language.
6. Only after step 5, retire the migration-0015 placeholders (unpublishes, deletes nothing; edited ones are kept):
   `python -m app.cli seed-daily-missions --apply --retire-placeholders`

Re-running any step is idempotent. Rotation needs at least `MIN_ELIGIBLE_PER_THEME` published, complete templates per
weekday theme before the placeholders are retired; 6 per theme are published by step 4.
