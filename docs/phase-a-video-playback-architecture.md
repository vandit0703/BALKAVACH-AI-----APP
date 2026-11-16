# Phase A Video Playback Architecture

## Existing authoritative path

The backend owns the allowance ledger. A qualifying parent-approved mission
creates one `mission_reward` entitlement for up to 900 seconds. The daily cap
is calculated from total seconds granted in the family's local day; consumed
seconds never create cap room. No client-side timer may grant or deduct time.

The current backend playback contract is:

1. `POST /api/v1/video-access/sessions` validates child role, published video,
   language, age, active entitlement, one active child session and device
   session identity.
2. The configured playback provider issues a URL limited by the lesser of 60
   seconds and remaining entitlement time.
3. `POST /api/v1/video-access/heartbeats` accepts at most 30 seconds elapsed,
   locks the watch session and entitlement, and deducts the accepted seconds.
4. `POST /api/v1/video-access/sessions/{id}/interrupt` closes the active watch
   session without deducting unobserved time and revokes provider playback.
5. Exhaustion marks both entitlement and watch session complete, revokes the
   provider session, and returns no remaining playback time.

Concurrency is protected by row locks on the child/session/entitlement path.
This must remain the only allowance deduction path.

## Missing implementation pieces

### Playback provider

`app.integrations.get_video_playback_provider()` currently resolves the
configured provider, but no production provider implementation is present in
the repository. A provider must implement:

- `issue_playback_url(video, session_id, expires_at)` using a private object
  key and a short-lived signed URL or equivalent token;
- `revoke_playback(session_id)` so interruption, exhaustion and unpublish can
  stop access where the media service supports revocation;
- server-side binding of the issued URL to the authorized playback session;
- no public bucket or permanent media URL.

### Private media storage

`app/integrations/storage.py` currently stores proof photos through local disk
or S3. That provider does not implement video upload, private video keys,
range requests, signed playback URLs or lifecycle cleanup. Production needs a
private S3-compatible bucket or media service, credentials, lifecycle policy,
and an ingress/admin upload workflow. Render local disk is not durable.

### Client session integration

The Flutter native player currently accepts a direct `Uri` through
`NetworkVideoPlaybackController`. The app has no repository for
`/video-access/sessions`, `/heartbeats` or `/interrupt`, so it cannot consume
the authorized playback URL or report authoritative progress.

The required client controller must:

- request a session before creating the native player;
- send heartbeats no more than every 30 seconds and stop them when paused;
- interrupt on pause/background/dispose and tolerate an already-ended session;
- stop the surface on a 403 exhaustion/expiry response;
- show the existing friendly exhaustion state and navigate to missions;
- never deduct locally and never treat player position as proof of watch time.

## Shorts and regular videos

YouTube Shorts and regular YouTube videos use the official YouTube player and
the separate watch-history completion path. They do not currently use the
mission entitlement playback-session API. Hosted videos are the path that
requires the missing provider and client session integration. Product must
decide explicitly whether hosted Shorts consume mission entitlement time; the
decision must be implemented in the same backend session path, never as a
second client deduction mechanism.

## Required external infrastructure

- Render Redis URL for shared authentication rate limits.
- PostgreSQL schema baseline or approved schema dump before migrations can run
  on a fresh database.
- Private S3-compatible video bucket or signed media provider.
- Provider credentials and URL-signing/revocation configuration.
- Admin upload or import workflow for hosted media.
- Device-level Android playback testing and background/lifecycle validation.

No provider, storage credential, media upload, or client heartbeat changes are
implemented by Phase A.