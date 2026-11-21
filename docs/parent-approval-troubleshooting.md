# Parent mission approval: "The server had a problem" (2026-11-21)

Status: hardened and tested locally on SQLite; **the production cause is not confirmed** (no PostgreSQL or live schema was
available, and the baseline schema is not in the repository). Nothing here was run against production.

## What an approval does (`POST /api/v1/reviews/submissions/{id}`)
One transaction: review row, submission and daily-assignment status, **10 stars**, **15 XP**, then the **15 minute** video
allowance, then notifications. Any failure rolls all of it back. Stars, XP and minutes are separate rows written by separate code
(`mission_rewards.py`, `task_service.review_submission`, `video_entitlement_service.grant_mission_video_entitlement`).

## What the app can now report
| Response | Code | Meaning | Parent sees |
|---|---|---|---|
| 200 | | approved, or a repeat of an approval that already succeeded (nothing paid twice) | "Approved! … earned 10 stars, 15 XP and 15 minutes" |
| 409 | `submission_already_reviewed` | a *different* decision was already recorded | already reviewed, lists refreshed |
| 404 | `submission_not_found` | unknown id or another family's | not found |
| 503 | `video_allowance_unavailable` | the database lacks the allowance columns; **nothing was written** | video time cannot be granted, nothing awarded |
| 500 | `approval_failed` | anything else failed; everything was rolled back | not saved, nothing awarded, try again |

## Confirm the cause (read-only; run against production only with your approval)
1. **Server log** (Render logs for the web service, around the failed tap). Look for either:
   * `Mission approval refused: the database lacks the video allowance schema (...)` (critical), or
   * `Mission approval failed and was rolled back (submission ..., decision approved): <ExceptionType>` with a traceback, or
   * `Unhandled database request error (<Type> sqlstate=.. constraint=.. table=.. column=..) on POST /api/v1/reviews/...`
     (the constraint and table are now logged; values never are).
2. **Schema check** (read-only SQL):
   ```sql
   select column_name from information_schema.columns
   where table_name = 'video_access_entitlements' order by 1;
   -- expect: submission_id, task_id, source_type (migration 0013), plus granted_seconds, consumed_seconds, ...
   select version_num from alembic_version;      -- expect 0013_mission_video_entitlement to be in the applied chain
   select conname, pg_get_constraintdef(oid) from pg_constraint
   where conrelid in ('video_access_entitlements'::regclass, 'star_transactions'::regclass, 'xp_transactions'::regclass);
   -- look for CHECK or NOT NULL rules the approval inserts could break (for example video_id / video_collection_id NOT NULL)
   ```
3. **Is the idempotency key unique in the database?** `star_transactions.idempotency_key` and `xp_transactions.idempotency_key`
   should have unique indexes; the repository cannot show this.

## If it is the missing migration
Apply `0013_mission_video_entitlement` (and `0017_child_video_daily_allowance`) through the normal, approved migration process.
**Do not run migrations without a separate decision**; approvals of missions stay refused (503) until then, by design: a mission
must not be approved without all three rewards.

## Not verified
PostgreSQL behaviour (row locks that serialise two simultaneous approvals, the live schema, error behaviour), and the three
PostgreSQL-only tests updated to expect a 200 repeat (`test_api_mission_flow.py`, `test_e2e_core_journey.py`,
`test_api_mission_rewards.py`). Run CI on a disposable PostgreSQL before relying on any of it.
