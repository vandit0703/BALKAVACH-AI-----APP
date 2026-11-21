# YouTube pipeline: operations guide

Audience: whoever runs the Render deployment and owns the Neon database.
Written 2026-11-04. Nothing in this file is a claim that a job *is* running; every
"verify" step says how to prove it.

## 1. Automatic approval and `YOUTUBE_AUTO_PUBLISH_AGE_BAND`

A discovered video is approved and published without an administrator only when every
mandatory rule in `auto_approval_blocker`
(`balkavach-backend/app/services/youtube_review_service.py`) passes: YouTube explicitly
marks it made-for-kids, no safety or metadata review flags remain, rights are not explicitly
denied, duration is within the applicable limit, and it has a supported age range. Trusted
channels use `YOUTUBE_TRUSTED_AUTO_PUBLISH_MAX_SECONDS` (default 3600); other channels use
`YOUTUBE_AUTO_PUBLISH_MAX_SECONDS` (default 180) and also require
`YOUTUBE_AUTO_PUBLISH_NON_TRUSTED=true`.

Confirmed age-restricted and explicitly not-made-for-kids videos remain quarantined. Confirmed
private, non-embeddable, unprocessed, or region-blocked videos are unavailable. Missing metadata
and keyword hits (including educational uses of “challenge”) wait for review and are never
auto-published. Trusted-channel status does not override an explicit video-level rights denial.

### The age band

A YouTube video has one age range. The four configured base bands are **`3-5`, `6-8`,
`9-12`, `13-15`** (`YOUTUBE_AGE_BANDS`); contiguous combinations such as `3-15` are also
valid trusted-channel ranges (`YOUTUBE_AGE_RANGES`). The global setting accepts only one of
the four base bands.

| Video from | Band used |
|---|---|
| An active **trusted channel** | A valid optional channel override, then `YOUTUBE_AUTO_PUBLISH_AGE_BAND`, then the supported `3-15` range. Channel age setup is not required. |
| Any other channel | `YOUTUBE_AUTO_PUBLISH_AGE_BAND` |

| `YOUTUBE_AUTO_PUBLISH_AGE_BAND` | Accepted values | Effect |
|---|---|---|
| `3-5`, `6-8`, `9-12`, `13-15` | exactly these | Every automatically approved non-trusted video is shown to children of **that band only**. |
| **unset or empty** | | **No non-trusted video is auto-approved.** Each waits in "Pending" with the reason "no age band is configured for automatic approval". Trusted-channel videos use the supported `3-15` range if no channel override is saved. |
| anything else (`4-12`, `3-15`, `kids`) | | Treated as invalid for this setting. Non-trusted videos wait; trusted channels fall back to `3-15` if no supported range is saved on the channel. |

Trusted channels are discovered from their YouTube uploads playlist. Trust triggers an
immediate scan of up to 150 uploads; older history continues in bounded scheduled scans until
complete. Later scans use the saved latest-upload anchor and are deduplicated. Both Shorts and
regular videos are processed; the existing child feeds continue to split them by duration.
Categories are optional because child feeds allow uncategorized videos. Language comes from
YouTube metadata when available; missing language is sent to review.

Consequences to understand before setting the global age band:

* One configured band applies to **all** automatically approved videos without a valid
  channel override. Setting `9-12` shows a toddler's
  nursery rhyme only to 9-12 year olds, and vice versa. Choose the band that is safe for the
  *content you let through*, or keep non-trusted auto-approval off
  (`YOUTUBE_AUTO_PUBLISH_NON_TRUSTED=false`) and approve by hand with a per-video band.
* Changing the variable affects **future** approvals only. Already-approved videos keep the
  band they were given.
* Whether a child sees a video also depends on the child's age, which comes from the birth
  date. A child without a birth date sees no videos (and cannot start hosted playback).

Set it in the Render **web service** environment (it applies when an admin presses
Discover/Process) and in the **cron job** that runs `youtube-discover` / `youtube-auto-review`.

> Added 2026-11-21: `youtube-recheck-health` and `video-feed-diagnose` (read-only), a `youtube.recheck.failed` audit row, and `last_recheck_*` fields in `youtube-report`. Runbook: `docs/video-feed-restoration.md`; example job files: `balkavach-backend/deploy/`.

## 2. Scheduling `youtube-recheck` on Render

**Status: not verified.** The repository contains no scheduler or Render configuration
(no `render.yaml`, Procfile, workflow or crontab). The production API is
`https://api.balkavach.tech` (the admin panel default). I have no Render
access, so whether a recheck job exists is unknown. Indirect evidence from the database on
2026-11-04 (oldest approved verification was two days old) suggests none is running.

Why it matters: the child feed hides an approved YouTube video whose `last_verified_at`
is older than `YOUTUBE_REVERIFY_HOURS` (72). If no job runs, **every approved video
disappears from the child app about 72 hours after it was last verified**, even though it
still shows as "approved/published" in the admin panel.

### Create the Cron Job (Render dashboard)

1. **New → Cron Job**; connect the same GitHub repository and branch as the web service.
2. **Root Directory:** `balkavach-backend`
3. **Runtime:** Python 3 (same version as the web service; copy its `PYTHON_VERSION`).
4. **Build Command:** `pip install -r requirements.txt`
5. **Command:** `python -m app.cli youtube-recheck --limit 200`
6. **Schedule:** `0 * * * *` (hourly, UTC). Hourly gives ~71 retries inside the 72-hour window.
7. **Environment** (copy from the web service, or attach one shared Environment Group):
   * `DATABASE_URL` (required)
   * `YOUTUBE_DATA_API_KEY` (or `YOUTUBE_API_KEY`) (required, else the job exits 1)
   * `YOUTUBE_REGION_CODE` and `YOUTUBE_REVERIFY_HOURS` (must equal the web service values)
   * No JWT or S3 variables are needed.
8. Enable failure notifications for the job (Render: job → Settings → Notifications).
9. Use **Trigger Run** once and open the run's Logs.

### Behaviour of the command

* Prints one line, `checked=N, verified=N, quarantined=N, unavailable=N, returned_to_review=N`, to stdout
  (visible in the Render run logs). No other logging is configured for the CLI.
* Exit codes: `0` success; `1` a handled error (YouTube not configured, quota exhausted,
  YouTube unreachable); `2` database error. Render marks a non-zero exit as a failed run.
* **Failure handling:** a YouTube error mid-way commits what was already re-verified and exits `1`;
  nothing is approved or rejected by an error. There is no built-in retry; the next hourly
  run retries. Videos are processed oldest-verification-first, 50 per YouTube call
  (200 rows ≈ 4 quota units). Overlapping runs are safe (`FOR UPDATE SKIP LOCKED`).
* A video that vanished, became private, or is no longer made-for-kids is withdrawn immediately;
  one that returns goes to Pending, never straight back to Approved.
* Render does **not** alert when a job is *missing or never ran*, only when a run fails. Use the checks below.

### Optional: a second job for discovery and auto-approval

`python -m app.cli youtube-discover` discovers curated candidates, scans trusted-channel upload
playlists, and re-reviews waiting videos. Schedule it to ingest future trusted uploads and
continue any initial backfill. It requires `YOUTUBE_DISCOVERY_ACTOR_ID` (an active admin with
`video:write`), `YOUTUBE_DATA_API_KEY` (or `YOUTUBE_API_KEY`), and `DATABASE_URL`. Set
`YOUTUBE_DISCOVERY_MAX_RESULTS=50` and run hourly while large trusted-channel backfills are
pending; each trusted channel is limited to three pages per run. `YOUTUBE_AUTO_PUBLISH_AGE_BAND`
is optional for trusted channels; without a channel override or global band, trusted videos use
the supported `3-15` range. `python -m app.cli youtube-auto-review --limit 100` runs only the
re-review step and does not discover new uploads.

### How to verify it is working

Any one of these, after the first scheduled hour:

* **Admin panel → YouTube review → Review summary**: "Oldest verification" should be less than about an
  hour old, and "approved videos past the 72-hour limit" must be `0`.
* `python -m app.cli youtube-report` (read-only) prints `oldest_approved_verification`, `approved_stale`,
  and `reverify_hours`.
* SQL: `select min(last_verified_at) from youtube_content_reviews where status='approved';`
  must stay within 72 hours (and within about 1 hour if the job is hourly), and
  `select count(*) from youtube_content_reviews where status='approved' and last_verified_at < now() - interval '72 hours';`
  must be `0`.
* Audit log: every recheck that examined at least one video now writes one `youtube.recheck.completed` row
  (actor empty for the command line job, with the counts in `details`):
  `select created_at, details from audit_logs where action = 'youtube.recheck.completed' order by created_at desc limit 5;`
  should show a row about every hour. **Runs before this change left no trace**, so an earlier recheck cannot
  be attributed to a button, a command or a cron job from the database.
* Render: the job's Events/Logs list a successful run each hour.

## 3. Videos stored with the unsupported `4-12` band (decision needed)

Production data on 2026-11-04 (read-only): **5 approved and published** and **35 pending** videos have
`age_min=4, age_max=12`, the old default for automatically discovered videos. It is not one of the four
bands, so the "publish approved" batch blocks such videos, and the admin diagnostics count them as an
invalid band. **No record has been changed.**

What the data shows:

* All 7 trusted channels are `3-5`. 11 of the 35 pending rows are from trusted channels; they will take the
  channel's `3-5` band automatically when approved. No manual mapping is needed for them.
* The other 24 pending rows come from non-trusted channels (e.g. SciShow Kids, Peekaboo Kidz, Smile and
  Learn, BYJU'S, CodeAI-style coding videos); 36 of the 55 pending videos are also over 180 s, so they
  would wait for a person regardless of the band.
* The 5 approved ones, all automatically approved: CodeAI "Unplugged - What is Computer Science?" (coding),
  BYJU'S "Visualising Surface Tension" (science), Nat Geo Kids "Intro to Cool Science Experiments", Anon Animation
  "English Stories For Kids", and Cocomelon "Learn Colors with Balls".

### Recommended strategy (needs approval before any change)

A video cannot carry two bands, so a `4-12` video must be placed in the *narrowest correct* band. Moving
to a band only **narrows** who sees it (4-12 currently covers three bands), which is the safe direction.

1. **Do not bulk-map.** Do not set every `4-12` row to one band.
2. **Trusted-channel rows (11 pending):** no action; the existing approval path applies the channel band.
3. **Approved + published (5): review each by hand and choose one band.** Suggested starting points for a
   reviewer to confirm after watching: Cocomelon colours → `3-5`; Nat Geo Kids experiments → `6-8`;
   BYJU'S surface tension → `6-8` or `9-12`; CodeAI computer science → `9-12`;
   Anon Animation stories → `3-5` or `6-8`. Until decided they stay visible to ages 4-12 (their
   current, previously-approved audience). If you prefer, withdraw them from the feed until mapped.
4. **Other pending (24):** leave pending. Approve each from the admin panel choosing a band (the manual
   approval dialog already forces one of the four). Do not rely on auto-approval for them unless
   `YOUTUBE_AUTO_PUBLISH_AGE_BAND` is deliberately set.
5. **Applying a change to existing rows:** there is currently no YouTube-specific "change band" action.
   `PATCH /admin/videos/{id}` can set ages but does not validate against the four bands and has no admin
   screen. Recommended small addition (not built; needs approval): an audited admin action that
   changes the band of a YouTube video and accepts only the four valid bands. Until then use the manual
   path: revoke, reopen, approve with the chosen band (this resets approval history; so prefer the
   addition above for the 5 published videos).
6. **Dry run first:**
   ```sql
   select r.youtube_video_id, v.title, r.channel_title, r.discovery_topic, r.status, v.age_min, v.age_max
   from youtube_content_reviews r join videos v on v.id = r.video_id
   where v.age_min = 4 and v.age_max = 12 order by r.status, r.channel_title;
   ```

## 4. Test and verification notes

* The backend suite was run against a disposable local PostgreSQL whose table definitions were copied
  (schema only) from Neon, never against Neon. See the audit report for the exact results.
* **Browser test of the admin panel (2026-11-04):** the built admin was served locally and pointed at a local
  backend with a scripted YouTube stand-in. Driven in Chrome: sign-in, YouTube review page, Discover,
  "Process waiting videos", the status counts, the Waiting reason and a quarantined video's flags.
  **Not driven in a browser:** the Approve/Reject/Revoke dialogs, Trust channel, Recheck button and
  "Publish approved" (covered by widget tests only). **There is no admin screen for importing a single
  YouTube URL**, so that endpoint was exercised over HTTP only. The browser run used a stand-in for
  YouTube, not the live YouTube API, and was not run against the Render deployment.
