# BalKavach AI — Implementation Roadmap

**Baseline:** commit `58b3545`, audit dated 2026-11-18. Finding IDs (SEC-, MIS-, VID-, …) refer to `BALkAVACH_GAP_ANALYSIS.md`; evidence is in `BALkAVACH_CURRENT_STATE_AUDIT.md`.
**Nothing in this document has been implemented.** Estimates are for **one developer**, in working days, including tests and review, excluding content-authoring and design work done by others. They are planning estimates, not measurements.

---

## 0. Order, adjustments to your priority list, and decisions needed

### 0.1 Order (your priority list, adjusted by what the code revealed)

| # | Phase | Why here |
|---|---|---|
| 0 | Foundations: decisions, test database, CI baseline | Without DB-backed tests running, changes to auth/missions/entitlements are unsafe (OPS-04). |
| 1 | Security and authentication | SEC-01 is P0 and parent-mode is the trust boundary for everything else. |
| 2 | Mission / reward / streak correctness | Fixes dating and single-writer streak **before** entitlements and notifications depend on them (MIS-03/04/05). |
| 3 | Video entitlement and playback enforcement (+ quick wins 3-QW) | P0 VID-01; defines the play-ticket model that feeds, recommendations and the mascot messaging use. |
| 4 | Trusted-channel moderation | Independent of 3 except for the shared scheduler; moderation must be right before catalogue grows. |
| 5 | Mission content catalogue + admin editor | **Moved ahead of the companion**: the companion has nothing worth saying until missions are real. Research can start on day 1 (non-code). |
| 6 | Child companion (Mitu Panda) MVP | Needs Phase 5 content, Phase 3 time-state events, Phase 7 transport for reminders only optionally. |
| 7 | Notifications | Needs Phase 2 (dates) and Phase 3 (events); deep links need router work. |
| 8 | Feed recommendations and horizontal playback | Needs Phase 3 tickets; the *quick wins* (description, logout, orientation hypothesis tests) are pulled forward as 3-QW. |
| 9 | Sharing, referrals, promotion | Needs deep links from Phase 7. |
| 10 | UI/responsive polish and performance | Rolling; final sweep last. |

### 0.2 Decisions required before the relevant phase (owner: product)

| Decision | Needed by | Options / recommendation |
|---|---|---|
| D1 Free daily 15 min (VID-03) | Phase 3 | The code gives every child 15 free minutes with no mission. Your requirement says time is **earned**. Recommend: remove or make it a parent-controlled "bonus" default 0; copy and mascot lines must match. |
| D2 Reward/streak date anchor (MIS-04, VID-05) | Phase 2 | Recommend: anchor to the **mission's local date** (assignment `local_date`), and give a granted entitlement at least a fixed validity window (e.g. until end of the next local day) so late approvals are not punished. |
| D3 What is an "eligible mission" (MIS-08) | Phase 2 | Recommend: only daily-mission tasks grant video time; parent chores grant stars/XP only (or a separate parent-set toggle per task). |
| D4 Parent-mode model (SEC-01/09) | Phase 1 | Recommend: child sessions carry `mode=child` + device id; leaving child mode is a step-up (`POST /auth/parent-mode`) requiring child bearer + parent PIN (≥6 digits) or parent password; per-account lockout; parent alert. Parent session issued is **family-scoped to that device** and short-lived (e.g. 15 min idle). |
| D5 Mission pool policy (MIS-02) | Phase 2/5 | Recommend: no permanent exclusion; repeat only after a cool-down (e.g. 6 weeks) with a different variation. |
| D6 YouTube enforcement level (VID-01) | Phase 3 | The embed plays on-device and cannot be truly controlled. Recommend play tickets + withheld IDs + client lock, and accept residual risk from rooted/modified clients (document it). |
| D7 Companion audio (MAS-03) | Phase 6 | Recommend text bubbles + sound effects at MVP; pilot recorded Gujarati/Hindi lines before any TTS dependency. |
| D8 Migration policy | Phase 0 | Memory notes show an earlier "one additive migration" allowance (2026-10-23); migrations 0011–0017 have since been added. Confirm that **additive, reviewed migrations are allowed** for the new tables below. All proposed schema changes are additive. |
| D9 Scheduler location | Phase 0 | Cron/systemd timers on the VPS vs a managed scheduler; needed for streak-check, YouTube recheck/discover, notification schedules (OPS-02). |

### 0.3 Dependency graph

```
P0 ──► P1 ──► P2 ──► P3 ──► P8
 │            │       │      ▲
 │            │       └──► P4 (shares scheduler)
 │            └──► P5 ──► P6
 │                  P2+P3 ──► P7 ──► P9
 └── CONTENT research (starts day 1) ──► P5
 └── CHARACTER design/clearance (starts anytime) ──► P6
 P10 runs alongside every phase and closes last.
```

**Independent tracks:** content research, character design, Admin Trusted Channels page UI (backend part of P4 first), admin l10n clean-up, 3-QW.

### 0.4 Effort summary (one developer)

| Phase | Days | Cumulative (upper bound) |
|---|---|---|
| 0 Foundations | 4–5 | 5 |
| 1 Security/auth | 9–11 | 16 |
| 2 Mission/reward/streak | 9–12 | 28 |
| 3 Video enforcement (+3-QW 3 d) | 12–16 | 44 |
| 4 Trusted channels | 8–10 | 54 |
| 5 Mission catalogue + editor | 10–14 (+ content work by others) | 68 |
| 6 Companion MVP | 12–15 | 83 |
| 7 Notifications | 10–14 | 97 |
| 8 Feed recs + horizontal | 10–13 | 110 |
| 9 Sharing/referrals | 8–10 | 120 |
| 10 UI/perf polish | 10–14 | 134 |
| **Total** | **~102–134 working days (≈5–6.5 months)** | |

Add ~15 % for review rounds, device testing and content revisions (≈117–154 days all-in).

---

## Phase 0 — Foundations

**Objective:** Make every later change verifiable.
**Features/tasks**
* Provision a **disposable PostgreSQL** database named `…_test…`, run `alembic upgrade head` on it (with `ALLOW_SCHEMA_MIGRATIONS=true` only there), set `TEST_DATABASE_URL`; install `requirements.txt` + pytest in a virtualenv; run the full backend suite and record the **actual** pass/fail/skip counts as the baseline.
* Run `flutter analyze` and `flutter test` for both Flutter apps; record baseline; fix or quarantine known flaky tests (the earlier report names `push_registration_test`).
* CI pipeline: backend (migrations → tests, **fail if skipped count > 0 for DB suites**), Flutter apps (analyze, test).
* Add CI check that calls `get_model` for every `MODEL_TABLES` entry against the migrated DB (OPS-03).
* Document scheduler decision (D9) and write the unit/timer definitions for existing CLI jobs (`streak-check`, `youtube-discover`, `youtube-recheck`, `youtube-auto-review`) in `docs/backend-operations.md`.
* Remove/relocate `notes.txt` secrets (SEC-08); rotate the server password; move to key-based non-root SSH.
**Backend / Flutter / Admin:** CI and docs only. **DB changes:** none. **API changes:** none.
**Security:** secrets hygiene (SEC-08).
**Tests:** baseline report committed to `docs/`.
**Dependencies:** D8, D9.
**Effort:** 4–5 days.
**Acceptance:** one command per repo runs its tests; backend DB suite runs (0 skipped for DB suites); baseline numbers recorded; cron definitions reviewed.

---

## Phase 1 — Security and authentication

**Objective:** Make parent mode a real security boundary and complete the account lifecycle.

**Features**
1. **Parent-mode step-up (SEC-01/02/09).**
   * Child sessions get claims `mode=child`, `device_id`. Add `POST /auth/parent-mode/enter` requiring a **child bearer**, the parent PIN (min 6 digits) *or* the parent password, optional `family_id` inferred from the child. Returns a short-lived parent session limited to that family. Keep `/auth/parent-pin/verify` only as a deprecated alias for one release, behind the same limiter, then remove.
   * Per-account failed-attempt counter (Redis + DB audit row): 5 failures → 15-minute lock, doubling; notification to the parent's other devices ("5 wrong PIN attempts on Aarav's tablet").
   * Child mode cannot start unless a PIN exists (`POST /auth/children/{id}/session` returns 409 `parent_pin_required`; Flutter routes the parent to PIN setup first).
   * PIN change requires current PIN or password (SEC-07).
2. **Limiter hardening (SEC-03):** trusted-proxy configuration (document `--proxy-headers --forwarded-allow-ips`), add per-account key beside per-IP key, readiness check failing when `REDIS_URL` unset in production.
3. **Password reset end to end (SEC-04):** web landing page (static) + Android App Link / in-app screen consuming the token; localised copy; tests with a stub mailer.
4. **Account lifecycle (SEC-05):** `POST /auth/password/change` (current password required, revokes other sessions), `GET /auth/sessions`, `DELETE /auth/sessions/{id}`, `POST /auth/logout-all`, `DELETE /users/me` (soft-delete + scheduled purge) and `GET /users/me/export` (JSON), parent profile screen. Email verification: optional flag, off by default, behind a setting.
5. **Token hygiene (SEC-06):** reject access tokens without `sid` when `ENVIRONMENT=production`; document Fernet key rotation; child password reveal made one-time or re-authenticated.
6. **Flutter gate UX:** a proper PIN pad dialog (no email field), labelled correctly, localized, with lock-out messaging; parent logout with confirmation and relocated to Account (FEED-05).

**Backend tasks:** new endpoints, claims, limiter keys, audit rows, alerts via existing notification service; production-guard for `sid`.
**Flutter tasks:** `ParentGateButton` rewrite, PIN setup flow before child mode, reset-password screen, account screens, logout confirmation.
**Admin tasks:** none (admin already separate); show parent-lockout events in audit page.
**DB changes (additive):** `auth_sessions.device_id`, `auth_sessions.mode`; `parent_pin_attempts` (user_id, failed_count, locked_until, updated_at) or Redis-only counters with audit rows; `users.deleted_at`, `users.email_verified_at` (nullable).
**API changes:** new routes above; `TokenResponse` unchanged; OpenAPI baseline `tests/contracts/openapi_baseline.json` updated deliberately.
**UI/UX:** PIN pad with large touch targets, haptic feedback, Gujarati/Hindi strings, error states for lock-out/offline.
**Security considerations:** step-up token scope; lock-out must not be usable to lock a parent out of their own *password* login (PIN lock is independent); avoid user enumeration; audit all parent-mode entries.
**Test plan:** see Testing Plan §3 (SEC suite), including brute-force simulation, lockout expiry, child-token-cannot-call-parent-endpoints matrix generated from the router.
**Dependencies:** Phase 0, D4.
**Effort:** 9–11 days.
**Acceptance criteria:** (a) child bearer + wrong PIN ×5 locks that account's PIN entry for 15 min regardless of IP; (b) there is no endpoint that mints a parent session from `email + pin` alone; (c) starting child mode without a PIN is impossible; (d) forgot-password works from email link to new login on a device (manual test log); (e) logout-all/delete/export covered by API tests; (f) a router-wide test proves every `/parent`-class route rejects child tokens.

---

## Phase 2 — Mission, reward and streak correctness

**Objective:** One consistent lifecycle: assigned → selected → submitted → approved, with correct dates, a single streak writer and no catalogue exhaustion.

**Features**
1. **Fix skip/replace (MIS-03):** flush before re-query (or set `autoflush=True` for the daily-mission unit of work), return the replacement in the skip response; limit skips per day (e.g. 2) with a clear error.
2. **Date anchoring (MIS-04, D2):** `review_submission` computes streak date, `ChildActivityDay.activity_date` and entitlement validity from the **assignment's `local_date`** (fallback: submission time for non-daily tasks). Entitlement `expires_at` ≥ grant time + minimum window (D2).
3. **Single streak writer (MIS-05):** delete the inline streak maths in `task_service.review_submission`; badge criteria read `record_qualifying_activity`'s result.
4. **Rotation (MIS-02, D5):** replace "exclude approved forever" with a cool-down window; track `last_assigned_at` per child/template (derive from assignments); surprise cadence rule (e.g. at most 2 per week); alert (log + admin dashboard) when eligible pool < 6.
5. **Variation management (MIS-06):** honour `variation_key`, avoid the last 2 variations used.
6. **Eligibility (MIS-08, D3):** `grant_mission_video_entitlement` only for tasks with a daily assignment link (or per-task flag).
7. **Age/DOB (MIS-09):** make DOB required at child creation (migration-free: validate in schema); align mission age range with video range or show a clear "ask a parent" state; capture family timezone (VID-04) at registration with device value.
8. **Flutter:** use `/active`, `/skip`, `/history`, `/weekly`; show mystery bonus; resilient states for 422/503.
**Backend tasks:** as above + tests. **Admin:** show eligible-pool health. **DB changes:** none required (derive from existing tables); optional index `(child_id, template_id, local_date)`.
**API changes:** `/daily-missions/{id}/skip` response unchanged shape but now correct; new error code `daily_skip_limit`; weekly summary unchanged.
**UI/UX:** history list, weekly chips, surprise treatment.
**Security:** all daily-mission routes remain `require_child`; admin routes keep permissions.
**Test plan:** DB-level lifecycle suite (Testing Plan §3.2): exhaustion, rotation, skip, late-night approval, DST/timezone boundary, concurrent select (two requests), double submission.
**Dependencies:** Phase 0; D2, D3, D5.
**Effort:** 9–12 days.
**Acceptance criteria:** after simulated 60 consecutive approved days the child still receives 3 choices; a mission completed at 23:50 and approved at 08:00 next day counts for the completed day and grants usable video time; badges and streak display never disagree; skip returns a replacement in the same response; all new tests pass on the disposable DB.

---

## Phase 3 — Video entitlement and playback enforcement

**Objective:** Meet the §4 "must not allow" list with the strongest controls available for YouTube embeds, with one metering path.

**Features**
1. **One metering model (VID-02):** introduce `POST /video-access/play` → returns a **play ticket** (`ticket_id`, `video_id`, `youtube_video_id` or MP4 URL, `expires_at` ≤ 60 s, `remaining_seconds`). Tickets are required to obtain the playable ID; `GET /videos/feed|shorts` return thumbnails/titles but `youtube_video_id` only through the ticket (or withheld when remaining ≤ 0). Retire or delete the old `/video-access/sessions|heartbeats` paths **or** reimplement them as this ticket API (one writer of `consumed_seconds`).
2. **Heartbeat contract:** `POST /video-access/tickets/{id}/heartbeat` every 10–15 s with `is_playing`; server credits `min(wall-clock since last heartbeat, 30 s)` while the last report was playing; if no heartbeat within 45 s the ticket closes and credit stops at last heartbeat + 10 s grace; one active ticket per child (second device gets 409 with a friendly code).
3. **Exhaustion behaviour:** at 0 remaining → heartbeat returns `status=exhausted`; feeds return items without playable IDs; client shows mascot message. Save last position before rejecting (VID-08).
4. **Pre-launch gate (VID-09):** Flutter checks allowance before opening any player.
5. **Notifications (VID-07):** server creates `video_time_nearly_exhausted` (≤2 min) and `video_time_exhausted` once per day each; use actual granted minutes in text.
6. **Decisions D1/D2 applied:** free allowance removed or parent-controlled; entitlement validity per D2; timezone captured (done in Phase 2).
7. **Observability:** counters for tickets issued, heartbeats rejected, exhausted events; audit entry for entitlement grants/revocations; parent screen shows "minutes earned / used today".

**3-QW (quick wins, ≈3 days, can start after Phase 0):** remove the description from the player area (FEED-04), move parent logout to Account with confirmation (FEED-05 — shares work with Phase 1), add a pre-launch allowance gate, and add on-device **repro logs** for the landscape issue (Testing Plan §6.3) so Phase 8 starts with facts.

**Backend tasks:** ticket service, heartbeat, feed shaping, notification emitters, migration for tickets (reuse `video_watch_sessions` if suitable), tests. **Flutter tasks:** player integration for YouTube embed and MP4, lock UI, exhaustion/mascot messaging, resume. **Admin tasks:** read-only entitlement/usage view per child for support.
**DB changes (additive):** `video_play_tickets` (id, child_id, video_id, entitlement_id nullable, device_id, started_at, last_heartbeat_at, ended_at, status, credited_seconds); index `(child_id, status)`.
**API changes:** new `/video-access/play`, `/video-access/tickets/{id}/heartbeat|end`; feed response change (`youtube_video_id` nullable when locked) — update Flutter models and `openapi_baseline.json`.
**UI/UX:** friendly lock screen, remaining-time pill, 2-minute warning.
**Security:** server clock only; ticket bound to child + device; rate limit per child; cannot extend by replaying tickets; ID withheld when exhausted. **Residual risk (document):** a modified client that already saw a YouTube ID can replay it outside the app; YouTube provides no server-side control.
**Test plan:** Testing Plan §3.3 anti-bypass suite: restart, second device, background, repeated calls, clock skew, double-writer assertion (a test that fails if two code paths mutate `consumed_seconds`), cap/idempotency, midnight/DST, concurrency.
**Dependencies:** Phases 0–2, D1, D2, D6.
**Effort:** 12–16 days (incl. 3-QW).
**Acceptance criteria:** with remaining = 0, no API returns a playable ID for a child; killing the app mid-play stops crediting within 45 s; two devices cannot hold tickets simultaneously; grants stay idempotent; exactly one code path mutates `consumed_seconds` (test-enforced); lock UI appears before playback starts.

---

## Phase 4 — Trusted-channel moderation

**Objective:** Admin can approve, monitor, suspend and revoke channels; trust never bypasses child-safety rules.

**Features**
* **Status model:** `status` enum `pending|approved|suspended|revoked`, `status_reason`, `approved_by`, `approved_at`, `suspended_at`; `is_active` kept in sync for compatibility.
* **Sync visibility:** `last_checked_at`, `last_successful_sync_at`, `last_error`, `channel_url` (derived), counters from `youtube_content_reviews` joined to videos: discovered / approved / pending / quarantined / unavailable, and Shorts vs regular.
* **Detail before approval:** `GET /admin/videos/youtube/channels/discover/{channel_id}` returns title, description, subscriber/video counts (YouTube API `channels.list`), and a sample of recent uploads screened with `screen_candidate`, with made-for-kids ratio; approval requires rights status choice and age band.
* **Suspend vs revoke:** suspend = hide all channel videos from feeds immediately (reversible, no discovery); revoke = also stop discovery and quarantine automatic publications; define manual-approval behaviour explicitly.
* **Trust history:** `GET /admin/videos/youtube/channels/{id}/history` from `audit_logs` plus new status-change rows.
* **Safety layering retained:** `auto_approval_blocker` untouched in meaning; add tests asserting that a trusted channel cannot publish a video that is not made-for-kids, has flags, exceeds duration or is age-restricted.
* **Rechecks:** channel-level recheck job (title/availability/made-for-kids ratio), scheduler health banner ("last successful recheck") and alert when recheck is older than 48 h (CHAN-03). Add reviewed Hindi/Gujarati keyword lists (CHAN-04).
* **Admin page:** dedicated *Trusted Channels* page (list with filters, detail drawer, actions, counts, history), all strings localised.
**DB changes (additive):** columns above on `youtube_trusted_channels`; optional `youtube_channel_events` table (channel_id, actor, action, reason, created_at).
**API changes:** extend `YouTubeTrustedChannelPublic`; new detail/history/suspend endpoints; keep existing ones.
**Security:** all under `video:write/read`; every state change audited; YouTube API key stays server-side.
**Test plan:** extend `test_youtube_rules.py`/`test_api_youtube.py` (status transitions, counts accuracy, suspend hides feed items, recheck moves changed videos to quarantine); admin widget tests with Gujarati/Hindi.
**Dependencies:** Phase 0 (scheduler), independent of Phases 1–3 except OPS.
**Effort:** 8–10 days.
**Acceptance criteria:** an admin can add a channel, see sample + safety summary, approve it, watch counts update after a sync, suspend it (videos vanish from child feeds within one request), revoke it, and see full history; a flagged upload from an approved channel lands in quarantine, never in the feed.

---

## Phase 5 — Mission content catalogue and admin editor

**Objective:** Real, research-backed, trilingual missions that rotate.

**Research method (for the content team; does not need code)**
* Build an evidence table per activity: *skill/purpose*, *age band*, *materials*, *safety notes*, *source*, **evidence grade** (A = established finding / consensus guideline, B = supported by reviews with caveats, C = reasonable practice, **P = product-design assumption**).
* Candidate sources to examine (named as **starting points, not yet reviewed** in this audit): Harvard Center on the Developing Child (serve-and-return, executive function), CASEL SEL competencies (emotion identification, empathy, responsible decision-making), WHO 2019 guidance on physical activity/sedentary behaviour for under-fives, American Academy of Pediatrics media-use guidance, habit-formation research (e.g. Lally et al. on time to automaticity; implementation-intention "if-then" planning), self-determination theory (autonomy → the three-choice design), and research on rewards undermining intrinsic motivation (relevant to the video-time reward, treat as a **risk to monitor**). Note that "brain-training" memory games show weak far-transfer evidence; frame memory missions as practice and play, not as proven cognitive enhancement.
* Distinguish **established findings** from **product assumptions** in the catalogue metadata (`evidence_level`).

**Initial catalogue:** 28 days (4 weekly rotations × 7 themes) × 3 age bands × 3 locales = 252 variations, authored by educators, Gujarati/Hindi reviewed by native speakers; expand to 365 only after parent/child feedback (rotation via cool-down means 28 distinct days already avoid exhaustion for months with variations).
**Features**
* Admin editor: create/edit templates & variations, per-locale completeness panel, preview as child (age band × locale), validation (existing PII rules + length limits), publish/unpublish, import/export JSON/CSV.
* Seed migration replaced by a **content import command** (not a schema migration) so content can change without releases; keep existing templates unpublished once the new set is live.
* Schema additions: `skill_area`, `developmental_purpose`, `evidence_level`, `parent_tip`, `estimated_minutes` on variations/templates.
**Backend tasks:** columns, import command, validators. **Flutter:** show purpose chip and materials; Gujarati/Hindi layout checks. **Admin:** editor UI.
**DB changes (additive):** columns above. **API changes:** admin template endpoints extended; child payload adds optional `skill_area`, `parent_tip`.
**Security/safety:** no mission may require location, photos of faces, contact info or spending (existing validator + review checklist); materials must be household items; adult-supervision text on anything involving scissors/heat/water.
**Test plan:** content lint test (every published template has 9 variations, no romanised gu/hi — check script ranges `઀–૿`/`ऀ–ॿ`), admin editor tests, render tests at text scale 1.3 for gu/hi.
**Dependencies:** Phase 2 (rotation), content team output.
**Effort:** 10–14 dev days (+ content/review time by others, estimated separately).
**Acceptance criteria:** catalogue lint passes; native speakers sign off gu/hi; a simulated child receives no repeat within the cool-down; admin can publish a new mission without a deployment.

---

## Phase 6 — Child companion MVP (Mitu Panda)

**Objective:** An animated, personalised companion that guides the mission→video loop without per-message AI calls.

**Characters (original; working names require a trademark/clearance search before adoption):** **Mitu Panda** (primary, existing panda art direction), **Tinku Robot** (tinkerer), **Captain Tara** (original superhero girl/boy variant), **Chiku the Squirrel** (friendly animal), **Zing the Dragon** (fantasy), **Dhruv & Disha** (cartoon kids). None may resemble Bheem, Shin-chan, Doraemon, Pokémon, Spider-Man, Mickey, Motu Patlu or Oggy in shape, colour scheme, name or voice; commission original art and keep licence/assignment paperwork. The appeal of those franchises (strong silhouette, catchphrase, signature gadget, running gag) can inspire **qualities**, not designs.

**MVP architecture**
* **Dialogue catalogue (server-driven, versioned JSON):** `events` × `age_band` × `locale` × `character` → arrays of lines with placeholders (`{name}`, `{minutes}`, `{mission_title}`) and tags (`tone`, `min_gap_hours`). Served by `GET /companion/dialogue?version=` with ETag; cached on device; falls back to a bundled English/Gujarati/Hindi default set so offline works.
* **State machine on device (deterministic):** events — `app_open_morning|afternoon|evening`, `missions_ready`, `mission_selected`, `mission_started`, `mission_submitted`, `mission_approved`, `video_unlocked`, `video_time_low`, `video_time_up`, `streak_at_risk`, `gentle_reminder`, `weekly_summary`. Inputs come from existing providers (missions, allowance, streak). Selection = seeded random over lines not shown in the last N occurrences (anti-repetition memory in local storage); per-event cooldowns prevent nagging.
* **Animation:** Rive or Lottie file per character with 5 states (idle, wave, talk, celebrate, sleepy); a single `CompanionView` widget; reduced-motion setting disables loops; target <5 MB total assets, lazy-load non-selected characters.
* **Audio:** none at MVP except short sound effects (D7). Pilot recorded lines for Gujarati/Hindi before choosing TTS.
* **Character selection:** child picks from a carousel in onboarding and Profile; stored server-side in `child_profiles.companion_key` (additive) with local cache; parent can change it.
* **Language & tone:** age-band tone (4–6 simple, short; 7–10 playful; 11–15 light, respectful); no guilt language, no streak shaming; reminders limited to 1/day in-app.
* **No AI calls per conversation:** all lines are authored; optional later: offline-generated line packs reviewed by humans.
**Backend tasks:** dialogue endpoint + admin editor (reuse Phase 5 patterns), `companion_key` field on child profile endpoints, event hints in allowance/missions payloads. **Flutter:** `CompanionController`, `CompanionView`, selection screens, integrate on Home/Missions/Video-lock/Approval states. **Admin:** dialogue catalogue editor with locale completeness. **DB changes (additive):** `child_profiles.companion_key`; `companion_dialogue_packs` (version, locale, payload JSONB, published_at).
**API changes:** `GET/PUT /companion` for the child (key), `GET /companion/dialogue`; admin CRUD.
**UI/UX:** bubble layout that wraps Gujarati/Hindi without clipping, tap-to-skip, safe-area aware, never covers primary buttons.
**Security/privacy:** the child's display name appears only on device; dialogue packs contain placeholders, not personal data; no analytics on the child's name.
**Test plan:** unit tests for the state machine (no repeats in N, cooldowns, event→line); golden tests per locale; performance test (frame times on a low-end device while animating); parent-controlled disable switch.
**Dependencies:** Phase 5 content tone, Phase 3 lock messaging, design assets.
**Effort:** 12–15 days (excluding art).
**Acceptance criteria:** the sequence "greeting → mission explained → submitted → approved → 15 minutes unlocked → low-time warning → time-up" shows distinct lines in each of the three languages; the same line does not repeat within the configured window; works offline with the bundled set; animation never drops below 50 fps on the reference device.

---

## Phase 7 — Notifications

**Objective:** Reliable, localised, deep-linked notifications with a delivery trail; parent and child kept separate.

**Architecture**
* **Event outbox → dispatcher:** keep `notifications` as the user-visible record; add `notification_deliveries` (notification_id, device_token_id, status `queued|sent|failed|invalid`, attempt, error_code, sent_at). A dispatcher process (same codebase, run by the scheduler or a worker loop) sends with retries/backoff for `retry` results and deactivates `invalid_token`s.
* **Scheduler jobs (per family timezone):** `daily_mission_ready` (e.g. 08:00), `mission_waiting` (afternoon if no mission selected), `weekly_challenge` (Sunday), `new_videos` (batched, max 1/day), existing `streak-check` (at-risk). All idempotent per child/day via a unique key.
* **Taxonomy and audience:** a table of types → audience (`child|parent`), category (`missions|rewards|videos|streak|system`), default on/off, quiet hours respected.
* **Preferences:** per-category toggles and quiet hours in `user_settings` (extend JSON) with separate defaults for child and parent accounts; parent can mute child categories.
* **Localisation:** store `type` + `params`, render in recipient language at read/send time (fixes NOT-05); extend `GENERIC_TEXT` to include every type including the new ones.
* **Deep links:** payload `route` (e.g. `/child/missions`, `/parent/approvals`); Flutter handles `onMessageOpenedApp`, `getInitialMessage`, foreground local banner; router mapping tested; unauthenticated/mismatched role falls back to home.
* **Polished UI:** notification centre screens for child (big friendly cards with the companion) and parent (grouped list, unread badge), pull-to-refresh, empty state.
* **Admin:** page to view recent deliveries/failure rates and send a **test** or announcement to a segment (guarded by `notifications:write`); templates managed with locale completeness.
**DB changes (additive):** `notification_deliveries`, `notification_templates` (optional), settings extension. **API changes:** `GET/PATCH /notifications/preferences`, `GET /notifications/unread-count`; admin delivery/broadcast endpoints.
**Security:** payload carries no names/titles (retain existing rule); admin broadcast rate-limited and audited; FCM key server-side only.
**Test plan:** dispatcher unit tests with a fake provider (ok/invalid/retry/error), timezone scheduling tests incl. DST, dedupe, preference/quiet-hour suppression, Flutter deep-link routing tests; manual FCM test on a real device (Firebase config must be present).
**Dependencies:** Phase 0 (scheduler), Phase 2 (dates), Phase 3 (video events), Firebase configuration (OPS-05).
**Effort:** 10–14 days.
**Acceptance criteria:** each example message in your list can be produced (morning mission, mission waiting, parent approved, 15 min unlocked, streak at risk, weekly challenge, new videos) in en/gu/hi; tapping opens the right screen; failures visible in admin; no duplicate sends on retry; parent and child inboxes show only their own types.

---

## Phase 8 — Feed recommendations and horizontal/portrait playback

**Objective:** YouTube-like next-video discovery and correct rendering of every aspect ratio.

**Recommendations (no ML needed for MVP)**
* `GET /videos/{id}/next?limit=` returns eligible videos scored by: same category (+3), shared topic/tags if stored (+2), same age band fit (+2), same language (+1), same channel (+1, capped), not watched in 14 days (+2), popularity among same-age cohort (+1), recency; **never** returns ineligible, locked or unapproved items; includes a fallback to "popular for your age" so the screen is never empty. Ticketed playback IDs (Phase 3).
* Home/feed: "Continue", "Because you watched…", "New for you", with cursor pagination (fix FEED-02); re-surface completed videos after a cool-down; parent replay stays.
* End-of-video overlay: 3–6 suggestions with thumbnails and an auto-advance countdown that parents can disable.
**Playback correctness**
* Add `orientation`/`aspect_ratio` metadata (additive columns on `videos`; for YouTube derive from thumbnails/`player.embedHtml` dimensions or oEmbed width/height, with admin override) and classify Shorts by **duration ≤ 60 s AND portrait**; landscape ≤60 s goes to the regular feed (FEED-03).
* One `PlayerShell` widget: portrait 16:9 box, fullscreen/landscape handler for **both** MP4 and YouTube embed (listen to the iframe fullscreen events; lock landscape in fullscreen; restore on exit), safe-area and notch handling, buffering/error/retry states, keep-screen-on while playing, pause on background (already present for the embed).
* Remove description from the main area (done in 3-QW); optional collapsible "About" shown only in parent view.
* Performance: keep one player instance alive per route, dispose on leave, avoid rebuilding the list while playing; split the 1500-line Shorts widget.
**Backend:** next endpoint, scoring query, metadata columns + backfill job, classification update with migration of existing rows. **Flutter:** player shell, overlay, feed sections. **Admin:** override orientation/category/tags on a video.
**DB changes (additive):** `videos.orientation`, `videos.aspect_ratio`, optional `video_topics`/tags. **API changes:** next endpoint; `VideoFeedItem` gains `orientation`.
**Security:** recommendations respect age/language/visibility/entitlement exactly like the feeds (shared eligibility function).
**Test plan:** scoring unit tests, eligibility parity test (every recommended item is feed-eligible), classification tests (portrait/landscape × duration), device matrix for fullscreen/rotation (Testing Plan §6.3), widget tests for the overlay.
**Dependencies:** Phase 3 (tickets), Phase 4 (channel data), 3-QW findings.
**Effort:** 10–13 days.
**Acceptance criteria:** after any video ends the child sees suggestions and the screen is never empty (given ≥ 10 eligible videos); a landscape 45-second video plays in the regular player at the correct aspect; fullscreen works for both players on the reference devices in portrait→landscape→portrait without layout breakage; no ineligible video can be recommended (parity test).

---

## Phase 9 — Sharing, referrals and app promotion

**Objective:** Parent-initiated sharing with attribution and a polished card.

**Features**
* **Referral model:** `referral_codes` (one per parent, short code), `referral_attributions` (code, installer_user_id, first_seen_at, registered_at, status), reward ledger entry credited **to the referring parent** (e.g. extra mission customisation, badge) with limits (max N/month, one reward per verified new family, no self-referral, no rewards that increase child screen time).
* **Links:** App Links (`https://<domain>/r/<code>`) with Android install-referrer handling; web fallback page showing the promotion card and store buttons; deep link opens registration with the code prefilled (parent flows only; never shown to children).
* **Share UI (parent area):** share sheet with localised message, promo card image (app name, short description, attractive visual using original panda art, store link, referral link), WhatsApp quick action using the system share sheet (and `whatsapp://send` only if installed), "invite friends" and "share weekly progress/badge" actions generating image cards.
* **Privacy:** achievement cards show first name only if the parent opts in; no child identifiers, ages or photos in links; consent text updated; kids cannot trigger shares.
**Backend:** tables, endpoints (`GET /referrals/me`, `POST /referrals/attribute`), anti-abuse rules, reward crediting, admin report. **Flutter:** share screens, card renderer (`RepaintBoundary` → PNG), deep-link handler. **Admin:** referral stats page. **DB changes (additive):** two tables + reward ledger reuse. **API changes:** as above.
**Security:** rate limit attribution; ignore codes after first attribution; validate store referrer signature; do not trust client-reported attribution for rewards without a verified registration.
**Test plan:** attribution edge cases (self-referral, duplicate device, expired code), link-handling tests, card golden tests in en/gu/hi, privacy review checklist.
**Dependencies:** Phase 7 deep-link plumbing, Phase 1 (registration), D-list for reward rules.
**Effort:** 8–10 days.
**Acceptance criteria:** a parent can share to WhatsApp in three taps; a new parent installing from the link is attributed once; reward is credited once after verified registration; no child data in any shared artefact.

---

## Phase 10 — UI/UX, responsiveness and performance

**Objective:** Prove and fix layout quality on real devices; consistent components.

**Features:** device/responsive sweep per Testing Plan §6; fix overflow/clipping (starting with 280 px choice cards, dense buttons, admin dialogs 480/520 px); skeleton loaders for feed, missions, parent hub; consistent spacing/typography tokens (use existing `app_spacing.dart`, `app_typography.dart`); Gujarati/Hindi text at 1.3× and 2.0× scale; admin string extraction and a test that fails on new hard-coded strings; accessibility pass (48 dp targets, labels, contrast, TalkBack); performance pass (rebuild profiling, image caching, cut unnecessary network calls such as repeated allowance fetches, split large widgets, avoid expensive animations in lists); remove dead code (`/video-access` old paths if superseded).
**Dependencies:** none hard; runs per phase and closes last. **Effort:** 10–14 days.
**Acceptance:** no overflow in the responsive matrix; frame-time budget met on the reference low-end device; localisation and accessibility checklists signed.

---

## 1. Risk register (top items)

| Risk | Impact | Mitigation |
|---|---|---|
| Phases 1–3 change core contracts (OpenAPI baseline, feed shape) | Old app builds break | Version the API or keep deprecated paths for one release; update `openapi_baseline.json` deliberately; staged rollout |
| Content quality (gu/hi) | Product credibility | Native-speaker review gates; lint for script |
| YouTube embed cannot be fully controlled | Residual bypass | Document; play tickets + withheld IDs reduce, not eliminate |
| Scheduler absent in production | Silent feature loss | Phase 0 definitions + health banner (CHAN-03) |
| Character IP | Legal | Original art, name searches, assignment paperwork |
| Single developer capacity | Schedule | Phases 4, 5(research), 6(art) have independent tracks that others can run |

## 2. What I recommend doing first (next two weeks)

1. Phase 0 (4–5 d) and start **content research** and **character design** in parallel (no code).
2. SEC-01/02 design sign-off (D4) and implement Phase 1 core (step-up + lock-out + PIN-required) — the highest-value risk reduction.
3. 3-QW (description removal, logout placement, pre-launch gate, repro logs) because they are small and unblock Phase 8 facts.
