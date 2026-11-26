# Approved mission still shows video locked: fix report

Date: 2026-11-26 · Branch `main` · HEAD `1d968cf` ("quiz", committed by the owner during this session; the previous HEAD was `a1d19f5`). Nothing was committed, pushed, deployed or migrated.

## Root cause

**The backend never grants video time on approval.** Commit `960926c` ("MISSION DONE", 2026-11-22) deleted the call to `grant_mission_video_entitlement(...)` (and its "video time unlocked" notification and schema pre-check) from `task_service.review_submission`. It replaced them with the comment *"Mission approval credits stars/XP only; it must not create ... video entitlements"*, and rewrote `tests/test_parent_mission_approval.py` to assert that no entitlement is created.

Later, the free daily allowance became 0 (`FREE_DAILY_ALLOWANCE_SECONDS = 0`). Together this leaves **no source of video time at all**: approval pays stars and XP, the child's balance stays 0, and every feed item stays `playback_locked`. The grant function, consumption, carry-forward, and the Flutter refresh were all intact. Only the call was missing.

The Flutter app was designed to refresh the balance when the server's `mission_video_time_granted` notification appears (`videoTimeGrantCountProvider`). That notification was also removed in `960926c`, so that refresh path never fired either.

## Approval → entitlement call chain (after the fix)

1. Child submits: `POST /api/v1/tasks/{id}/submissions` → `task_service.submit_completion` (submission `pending`, daily assignment `pending_parent_approval`).
2. Parent approves: `POST /api/v1/reviews/submissions/{id}` → `task_service.review_submission` (wrapped by `_all_or_nothing`).
3. Row locks (`SELECT … FOR UPDATE`) on the submission, task and child; family membership is checked. A repeat of the same decision returns the existing result and writes nothing; a different decision returns 409.
4. **Restored:** if the reflected schema lacks the entitlement columns (`missing_mission_allowance_columns()`), the request is refused with **503 `video_allowance_unavailable`** before anything is written.
5. Stars and XP ledger rows (idempotency keys `task-approved:{submission}:stars|xp`), progress, activity day, streak, badges.
6. **Restored:** `grant_mission_video_entitlement(session, child, task, submission)` inserts one `video_access_entitlements` row: `source_type='mission_reward'`, `child_id` = the submission's child, `submission_id` (unique, used for idempotency), `granted_seconds=900`, `consumed_seconds=0`, `expires_at=NULL` (carries forward), `status='active'`. Whole or nothing: if the family's daily mission-video cap (default 3600 s) has no 900 s room left, it grants 0 (an existing rule, unchanged). It then creates the `mission_video_time_granted` notification.
7. One `session.commit()`. Any failure rolls back the approval, stars, XP and grant together (`approval_failed`, 500).
8. Child: `GET /api/v1/video-access/allowance` → `get_child_video_allowance_today`: `remaining = free_remaining (0) + Σ(active mission grants − consumed)`, all days.
9. Flutter refreshes the balance from: the grant notification count, push, app resume, return to Home, the lock screen's periodic check, and (**new**) `MissionApprovalCelebrator` as soon as it detects a newly approved submission.
10. Before any playback, `ensureVideoAllowance` re-asks the server; players then receive playable ids.

Diagnostic log (new; internal UUIDs only, no names, tokens or secrets):
`Mission review committed (submission=… child=… decision=approved video_grant_attempted=True existing_entitlement=False seconds_granted=900)`, and on failure `Mission review rolled back (submission=… child=… decision=… video_grant_attempted=…)`. The grant function keeps its own "already exists" and "daily cap reached" logs.

## Files changed

Backend
- `app/services/task_service.py`: restored the schema pre-check (503) and the grant + notification inside the approval transaction; added commit/rollback diagnostics.
- `app/services/video_entitlement_service.py`: `has_mission_entitlement_for(session, submission_id)` (read-only helper for the diagnostic).
- `tests/test_parent_mission_approval.py`: the 7 assertions `960926c` reversed are restored to the original spec (900 s once, a full cap still pays stars/XP, rollback on a failed grant, 503 without schema).
- `tests/test_mission_approval_video_grant.py` (new, 10 tests): locked → 900 s via the real allowance endpoint, correct child/submission, 1800 s for two missions, double approval = 900 s, rejected/retry/pending = 0, rejected-then-approve = 409 and 0 s, carry-forward to a later day, consumption never negative.

Frontend (`balkavach-frontend/`)
- `lib/features/missions/presentation/mission_approval_celebrator.dart`: on a newly detected approval, invalidates `videoAllowanceProvider` and `childNotificationsProvider` immediately (before the celebration).
- `test/features/approval_unlocks_video_test.dart` (new, 4 tests).

No rule changed: free allowance 0, 900 s per approved mission, once per submission, carry-forward, cap behaviour, and server authority all stay as they were. No client value is trusted.

## Database schema requirements

The grant needs `video_access_entitlements` with `child_id, source_type, task_id, submission_id (unique), granted_seconds, consumed_seconds, granted_at, valid_from, expires_at (nullable), status` (migrations `0013`/`0015` era). The allowance needs `child_video_daily_usage` (`0016`). Migrations `0021` and `0022` are not required by this fix; they are needed by quizzes and interests.

**Deployment caution:** on the local reconstructed schema, `0022_production_readiness` failed with `DuplicateColumn: redemption_requests.cancelled_at`, because the reconstruction (not production DDL) already had that column. Before running `0022` in production, check whether `redemption_requests.cancelled_at` already exists.

## API response before / after (child, one approved mission, no prior time)

`GET /api/v1/video-access/allowance`

| field | before (HEAD) | after |
|---|---|---|
| `remaining_seconds` | 0 | 900 |
| `mission_remaining_seconds` | 0 | 900 |
| `free_allowance_seconds` | 0 | 0 |
| `is_exhausted` | true | false |
| `active_entitlements_count` | 0 | 1 |

(Taken from `test_child_is_locked_before_and_unlocked_with_900_seconds_after_approval`, which drives the real routes.)

## Tests

| Suite | Unfixed code | With fix |
|---|---|---|
| `test_parent_mission_approval.py` (restored spec, SQLite) | 7 failed, 13 passed | **20 passed** |
| `test_mission_approval_video_grant.py` (new, SQLite) | 4 failed (every grant case), 4 passed | **10 passed** |
| `test_parent_approval_postgres.py` (**real PostgreSQL 16**) | 19 failed, 4 passed | **18 passed, 5 failed** (see below) |
| Full backend, no DB (`pytest tests`) | — | 52 failed, 1100 passed, 284 skipped: same failure set as HEAD |
| `approval_unlocks_video_test.dart` | refresh test fails with the new invalidation disabled | **4 passed** |
| Full frontend `flutter test` | — | **2748 passed, 2 skipped, 0 failed** |
| `flutter analyze` | — | 2 infos, both from before this change, in untouched test lines |

**PostgreSQL integration** ran on a disposable local cluster (`pgserver`, 127.0.0.1, database `balkavach_test`, reconstructed baseline + `alembic upgrade head` to `0022`, fakeredis). It confirmed on real PostgreSQL row locks and unique keys: 2 and 10 simultaneous approvals and approve-vs-decline races create **exactly one 900 s entitlement**; a failure in any step (stars, XP, allowance, streak) rolls back everything and a retry succeeds; pushes never undo a commit. The 5 remaining failures are not about video time:
- 4 concurrency tests expect 10 Stars / 15 XP, but their fixture inserts a task with `star_reward=5, xp_reward=10`, and approval pays the task's configured amounts. Their other fields (`grants: 1`, `seconds: 900`, reviews, status) match. This is the existing open question of fixed 10/15 rewards versus task-configured rewards. It is out of scope and unchanged.
- `test_a_database_without_migration_0013…` builds its own fresh database and hits the `cancelled_at` duplicate above.

The reconstructed baseline is my inference from the code and migrations, not production's schema.

Pre-existing, unrelated backend failures (they fail identically at HEAD): play tickets (19), video time alerts (10), feed real filters (4), entitlement unit tests built on fakes for the old midnight-expiry / 900-free rules (5, e.g. `test_mission_approved_before_midnight_expires_at_local_midnight`; these contradict the confirmed carry-forward and zero-free rules), metering, catalogue, authorization boundaries. `test_mission_catalogue.py::test_the_weekday_theme_is_offered` is flaky on both trees.

**Concurrent edits:** between 13:34 and 13:41, while the full suites were running, another writer modified `app/api/v1/videos.py`, `tests/feed_world.py`, the child interests card, and the l10n files, and added `tests/test_interest_recommendation_ranking.py` and `tests/test_parent_interest_management_pg.py`. Those are not part of this fix and were left untouched. The full-suite counts above may include part of those edits. After they landed, the targeted suites were re-run on the current tree: backend approval tests **30 passed**; frontend approval/celebration/allowance tests **35 passed**.

## Production check (read-only, unauthenticated)

`GET https://api.balkavach.tech/openapi.json`, no credentials, no writes:
- Production was redeployed during the day: 186 → 207 operations; `/quizzes` and `/videos/interests` now exist.
- `VideoAllowancePublic` defaults are `free_allowance_seconds: 900`, which matches `a1d19f5` and not `1d968cf` (which sets them to 0). **Production runs `a1d19f5`**, where `FREE_DAILY_ALLOWANCE_SECONDS = 0` and `review_submission` grants nothing. That reproduces the reported bug exactly.
- Whether migrations `0021`/`0022` are applied cannot be seen without an authenticated request; none was made.

## Device verification

Not performed: no Android device or emulator is attached. Against production it would also still fail until this fix is deployed.

## Deployment requirements (separate approval needed)

1. Deploy a commit containing this change (current working tree on top of `1d968cf`).
2. No new migration is needed for the grant. Confirm production has `video_access_entitlements.submission_id/source_type/task_id` (`0013`); if not, approvals now return 503 `video_allowance_unavailable` instead of silently granting nothing.
3. Before running `0022`, check `redemption_requests.cancelled_at` (see above).
4. Missions approved while the bug was live earned no time, and **this fix does not back-fill them**. Granting that time retroactively would be a data change on production, which needs the owner's decision.
