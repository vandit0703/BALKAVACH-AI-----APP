# Home and Shorts feed: diagnosis, fix and scheduling (2026-11-21)

> Production procedure: `docs/video-feed-production-recovery.md` (read-only checks, approval gate, canary recheck, rollback).

Status: code and tests done; **not deployed, no database was read or changed.** Whether the feed shows videos in production
depends on three owner actions in section 6.

## 1. Endpoints

| Surface | Flutter | Backend | Rule set |
|---|---|---|---|
| Home video list | `VideoFeedPager(kind: learn)` | `GET /api/v1/videos/feed` | `eligible_feed(video_format="regular")` |
| Home Shorts row and the full-screen Shorts feed | `VideoFeedPager(kind: shorts)` | `GET /api/v1/videos/shorts` | `eligible_feed(video_format="short")` |
| "Picked by grown-ups" (third, separate source) | `learningItemsProvider` | `GET /api/v1/educational-content` | not the feed rules |
| Playback progress and charging | video/Shorts players | `POST /api/v1/videos/watch-history/{id}/progress` | `_eligible_video` (same visibility rule) then the allowance ledger |

Shorts is **not** a different rule set: it is the same query as Home with the duration split `1-60 s` (`video_classification.short_clause`).
Both feeds, the "Up next" list and playback by id share `youtube_visibility_clause`.

## 2. Why a child can see zero videos (proved by tests, not assumed)

`eligible_feed` returns a video only if **all** of these hold (`video_service.feed_conditions`, now the single definition):
published; age band contains the child's age (3-15, from the birth date); rating general/educational; language is the child's or
English; category active; for YouTube rows: review `approved`, `made_for_kids`, rights `cleared` **and `last_verified_at` within
`YOUTUBE_REVERIFY_HOURS` (72)**; not a duplicate; not already completed by this child unless a parent authorised a replay. If the
daily allowance is used up, both routes return `[]` before any query.

`tests/test_video_feed_real_filters.py` runs these real SQL rules (SQLite) and shows each rule alone can empty the feed. The one that
needs no wrong data and nobody's mistake is **freshness**: an approved, published, rights-cleared video older than 72 h since its last
check disappears from Home, Shorts, Up-next and playback, and only `recheck` brings it back. `youtube-recheck` is started by nothing in
the repository (no scheduler, no in-process timer; `docs/youtube-operations.md` recorded a database sample on 2026-11-04 whose oldest
verification was two days old). If no job has run since, every approved video verified before ~2026-11-18 is hidden now.

**What is NOT confirmed:** the actual rows in production. I cannot tell from here whether the empty feed for that child is stale
verification, no approved videos at all, a missing birth date, a language/age mismatch or finished videos. The new read-only command
below gives that answer in one run.

### Prove it for the real database (read-only, safe on production)

```
python -m app.cli video-feed-diagnose --child-id <child uuid>        # the child's real age, language, allowance
python -m app.cli video-feed-diagnose --age 8 --language en          # no child needed
python -m app.cli youtube-report                                     # approved_stale, last_recheck_run, reasons
python -m app.cli youtube-recheck-health                             # exit 0 healthy / 3 unhealthy
```

`video-feed-diagnose` prints, for Home (`regular`) and Shorts (`short`), how many videos survive each rule in order, the
`limiting_stage` (first rule after which nothing is left) and plain-English `findings`, for example
"1 otherwise-eligible YouTube video(s) are hidden by approval or freshness rules; 3 approved video(s) are stale ... which
youtube-recheck repairs." It uses the same rule list as the feed, so it cannot disagree with it. The same funnel is logged as
`videos.feed.empty` (with `limiting_stage` and `stage_*` counts) whenever a child's first feed page is empty.

## 3. Changes

Backend
* `video_service.feed_conditions` / `eligible_feed`: one named rule list used by the feed and the diagnosis. Behaviour is unchanged
  (all existing feed tests pass), except that a latent `NameError` when watch history is unavailable was removed and the empty-feed
  log now runs only for the first page.
* `video_feed_diagnostics.py` (new): `funnel`, `diagnose`, `youtube_freshness`. Read-only.
* `youtube_review_service.diagnostics` and `YouTubeDiagnosticsPublic`: `last_recheck_run`, `last_recheck_result`,
  `last_recheck_failure`, `last_recheck_failure_code` (optional fields; the admin app ignores unknown keys).
* `cli.py`: `youtube-recheck` now writes a `youtube.recheck.failed` audit row and prints the error code on failure (exit 1; 2 for a
  database error); new read-only `video-feed-diagnose` and `youtube-recheck-health`.
* Added after review (2026-11-21, see the recovery doc): the three read-only commands run in a database-enforced read-only transaction;
  `youtube-recheck` now takes approved videos before unavailable ones (permanently unavailable videos could fill the whole `--limit`
  batch and starve approved ones; reproduced by a test first); the diagnosis no longer counts one hidden video once per feed.
* Not changed: freshness window, approval/auto-approval rules, screening, publication, allowance and charging, play-ticket flags
  (`VIDEO_PLAY_TICKETS_ENABLED` untouched; tickets cannot activate without the deferred table), YouTube client.

Flutter
* `WatchHomeScreen`: when the server empties the feeds because today's allowance is used up, Home shows the time-up state
  (`watch.timeUp`, the existing "used today's video time" text) instead of "No videos here right now".

Deliberately **not** done: no auto-publish of anything, no seed or data command run, no extension of the 72 h window (it is a safety
control: a video made private or unsuitable on YouTube must leave the feed within that time), no hard-coded or mock videos.

## 4. Existing content, scheduled jobs and the approval process

* `youtube-recheck` only re-verifies videos that are already `approved`/`unavailable`. A video YouTube still serves as public,
  embeddable, made-for-kids with no new screening flag gets a new `last_verified_at` and stays approved. One that vanished or
  changed is withdrawn (`unavailable` / `quarantined`); one that returned goes to `pending_review`, **never straight back to
  approved** (tested).
* `youtube-discover` and `youtube-auto-review` publish only through `auto_approval_blocker` (trusted channel or configured
  non-trusted policy, clean screening, made for kids, supported age band, duration limit). Unchanged.
* Idempotent and retry-safe: re-running changes only timestamps; rows are locked with `FOR UPDATE SKIP LOCKED`; a failure keeps what
  was already committed and the next run continues with the oldest remaining. The YouTube client already retries timeouts and 5xx
  twice; an hourly schedule gives about 71 further attempts inside the window. Quota: 1 `videos.list` call per 50 videos, so 200
  videos hourly is about 96 units a day against YouTube's default 10,000.

## 5. Tests (all fake/SQLite; see the final report for counts)

| File | Type | Proves |
|---|---|---|
| `balkavach-backend/tests/test_video_feed_real_filters.py` | real SQL on SQLite + real HTTP routes with overridden auth/db | fresh/stale/never-verified; not-approved statuses; unpublished; age; language; rating; category; duplicates; completed; pagination; Home and Shorts routes; exhausted allowance; charging via `record_progress`; playback refused for stale/ineligible; contract fixture equals the real route output |
| `balkavach-backend/tests/test_video_feed_cli.py` | CLI functions on SQLite, fake YouTube | recheck restores, is idempotent, fails loudly with an audit row; diagnose is read-only; health monitor |
| `balkavach-frontend/test/features/home_feed_states_test.dart` | Flutter, fake backend using the contract fixture | Home shows server videos and Shorts; empty only when nothing eligible; time-up state; error with retry; loading; cached card cannot play at zero allowance |
| `balkavach-frontend/test/fixtures/video_feed_contract.json` | fixture | JSON produced by the real routes; the backend test fails if it drifts |

A mutation check (disabling the freshness condition) failed 11 of these tests, then the code was restored.
**Not covered:** PostgreSQL, the real YouTube API, real data, a physical device, concurrent recheck runs.

## 6. Owner actions required (nothing here was done)

1. **Find the cause for the affected child (read-only).** On a machine with the production `DATABASE_URL`:
   `python -m app.cli video-feed-diagnose --child-id <id>` and `python -m app.cli youtube-report`. Read `findings`.
2. **If it is stale verification (most likely), refresh now, then schedule.** Immediate: run `python -m app.cli youtube-recheck
   --limit 200` (needs `DATABASE_URL`, `YOUTUBE_DATA_API_KEY`, `YOUTUBE_REGION_CODE`), or call the existing admin API
   `POST /api/v1/admin/videos/youtube/recheck` with `{"limit": 500}` as an administrator with `video:write` (the admin app has no
   button for it). Repeat while `approved_stale` is above 0.
3. **Create the schedule.** The host is **not verified**: `docs/youtube-operations.md` assumes Render; `servecmd.txt` shows a separate
   Ubuntu VPS. Use whichever serves `api.balkavach.tech`:
   * **Render:** three Cron Jobs from `balkavach-backend/deploy/render-cron-jobs.example.yaml` (root `balkavach-backend`, build
     `pip install -r requirements.txt`, shared Environment Group with the web service's values, failure notifications on):
     recheck hourly `0 * * * *`, discover `30 */3 * * *`, health `15 * * * *`.
   * **VPS:** copy `deploy/systemd/*` to `/etc/systemd/system/`, create the `balkavach` user and `/etc/balkavach/backend.env`
     (mode 0600), then `systemctl enable --now balkavach-youtube-recheck.timer balkavach-youtube-recheck-health.timer`.
   * Add `youtube-discover` only with `YOUTUBE_DISCOVERY_ACTOR_ID` set to an active administrator with `video:write`.
4. **Verify** after the first scheduled hour: `youtube-recheck-health` exits 0, `youtube-report` shows `approved_stale: 0` and a recent
   `last_recheck_run`, and the app Home lists videos.

## 7. Remaining blockers (what the code cannot supply)

* **Content:** if `video-feed-diagnose` shows no approved/published videos for the child's age and language (stage `published`,
  `age_band` or `language`), nothing is wrong with the code: there is no eligible content, and videos must be discovered and approved
  through the existing process (admin review, or `youtube-discover` with trusted channels). No videos were invented.
* **Child data:** a child without a birth date, or outside 3-15, sees nothing by design; a parent must add the birth date.
* **Finished videos:** a child who completed every eligible video sees none until new ones arrive or a parent authorises a replay.
* **Hosting:** the scheduler cannot be created from the repository; it needs the owner's Render or VPS access.
* **YouTube quota/key:** the recheck needs a valid `YOUTUBE_DATA_API_KEY`; a rejected key or exhausted quota fails the job
  (`youtube.recheck.failed`, exit 1) and the feed empties after 72 h without a successful run.
