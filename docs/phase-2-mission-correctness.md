# Phase 2: mission, reward and streak correctness (work log)

Status 2026-11-18. Everything here is **code + tests that ran without the PostgreSQL baseline**
(`tests/schema/baseline.sql` is still not in the repository). Nothing was run against PostgreSQL, so none of it is
"integration verified".

## What changed

| Area | Defect found | Change | Files |
|---|---|---|---|
| Skip / replacement (MIS-03) | `skip` never produced a replacement. (1) `autoflush=False`: the skipped row was still "current" when the choices were re-read, so the response contained the skipped mission. (2) After fixing that, the candidate list was cut to the same top 3, so a replacement could never be chosen (503). | flush before reading current choices; candidates exclude every template already issued today and are no longer cut to 3; free slots are filled in order; skip limit `MAX_SKIPS_PER_DAY = 2` (`daily_skip_limit`, 409); an empty catalogue answers `daily_mission_no_replacement` (409) instead of 503 | `app/services/daily_mission_service.py` |
| Weekly summary | a day with a skipped mission *and* its replacement was reported by row creation order | the day shows its current row, furthest-along status wins | same |
| Activity date (MIS-04) | `ChildActivityDay.activity_date` and the streak day came from **approval time** | activity day = family-local date of `task_submissions.submitted_at` (server-stamped; the client supplies no date); `submitted_at` and `reviewed_at` stay separate and untouched | `task_service.py`, `timezone_service.local_date_of` |
| Single streak writer (MIS-05) | `review_submission` computed a second, grace-less streak for badges | removed; badges read `record_qualifying_activity`'s result | `task_service.py` |
| Streak writer | could only date an activity "now" | `record_qualifying_activity(..., activity_date=D)`: judged as of day D (grace = D < last day + 3), never moves backwards, future dates clamped, resulting state computed from now | `streak_service.py` |
| One approval instant | stars/streak/entitlement each called `datetime.now()` separately | one `approved_at` for every write of an approval | `task_service.py` |

The approval-time entitlement rules (grant at approval, 900 s, family-local daily cap measured on *granted* seconds,
expiry at the end of the family-local day, one grant per submission) were reviewed and **left as they are**.

## Behaviour to know

* **Late approval**: a mission submitted on the 10th and approved on the 11th counts for the 10th. The streak is then
  `at_risk` (the 11th is still open) until the 11th is done.
* **Rejected then resubmitted**: the resubmission is a new submission, so it counts for the resubmission day.
* **Duplicate approval**: second approval is `409 submission_already_reviewed`; the ledgers use idempotency keys
  (`task-approved:{submission}:stars|xp`, `daily-surprise:{submission}:stars`) and the entitlement is unique per submission.
* **Out-of-order approvals** (Tuesday approved before Monday): the older activity does not backfill the streak. It never
  makes it worse; it may leave it one day lower than a full recompute would. Accepted limitation.
* **Family timezone change** between submission and approval re-dates the activity with the *current* timezone. Rare;
  not stored because no migration is allowed.

## Open decisions (not implemented, needs a product owner)

1. **D2 near-midnight approval.** The entitlement expires at the end of the family-local *approval* day, so an approval
   at 23:55 gives about 5 usable minutes. Extending validity into the next day needs `consume_video_allowance` and the
   allowance summary to stop bucketing by `granted_at` day, and it can let two days' allowance overlap (breaking the
   daily cap). Recommend: decide the rule first, then change both together in the Phase 3 milestone.
2. **D3 eligibility.** Any approved task, including parent chores, still grants video time. Recommend daily-mission tasks
   only; this is a visible product change for parents.
3. **D5 pool exhaustion.** Approved templates are excluded forever, so a child runs out of missions. Handled in
   milestone item 2 below.

## Historical data

Existing `child_activity_days` / `child_streaks` rows were written with approval dates. **Nothing was changed.**
To size the problem a person with read access can run (read-only):

```sql
-- approved daily-mission submissions whose submission day and approval day differ (UTC; repeat per family timezone)
SELECT count(*) FROM task_submissions
WHERE status = 'approved' AND (submitted_at AT TIME ZONE 'UTC')::date <> (reviewed_at AT TIME ZONE 'UTC')::date;
```

A correction, if wanted, must be a reviewed migration/script that recomputes `child_activity_days` and rebuilds
`child_streaks` from submission days per family timezone, run first on a restored copy.

## Tests

* `tests/test_daily_mission_skip.py` (9), `tests/test_streak_activity_date.py` (15), `tests/test_review_activity_date.py` (6),
  `tests/test_phase1_hardening.py` (8): run on an in-memory SQLite "world" (`tests/sqlite_world.py`) that reproduces
  `autoflush=False` and the partial unique slot index. **SQLite is not PostgreSQL**: no row locks, no `ON CONFLICT`, so
  `review_submission` itself is not executed by these.
* `tests/test_api_mission_dates.py` (3) and 4 additions to `tests/test_api_parent_mode.py` are PostgreSQL tests. They
  skip locally and have **never been run**.

# Next milestone: plan (do one at a time, in this order)

1. **Real localized seven-day mission catalogue.** Content, not code: 7 themes x 3 age bands x en/gu/hi, each
   safety-reviewed; load through the existing admin template/variation endpoints (publish already enforces all 9
   variations). Add a catalogue-completeness check (CLI + admin card) so an incomplete theme is visible. Needs the content
   team's output; the code is about 2 days.
2. **Rotation and repeat prevention (D5).** Replace "exclude approved forever" with a cool-down (default 6 weeks) derived
   from `daily_mission_assignments`; avoid the last two `variation_key`s; at most 2 surprise missions per week; log + admin
   warning when the eligible pool is under 6. No schema change. Tests: 60 consecutive approved days still yield 3 choices.
3. **Server-enforced video time and playback locking (Phase 3).** `POST /video-access/play` tickets (<= 60 s), heartbeat
   crediting, one active ticket per child, feeds withhold `youtube_video_id` when exhausted. One additive migration
   (`video_play_tickets`; already allowed). Resolve D2 first. Needs a real YouTube player to test on device.
4. **Trusted YouTube channel administration and scheduled re-checking.** Admin UI for trusted channels + a scheduled
   re-check job using the scheduler documented in `docs/scheduler-deployment.md`; first confirm that scheduler actually
   runs (OPS-02).
