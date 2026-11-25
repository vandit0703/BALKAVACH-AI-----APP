# P0 remediation plan

Date: 2026-11-25. For the project owner and developers. Nothing in this plan was implemented by its author, and no production system was contacted.

**Sensitive:** this document describes open weaknesses. Check who can read the repository before committing it.

## 0. Evidence basis

- **12:10 state:** HEAD `36a7c06` plus the uncommitted files, rebuilt and hash-checked. All line numbers refer to it.
- **Reproduced** means an end-to-end API test on a reconstructed local PostgreSQL showed the behaviour. **Code** means read, not executed.
- **Live tree:** another process was fixing some of these while this was written. "Live" notes come from a snapshot at 12:54 and a code check at about 13:00. They are provisional, and none of that work was reviewed.

| ID | Issue | Severity | 12:10 | Live (provisional) |
|---|---|---|---|---|
| P0-0 | Trusting a channel publishes blocked videos | Critical, child safety | Reproduced | Partly fixed |
| P0-1 | Video identifiers at zero allowance | High | Reproduced | Open |
| P0-2 | Watch time can be avoided; metering paths | High | Reproduced | Code unchanged |
| P0-2b | Re-verification window not enforced | High, child safety | Reproduced | Code unchanged |
| P0-3 | Free time versus mission-earned time | Critical, product | Reproduced | Worse: no source of video time |
| P0-4 | Parent sets any mission reward | High | Reproduced | Create fixed, edit open |
| P0-5 | Migration graph and version column | High, release | Reproduced | Fix does not work on a fresh database |
| P0-6 | Migration `0021` dependency | High, release | Reproduced | Now also `0022` |
| P0-7 | Account deletion and privacy | Release blocker | Reproduced | Endpoint added, not reviewed |
| P0-8 | Secrets and SSH | High, unverified | Partly checked | Not touched |

### Reproduction setup (local only)
1. Disposable PostgreSQL with `tests/schema/reconstructed_baseline.sql`; create `alembic_version(version_num varchar(64) primary key)`; `alembic upgrade head` with `ALLOW_SCHEMA_MIGRATIONS=true`; add the admin tables the baseline lacks.
2. Redis stand-in: `python scripts/testenv.py _redis`.
3. Run API tests with `TEST_DATABASE_URL` and `REDIS_URL`; YouTube is faked as in `tests/test_api_youtube.py`.

The reproduction tests lived in a temporary session folder and may be cleared; each "Reproduce" entry below is enough to rewrite them.

---

## P0-0 Trusting a channel publishes blocked videos

**Evidence.** `app/services/youtube_review_service.py`: `_force_publish_for_trusted_channel` (line 428) is documented as "bypassing per-video approval/quarantine gates". `_apply_trusted_channel_defaults` (403) sets `rights_status="cleared"`, `made_for_kids=True`, `screening_flags=[]`, `is_published=True`. Callers: `trust_channel` (610, every existing video of the channel), `discover_trusted` (813), `_refresh_trusted_candidate` (995). `app/cli.py:347` runs it from `youtube-discover`, which the example Render cron schedules every 6 hours. Introduced by `36a7c06`; 6 safety tests started failing there.

**Reproduced.**
- A quarantined video with rights `not_cleared`, not made for kids, became approved, cleared, made for kids, no flags, and appeared in the child's Shorts feed after `POST /admin/videos/youtube/channels/trust`.
- An age-restricted, not-for-kids video was published to the child feed by scheduled discovery.
- A rejected video's record changed to approved and cleared. It stayed unpublished in this run; a later publish action could expose it (not tested).

**Expected.** Trust never overrides a human rejection or revocation, an open report, a rights denial, a screening flag, YouTube's made-for-kids or age restriction, duration or age limits. Stored YouTube facts are never overwritten with assumed values.

**Dependencies.** Whether production runs `36a7c06` or later, and whether the cron jobs are active (**unverified**).

**Urgent containment (owner action).** If deployed: pause `youtube-discover`, avoid trusting channels, and review videos published automatically since the deployment (`publication_source="automatic"`, audit entries `trusted_channel`). Because the function erased flags and made-for-kids values, re-check those videos against YouTube instead of trusting stored data.

**Fix.** Remove the force-publish path and route trusted channels through `auto_approval_blocker` / `_auto_publish`, which already holds every rule. Then repair affected rows with a reviewed, one-off re-verification.

**Live.** Quarantined and `not_cleared` videos are now blocked and the age-restricted case is quarantined. The code still reopens rejected and revoked videos and still forces `made_for_kids=True` for pending ones. **Not sufficient.**

**Acceptance.** The 6 failing safety tests pass unchanged; new tests for rejected, revoked, reported, age-restricted, not-for-kids, unknown made-for-kids, over-length and rights-denied videos through all three callers; none appear in any child endpoint.

## P0-1 Video identifiers at zero allowance

**Evidence.** Feeds, Shorts, next, history and learning content withhold identifiers (`videos.py:88-111`). Two routes do not:
- `thumbnail_url` (`videos.py:99`, watch history, learning content) is `https://i.ytimg.com/vi/<video id>/...`.
- `GET /tasks/{id}/video-catalogue` (`tasks.py:261-280`) returns `playback_locked=False` with IDs, whatever the allowance. The app calls it (`video_feed_repository.dart:379`). Mission watching is not charged.

**Reproduced.** With the allowance exhausted: feed ID `null`, thumbnail URL containing the ID, `next` empty, mission catalogue returning the ID unlocked.

**Expected (2026-11-21 decision).** At zero time the catalogue is listed, locked, with no playable identifier.

**Limit.** The server cannot stop a YouTube player that already holds an ID. Hard enforcement needs hosted media with short-lived URLs.

**Dependencies.** Decision: may mission videos play at zero allowance (needed if missions are the only way to earn time), and which videos qualify?

**Fix.** Proxy or re-host thumbnails, or omit them when locked. Limit the mission catalogue to videos chosen for that mission, only while its requirement is incomplete.

**Acceptance.** No child response at zero allowance contains the ID in any field; the catalogue refuses completed, approved and unrelated missions; locked cards still render.

## P0-2 Watch time can be avoided; metering paths

**Evidence.** `video_watch_history_service.py:35` charges only if the previous report said playing **and** the position advanced by about the elapsed time; a gap over 32 s charges nothing. Its docstring and `docs/video-allowance-policy.md` say the client's flag and position are not proof. Since `d905466`; `81f3cff` charged elapsed time.

**Reproduced.** Honest 60 s: charged 60. Charged 0 for: constant position (290 s), "paused" flag with advancing position (290 s), reports every 33 s. An honest 40 s looping clip watched 120 s: charged 90.

**Other paths.** `record_progress` is the one mission/free deduction path; `/video-access/heartbeats` does not charge mission time; play tickets are inactive (no table). No double charge was found. By code reading, a redeemed `video_time` reward cannot be played: it needs `/video-access/sessions` with `VIDEO_PLAYBACK_PROVIDER` (`integrations/__init__.py:44`, empty by default), so Stars can be spent for nothing. **Not reproduced** (local database lacks `video_watch_sessions`).

**Expected.** Time the player could have been playing is charged from the server clock; pauses are free only when they cannot be abused.

**Dependencies.** P0-3. Decision on honest edge cases (buffering, seeking, looping). Production setting of the playback provider.

**Fix.** Charge capped elapsed time unless two consecutive reports show a stationary position and a paused flag; charge a capped interval after long gaps while the last state was playing; treat a wrapped position as progress. Longer term, enable play tickets. Block creating or approving `video_time` rewards while no provider exists.

**Acceptance.** The five scenarios above, plus pause, resume, background, two devices and midnight. A modified client cannot get free time by varying flag, position or interval.

## P0-2b Re-verification window not enforced

**Evidence.** `youtube_visibility_clause` (`youtube_review_service.py:149`) says videos must be within the re-verification window but does not check it. `960926c` removed `last_verified_at >= now - youtube_reverify_hours` (`config.py:82`, 72 h). This contradicts the 2026-11-21 decision to keep the 72-hour rule.

**Reproduced.** A video last verified 100 days ago appeared in the child feed.

**Dependencies.** The removal avoided an empty feed when the recheck job does not run. Restoring it requires a monitored, working scheduler (`youtube-recheck`, `youtube-recheck-health`).

**Fix.** Confirm the scheduler first, then restore the condition.

**Acceptance.** Stale videos are hidden; fresh ones visible; the health check alerts before the window expires.

## P0-3 Free 900 seconds versus mission-earned time

**Evidence.** Approved policy (`docs/video-allowance-policy.md`): 900 s free per day plus exactly 900 s per approved mission, expiring at midnight. Code: `FREE_DAILY_ALLOWANCE_SECONDS = 900` (`video_entitlement_service.py:33`), but `960926c` removed the grant from approval (`task_service.py:199`); `grant_mission_video_entitlement` (164) is never called. The review card still reports 15 minutes (`reviews.py:73`) and the app shows it.

**Reproduced.** Approval: card promised 15 minutes; allowance 900 before and after, mission time 0.

**Live.** Free time set to 0 ("Decision B") and the grant is **still not called**: on the 12:54 snapshot allowance was 0 before and after approval, so no child could watch anything. At 13:00 unused earned time was also being changed to carry across days ("DEC-03"), which contradicts the midnight-expiry policy.

**Decision needed, in writing:** free time (900 or 0), grant per mission, daily cap, expiry or carry-over.

**Fix.** Restore the grant inside the approval transaction first; only then change the free amount. Ship both together. Update the policy document, app text and notifications.

**Acceptance.** The 19 approval tests pass or are changed to match the written decision; one grant per submission under retries and concurrency; shown minutes equal granted minutes; a new child's first-day experience is defined and tested.

## P0-4 Mission Stars and XP not enforced

**Evidence.** `schemas/task.py:26,46` accept up to 10000 Stars and 100000 XP; `tasks.py:151` stores them on create and `tasks.py:243` on edit; approval pays them. `81f3cff` paid fixed constants.

**Reproduced.** A parent task paid 10000 Stars and 100000 XP; `PATCH` set 999 / 9999.

**Live.** Create now stores 10 / 15. Edit still applies any value.

**Dependencies.** Confirm 10 / 15 covers daily, preset and custom missions. Existing rows keep old values. Badge thresholds depend on totals.

**Fix.** Pay constants in `review_submission` (covers old rows), ignore or reject client values on create and edit, and show the constants everywhere. Do not rewrite past ledger rows; list unusually large ones for review.

**Acceptance.** The 4 tests in `test_api_mission_rewards.py` pass; create, edit, preset and old-row cases pay 10 / 15 once.

## P0-5 Migration graph and version column

**Evidence.** Committed `0017_child_video_daily_allowance.py` declares a different revision id from the one `0018` points at (renamed in `bb08a99`). The uncommitted fix restores `0016_child_video_daily_allowance`. Three ids exceed Alembic's 32 characters: `0009` (33), `0020` (35), `0015_trusted_channel_upload_discovery` (37).

**Reproduced.** HEAD: `alembic heads` fails with `KeyError: '0016_child_video_daily_allowance'`. 12:10 state, fresh database: upgrade fails at `0009` (value too long), and rolls back.

**Live.** `env.py` widens the column only if the table already exists. On a fresh database Alembic creates it afterwards, and **upgrade still fails at `0009`** (tested). The tracker marks this fixed.

**Dependencies.** Production's current `alembic_version` value and column width (**unverified**; read-only query by the owner). The revision id must not be changed again without it. CI also needs `tests/schema/baseline.sql`, which is missing.

**Fix.** Create the version table at `VARCHAR(64)` when absent, and widen it when present; commit the `0017` correction; add a real schema-only baseline.

**Acceptance.** Fresh database and a copy at production's revision both reach a single head; downgrade and re-upgrade work; CI runs it.

## P0-6 Migration 0021 dependency

**Evidence.** `0021_quiz_system.py` (uncommitted) adds six tables; `db/base.py` maps them without a `has_model` guard.

**Reproduced** at revision `0020`: child list, child history, parent history and admin list return 500; achievements, progress and mission approval return 200.

**Live.** `0022` adds columns the new code expects. On a database that already had `redemption_requests.cancelled_at` (as the reconstructed baseline does), `0022` failed with `DuplicateColumn`. Whether production has that column is **unverified**.

**Dependencies.** P0-5. Backup. Order: database, backend, then app and admin.

**Fix.** Check production's columns first; make `0022` tolerate existing columns or correct the baseline; add a guarded 503 for quiz routes; write a rollout and rollback runbook.

**Acceptance.** Rehearsal on a copy of production schema; quiz routes work after it; before it they return a clear 503; old app versions keep working.

## P0-7 Account deletion and privacy

**Evidence.** No account or family deletion route. Removing a child only deactivates it (`families.py:277`). The consent checkbox cites "Terms of Service & Child Data Protection Policy" (`app_en.arb:36`); no link to either was found in the consent screen or settings.

**Reproduced.** Deletion routes return 404/405; a removed child's name and password hash remain.

**Requirement.** Google Play requires apps with account creation to offer deletion in the app and on a web page, and to answer the data-deletion questions ([Google Play help](https://support.google.com/googleplay/android-developer/answer/13327111)). Check the current page before release. Obligations under Indian data-protection law for children need legal advice (**not assessed**).

**Live.** `DELETE /auth/account` added that anonymizes and keeps ledgers; not reviewed or tested, no app screen, no web page.

**Dependencies.** Decisions on retention, co-parent families, proof photos, backups, push tokens; published policy pages; P0-5/6.

**Fix.** Re-authenticated deletion covering parent, children, photos, tokens and sessions; documented retention; web request page; policy links in consent and settings; data export if counsel requires it.

**Acceptance.** After deletion no login works and no name, email, photo or token remains outside documented retention; a second parent keeps their data; interrupted deletion can resume.

## P0-8 Production secrets and SSH

**Checked locally, values not displayed.**
- `servecmd.txt` was committed in `1d75907` (2026-11-14), later removed, and **is still reachable from `main` and the `origin/main` ref**. It contains one `ssh root@` line, one password prompt and several IP addresses. No key, token or password assignment matched the patterns used.
- This updates `docs/security-ssh-remediation.md`, which says history was not scanned.
- `notes.txt`, `servecmd.txt`, `.env` and `android/key.properties` exist locally and are ignored.
- Pattern scan of 117 commits (excluding docs and build output): no private-key blocks, Google or AWS access keys; database URLs found only in CI (localhost) and `.env.example` (placeholder).

**Unverified.** Who can read the GitHub repository; whether root or password SSH is still enabled; whether any credential was reused or rotated; production environment variables; secrets in a form the patterns miss.

**Fix (owner only).** Confirm repository visibility; follow `security-ssh-remediation.md` (key login, disable root and password login, rotate, patch, review logs); decide on history removal, which rewrites shared history and does not undo copies already made.

**Acceptance.** Password and root login refused from outside; secrets rotated and recorded; a secret scanner in CI.

---

## Recommended order

0. **Stop concurrent editing** and agree one owner for the working tree. Review the other process's changes before keeping any.
1. **P0-0** containment today (check deployment), then the fix.
2. **P0-8** server access checks (owner, independent of code).
3. **Decisions:** video policy (P0-3), mission videos (P0-1), freshness (P0-2b), deletion retention (P0-7).
4. Decide what to recover from `backup-main-2026-11-21`: it holds the reward enforcement, approval grant and stricter metering that pass the older tests. Port the specific logic; do not merge the branch.
5. **P0-4**, then **P0-3** with **P0-2**, then **P0-1**.
6. **P0-2b** once the scheduler is proven.
7. **P0-5**, then **P0-6**, rehearsed on a schema copy.
8. **P0-7** before any store submission.
9. Cleanup: committed backup and temporary files, tracked admin `build/`, remaining admin tests, the 23 undiagnosed backend failures.

## Open questions about production
Deployed commit; active cron jobs; `alembic_version` value; `cancelled_at` presence; `VIDEO_PLAYBACK_PROVIDER`; repository visibility; SSH configuration.
