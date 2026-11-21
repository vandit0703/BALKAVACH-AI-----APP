# Scheduler requirements and deployment approach

Several features depend on **scheduled jobs that nothing in the repository starts**. If they do not
run, features degrade silently. This document lists them and the recommended way to run them.
It changes no server and no configuration; it is the plan to execute under your authorisation.

## 1. Jobs that exist today (all are `python -m app.cli <command>`)

| Command | What it does | Cadence | Failure impact |
|---|---|---|---|
| `youtube-recheck --limit 200` | Re-verifies approved YouTube videos; withdraws changed/unavailable ones | hourly | **Child feed empties ~72 h after the last run** (`YOUTUBE_REVERIFY_HOURS`, fail-closed) |
| `youtube-discover --max-results 50` | Finds curated and trusted-channel uploads, auto-reviews | hourly during backfill, then every 3–6 h | New trusted-channel videos never appear |
| `youtube-auto-review --limit 100` | Re-reviews waiting videos only | optional (discover already does it) | Waiting videos stay pending |
| `streak-check` | Moves streaks to at-risk/broken and sends "streak at risk" notifications | hourly (idempotent, 20 h notification de-dupe) | No at-risk pushes; states update lazily on next activity |
| `youtube-report` | Read-only status report | on demand / daily to logs | none |
| `youtube-recheck-health` | Read-only monitor: exit 3 if approved videos are stale or no recheck completed in `--max-age-hours` (default 3) | hourly | none; a non-zero exit is the alert |
| `video-feed-diagnose --child-id <id>` | Read-only: which feed rule empties a child's Home/Shorts | on demand | none |

Example Render and systemd definitions for these jobs are in `balkavach-backend/deploy/`; the runbook is `docs/video-feed-restoration.md`.

Exit codes: `0` success, `1` handled error (e.g. YouTube quota), `2` database error. Overlapping runs are safe for
`youtube-recheck` (`FOR UPDATE SKIP LOCKED`); do not run two `youtube-discover` at once.

Required environment per job: `DATABASE_URL`; YouTube jobs also `YOUTUBE_DATA_API_KEY`,
`YOUTUBE_REGION_CODE`, `YOUTUBE_REVERIFY_HOURS` (same as the web service) and, for discover, `YOUTUBE_DISCOVERY_ACTOR_ID`;
`streak-check` additionally needs the `NOTIFICATION_PROVIDER`/FCM settings for its pushes to be delivered.

## 2. Jobs required by later phases (not implemented yet)

Per-family-timezone notification schedules (morning mission, mission waiting, weekly challenge, new videos),
notification dispatcher retries, trusted-channel recheck health, content/catalogue pool alerts. They will use the
same mechanism below, so choose it once.

## 3. Where to run them (decision needed)

The repository documents the API at `https://api.balkavach.tech` and Render cron jobs
(`docs/youtube-operations.md`); a separate Ubuntu VPS is also used (see `docs/security-ssh-remediation.md`). **I could
not verify which host serves production or whether any job exists.** Recommended order of preference:

1. **Render Cron Jobs** (already documented): one job per command, root `balkavach-backend`, build
   `pip install -r requirements.txt`, shared Environment Group with the web service, failure notifications on.
2. **systemd timers on the VPS** if the API runs there (units below). Timers are preferable to cron: logs in the journal,
   `Persistent=true` catches up after downtime, `flock`-style overlap protection via `Type=oneshot`.
3. Avoid in-process schedulers inside the web workers: duplicated runs per instance and lost on restart.

### systemd timer template (VPS option)

```ini
# /etc/systemd/system/balkavach-youtube-recheck.service
[Unit]
Description=BalKavach YouTube recheck
[Service]
Type=oneshot
User=balkavach            # dedicated non-root user
WorkingDirectory=/opt/balkavach/balkavach-backend
EnvironmentFile=/etc/balkavach/backend.env     # mode 0600, owned by root:balkavach
ExecStart=/opt/balkavach/venv/bin/python -m app.cli youtube-recheck --limit 200
TimeoutStartSec=900

# /etc/systemd/system/balkavach-youtube-recheck.timer
[Unit]
Description=Hourly YouTube recheck
[Timer]
OnCalendar=hourly
Persistent=true
RandomizedDelaySec=120
[Install]
WantedBy=timers.target
```
Repeat for `youtube-discover` (hourly), `streak-check` (hourly). Enable with `systemctl enable --now <name>.timer`.

## 4. Monitoring (so a missing job is noticed)

* Each job logs one summary line; ship the output to your log service and **alert on absence** (no run in 2 h), not only on failure.
* Admin panel → YouTube review → summary: "oldest approved verification" must stay under ~1 h; "approved past the 72 h limit" must be 0.
* Read-only SQL checks are in `docs/youtube-operations.md` (audit rows `youtube.recheck.completed`).
* Phase 4 adds an in-admin banner for "last successful recheck".

## 5. Acceptance for this item

A reviewer can answer, from documentation alone: where each job runs, its schedule, its environment, how to see the last
run, and who is alerted when it stops. **Status today: documented only; nothing was created or changed on any host.**
