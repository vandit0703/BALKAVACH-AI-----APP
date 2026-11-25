# Mission Library (500-concept catalogue): implementation plan

Status: 2026-11-25. Pilot batch only. Nothing is published, committed or applied outside a disposable local database.

## What already exists (verified in the repository)

| Area | What is there |
| --- | --- |
| Tables | `daily_mission_templates` (slug, theme, mission_type, is_published, ...), `daily_mission_variations` (one row per template x age band x locale x `variation_key`), `daily_mission_assignments` (per child, per family-local date, 3 choice slots, snapshot, history). Migrations 0015, 0019 (structured columns `learning_objective`, `steps`, `observation_guidance`, `submission_requirements`). |
| Core catalogue `c1` | `app/content/daily_missions/`: 42 templates (7 weekday themes x 6) x 3 age bands x en/gu/hi = 378 variations. |
| Seeder | `python -m app.cli seed-daily-missions`: dry run by default, `--compare-db` (read-only), `--apply` (insert missing only, never update or delete), `--publish`, `--publish-existing`, `--backfill-structured`, `--retire-placeholders`. |
| Validation | `mission_catalogue_service.validate_catalogue` (script checks, romanisation, restricted terms, pressure words, admin validator, task text length), `mission_instructions.validate_content` (steps, materials, submission, safety), `mission_audit_service` (COMPLETE / NEEDS IMPROVEMENT / INCOMPLETE / SAFETY REVIEW). |
| Selection | `daily_mission_service.ensure_daily_choices` + `mission_rotation_service`: 3 choices per child per family-local day, stored once (stable on refresh), age band from birth date, 42-day cooldown from the child's own history, variety across themes. **It also ranks missions of "today's weekday theme" first** (`THEMES_BY_WEEKDAY`). |
| Rewards | `mission_rewards`: 10 Stars / 15 XP, paid only through the existing approval + ledger pipeline. Not touched. |
| Child UI | Already renders title, description, learning objective, materials, duration, steps, observation guidance, submission requirements, safety, completion. `theme` is not shown. No UI change is needed for new content. |
| Admin | Template list (all templates in one expandable card), per-template preview of all 9 versions, variation editor, publish switch, catalogue health per weekday theme. No category / age / language filter or search for templates. |

## Design (no new tables, no migration)

* New content package `app/content/mission_library/` (plain data). Each concept = one template; `theme` = one of 24 developmental categories; slug prefix `lib_`. It is converted into exactly the dict shape of the core catalogue, so the existing `variation_payload`, validator, seeder, compare and audit work unchanged.
* Every variation stores: title, description, learning objective, numbered steps (+ "Another way" line), materials, duration, safety, completion criteria (+ parent check line), observation guidance, submission requirements. Same columns as `c1`.
* `mission_library_service` adds library rules on top of the core checks: 24 known categories; age-scaled durations (4-6: 5-10 min, 7-10: 8-15, 11-15: 10-20, never shorter for an older band); step counts per band (3-4 / 4-5 / 5-7); objective, observation and submission required in all 3 languages; steps of two bands of one concept must differ; near-duplicate detection across the **whole** catalogue (core + library, every age band); localisation checks (missing / empty fields, Latin letters in hi/gu, English left in hi/gu, step / material count mismatch, numbers that differ between languages, implausible length ratios); extra restricted terms (internet, social media, downloads, speed races).
* Translation review: every concept carries a per-language review status. Hindi and Gujarati written here are `pending` native review. **The seeder will not publish a library concept whose translations are pending**; it reports them instead.
* Seeder: `seed-daily-missions --source core|library|all` (default `core`, so existing behaviour and tests are unchanged). Output adds inserted / updated / unchanged / skipped / failed counts.
* Reports: `python -m app.cli mission-library-report` prints category distribution, age coverage, language completeness, duplicate audit and the human-review list.

## Decisions needed from the product owner

1. **Weekday theme bias in rotation.** Existing code ranks the weekday theme first, so slot 1 is a weekday-theme mission most days. Recommendation: remove the weekday preference (rank all categories equally, keep cooldown, history and variety). Not changed until approved.
2. **Daily shape.** The existing engine offers 3 choices per child per day and the child picks 1. The plan keeps that (no second mission system). Confirm.
3. **Authoring scale.** Concepts at the quality of `c1` are about 15-20 KB each in three scripts. 500 concepts are written in batches; each batch is validated before the next. Hindi/Gujarati need native-speaker review before publishing.
4. **Admin filters.** Category / age / language filter, search and pagination for the template list (Flutter Web Admin + query parameters on `GET /admin/daily-missions/templates`). Planned for the batch after approval.

## Batches

| Batch | Content | Status |
| --- | --- | --- |
| 0 | Infrastructure, validation, reports, seeder source flag, tests | this session |
| 1 | 12 pilot concepts, one in each of 12 categories | this session |
| 2+ | ~20 concepts per batch until every category has ~21 | pending approval of the pilot |
