# Production video feed recovery procedure

Prepared 2026-11-21 **without connecting to production or staging**. Nothing here has been run against a real database,
the real YouTube API, or any deployed service. Every "verified" below says what kind of verification it was.

Read first: `docs/video-feed-restoration.md` (what was built and why), `docs/youtube-operations.md`, `docs/scheduler-deployment.md`.

## 0. Summary for the owner

1. **Status update 2026-11-21:** the new commands and the feed change are now **committed and pushed to `origin/main`** (commits
   `0ceda6f`, `77470d9`, `63b959a`; the last two were made by the repository owner while this work was in progress). **Whether Render
   built and deployed them is unknown**: read the deployed commit in the Render dashboard before assuming any new command exists.
   Production as last known ran `822892a`, where only `create-admin`, `youtube-report`, `streak-check` and `youtube-recheck`
   exist. Two read-only things work there: `python -m app.cli youtube-report` and
   `GET /api/v1/admin/videos/youtube/diagnostics` (both show `approved_stale` and `oldest_approved_verification`).
2. **A recheck bug was found and fixed locally** (needs the same deploy): permanently `unavailable` videos kept their old timestamp,
   sorted first, and could fill the whole `--limit` batch so approved videos were never re-verified. Approved videos now go first.
   Until the fix is deployed, use `--limit 1000` and check `unavailable` in `youtube-report` (section 4.3).
3. **The production host is not proven.** Render is the best-supported answer, but nothing in the repository confirms it
   (section 2.1). Do not create systemd timers on the VPS until you have confirmed which host serves `api.balkavach.tech`.
4. **Recheck is the only mutating step and it needs your explicit approval** (section 5), a database snapshot, and a 5-video canary run first.
5. Recheck fixes only *stale verification*. If the diagnosis shows another cause (no approved videos, no birth date, wrong
   language, all videos finished) it will not help, and running it is not appropriate (section 3.2).

## 1. What each command does (inspected, and tested locally on SQLite)

| Command | Writes? | What it writes | Exit codes | Deployed today? |
|---|---|---|---|---|
| `youtube-report` | **No** | none (rolls back) | 0 ok, 2 no `DATABASE_URL` / database error | yes (older output: no `last_recheck_*`) |
| `youtube-recheck-health [--max-age-hours N]` | **No** | none | 0 healthy, **3 unhealthy**, 2 no `DATABASE_URL` / database error | no |
| `video-feed-diagnose --child-id ID` or `--age N [--language en\|hi\|gu]` | **No** | none | 0 ok, 1 child not found, 2 no `DATABASE_URL` / database error / bad arguments | no |
| `youtube-recheck [--limit 1-1000]` | **Yes** | see 1.2 | 0 ok, 1 handled error (key missing/rejected, quota, YouTube unreachable, tables missing), 2 no `DATABASE_URL` / database error | yes (without ordering fix, failure audit row) |
| `youtube-discover`, `youtube-auto-review` | **Yes, and may publish** | new candidates, auto-approval and publication under the existing policy | 0, 1 (actor missing, YouTube error), 2 | yes. **Do not run for recovery.** |
| `streak-check`, `seed-daily-missions --apply` | Yes | unrelated | | unrelated |

`argparse` errors (bad command or argument) also exit **2**, so exit 2 alone does not mean "database". Read stderr.

### 1.1 Read-only is enforced, not just claimed (local verification)
`youtube-report`, `youtube-recheck-health` and `video-feed-diagnose` run inside `cli._read_only(session)`: PostgreSQL
`SET TRANSACTION READ ONLY` (any INSERT/UPDATE/DELETE then raises and the command exits 2), rolled back on exit. Tests
(`tests/test_video_feed_cli.py`) prove on SQLite that a write attempted inside each command is blocked and that the PostgreSQL
statement is issued. **The PostgreSQL behaviour itself is not exercised locally.** If you want a second layer, use a database role
that has only `SELECT` for these three commands.

### 1.2 What `youtube-recheck` changes (code inspection + SQLite tests)
It does **not** only process stale videos. Each run takes up to `--limit` reviews in status `approved` or `unavailable`, **approved first,
then oldest `last_verified_at` first**, asks YouTube about them (50 ids per call), and for each:

| Before | YouTube says | After | Effect on the child feed |
|---|---|---|---|
| `approved` | public, embeddable, processed, made for kids, no new screening flag | `approved`; `last_verified_at = now`; title, description, thumbnail, duration, YouTube category refreshed | visible again (if published and eligible) |
| `approved` | missing, private, not embeddable/processed, or blocked in `YOUTUBE_REGION_CODE` | `unavailable`; **unpublished**; `content_rating` set to `parent_review_required`; `published_at` cleared | hidden |
| `approved` | not made for kids, age restricted, or a new screening flag | `quarantined`; withdrawn as above | hidden |
| `unavailable` | now fine | `pending_review` (**never straight back to approved**) | still hidden until an admin approves or auto-review passes |
| `unavailable` | still unavailable | unchanged (timestamp not touched) | hidden |
| `pending_review`, `quarantined`, `rejected`, `revoked` | not read at all | unchanged | hidden |

Every move writes an audit row (`youtube.unavailable`, `youtube.quarantined`, `youtube.pending_review`, with the previous status) and a
completed run writes `youtube.recheck.completed` with the counts. A failed run writes `youtube.recheck.failed` with the error code.
**Withdrawal is not automatically reversible**: the original `content_rating` and `published_at` are overwritten; the way back is an
administrator re-approving (which re-checks YouTube again) or a snapshot restore.

Hourly cost: every run re-checks up to `--limit` approved videos **whether or not they are stale**. At 200 videos that is 4 `videos.list`
calls (4 quota units) an hour, about 96 a day against YouTube's default 10,000. It is wasteful but safe, and it is what keeps timestamps
inside the 72 h window.

### 1.3 Concurrent runs (code inspection; **not tested locally**: SQLite has no row locks)
* Reviews are selected `FOR UPDATE SKIP LOCKED`. Two overlapping runs do not process the same row; the second skips what the first holds.
  They do not deadlock each other. The cost is duplicate YouTube calls for different rows, nothing worse.
* The run holds those row locks until it commits (one commit at the end, or a commit of earlier batches if YouTube fails). An
  administrator's approve/revoke/reject on a locked video **waits** for the run to finish. A run is normally seconds; the worst case
  at `--limit 1000` (20 calls, 5 s timeout, 3 attempts each) is about 5 minutes. Run the first manual recheck at a quiet time.
* The video row itself is not locked by recheck; a simultaneous admin edit of the same video could be overwritten by the refresh. Rare;
  avoid editing videos during the run.
* `youtube-discover` must not overlap itself (documented); it may run beside recheck.

## 2. Deployment requirements

### 2.1 Which host? (evidence only; not proven)

| Evidence | Points to |
|---|---|
| `balkavach-frontend/lib/core/network/api_client.dart:8` and `docs/frontend-architecture.md:110`: timeouts "sized for a cold Render instance... observed" | Render (developers saw cold starts) |
| `docs/backend-operations.md:206`, `docs/phase-a-video-playback-architecture.md:48,78`: "Render's default", "Render Redis URL" | Render |
| `docs/youtube-operations.md` §2: cron job instructions for Render | Render (a plan, not proof it exists) |
| `docs/backend-operations.md`: "Neon: create a branch or use point-in-time restore" | database is Neon |
| `servecmd.txt` (git-ignored): an interactive `root` SSH session to an Ubuntu 24.04 host whose home holds only `balkavach-backup` and `snap`; no application directory listed | VPS looks like a **backup box**, not shown to run the API |
| `docs/security-ssh-remediation.md`: "is this VPS production, staging, a backup box, or retired?" listed as an open question | undecided |
| Repository has no `render.yaml`, Procfile, Dockerfile, deploy workflow or systemd unit (only the examples added in `balkavach-backend/deploy/`) | no declared deployment |

**Conclusion: Render is the best-supported host; it is not proven.** Confirm before scheduling anything (any one is enough):
1. Render dashboard: a web service has the custom domain `api.balkavach.tech`; note its **deployed commit**.
2. DNS: `api.balkavach.tech` resolves to the same target the Render service shows (a CNAME to `*.onrender.com` is typical).
3. Compare the VPS public IP with the DNS answer; if they differ, the VPS does not serve the API.

### 2.2 Is the deployment on the code you need?
Not verifiable from the repository (it cannot see what Render runs). Check the deployed commit in the Render dashboard, then compare:

| Needed for | Needs this code |
|---|---|
| Steps 1-2 using `youtube-report` / admin diagnostics, and a recheck | already in `822892a` |
| `video-feed-diagnose`, `youtube-recheck-health`, `youtube-report` `last_recheck_*`, failure audit row, DB-enforced read-only | in `0ceda6f`+ (pushed to `origin/main`); **deployed state unknown** |
| Starvation fix (approved videos first) | in commits `0ceda6f`..`63b959a` on `origin/main`; **deployed state unknown** |

Deploying means: review the diff, commit, push `main`, let Render build, confirm the deployed commit. That needs your approval and was
not done. CI (`.github/workflows/ci.yml`) runs the backend suite on a disposable PostgreSQL; it has **never run these new tests**.
Run it (push to a branch/PR) before relying on the PostgreSQL behaviour of anything here.

### 2.3 Environment variables (names only; never paste values into tickets or chat)

| Variable | Needed by | Notes |
|---|---|---|
| `DATABASE_URL` | every command | secret; Neon connection string. Missing: exit 2 "DATABASE_URL is not configured" |
| `YOUTUBE_DATA_API_KEY` (alias `YOUTUBE_API_KEY`) | `youtube-recheck`, `youtube-discover`, `youtube-auto-review` | secret. Missing: exit 1 `youtube_not_configured`. Rejected by Google: exit 1 (same code) |
| `YOUTUBE_REGION_CODE` | recheck, discover | default `IN`. A wrong country marks region-restricted videos `unavailable`; must match the web service |
| `YOUTUBE_REVERIFY_HOURS` | health, report, diagnose (and the **web service**, which decides what is hidden) | default 72. **Must equal the web service's value**; a smaller value on the web service hides videos sooner |
| `YOUTUBE_DISCOVERY_ACTOR_ID` | `youtube-discover`, `youtube-auto-review` only | active admin with `video:write` |
| `PYTHON_VERSION` (Render) | the job runtime | copy the web service's |

Not needed by any of these commands (verified: the settings default to unset and the CLI does not validate them; local run):
`JWT_SECRET_KEY`, `REDIS_URL`, `CHILD_CREDENTIALS_ENCRYPTION_KEY`, `S3_*`, `FCM_*`, `SMTP_*`. `VIDEO_PLAY_TICKETS_ENABLED` must stay unset/false.

**Check which are missing without printing them**, in the Render dashboard: Environment tab (names are listed; do not reveal values)
for the web service and for the cron/shell environment. Locally, never `echo` them; `env | grep -c '^DATABASE_URL='` prints 0 or 1 only.

### 2.4 Database must already have these migrations
The reflected models are used directly; a missing column raises `AttributeError` and the command exits non-zero with a traceback.
Recheck and report need at least `0008_youtube_content_review`, `0009_youtube_discovery_provenance` (`youtube_category_id`),
`0010_youtube_trusted_channels` (`publication_source`); the feed also needs `0011` (watch history) and `0016` (allowance, the single head after the 0015 merge).
Read-only check by the owner: `alembic current` shows `0016_child_video_daily_allowance (head)`. **Do not run `alembic upgrade`** for this recovery.

## 3. Interpreting the diagnosis

### 3.1 Commands (read-only)
```
python -m app.cli youtube-recheck-health --max-age-hours 3
python -m app.cli youtube-report > report-before.json
python -m app.cli video-feed-diagnose --child-id <child uuid>
python -m app.cli video-feed-diagnose --age 8 --language en          # no child needed
```
Find the child id read-only from the admin panel or `GET /api/v1/families/{family_id}/children` as the parent.

Health output (real output from the local fixture, stale case):
```
{"approved": 2, "approved_stale": 2, "healthy": false, "last_recheck_run": null, "oldest_approved_verification": "2026-11-04 ...",
 "problems": ["2 approved video(s) are past the 72 h window", "no completed recheck on record"]}      -> exit 3
```
Healthy: `"healthy": true, "problems": []` -> exit 0.

Diagnose output (trimmed): `findings` in plain English, and for `feeds.regular` / `feeds.short`: `stages` (remaining and removed per rule), `limiting_stage`, `eligible`.
Example `limiting_stage` for the stale case: `youtube_approved_and_fresh`, with `removed: 2` at that stage.

### 3.2 Reading it

| `limiting_stage` / finding | Meaning | Right action | Is recheck appropriate? |
|---|---|---|---|
| `youtube_approved_and_fresh` and `youtube.approved_stale` > 0 | approved videos fell outside the window | recheck | **Yes** |
| `youtube_approved_and_fresh`, `approved_stale` = 0 | videos are not `approved`, or rights not `cleared`, or not made-for-kids | admin review queue; look at `publication_failure_reasons` in `youtube-report` | **No** |
| `published` | nothing is published | content must be approved/published through the existing process | **No** |
| `age_band` | videos exist but none for this child's age | content gap (supported bands 3-5, 6-8, 9-12, 13-15) | No |
| `language` | none in the child's language or English | content gap, or the child's language setting | No |
| `content_rating` / `active_category` | wrong rating, or category retired | admin fix | No |
| `not_already_completed` | child finished everything | new content, or parent replay | No |
| "no birth date" / "age missing or outside 3-15" | by design the server shows nothing | parent adds the birth date | No |
| "allowance is used up" | by design | none; resets next family-local day | No |
| `format_short` or `format_regular` only | one feed empty (for example no video of 1-60 s) | content mix | No |
| `youtube.approved` = 0 | nothing approved at all | content | **No** (nothing to recheck) |

### 3.3 When recheck is appropriate (all must hold)
1. `approved_stale` > 0 (or `youtube-recheck-health` exits 3) **and** the child's `limiting_stage` is `youtube_approved_and_fresh`.
2. `DATABASE_URL`, a valid `YOUTUBE_DATA_API_KEY` and the correct `YOUTUBE_REGION_CODE` are present in the environment you will run from.
3. The migrations in 2.4 are applied.
4. A snapshot exists and the owner has signed the approval in section 5.

## 4. Recovery sequence

Run commands from `balkavach-backend`, with the environment above set for that shell only. **Never run `pytest` with the production
`DATABASE_URL`** (`docs/testing-and-ci.md`).

### 4.1 Where to run
* **Render (preferred):** the web service's **Shell** if your plan has one, or temporarily create the cron job from
  `balkavach-backend/deploy/render-cron-jobs.example.yaml` and use **Trigger Run** (as `docs/youtube-operations.md` describes), then read the run's logs.
* **A local machine:** possible, but it puts the production database and API key on that machine. Prefer a read-only database role for steps 1-3 and delete the variables afterwards.

### 4.2 Steps 1-3: read-only (no approval needed beyond access)
1. Health: `youtube-recheck-health` (after deploy) **or** `youtube-report` / `GET /api/v1/admin/videos/youtube/diagnostics` on today's code. Save `youtube-report` output as `report-before.json`.
2. Diagnose the affected child (and one other child of a different age) with `video-feed-diagnose`.
3. Match the finding to section 3.2. **If recheck is not appropriate, stop here.**

### 4.3 Preconditions to check in the saved report
* `unavailable` count. If the ordering fix is **not** deployed and `approved + unavailable` is more than the limit, use `--limit 1000`; otherwise a batch can be filled by dead videos.
* `configuration.youtube_api` is `true`.
* `reverify_hours` equals the web service's value.

### 4.4 Step 4: approval gate (mutating)
Do not proceed without the owner's written approval of the checklist in section 5.

### 4.5 Step 5: recheck, canary first
1. Snapshot: a Neon branch (or point-in-time restore point) of the production database. Note its name and time.
2. Canary: `python -m app.cli youtube-recheck --limit 5`. Expected (one line): `checked=5, verified=5, quarantined=0, unavailable=0, returned_to_review=0`, exit 0.
   * `unavailable` or `quarantined` above 0: **stop**, run `youtube-report`, read the reasons. Those videos are already withdrawn (reversible only by re-approval). Check that `YOUTUBE_REGION_CODE` is right and the key's restrictions allow the server before continuing.
   * Exit 1 with `youtube_quota_exhausted`, `youtube_not_configured` or an unreachable YouTube: see 4.9.
3. Full: `python -m app.cli youtube-recheck --limit 200`. Repeat until `youtube-recheck-health` exits 0. Use 1000 if 4.3 says so.
4. Save `youtube-report > report-after.json`; compare with the before file.

### 4.6 Step 6: verify Home and Shorts
1. `video-feed-diagnose --child-id <id>`: `findings` is `["Both feeds have eligible videos."]` or only names a *content* reason (for example no video of 1-60 s).
2. As the child, or with the child's bearer token: `GET /api/v1/videos/feed` and `GET /api/v1/videos/shorts` return non-empty arrays, each item with `youtube_video_id`.
3. In the app: pull to refresh Home; the Shorts row and video list appear; open one video (the allowance check runs and playback starts).
4. If a feed is still empty, the diagnosis names the next rule; do not re-run recheck for a non-freshness cause.

### 4.7 Step 7: schedule (after the host is confirmed, section 2.1)
* **Render:** create the three cron jobs in `balkavach-backend/deploy/render-cron-jobs.example.yaml` (recheck `0 * * * *`, health `15 * * * *`, discover `30 */6 * * *` only if wanted, and only after recheck is proven: each run costs ~700 quota units) using the shared environment group; turn on failure notifications. Check the keys against Render's current Blueprint reference first.
* **VPS (only if proven to serve the API):** `deploy/systemd/*`, a dedicated `balkavach` user, `/etc/balkavach/backend.env` mode 0600.
* Verify after the first hour: `youtube-recheck-health` exits 0; `youtube-report` shows a recent `last_recheck_run`; the audit table has a `youtube.recheck.completed` row.

### 4.8 Step 8: monitoring
* The health job exits 3 when approved videos are stale or no recheck completed within 3 hours, or the last recheck failed; Render marks the run failed and notifies. Render does **not** alert when a job was never created, so also set a calendar check that a run exists each hour.
* The recheck job exits non-zero on failure and writes `youtube.recheck.failed` (read-only SQL: `select created_at, details from audit_logs where action in ('youtube.recheck.completed','youtube.recheck.failed') order by created_at desc limit 10;`).
* Keep `LOG_LEVEL` at INFO so `videos.feed.empty` (with `limiting_stage`) is logged when a child's first page is empty.

### 4.9 Failure and rollback

| Situation | What happened | What to do |
|---|---|---|
| exit 1 `youtube_not_configured` | key missing or rejected by Google | fix the secret; nothing was changed; re-run the canary |
| exit 1 `youtube_quota_exhausted` | quota reached (resets at midnight Pacific) | wait; earlier batches in this run were committed, the next run continues; do not retry in a loop |
| exit 1, YouTube unavailable | transient | the client already retried twice; re-run later (idempotent) |
| exit 2 | no `DATABASE_URL`, or a database error | check the variable and the Neon status; re-run (idempotent) |
| traceback with `AttributeError` on a model (expected from the reflection design; not exercised) | a migration from 2.4 is missing | stop; do not run migrations without a separate decision |
| canary withdrew videos you expected to stay | region/key problem, or YouTube really changed them | stop; fix `YOUTUBE_REGION_CODE`/key; affected videos are `unavailable`/`quarantined`: a recheck moves `unavailable` to `pending_review` once YouTube serves them, then an administrator approves (or `youtube-auto-review` under the existing policy); for `quarantined` use the admin reopen then approve |
| a mass withdrawal in the full run | as above, at scale | stop further runs; restore from the snapshot **only if** the owner decides the whole run was wrong (it also discards anything else changed since); otherwise re-approve |
| a run is killed mid-way | single commit at the end, so either nothing or earlier batches persist | re-run; safe |
| two runs overlapped | rows split between them (section 1.3) | nothing to do |
| the feed is still empty after a clean run | the cause was not freshness | section 3.2 |

What cannot be undone by the tool: the overwritten `content_rating` and `published_at` of withdrawn videos, and refreshed titles/descriptions (YouTube is the source of truth). Everything else is in the audit log with the previous status.

## 5. Human approval required before any mutating step

Copy, fill and keep with the run record.

```
Production recovery approval (youtube-recheck)
Date/time:                         Approver:
[ ] Diagnosis attached: approved_stale = ___, limiting_stage = ___ for child ___
[ ] The cause is stale verification (section 3.3 #1), not content/child data
[ ] Host confirmed: ___ (deployed commit ___; contains the starvation fix: yes/no)
[ ] Migrations confirmed (alembic current = ___)
[ ] Environment names present: DATABASE_URL, YOUTUBE_DATA_API_KEY, YOUTUBE_REGION_CODE (=___), YOUTUBE_REVERIFY_HOURS (= web value)
[ ] Snapshot taken: ___ at ___
[ ] Quiet period; admins told not to approve/revoke during the run
[ ] Canary (--limit 5) approved first; stop rule understood
[ ] No auto-publish commands (youtube-discover / auto-review) will be run for this recovery
[ ] Scheduler creation approved separately: yes/no
```

## 6. Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Discovery can starve the recheck of YouTube quota** (found in the 2026-11-21 audit). `youtube-discover` runs one `search.list` per topic (100 quota units each) and there are 7 default topics, so one run is about 700+ units; every 3 hours that is about 5,600 units a day, over half of the default 10,000, and the recheck shares the same key. If quota runs out the recheck fails (`youtube_quota_exhausted`) and the feed empties 72 h later. | medium | Do not create the discover job until recheck is proven; then run it every 6-12 h, or reduce `YOUTUBE_DISCOVERY_TOPICS`, or use a separate API key/project for discovery. The recheck alone is about 96 units a day. |
| Wrong `YOUTUBE_REGION_CODE` withdraws region-blocked videos | medium if unset/changed | canary; verify the value |
| Recheck withdraws a video that should be shown (YouTube really changed it) | expected, by design | audit rows; admin re-approve |
| Admin actions wait on locked rows during a run | low | quiet period |
| New commands and fix are untested on PostgreSQL | certain until CI runs | push to a PR branch and let CI run before deploying |
| Neon snapshot restore rolls back unrelated changes | if used | prefer re-approval; restore only by decision |
| Schedule created on a host that does not serve the API | medium | section 2.1 first |
| Feed empties again if the job stops | certain without monitoring | health job, alert on absence |

## 7. What was verified, and how

**Local verification (done 2026-11-21, SQLite in memory, fake YouTube, no network, no secrets):**
* Read-only commands cannot write even if their code tried (3 commands, tests); PostgreSQL `SET TRANSACTION READ ONLY` statement issued (mock).
* Exit codes: success 0; recheck failure 1 with an audit row; health unhealthy 3; `diagnose` unknown child 1; no `DATABASE_URL` 2 for six commands; bad arguments 2 before any database work.
* Recheck: restores stale approved videos; withdraws/quarantines/returns-to-review as in 1.2; idempotent; a failed run keeps earlier work; unavailable videos no longer starve approved ones (reproduced first, then fixed).
* Template files call valid commands, hold no secret, do not mention play tickets outside comments.
* Suites: see the final report in the conversation for counts.

**Not verified locally, and not verified at all in production:** PostgreSQL behaviour (read-only transaction, `SKIP LOCKED`, long locks), the real YouTube API responses and quota, Render or VPS behaviour, which commit is deployed, the production data, whether a recheck restores the actual feed, any real device.

## 8. Open questions for the owner

1. Which host serves `api.balkavach.tech`, and what commit is deployed?
2. Is the Neon plan able to branch (snapshot) before the run?
3. Does Render's plan include a Shell, or will you use a temporary cron job with Trigger Run?
4. Is the key restricted by IP in Google Cloud (a restriction to the VPS would block Render, and the reverse)?
5. Approve committing and deploying the working tree (the new commands, the starvation fix, the Panda and mission changes are all in it; consider splitting the commits).
