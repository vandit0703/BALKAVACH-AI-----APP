# Frontend Functional Audit

> **Update 2026-10-13 (second pass).** Rows marked *Blocked* or *Honest limit* for photo
> proof, child reward shop, parent reward approval, approval inbox fan-out, child
> submission status, session length, weekly report time zone, garden, consent version and
> learning are **superseded**: those features are now implemented against the backend.
> Test counts here (576) are historical; see `feature-implementation-matrix.md` for the
> current verification (790 app tests, 152 backend tests, admin panel, live runs) and
> for what remains unbuilt.


Audit date: 2026-10-13. Scope: `balkavach-frontend/` against the FastAPI source in
`balkavach-backend/app/` and the live OpenAPI document
(`https://balkavach-ai-app.onrender.com/openapi.json`, 68 operations, identical
route list to the source). The backend contract is treated as authoritative. No
backend code, schema or migration was changed. Nothing was committed or pushed.

This audit was done by reading every screen's source and then fixing gaps; a
screen is not marked complete because it renders — each action below was traced
to its code path and to a test.

## Verification (re-run, not copied)

| Check | Result |
|---|---|
| `flutter pub get` | OK |
| `dart format --set-exit-if-changed lib test` | clean, 100 files |
| `flutter analyze` | no issues |
| `flutter test` | **576 tests, all passing** (395 at the start of this pass) |
| Debug APK | see the build result in the final report |
| Device / emulator | **never run** — no claim is made |

## Legend

**Data source** — `API` real backend call; `Local` device only (SharedPreferences,
secure storage, clipboard); `Derived` computed in the app from API data and not
persisted; `Placeholder` shown but not functional (none remain).

**Status** — `Complete` works against the real backend (or is a legitimate
local-only action) and is tested; `Honest limit` works as far as the API allows
and says so on screen; `Blocked` cannot be built without a backend or product
decision (see the Blockers section).

## Screen-by-screen action matrix

### Onboarding and authentication

| Screen (role) | Action | Behaviour | Endpoint / contract | Data | Status | Tests |
|---|---|---|---|---|---|---|
| Welcome (all) | Pick language | Applies immediately, persisted | – | Local | Complete | `widgets/app_flow_test`, `localization/localization_audit_test` |
| Welcome | Get Started | → consent | – | Local | Complete | `widgets/app_flow_test` |
| Welcome | Select-language radio | One labelled, checkable node per language for screen readers (**fixed in this pass**: radios were unlabelled) | – | Local | Complete | `responsive/…` a11y guideline |
| Consent (parent) | Tick + continue | Stores accepted document version; later recorded on the server | `POST /settings/families/{id}/consents` (after a family exists) | Local → API | Complete | `widgets/app_flow_test`, `features/missions_state_test` |
| Consent | New version after an update | **Fixed in this pass:** a signed-in parent is sent back to consent when the stored version is outdated; children are not | – | Local | Complete | `core/batch_route_guard_test`, `widgets/functional_flows_test` |
| Role (all) | Parent / Child | → parent sign-in / child explainer | – | – | Complete | `widgets/app_flow_test` |
| Role | Session-ended notice | **Added:** after a server 401 the user sees "Your session has ended…" instead of being dropped silently; cleared when a role is chosen; not shown for a deliberate sign-out | – | Local | Complete | `widgets/functional_flows_test` |
| Parent auth | Sign in | Email + password, field and server errors mapped | `POST /auth/login` | API | Complete | `features/repositories_test`, `widgets/forms_test` |
| Parent auth | Register | `full_name` 2–160, password 12–128 validated before the call | `POST /auth/register` (409 `email_in_use`) | API | Complete | same |
| Parent auth | Phone OTP / Google | Not offered; notice explains | – | – | Blocked (B1) | – |
| Parent auth | Server status badge | Health + DB readiness | `GET /health`, `GET /ready` | API | Complete | `core/network_test` |
| Session | Restore on launch | Expired token dropped locally; otherwise confirmed; offline keeps an unexpired session | `GET /auth/me` | API + Local | Complete | `features/session_controller_test` |
| Session | 401 anywhere | Clears the session, returns to role selection with the notice | – | Local | Complete | `widgets/app_flow_test`, `widgets/functional_flows_test` |
| Session | Role protection | Child sessions reach only `/child/**`; parents only `/parent/**`; all new routes covered | – | Local | Complete | `core/route_guard_test`, `core/batch_route_guard_test` |

### Parent Hub, family and children

| Screen | Action | Behaviour | Endpoint | Data | Status | Tests |
|---|---|---|---|---|---|---|
| Parent Hub | Create family | Name 2–160 | `POST /families` | API | Complete | `widgets/app_flow_test` |
| Parent Hub | Pending-approval count | **Changed:** one cheap request (unread `task_submitted` notifications) instead of loading the whole inbox on every visit | `GET /notifications` | API (derived count) | Complete | `widgets/functional_flows_test` |
| Parent Hub | Approvals / Reports / Settings entries | Navigate | – | – | Complete | `widgets/batch_screens_test` |
| Parent Hub | Child card → profile; Start child mode | Confirm, swap session; spinner only during the request | `POST /auth/children/{id}/session` | API | Complete | `widgets/app_flow_test`, `widgets/batch_screens_test` |
| Parent Hub | Mission tile | **Added:** opens the editor | – | – | Complete | `widgets/functional_flows_test` |
| Parent Hub | Show more | **Added:** first 20 missions, expand on demand | – | Local | Complete | `widgets/functional_flows_test` |
| Parent Hub | Sign out | Clears local session (the API has no logout endpoint) | – | Local | Complete | `features/session_controller_test` |
| Create child | Create | name 1–100, DOB past and under 18, language | `POST /families/{id}/children` | API | Complete | `widgets/forms_test`, `features/repositories_test` |
| Create child | Avatar | Stored **on this device only** and labelled so | – | Local | Honest limit (B7) | `widgets/forms_test` |
| Create child | Age bracket, interests | Omitted | – | – | Blocked (B8) | – |
| Child profile | Edit name / date of birth | Saved on the server | `PATCH /families/{id}/children/{child_id}` | API | Complete | `widgets/batch_screens_test` |
| Child profile | Edit avatar | Device only | – | Local | Honest limit (B7) | same |
| Child profile | Remove | Confirmed; wording says it **deactivates** and that records stay on the server | `DELETE /families/{id}/children/{child_id}` (soft) | API | Honest limit | same |
| Child profile | Activity history / Start child mode / add child / siblings | Navigate / start | – | – | Complete | same |
| Child profile | Interests, daily target, reward multiplier | Omitted | – | – | Blocked (B8) | – |

### Missions (parent side)

| Screen | Action | Behaviour | Endpoint | Data | Status | Tests |
|---|---|---|---|---|---|---|
| Mission form | Create | title 2–180, stars 0–10000, XP 0–100000, optional category, assignee, **due date (added)** | `POST /tasks` | API | Complete | `widgets/forms_test`, `widgets/functional_flows_test` |
| Mission form | Edit | **Added:** pre-filled; sends every field with explicit `null` to clear category/assignee/due date | `PATCH /tasks/{id}` | API | Complete | `widgets/functional_flows_test`, `features/mission_management_test` |
| Mission form | Remove | **Added:** confirmed; says children stop seeing it and reviews stay on record | `DELETE /tasks/{id}` (soft) | API | Complete | same |
| Mission form | Mission removed elsewhere | "no longer available" state, not a blank form | – | – | Complete | `widgets/functional_flows_test` |
| Mission form | Repeat rule | In the API, in no Stitch design | `repeat_rule` | – | Not built (product) | – |
| Missions list | > 100 missions | **Fixed:** pages of 100 until a short page, capped at 500; a failing later page fails the load (no silent gaps) | `GET /tasks?limit&offset` | API | Complete | `features/mission_management_test` |

### Approvals, reports, settings (parent)

| Screen | Action | Behaviour | Endpoint | Data | Status | Tests |
|---|---|---|---|---|---|---|
| Approvals | Load inbox | Tasks found from `task_submitted` notifications; submissions fetched per task, 5 at a time, max 25 tasks | `GET /notifications`, `GET /tasks/{id}/submissions` | API | Honest limit (B4) | `widgets/functional_flows_test` |
| Approvals | **Partial failure** | **Fixed:** a task whose request fails is skipped and counted; a notice with Retry shows; the inbox only fails if every request failed or the session ended; a 404 task is skipped silently | – | API | Complete | same |
| Approvals | Truncation | Warns when more than 25 tasks or a full page of 100 notifications | – | – | Complete | same |
| Approvals | Approve | Awards the task's stars/XP on the server; per-card spinner blocks double taps | `POST /reviews/submissions/{id}` | API | Complete | `widgets/batch_screens_test` |
| Approvals | Ask to retry / Decline | Optional note | same (`resubmission_requested`, `rejected`) | API | Complete | same |
| Approvals | Already reviewed (409) | Explains and refreshes | same | API | Complete | same |
| Approvals | After a review | **Added:** marks the matching notification read (best effort; a failure never undoes the review) so the hub count drops | `POST /notifications/{id}/read` | API | Complete | `widgets/functional_flows_test` |
| Approvals | Photo proof | Shown only if a submission carries an image URL | – | – | Blocked (B2) | – |
| Approvals | Long lists | **Changed:** lazily built (60 submissions build < 20 cards) | – | – | Complete | `widgets/functional_flows_test` |
| Reports | Child picker, week | Seven days ending today from `activity_days` (UTC dates, shown against the local date) | `GET /progress/children/{id}` | API (derived) | Complete | `widgets/batch_screens_test`, `features/batch_logic_test` |
| Reports | Copy weekly summary | Copies the figures shown on screen | – | Local | Complete | same |
| Reports | Reading hours, habit split, PDF export | Omitted | – | – | Blocked (B9) | – |
| Settings | Push / email toggles | Optimistic, one save at a time, controls disabled while saving, rolled back on error | `PATCH /settings/me` | API | Complete | `widgets/batch_screens_test`, `widgets/functional_flows_test` |
| Settings | Language | Applies now; saved to the account best-effort | `PATCH /settings/me` | Local + API | Complete | same |
| Settings | Consent records | Read-only list | `GET /settings/families/{id}/consents` | API | Complete | same |
| Settings | Revoke consent | **Not wired:** the endpoint exists but its effect on the account is undefined | `POST /settings/consents/{id}/revoke` | – | Blocked (product, B11) | – |
| Settings | Log out | Clears the session | – | Local | Complete | `widgets/batch_screens_test` |
| Settings | PIN, bedtime/screen-time lock, data export, family wipe | Omitted | – | – | Blocked (B10, B13) | – |

### Child mode

| Screen | Action | Behaviour | Endpoint | Data | Status | Tests |
|---|---|---|---|---|---|---|
| Child home | Stats, level, streak | Real balance/XP/streak | `GET /progress/children/{id}` | API | Complete | `widgets/app_flow_test` |
| Child home | Today's missions, Start | First two open missions | `GET /tasks` | API | Complete | same |
| Child home | Garden card, quest hub | Omitted (garden has its own tab) | – | – | Honest limit (B9) | – |
| Child home | Parent Gate | Signs the child out (no PIN exists) | – | Local | Honest limit (B10) | `widgets/app_flow_test` |
| Missions | Filter by category | Local filter; **lazy** list; 2 columns ≥ 720 px | `GET /tasks`, `GET /tasks/categories` | API | Complete | `widgets/functional_flows_test` (250 missions) |
| Missions | Status chips | Derived from the child's review notifications + a device log of what it submitted | `GET /notifications` | Derived | Honest limit (B3) | `features/missions_state_test` |
| Mission detail | Start / Do again / Waiting | Routes by status | – | – | Complete | `widgets/app_flow_test` |
| Mission submit | Submit with note | `none` or `note`; **duplicate taps create one submission (fixed)** | `POST /tasks/{id}/submissions` | API | Complete | `widgets/app_flow_test`, `widgets/functional_flows_test` |
| Mission submit | Photo | Explained as unavailable | – | – | Blocked (B2) | – |
| Waiting | Check again | Re-reads notifications; no push channel | `GET /notifications` | API | Honest limit | `widgets/app_flow_test` |
| Rewards | Balance, streak, badges | Real | `GET /progress/children/{id}` | API | Complete | `widgets/batch_screens_test` |
| Rewards | My requests | Child's own requests with status | `GET /redemptions/mine` | API | Complete | same |
| Rewards | Catalog / Redeem | **Not shown** — a child cannot list rewards; no button implies success | `GET /rewards` is parent-only | – | Blocked (B5, B12) | asserted absent |
| Garden | Stage | Derived from approved missions this week; labelled presentation-only | `GET /progress/…` | Derived | Honest limit (B9) | `widgets/batch_screens_test` |
| Garden | Milestones | Derived from `longest_streak` | same | Derived | Honest limit (B9) | same |
| Garden | Water / decorations | Omitted | – | – | Blocked (B9) | – |

## What changed in this pass

**Functional gaps found and fixed**

1. Approvals fan-out failed as a whole when one task request failed — now partial, with a counted notice and retry.
2. The Parent Hub loaded the entire inbox (notifications + one request per task) on every visit — now a single notifications request; reviews mark the notification read.
3. Missions could not be edited or removed although the API supports it — added edit, remove and an optional due date.
4. Mission lists silently stopped at 100 — paged, capped, no silent gaps.
5. A server-ended session dropped the user with no explanation — added the notice.
6. A changed consent version never re-prompted a signed-in parent — fixed.
7. Rapid taps could create two submissions; rapid settings changes could race the rollback — both guarded and tested.
8. Child missions were requested twice on a cold start (once before the child session existed) — fixed.
9. Long collections built every row — child missions and approvals are now lazy; Parent Hub missions are collapsed to 20.

**Design and accessibility**

- Language radios had no accessible name (found by Flutter's labelled-tap-target guideline) — fixed.
- Mission-detail and parent-sign-in hero text failed WCAG contrast over photos (1.51:1 and 2.04:1 measured) — scrims strengthened.
- Splash overflowed on a 568×320 window at 2× text — now scrolls.
- Duplicated helpers removed: the refresh-then-ignore-errors block (8 copies) → `refreshQuietly`; three copies of wrap-grid column maths → `AdaptiveWrap`; two duplicate icon-row tiles → `NavTile`.

**Regression nets added**

- Responsive matrix now also runs every screen at 740×360 and 568×320 (1× and 2× text), checks the tap-target, labelled-target and text-contrast guidelines at 393 px, and checks that the focused field stays above a 300 px keyboard on the four forms.
- `localization_audit_test`: every key exists in en/gu/hi with matching placeholders, no silent copies of English text, and a scan that fails if visible text is hard-coded.

## Localization audit

- 364 message keys in each of English, Gujarati and Hindi; none missing, none extra, placeholders match. The only string identical to English is the unit "XP".
- No visible text is hard-coded. The only literals left are internal exception messages (never displayed — the UI maps by exception type) and interpolated semantic labels built from localized parts.
- **Every Gujarati and Hindi string (all 364 in each language) was machine-written and has not been reviewed by a native speaker.** This is the largest localization risk. Plural forms are written for the ICU `=0/=1/other` cases only.
- Rubik and Nunito Sans have no Gujarati/Devanagari glyphs; Android falls back to Noto. Not checked on a device.

## Blockers needing backend or product approval

| # | Blocked action | Why | Proposed contract | Honest UI today | Approval |
|---|---|---|---|---|---|
| B1 | Phone OTP, Google sign-in | Backend has email + password only | `POST /auth/otp/request`, `/auth/otp/verify`, `/auth/google` | Notice explains | Product + backend |
| B2 | Photo proof | No upload endpoint | `POST /uploads/task-proofs` (multipart, child auth) → `{proof_url}` | Note-only; photo explained | Backend + storage |
| B3 | Child sees own submission history | `GET /tasks/{id}/submissions` is parent-only | `GET /tasks/submissions/mine` (child) | Derived from notifications + device log | Backend |
| B4 | Parent inbox without N+1 | No family-wide list | `GET /reviews/pending?family_id=` | Per-task fan-out, bounded and partial-failure-tolerant | Backend |
| B5 | Child reward shop | `GET /rewards` is parent-only | allow child on `GET /rewards` | Catalog hidden; own requests shown | Backend |
| B6 | Child session longer than 30 min | No refresh | Refresh token or device-bound child session | Session-ended notice | Backend |
| B7 | Avatar from the built-in set | `avatar_url` must be http(s) | `avatar_key` enum | Device-only, labelled | Backend |
| B8 | Interests, age bracket | Not stored | `interests: string[]` | Omitted | Product |
| B9 | Garden state, mission steps/duration, reading hours, habit split | Not modelled/exposed | expose `garden_progress`; add fields | Derived/omitted, labelled | Product + backend |
| B10 | Parent PIN | Not implemented | `POST /auth/parent-pin/verify` | Parent Gate = sign out | Product + backend |
| B11 | Real consent document version; consent revoke semantics | Draft string; undefined effect | publish canonical versions | Draft version; revoke not wired | Legal + product |
| B12 | Parent approves reward requests | No parent list of redemptions | `GET /redemptions?family_id=&status=` | Not built | Backend |
| B13 | Phone number; screen-time enforcement | Stored but unused / absent | add `phone`; enforce limits | Omitted | Product + backend |
| B14 | Quizzes, learning progress | No quiz API; no Stitch design | define resources | Not built | Product |
| – | Parent reward creation (`POST/GET /rewards`) and learning content (`GET /educational-content`) | Supported by the API but no Stitch screen, and without B5/B12 they cannot complete a user journey | – | Not built | **Product scope approval needed** |

## Remaining risks

**Security**
- Debug-signed builds only; release signing, obfuscation and Play-integrity are not configured.
- Tokens are in Android Keystore-backed secure storage; the log interceptor prints only method, path with ids redacted, status and timing. No certificate pinning.
- The backend `.env` (database URL, JWT secret) must be confirmed never committed and rotated if it was; it is gitignored.

**Accessibility**
- Contrast, tap-target and label guidelines pass on every screen at 393 px / 1× text in English only; not re-run at 2× text, in Gujarati/Hindi, or with TalkBack. Focus order and reading order were not audited on a device.
- Motion: only short press/transition animations; no reduced-motion setting is read.

**Device and performance**
- Nothing has run on a device or emulator: gestures, keyboard behaviour, font fallback, image decode cost and real cold-start latency (the Render instance takes 12–45 s) are unmeasured.
- Report days use the server's UTC dates against the device's local date; an approval made near midnight IST can land on the previous day.
- The pending count is per account (all families), the inbox per family; with several families the numbers can differ. The app uses the newest family only.

## Next highest-priority task

Run the app on a real Android device or emulator against the deployed server and walk both journeys end to end (register → family → child → mission → child submit → parent approve → rewards/garden/report), with TalkBack on and Gujarati selected — that is the largest unverified surface. In parallel, get a native-speaker review of the Gujarati and Hindi text and a backend decision on B4, B5 and B12, which unblock the two flows the app still has to work around.
