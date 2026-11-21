# Parent mission approval: "The server had a problem" (2026-11-21)

Status: **the production cause is still not confirmed.** The approval is hardened and was verified on a disposable LOCAL
PostgreSQL built from a *reconstructed* baseline (`balkavach-backend/tests/schema/reconstructed_baseline.sql`). That file is my
reconstruction from the code and migrations, **not a dump of production**, so it proves the application logic on real
PostgreSQL semantics, not what constraints production has. Nothing here touched a production or staging database.

## 1. What one approval does (`POST /api/v1/reviews/submissions/{id}`, `task_service.review_submission`)
One transaction, all or nothing: review row, submission and daily-assignment status, **10 stars**, **15 XP**, streak and badges,
the **15 minute** video allowance, then notifications; pushes go out only after commit.

### Schema the approval transaction requires
| Table | Needed | Source / why |
|---|---|---|
| `task_submissions` | `status`, `reviewed_at`, `submitted_at`; row lock `FOR UPDATE` | the row lock is what serialises two simultaneous reviews |
| `task_reviews` | `submission_id`, `reviewed_by`, `decision`, `review_note`, `created_at` | insert |
| `tasks` | `family_id`, `title`, rewards (history only) | read, locked |
| `family_members` | `family_id`, `user_id`, `is_active` | authorisation: the parent must belong to the family |
| `daily_mission_assignments` | `status` CHECK allows `approved` and `rejected` | 0015 `daily_assignment_status_check` (confirmed in the repo) |
| `star_transactions` | `child_id, amount, transaction_type, submission_id, idempotency_key, description` | insert `task_approved`, +10 |
| `xp_transactions` | `child_id, amount, submission_id, reason, idempotency_key` | insert `task_approved`, +15 |
| `child_progress` | **unique/PK on `child_id`** | `INSERT ... ON CONFLICT (child_id) DO UPDATE` fails with "no unique or exclusion constraint matching" if absent |
| `child_activity_days` | **unique index on exactly `(child_id, activity_date)`** | `ON CONFLICT (child_id, activity_date)` |
| `child_streaks`, `child_badges`, `badges`, `levels` | columns used by streak/badge code (0012 adds streak columns) | read/write |
| `notifications` | `recipient_user_id, notification_type, title, message, related_*`; **no CHECK on `notification_type`** | new types are inserted (`task_approved`, `mission_video_time_granted`, streak types) |
| `video_access_entitlements` | `task_id`, `submission_id` (**unique**), `source_type` with CHECK allowing `mission_reward`, `granted_seconds`, `consumed_seconds`, `granted_at`, `valid_from`, `expires_at`, `status` | **migration 0013** adds `task_id`, `submission_id` (+unique), `source_type` (+CHECK) and an index |
| same table | **`video_id` and `video_collection_id` must be nullable, with no "exactly one target" rule** | the mission grant writes both as NULL. **Migration 0013 does not relax any such rule.** The star-redemption path always sets exactly one target, so a baseline rule like that is plausible. |

Not assumed: nothing above is known to be present or absent in production.

### Two independent ways production could fail every approval (both reproduced locally)
1. **Migration 0013 not applied.** The grant would raise `AttributeError: type object 'video_access_entitlements' has no attribute 'submission_id'` (reproduced) and the parent saw a generic 500. Now the approval is refused first with `503 video_allowance_unavailable`, nothing written.
2. **A baseline rule requiring a video target** on `video_access_entitlements` (`video_id NOT NULL`, or a CHECK "exactly one of video_id / video_collection_id"). Every mission grant hits an `IntegrityError`; the approval rolls back with `500 approval_failed` (both variants reproduced). **No code change can satisfy this without a schema change**, which needs your authorisation.

Both would have been present since the allowance feature shipped, which fits "approval has never worked in production" and does *not* depend on the recent mission changes. Other candidate causes were checked and ruled out locally: response parsing, request shape, authentication, status transitions, the reward amounts, the response serialisation.

## 2. Evidence needed from the production operator (read-only; nothing here writes)
Run against production only with your approval, using a read-only role.
```sql
-- A. Is migration 0013 present?  expect the three columns below
select column_name, is_nullable from information_schema.columns
where table_name = 'video_access_entitlements' order by ordinal_position;
select version_num from alembic_version;

-- B. Any rule requiring a video target, or restricting source_type?
select conname, contype, pg_get_constraintdef(oid)
from pg_constraint where conrelid = 'video_access_entitlements'::regclass;

-- C. Are the star/XP idempotency keys unique in the database?
select c.relname, i.indisunique, pg_get_indexdef(i.indexrelid)
from pg_index i join pg_class c on c.oid = i.indrelid
where c.relname in ('star_transactions','xp_transactions');

-- D. The upsert targets the approval needs
select c.relname, pg_get_indexdef(i.indexrelid) from pg_index i join pg_class c on c.oid = i.indrelid
where c.relname in ('child_progress','child_activity_days') and i.indisunique;

-- E. Any CHECK that could reject the new notification types?
select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'notifications'::regclass and contype = 'c';
```
And from the Render logs around one failed tap (server logs now name the failing rule, never row values):
* `Mission approval refused: the database lacks the video allowance schema (...)` (critical), or
* `Mission approval failed and was rolled back (submission ..., decision approved): <ExceptionType>` with a traceback, or
* `Unhandled database request error (<Type> sqlstate=.. constraint=.. table=.. column=..) on POST /api/v1/reviews/...`.

If the production deployment predates these changes, the failing line is the older `Unhandled request error` with a traceback; send that traceback.

## 3. PostgreSQL verification (local, disposable, reconstructed baseline)
Tests: `balkavach-backend/tests/test_parent_approval_postgres.py` (23 tests) plus the repo's existing PostgreSQL tests, run with
`TEST_DATABASE_URL` set (see `scripts/testenv.py`; recipe in the project memory).

| Required check | Result |
|---|---|
| Successful approval (10 stars, 15 XP, 900 s, review row, counts Pending/Approved/Retry) | passes |
| Decline and retry pay nothing, move the counts | passes |
| Rollback when stars, XP, allowance or streak processing fails; retry then succeeds | passes (4 stages) |
| Repeat after a lost response | returns the existing result (200), pays nothing more |
| Conflicting decisions | 409, nothing changes |
| Two concurrent requests, same submission | pay once (also 10 at once) |
| Approve vs decline racing | exactly one winner, the other gets 409 |
| Cross-family approval | 404, nothing changes |
| Unique reward idempotency | star and XP duplicate keys fail the whole approval, nothing half written |
| Missing allowance schema (0013 removed) | 503 `video_allowance_unavailable`, nothing written; decline still works; without the check the same schema gives `AttributeError` |
| Video target rule (two variants) | 500 `approval_failed`, rolled back |
| Failing FCM (exception, hard error, transient retry) | approval stays committed |

**The concurrency tests are real, not trivially passing:** removing `FOR UPDATE` from every statement (a scratch pytest plugin, no app
change) makes all four concurrency tests fail (approve and decline both "succeeded", duplicates, or collisions).

### Database-level uniqueness for stars and XP
* In the repository: `video_access_entitlements.submission_id` is **unique** (migration 0013). **No migration creates a unique key on
  `star_transactions.idempotency_key` or `xp_transactions.idempotency_key`**; the baseline is not in the repo. The local database has
  them only because my reconstruction declares them.
* **Safe without them:** `test_without_a_database_unique_key_the_row_lock_still_prevents_double_payment` drops both keys, races ten
  approvals and still pays once, because the submission row is locked `FOR UPDATE` and re-checked as pending. So duplicate prevention
  does not need a migration, but it does depend on the row lock, which only PostgreSQL provides (verified locally; not on production).

## 4. Notification transaction safety (code read + PostgreSQL tests)
| Question | Finding |
|---|---|
| Rows created in the same transaction? | Yes (`create_notification` adds to the session); a failed approval leaves none (tested). |
| External dispatch only after commit? | Yes: `stage_push` queues, `after_commit` promotes, `get_db` delivers after the request; `after_rollback` discards. A rolled-back approval sends no push (tested). |
| Failed FCM can undo an approval? | No (tested: exception, hard error and transient-retry all leave the approval committed). Delivery runs in an executor with its own session; exceptions are logged. |
| Retried safely? | Only in-process: up to 3 attempts (0.5 s, 2 s) for a transient `retry`; an exception or hard error is not retried. **There is no durable outbox**: a process crash after commit, or an outage longer than a few seconds, loses that push (the in-app notification remains). |
| Duplicates? | Repeating an approval creates no second notification and no second push (tested); a batch de-duplicates per (user, notification). |

Caveat: another session was editing `push_service.py`, `notification_service.py` and `fcm.py` while this was checked; tests use
fake providers, not real FCM.

## 5. Video allowance policy: the exact current rule and the open decision
Current behaviour (`video_entitlement_service.grant_mission_video_entitlement`):
* Every child has a free 900 s per family-local day (separate from the cap).
* An approved mission grants **900 s or nothing**.
* The parent's cap (`video_settings.daily_limit_seconds`, default **3600 s**, clamped to 900-14 400 s) limits the mission seconds **granted** that day; watching does not create room.
* With the default cap: missions 1-4 each grant 15 min; **from the 5th mission the approval still pays 10 stars and 15 XP but grants no video time**, and nothing tells the child or the parent that no time was earned.
* A cap that is not a multiple of 900 s wastes the remainder (cap 1000 s: one mission, 100 s unused).

**This conflicts with your stated rule ("15 minutes per approved mission") whenever the cap is reached, and it is not mine to choose.**
Also note: `docs/video-allowance-policy.md` says the cap rules were *approved by the product owner on 2026-11-19; do not change
without approval*. Before my change of 2026-11-21 the code granted a **partial remainder**; I changed it to whole-or-nothing on
my own reading of your request. That change needs your decision, not mine.

Decision needed (pick one):
1. **Keep the parental cap, whole 15 minutes or nothing** (current code).
2. **Keep the cap, grant the partial remainder** (the owner-approved 2026-11-19 behaviour; restore by one line).
3. **Every approved mission grants 15 minutes whatever the cap** (the cap then only limits watching per day, which needs its own rule).
Independent of the choice, I recommend telling the child and parent when a mission earned no time (today it is silent).
Stars and XP are independent of the allowance in every option.

## 6. Other findings (do not block approval, but matter for deployment)
* `alembic upgrade head` fails on a standard Alembic table: `alembic_version.version_num` is `varchar(32)` and revision `0009_youtube_discovery_provenance` is 33 characters. Production must have widened it or applied migrations another way.
* Migration `0015_daily_mission_engine` seeds JSONB columns with an untyped `bulk_insert`; **psycopg 3 (the driver this app uses) cannot adapt a Python dict/list there**. On a database that has not applied 0015, `alembic upgrade head` fails. I did not change the migration; locally a dict/list-to-JSONB adapter was registered for the alembic process only.
* `tests/schema/baseline.sql` does not exist, so the CI PostgreSQL job cannot run. `reconstructed_baseline.sql` is a stand-in for local work only.
* PostgreSQL tests not passing for reasons unrelated to approval: admin, YouTube, parent-mode and learning suites need production seed data and tables that were not reconstructed (`admin_roles`, `audit_logs`, `educational_content`, `video_watch_sessions`); three password-reset tests hit a naive-versus-aware datetime mismatch on the token table created by migration 0014.

## 7. Deployment prerequisites
1. Read the Render logs and run section 2's queries (read-only). That settles the cause.
2. If 0013 is missing: apply it through the normal approved migration process (also check 0016 and the `alembic_version` width).
3. If a video-target rule exists: a schema change relaxing it is required (needs your authorisation); the code cannot work around it.
4. Deploy the backend and the app together (the app's card reads the new `video_minutes_reward` field; older builds show only stars).
5. Run CI on a PostgreSQL loaded with the **real** schema dump (create `tests/schema/baseline.sql`; `scripts/testenv.py load-schema`).

## 8. Not verified
The production schema, constraints and logs; the real FCM service; the failing PostgreSQL suites listed above; behaviour on Neon.
