# Video play tickets (decision D6)

**Status, 2026-11-19:** architecture **approved** by the product owner. The database work is **deferred** (no migration, no table).

**Implementation status (inactive in production)**

| Part | State |
|---|---|
| Rules (`play_ticket_rules.py`) | Done; unit tests (pure). |
| Single charging gate (`charging_path.py`) | Done. Tickets are active only when `VIDEO_PLAY_TICKETS_ENABLED=true` **and** the `video_play_tickets` table exists (`has_model`). Today that is never true, so `record_progress` charges as before. With tickets active, `record_progress` refuses with 409 `play_ticket_required`, and never both charge. |
| Shared ledger writer | `apply_allowance_charge` was extracted from `record_progress` with no behaviour change. It is used by both paths, so free time first, parent grants, the cap, expiry and alerts stay identical. |
| Service (`play_ticket_service.py`) | Issue (child lock, eligibility, allowance, supersede, race retry), heartbeat (token, ownership, sequence, midnight split, video revocation, exhaustion), end (idempotent) and revoke. Persistence sits behind `PlayTicketRepository`. The production `SqlPlayTicketRepository` targets the deferred table. **No in-memory production store.** |
| API (`api/v1/play_tickets.py`) | `POST /video-access/tickets`, `/{id}/heartbeat` and `/{id}/end`: child only, rate limited, tokens never logged. They return **503 `play_tickets_unavailable`** while tickets are inactive. |
| Tests | Service and API tests run on an in-memory **SQLite** copy of the proposed table (`tests/video_world.py`), with doubles for the PostgreSQL partial unique index and a start race. **Not PostgreSQL**; real concurrency is still unverified. |
| Flutter (`play_ticket_client.dart`) | API client and `PlayTicketSession` lifecycle (heartbeats only while playing, rising sequences, a queued pause so it is never lost, stop on refusal or after 2 network failures, end). It sits behind `--dart-define=VIDEO_PLAY_TICKETS=true` (default off). **No player uses it yet**; they still report through `record_progress`. |

## 1. Findings from the current code

| Area | What the code does today | Consequence for tickets |
|---|---|---|
| `record_progress` (`video_watch_history_service.py`) | The single deduction path. It locks the child row, measures elapsed time with the server clock from `child_video_daily_usage.last_heartbeat_at` (**one row per child per day**), and caps an interval at 30 s. It charges free time first, then mission grants oldest first. | Two devices share that one timestamp, so concurrent playback is charged about **once**. Reports more than 30 s apart get the excess **free**. Tickets fix both. |
| `video_time_alerts.py` | Low-time/time-up alerts from the before/after figures of a charge. | Unchanged: it is called by whichever path charges. |
| `video_access_service.py` + `video_watch_sessions` | A session/heartbeat API for **hosted media** (needs `VIDEO_PLAYBACK_PROVIDER`, currently not configured). It allows one active session per child (409 for a second). Its heartbeat deducts **nothing** from the mission/free allowance. **The Flutter app does not call it.** | Closest existing shape, but it is not suitable for reuse without seeing the real schema: `entitlement_id` is filled on every row, yet YouTube viewing on the free allowance has no entitlement, and nullability/indexes are only known in the live database (reflected, not in the repo). `learning_gate_service` also sums `video_watch_sessions.watched_seconds`, so writing YouTube tickets there would change the learning-gate figures. **Recommendation:** a dedicated `video_play_tickets` table. Retire the old session API, or re-implement it on tickets later. |
| Feeds | `youtube_video_id` is withheld only when the allowance is 0. | With tickets, the ID comes only with a ticket (see §5 for what that does and does not achieve). |
| Flutter | `PlaybackGuard` interprets every progress report (regular player, detail player, Shorts) and pauses on refusal or 2 failures. The lock page re-checks the allowance. | The guard becomes the ticket client: start ticket → heartbeat → stop on a refusal or supersession. |

## 2. API contract (proposal)

All require a **child** bearer token (`require_child`), are rate limited per child, and use server time only.

### `POST /api/v1/video-access/tickets`
Request: `{ "video_id": uuid, "device_session_id": "string ≤64", "resume_position_seconds": int? }`

The server, under `SELECT … FOR UPDATE` on the child row:
1. Checks the child is active and the video is eligible (same rules as the feeds: published, rating, age band, language, YouTube visibility).
2. Checks the remaining allowance is > 0 (the existing `get_child_video_allowance_today`).
3. **Supersedes** any active ticket of this child: `state = superseded`, `ended_at = now`, `superseded_by = new id`.
4. Inserts the new ticket `issued`, storing only a **keyed hash** of an opaque token.

201: `{ "ticket_id", "ticket_token", "youtube_video_id" | "playback_url", "expires_at", "heartbeat_interval_seconds": 10, "remaining_seconds" }`

Errors: 403 `video_time_exhausted`, 403 `video_not_eligible`, 429.

### `POST /api/v1/video-access/tickets/{ticket_id}/heartbeat`
Request: `{ "ticket_token", "sequence": int, "is_playing": bool, "position_seconds": int }`

200: `{ "state", "accepted_seconds", "remaining_seconds", "is_exhausted", "duplicate" }`

Refusals end playback on the client:
- 409 `ticket_superseded` ("playing on another device")
- 409 `ticket_expired` (start a new ticket)
- 403 `ticket_revoked`
- 403 `ticket_exhausted` / `video_time_exhausted`
- 404 (ticket not found, or not this child's)
- 401/403 on a token mismatch: 403 `ticket_invalid`, no oracle for which part was wrong

### `POST /api/v1/video-access/tickets/{ticket_id}/end`
Request: `{ "ticket_token", "sequence", "position_seconds" }`. It charges the last interval if it was playing, then moves the ticket to `ended` and saves the resume position. It is idempotent.

**Watch history** (position, completion) keeps using the existing `child_video_watch_history` columns. It is written by the heartbeat instead of by `record_progress`.

## 3. States and charging

```
issued ──first heartbeat──▶ playing ⇄ paused
   │                            │
   └──────────┬─────────────────┘
              ▼ (any of)
  superseded │ expired │ revoked │ exhausted │ ended   (terminal, never revived)
```

The rules are implemented and unit-tested in `play_ticket_rules.heartbeat`:
- **Nothing is charged** until a heartbeat reports playing, and only for intervals that **began** playing. A ticket that was issued but never played, or a paused one, costs nothing.
- An interval up to **45 s** is charged in full (no free excess). Longer silence (app killed, device asleep, network gone) **lapses** the ticket: at most a **10 s grace** is charged, then a new ticket is needed.
- **Duplicates:** the client numbers its heartbeats. A repeat or slightly older number is charged 0. An old replay (more than 3 behind) is refused.
- **Clock manipulation:** the client sends no time. Only server timestamps are used, and a server clock going backwards is refused without charging.
- The charge never exceeds the live remaining allowance. Reaching 0 moves the ticket to `exhausted`.
- **Local midnight:** a ticket never outlives the family-local midnight (`ticket_expires_at`). An interval that crosses it is split (`split_at_local_midnight`), and the ticket ends so the new day starts with a fresh check. Allowance and expiry rules are unchanged.
- **A parent approval during a session** simply raises the live remaining figure, because tickets are not bound to an allowance snapshot. After `exhausted`, the child needs a new ticket; the lock page's "Video time is back" leads there.

## 4. Security

- **Token:** 32 random bytes. Only an HMAC-SHA256 (keyed with a server secret) is stored, and comparison is constant-time. A leaked table cannot be replayed.
- **Binding:** the ticket is tied to the child (bearer token), and its row records `device_session_id`. A ticket from another child is 404.
- **One active ticket per child:** the child row lock serialises starts. A **partial unique index** on `child_id WHERE state IN ('issued','playing','paused')` is the database guarantee. A losing concurrent insert gets a constraint error and retries as a supersede.
- **No reuse:** terminal tickets refuse every call.
- **Rate limits** per child: starts 6/min, heartbeats 12/min.
- **Logs:** ids and states only, never tokens.

## 5. What tickets can and cannot enforce with YouTube

| Can | Cannot |
|---|---|
| Charge time exactly once, server-side, per device, with no free gaps or double sessions. | **Stop an already-loaded YouTube player** in a modified app that ignores refusals and stops sending heartbeats. YouTube offers no server-side kill switch for embeds. |
| Hand out the YouTube ID only with a ticket, so the honest app never plays without authorisation. | **Hide YouTube content:** the IDs are public videos. Anyone can open them on youtube.com or in the YouTube app, outside BalKavach. |
| Stop the honest app within one heartbeat (≤ about 10 s) of supersession, exhaustion or revocation. | Prevent screen recording or a second app. |

Stronger options, in increasing cost:
1. **Device controls:** Android screen pinning, or a device-owner/kiosk mode for a dedicated child device, plus Google Family Link limits for the YouTube app. This is outside the app, needs parent setup, and is documented guidance only.
2. **Hosted media:** the existing `VideoPlaybackProvider` abstraction (`issue_playback_url` / `revoke_playback`), private storage and **short-lived signed URLs** (≤ 60 s, re-issued per heartbeat). Revocation then truly stops playback after the current segment. It needs licensed or owned content, a CDN/storage provider and an upload workflow (`phase-a-video-playback-architecture.md`).
3. **DRM** (Widevine) on hosted media, for protection against copying. This is the most expensive option, and probably unnecessary for a children's learning catalogue.

## 6. Test plan

| Scenario | Unit (pure, done) | SQLite service test | PostgreSQL (needs `TEST_DATABASE_URL`) |
|---|---|---|---|
| Duplicate heartbeats, sequence replay | ✅ `test_play_ticket_rules` | service writes nothing on a duplicate | |
| Missing / delayed heartbeats, lapse grace | ✅ | ticket row → `expired` | |
| Clock manipulation (client sends no time, server time going back) | ✅ | | |
| Issued-but-not-played costs nothing | ✅ | | |
| Allowance exhaustion → `exhausted`, alert fires once | ✅ (state) | ✅ with `video_time_alerts` | |
| Midnight split and expiry | ✅ | grants of the old day are not used | DST-free zones only (India has none) |
| Parent approval mid-session | ✅ (live remaining) | grant then heartbeat | |
| Old ticket invalidated on a new start | | ✅ (sequential) | |
| **Two devices starting simultaneously** | | ✗ (no row locks in SQLite) | ✅ two connections, both `POST /tickets`: exactly one active, the other superseded |
| **Concurrent heartbeats on one ticket** | | ✗ | ✅ charged once |
| Unauthorised reuse (other child, wrong token, ended ticket) | ✅ (token, terminal) | ✅ 404/403 | |
| Single writer of consumption | ✅ (rules not imported anywhere yet) | test fails if both `record_progress` and the ticket heartbeat deduct | |
| Network interruption in Flutter | | | widget tests with a fake backend: guard stops on refusal, resumes with a new ticket |

## 7. Migration and roll-out plan (when database work is authorised)

1. **Additive migration:** create `video_play_tickets` with its indexes (schema in `deferred-database-integration.md`). No existing table changes.
2. **Ticket service and endpoints** behind the setting `VIDEO_PLAY_TICKETS_ENABLED` (default off).
3. **Single writer:** when the flag is on, ticket heartbeats deduct and `record_progress` stops deducting (it keeps saving position for older app versions). When it is off, nothing changes. A test enforces that never both deduct.
4. **Flutter:** `PlaybackGuard` speaks the ticket protocol (start → heartbeat every 10 s with sequence → end; stop on any refusal; "playing on another device" message for `ticket_superseded`). The feed stops relying on IDs in list responses.
5. **Feeds:** list responses omit `youtube_video_id` once all supported app versions use tickets.
6. Retire `/video-access/sessions|heartbeats`, or re-implement them on tickets for hosted media.
7. **Verification:** the PostgreSQL concurrency suite, then two real Android devices on one child account.
