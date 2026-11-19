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

## What the server cannot do

A YouTube player that is already loaded cannot be stopped remotely. The backend withholds video ids
once the allowance is zero, and every report returns the remaining time, but a modified client that
never reports progress can keep playing a video it already holds. Hard enforcement needs hosted media
with short-lived signed URLs (see `phase-a-video-playback-architecture.md`).
