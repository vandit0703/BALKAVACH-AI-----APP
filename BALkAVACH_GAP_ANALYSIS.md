# BalKavach AI — Gap Analysis

**Baseline:** commit `58b3545`, audit dated 2026-11-18. IDs match `BALkAVACH_CURRENT_STATE_AUDIT.md`.
**Evidence level** (column "Ev."): **V** = verified by reading code, **S** = suspected (needs test/run), **U** = unverified (live data/deployment/device).
**Owner:** BE = backend, FL = Flutter child/parent app, AD = admin panel, OPS = deployment/infra, PROD = product decision, CONTENT = non-code content work.
**Priority:** P0 = fix before any wider release; P1 = required for the requirements to be true; P2 = important; P3 = hygiene.
**Status:** Missing / Partial / Broken / Risk (works but unsafe) / Decision (needs owner choice).

---

## A. Summary matrix by requirement area

| Area | Backend | Flutter | Admin | API integration | Tests (static) | Biggest gap |
|---|---|---|---|---|---|---|
| Mission engine (§2) | Partial | Partial | Partial | Partial (2 of 9 endpoints used) | Pure tests only | Placeholder content; exhaustion after ~20 missions |
| Companion (§3) | Missing | Missing (static panda art only) | N/A | Missing | None | No engine, no server-side character |
| Video entitlement (§4) | Implemented, risky | Implemented (reactive lock) | N/A | Verified for progress+allowance; `/video-access/*` unused | 17+12+5 tests | Server hands out YouTube IDs when time is 0 |
| Notifications (§5) | Partial | Partial | Missing | Partial | 15+2 + 1 FL | No schedules, no deep links, no delivery log |
| Sharing/referrals (§6) | Missing | Partial (plain text share) | N/A | Missing | None | Whole referral system |
| Streak (§7) | Implemented | Implemented | N/A | Verified | 17+2 | Approval-time dating; duplicate inline calc |
| Auth/security (§8) | Implemented, with gaps | Partial | Implemented | Verified | 14+7+4 | Unauthenticated PIN→parent-session endpoint |
| Trusted channels (§9) | Partial | N/A | Partial | Verified | ~121 | No status workflow, stats, page, scheduler guarantee |
| Feed/playback (§10) | Partial | Partial | N/A | Verified | Many FL tests | No recommendations; empty-feed; landscape handling |
| UI/UX (§11) | N/A | Partial | Partial | N/A | responsive + l10n tests exist | Not verified on devices |

---

## B. Prioritised gap register

### B1. Security and authentication

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| SEC-01 | **P0** | Risk | V | BE+FL | Unauthenticated `POST /auth/parent-pin/verify` (email + 4–8 digit PIN) returns a full parent session; limiter is per IP+email only, no per-account lockout/alert/audit | Parent-mode entry becomes an authenticated step-up bound to the child device session; per-account failure counter with exponential lockout and parent alert; PIN ≥ 6 digits or password re-auth option; audit log |
| SEC-02 | P1 | Broken | V | FL+BE | Parent trapped in child mode when no PIN exists; PIN fields labelled "Password"; success toast says "Parent gate"; parent email retyped each time | Child mode cannot start without a PIN; PIN set/verify copy fixed; gate remembers the family (no email entry) |
| SEC-03 | P1 | Risk | U | OPS+BE | Limiter keyed on `request.client.host`; no proxy-header policy; Redis mandatory | Trusted-proxy configuration documented and tested; health check that fails deploy if `REDIS_URL` missing; per-account limiter in addition to per-IP |
| SEC-04 | P1 | Partial | V | BE+FL+OPS | Password reset has no landing screen/deep link; link target undefined | Reset screen (app + web fallback), token consumed, all sessions revoked (already done server-side) |
| SEC-05 | P2 | Missing | V | BE+FL | No change-password, own-session list/logout-all, account deletion/data export, email verification | Endpoints + parent settings UI; deletion/export aligned to the consent flow |
| SEC-06 | P2 | Risk | V | BE | Tokens without `sid` skip revocation; child passwords reversibly encrypted | Reject `sid`-less tokens in production; document/rotate Fernet key; consider one-time child password reveal |
| SEC-07 | P2 | Risk | V | BE | PIN change needs only bearer | Require current PIN or password |
| SEC-08 | P3 | Risk | V | OPS | Local `notes.txt` has a root-password SSH transcript for production | Delete; use key-based non-root access; rotate the password |
| SEC-09 | P2 | Decision | V | PROD | Server has no concept of "device in child mode" | Introduce a device/mode claim (e.g. `mode=child` on child sessions, `device_id`) so the server can distinguish contexts |

### B2. Mission, reward, streak correctness

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| MIS-01 | **P0** | Broken (content) | V | CONTENT+BE+AD | Seeded missions are placeholder text; gu/hi are romanised | Curated, reviewed catalogue in real scripts; purpose/skill metadata; import tooling |
| MIS-02 | P1 | Broken | V | BE | Approved templates excluded forever → 503 after ≈20 approvals; surprise only ever appears once | Cool-down-based rotation (e.g. not repeated within N weeks), graceful degradation, surprise cadence rule, alert when pool < threshold |
| MIS-03 | P1 | Broken? | **S** | BE | `skip` response may return stale choices (`autoflush=False`) | DB test; `session.flush()` before re-query; return replacement in the skip response |
| MIS-04 | P1 | Broken | V | BE+PROD | Streak, activity-day, entitlement dated by approval moment | Anchor all three to the assignment's `local_date` (or submission time) per an explicit rule; entitlement validity must not be shorter than N hours after grant |
| MIS-05 | P1 | Risk | V | BE | Inline streak computation in `review_submission` (no grace) vs `streak_service` | Single writer/reader (`streak_service`); delete inline logic; badge criteria use service result |
| MIS-06 | P2 | Partial | V | BE | `variation_key` ignored; no variation rotation | Selection honours key and avoids recent variations |
| MIS-07 | P2 | Partial | V | FL | Skip/history/weekly/active endpoints not used | Skip UI (limited), mission history, weekly summary cards |
| MIS-08 | P2 | Decision | V | PROD+BE | Any approved task grants video time | Define "eligible mission" (daily-mission tasks only? parent chores?) and enforce in `grant_mission_video_entitlement` |
| MIS-09 | P2 | Partial | V | BE+FL | DOB optional but required for missions; missions 4–15 vs videos 3–15 | Required DOB at child creation (or clear child UI), aligned age ranges |
| MIS-10 | P2 | Missing | V | AD | Admin lists/publishes only | Template/variation editor with preview and per-locale completeness |
| MIS-11 | P2 | Missing | V | BE | No DB tests for lifecycle | See Testing Plan §3 |
| MIS-12 | P3 | Unknown | U | BE | Child language source (`users.preferred_language` of the child user) not traced | Verify at child creation/settings |

### B3. Video entitlement and playback enforcement

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| VID-01 | **P0** | Risk | V | BE+FL | Server returns `youtube_video_id` irrespective of allowance; lock is UI-only | Feeds and a play-ticket endpoint refuse/withhold IDs at 0 remaining; ticket-based metering with heartbeat deadline; client lock stays as UX |
| VID-02 | P1 | Risk | V | BE | Two metering paths mutate the same counters; `/video-access/*` has no provider and no client | Retire or merge so exactly one writer exists; document ticket model |
| VID-03 | P1 | Decision | V | PROD | Free 15 min/day for every child | Decide: remove, keep as separate "bonus", or rename in UI/copy |
| VID-04 | P1 | Broken | V | BE+FL | Timezone defaults to UTC until a parent saves one | Capture device timezone at registration/child creation; warn when unset |
| VID-05 | P2 | Risk | V | BE | Entitlement expires at local midnight; late approvals leave minutes | Minimum validity window or carry-over rule (product decision) |
| VID-06 | P2 | Risk | V | BE | `is_playing` is client-claimed; no per-child active-session lock in path B; ≤30 s over-credit tail | Heartbeat deadline + single active ticket per child |
| VID-07 | P2 | Missing | V | BE | `video_time_nearly_exhausted`/`video_time_exhausted` never created; push text hard-codes "15 minutes" | Emit events once per day per threshold; use actual granted minutes |
| VID-08 | P2 | Partial | V | BE | Exhausted 403 prevents saving last position | Save position, then reject |
| VID-09 | P2 | Missing | V | FL | No pre-launch allowance gate | Block launch with mascot message when remaining ≤ 0 |

### B4. Trusted-channel moderation

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| CHAN-01 | P1 | Missing | V | BE | No status workflow, approved_by/at, channel URL, last_checked/sync, per-channel counts, history API | Additive migration + `GET /admin/videos/youtube/channels/{id}` with stats and history |
| CHAN-02 | P1 | Partial | V | AD | No dedicated page; hard-coded English strings | Trusted Channels page with list, detail drawer, suspend/revoke, counts, history; l10n |
| CHAN-03 | P2 | Risk | U | OPS+BE | Feed fails closed after 72 h without recheck; scheduler not in repo | Scheduler defined in deployment docs/unit files; admin banner "last successful recheck" with alert |
| CHAN-04 | P2 | Partial | V | BE | English-only keyword denylist | Add Hindi/Gujarati terms reviewed by native speakers; keep `madeForKids` mandatory |
| CHAN-05 | P2 | Partial | V | BE | Untrust affects only automatic publications | Separate **suspend** (hide all, reversible) from **revoke** (also stop discovery); define manual-approval behaviour |
| CHAN-06 | P3 | Missing | V | BE | No channel-level recheck | Periodic channel metadata re-fetch (title, made-for-kids ratio, availability) |

### B5. Companion and mission experience

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| MAS-01 | P1 | Missing | V | FL+BE+CONTENT | No animation/TTS/dialogue engine; mascot named "Kavach Panda" not "Mitu Panda"; character choice local-only | MVP per Roadmap Phase 6; additive `companion_key`; original character set with clearance check |
| MAS-02 | P2 | Missing | V | BE+FL | Dialogue hard-coded in ARB; no variation/age tone | Server-driven dialogue catalogue with anti-repeat memory |
| MAS-03 | P2 | Decision | — | PROD | Audio: no TTS dependency; gu/hi on-device TTS quality unknown | Pilot recorded lines vs on-device TTS before committing |

### B6. Notifications

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| NOT-01 | P1 | Missing | V | BE+OPS | No scheduled notifications | Scheduler + per-family-timezone jobs for morning/waiting/weekly/new-videos |
| NOT-02 | P1 | Missing | V | FL+BE | No deep links from pushes | `route` in payload, `onMessageOpenedApp`/`getInitialMessage` handling, router mapping |
| NOT-03 | P2 | Missing | V | BE | No delivery log/outbox/retry; in-process pool | `notification_deliveries` table, retry with backoff, failure metrics |
| NOT-04 | P2 | Missing | V | BE+FL | Only global on/off | Categories + quiet hours; parent and child separated |
| NOT-05 | P2 | Partial | V | BE | In-app text English-only | Store type+params, render localised on read |
| NOT-06 | P2 | Missing | V | FL | No notification centre screens | Parent and child inboxes |
| NOT-07 | P2 | Missing | V | AD+BE | No admin broadcast/templates/delivery view; Firebase config absent here | Admin notification page; environment configuration documented |

### B7. Sharing and referrals

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| SHR-01 | P2 | Missing | V | BE+FL | No referral codes, attribution, reward rules | `referral_codes`, `referral_attributions` tables; rewards credited to the parent account, anti-abuse rules |
| SHR-02 | P2 | Missing | V | FL+OPS | No deep links/app links, promo card, WhatsApp-tuned message | App Links + install referrer, share card, localised copy |
| SHR-03 | P2 | Decision | — | PROD | Sharing child achievements | Parent-gated, no child identifiers in links; consent copy |

### B8. Feed and playback

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| FEED-01 | P1 | Missing | V | BE+FL | No recommendation/related API; Up-next is client-side; no end-of-video suggestions | `GET /videos/{id}/next` (category/age/topic scored), end-screen overlay, never an empty screen |
| FEED-02 | P1 | Risk | V | BE | Completed videos excluded forever; offset paging over a mutable filter | Re-surface after cool-down; cursor paging; recycle "favourites" |
| FEED-03 | P1 | Broken? | **S** | FL+BE | Horizontal/portrait handling: duration-only classification, fixed 16:9, custom fullscreen only for MP4 | Add orientation metadata (YouTube API provides dimensions via thumbnails/`contentDetails`; store `aspect`/`orientation`), unified fullscreen controller, device test matrix |
| FEED-04 | P2 | Partial | V | FL | Description shown under the player | Remove from primary viewing area (collapsible "About" for parents only) |
| FEED-05 | P2 | Decision | V | PROD+FL | Logout placement (child none; parent one-tap, no confirm) | Parent logout only in Account/Settings with confirmation; none on viewing screens |
| FEED-06 | P3 | Debt | V | FL | Very large widget files | Split by responsibility when touching |

### B9. UI/UX and operations

| ID | Pri | Status | Ev. | Owner | Gap | Required outcome |
|---|---|---|---|---|---|---|
| UX-01 | P2 | Unknown | U | FL+AD | Overflow/clipping not verified on devices; fixed widths (daily choice cards 280, admin dialogs 480/520) | Device/responsive sweep per Testing Plan §6 |
| UX-02 | P2 | Partial | V | FL | No skeleton loaders (spinners only) | Skeletons for feed, missions, parent hub |
| UX-03 | P2 | Partial | V | AD | Hard-coded English strings in admin pages | Move to ARB; add a lint-style test |
| UX-04 | P3 | Unknown | U | FL | Touch targets of dense buttons; Gujarati/Hindi at large text scale | Accessibility pass |
| OPS-01 | P3 | Debt | V | BE | Confusing migration numbering | Add note in `docs/backend-operations.md`; never renumber applied revisions |
| OPS-02 | P1 | Risk | U | OPS | Cron jobs not defined in repo | Scheduler definitions + monitoring |
| OPS-03 | P2 | Risk | V | BE | Runtime table reflection hides schema drift | CI step that boots the app against a migrated disposable DB and calls `get_model` for every `MODEL_TABLES` entry |
| OPS-04 | P1 | Risk | V | BE | DB-backed tests do not run without `TEST_DATABASE_URL` | Provision a disposable Postgres in CI; make skipped-count a CI failure |
| OPS-05 | P2 | Unknown | U | OPS | Firebase/SMTP config absent from workspace | Environment checklist |

---

## C. Critical blockers and independence

**Blockers (must precede dependent work)**
1. **Test foundation (OPS-04)** — no safe change to missions/entitlements/auth without DB-backed tests running. Everything in Phases 1–3 depends on it.
2. **Product decisions** — VID-03 (free minutes), MIS-04/VID-05 (which date anchors rewards), MIS-08 (eligible missions), SEC-09 (parent-mode model), mascot audio (MAS-03), migration policy (see Roadmap §0). Without them, implementation will be rework.
3. **SEC-01/02** — block any release that promotes parent-mode as secure.
4. **VID-01 + VID-02** — must be designed together (play ticket model) before FEED-01 (next-video API) so recommendations return ticketed items.

**Can proceed in parallel (independent)**
* Mission content research and authoring (CONTENT) — can start immediately.
* Admin Trusted Channels page and stats (CHAN-01/02) — independent of playback work.
* Original character design and clearance (MAS-01 art) — independent of code.
* Description removal and parent-logout placement (FEED-04/05) — small, independent.
* Admin l10n clean-up (UX-03).

## D. Counts

| Priority | Count |
|---|---|
| P0 | 3 (SEC-01, MIS-01, VID-01) |
| P1 | 20 |
| P2 | 35 |
| P3 | 6 |
| **Total** | **64** |

(Counted from the tables in section B.)
