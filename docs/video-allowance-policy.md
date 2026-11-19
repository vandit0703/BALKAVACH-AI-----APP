# Video allowance policy

Authoritative description of how video time is earned and spent. Code:
`balkavach-backend/app/services/video_entitlement_service.py` (grant, calculation) and
`video_watch_history_service.py` (`record_progress`, the only deduction path).
Approved by the product owner on 2026-11-19; do not change without approval.

## Policies

| Policy | Rule |
|---|---|
| Free allowance | Every child gets 900 s (15 min) of video per family-local day with no mission. It is spent first. |
| Mission reward | Each parent-approved mission grants exactly 900 s. Pending, rejected or unapproved missions grant nothing. |
| Stacking | Grants add up (15, 30, 45, 60 min ...). |
| Daily cap | The parent's `video_settings.daily_limit_seconds`, default 3600 s, clamped to 900-14400 s. It limits mission seconds *granted* that day, plus the free 900 s. Watching does not create room for more grants. A partial remainder is granted in part. |
| Duplicate grants | One grant per submission (unique `submission_id`); re-approval returns the existing grant. |
| Approval-date rule | A grant belongs to the family-local day on which the parent **approves** the mission (`granted_at`), not the day it was submitted. A mission done on Monday and approved on Tuesday counts toward Tuesday's cap and Tuesday's time. (Streaks and activity use the submission day; that is separate.) |
| Midnight expiry | Unspent time expires at the end of the family-local day (the family timezone, falling back as in `timezone_service`). Nothing carries over. |

## Single deduction path

Watch time is deducted only by `record_progress`
(`POST /api/v1/videos/watch-history/{video_id}/progress`). The server measures elapsed time with its
own clock, caps one report at 30 s, and charges free time first, then mission grants oldest-first. The
client's position and `is_playing` flag are never trusted as proof of time: a "paused" report whose
position still advances at playback speed is charged.

`/video-access/heartbeats` does **not** deduct mission/free time. For a `mission_reward` entitlement
it reports the authoritative remaining time and ends the session at zero. Only the separate
star-redemption pool (a specific reward video) is still charged by that route; it has no overlap with
the mission allowance.

## Low-time and time-up alerts (2026-11-19)

| Rule | Detail |
|---|---|
| Thresholds | `video_time_nearly_exhausted` when the remaining time falls from above **120 s** to 120 s or less (but above 0); `video_time_exhausted` when it reaches 0. The 120 s value is the roadmap's "≤2 min" (Phase 3, item 5). |
| Source | Only `record_progress`, after it has charged time, using its own before/after figures (`app/services/video_time_alerts.py`). Nothing else creates them. |
| Once only | At most one of each per family-local day, re-armed only by a new parent-approved grant later that day. Further reports below the line, other videos, Shorts or resumes never repeat it. |
| Language | The in-app notification uses the child's `preferred_language` (en/hi/gu) and the server's real minutes. Push text says "a little" because it is templated per type. |
| Wording | Never says time was earned or unlocked. The time-up text always says a grown-up must approve a mission. |
| Safety | Created inside a savepoint: if storing the alert fails, the charge is still committed. |
| In the app | `PlaybackGuard` (shared by the YouTube player, the detail player and Shorts) raises one gentle Panda notice per crossing, from the server's figure, shown app-wide. Reaching zero, or the server reporting more than 120 s again, re-arms it. |

## Fixes found while completing Phase 3 (2026-11-19)

1. **Every progress report failed.** `record_progress` passed a naive datetime to the allowance helpers, whose `utc_naive()` rejects naive values, so each report raised `ValueError` (HTTP 500). The client then paused playback as "offline" after two reports. The mocked tests never ran the real calculation, and the PostgreSQL suite has never run. Fixed: one timezone-aware instant is passed. A SQLite regression test now runs the real path.
2. **Remaining time was over-reported.** Sessions use `autoflush=False`, so the post-charge re-read missed the free seconds just charged. The reply then overstated the remaining time by up to 30 s, and `is_exhausted` was never true at the moment the free time ran out. Fixed with a `flush()` before the re-read.

## Enforcement edge cases (code audit, not device verified)

| Case | Behaviour |
|---|---|
| Time runs out during playback | The report that reaches 0 returns `is_exhausted: true` (later ones get 403 `video_time_exhausted`). The player pauses or removes the embed and opens the lock page. |
| Background, screen lock, sleep | The players pause on leaving the foreground. The server charges at most 30 s for one interval, so a long gap is not charged. On return a paused report re-checks. The lock page re-checks on resume and stops its refresh timer in the background. |
| Network loss | Two failed reports in a row pause playback ("offline"). It resumes only after the server answers. An unanswered check is never treated as a yes. |
| Delayed reports | One report is charged at most 30 s. **Gap:** a client reporting less often than every 30 s gets the difference free; the app reports every 10 s. |
| Repeated reports | The same instant charges 0 (tested). |
| Seeking | A seek while paused is free; while playing, only wall-clock time is charged (tested). |
| Two devices at once | **Gap:** both devices report into the same daily-usage row, so concurrent playback is charged about once, not twice. Fixing it needs the one-session-per-child / play-ticket model (deferred, product decision D6). |
| Parent approves while the child is on the lock page | Push refreshes notifications and then the allowance. The lock page also re-checks every 45 s, on resume and on "Check again", then shows "Video time is back" with a button home. It unlocks nothing itself: opening a video asks the server again. |
| Local midnight | Allowance, usage and grants are per family-local day. Unspent time expires (tested), and alerts from yesterday do not silence today's (tested). |
| Regular videos vs Shorts | Same endpoint, same guard, same rules. |
| Player error or app killed | No reports means no charge. The first report after a crash may charge up to 30 s for the gap (the last state was "playing"). |

## What the server cannot do

A YouTube player that is already loaded cannot be stopped remotely. The backend withholds video ids
once the allowance is zero, and every report returns the remaining time, but a modified client that
never reports progress can keep playing a video it already holds. Hard enforcement needs hosted media
with short-lived signed URLs (see `phase-a-video-playback-architecture.md`).
