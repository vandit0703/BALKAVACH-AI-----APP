# API Integration Matrix

> **Update 2026-10-13 (second pass).** This document describes the first slice. Since
> then the backend gained the endpoints that resolved blockers B2–B6, B9, B11, B12,
> B15 and B16: `POST/GET /uploads/task-proofs`, `GET /tasks/submissions/mine`,
> `GET /reviews/pending`, `GET /reviews/submissions`, child `GET /rewards`,
> `PATCH/DELETE /rewards/{id}`, `GET /redemptions`, `POST /auth/refresh`, `POST /auth/logout`,
> `DELETE /auth/children/{id}/sessions`, `GET /progress/children/{id}/weekly`
> (plus `garden` in `/progress`), `GET /tasks/presets`, `PUT/POST /notifications/devices`,
> `GET /app-config`, and ~25 `/admin/*` operations. Still open: B1 (OTP/Google), B7, B8,
> B10, B13, B14. The "not wired" table below is obsolete. Current state and the
> backward-compatibility review: `feature-implementation-matrix.md` and
> `backend-operations.md`.


Source of truth: `balkavach-backend/app/**` cross-checked against the live
OpenAPI document at `https://balkavach-ai-app.onrender.com/openapi.json`
(fetched 2026-10-12, title `BalKavach API` v0.1.0, 68 operations). The live
document and the source tree list the same routes.

## Verification status legend

| Mark | Meaning |
|------|---------|
| **Live** | Called against the deployed server without writing data; response shape confirmed. |
| **Source** | Contract read from FastAPI route + Pydantic schema; not exercised live (it writes data or needs an account). |
| **Mocked** | Covered by a Flutter test using a fake HTTP adapter that mirrors the source contract. |

No production accounts, families, children, or tasks were created during this
audit. Write operations need a test account the team agrees to use.

## Common contract

- Base path: `/api/v1` (health checks are at the root).
- Auth: `Authorization: Bearer <jwt>`. HS256, `sub` = user id, default expiry
  30 minutes (`ACCESS_TOKEN_EXPIRE_MINUTES`). **No refresh token exists.**
- Error envelope (all handlers in `app/core/exceptions.py`, confirmed live):
  ```json
  {"error": {"code": "invalid_credentials", "message": "Email or password is incorrect"}}
  {"error": {"code": "validation_error", "message": "Request validation failed",
             "details": [{"location": ["body","email"], "message": "...", "type": "value_error"}]}}
  ```
  `HTTPException`s use `code: "http_error"`. Unhandled errors return `internal_error` (500).
- Timestamps are ISO-8601 UTC with offset. IDs are UUID strings.
- Observed latency: `/health` ≈ 2.6 s, `/ready` ≈ 5 s, DB-backed login ≈ 12 s
  on a cold instance. The client uses a 45 s receive timeout.

## Operations used by the Flutter app (first slice)

| Operation | Request | Response | Auth | Notable errors | Caller (screen → provider) | Status | Flutter tests |
|---|---|---|---|---|---|---|---|
| `GET /health` | – | `{"status":"ok"}` | none | – | Parent sign-in server badge → `serverHealthProvider` | **Live** | `core/network_test` |
| `GET /ready` | – | `{"status":"ready"}` or 503 | none | 503 DB down | same | **Live** | `core/network_test` |
| `POST /api/v1/auth/register` | `{full_name 2–160, email, password 12–128}` | `TokenResponse` 201 | none | 409 `email_in_use`, 422 | Parent auth → `sessionControllerProvider` | **Live** (422 path only), Source | `features/repositories_test`, `widgets/forms_test` |
| `POST /api/v1/auth/login` | `{email, password}` | `TokenResponse` | none | 401 `invalid_credentials`, 422 | Parent auth → `sessionControllerProvider` | **Live** (401, 422 paths) | `features/repositories_test`, `features/session_controller_test`, `widgets/forms_test` |
| `GET /api/v1/auth/me` | – | `UserPublic` | bearer | 401 | Session restore → `sessionControllerProvider` | **Live** (401 paths) | `features/session_controller_test` |
| `POST /api/v1/auth/children/{child_id}/session` | – | `TokenResponse` (child user) | parent | 404 not in family | Parent home "Start child mode" → `sessionControllerProvider` | Source | `features/session_controller_test`, `widgets/app_flow_test` |
| `GET /api/v1/families` | – | `FamilyPublic[]` | parent | 403 | Parent home → `currentFamilyProvider` | Source | `features/repositories_test`, `widgets/app_flow_test` |
| `POST /api/v1/families` | `{family_name 2–160}` | `FamilyPublic` 201 | parent | 422 | Parent home (first run) → `currentFamilyProvider.create` | Source | `features/repositories_test`, `widgets/app_flow_test` |
| `GET /api/v1/families/{id}/children` | – | `ChildPublic[]` | parent | 404 | Parent home → `familyChildrenProvider` | Source | `features/repositories_test`, `widgets/app_flow_test` |
| `POST /api/v1/families/{id}/children` | `{display_name 1–100, date_of_birth?, avatar_url? (http URL), preferred_language}` | `ChildPublic` 201 | parent | 404, 422 (age ≥ 18, future DOB) | Create child profile → `FamilyRepository.createChild` | Source | `features/repositories_test`, `widgets/forms_test` |
| `GET /api/v1/settings/families/{id}/consents` | – | `ConsentPublic[]` | parent | 404 | Parent home (consent sync) → `consentSyncProvider` | Source | `features/missions_state_test` |
| `POST /api/v1/settings/families/{id}/consents` | `{child_id?, consent_type, document_version, accepted}` | `ConsentPublic` 201 | parent | 404 | same | Source | `features/repositories_test`, `widgets/app_flow_test` |
| `GET /api/v1/tasks/categories` | – | `TaskCategoryPublic[]` | any user | 401 | Missions → `taskCategoriesProvider` | Source | `features/repositories_test` |
| `GET /api/v1/tasks` | `family_id?, limit ≤100, offset` — **paged**: the app requests `limit=100` and follows with `offset=100, 200, …` while a page comes back full, up to 5 pages (500 missions); a failing later page fails the whole load | `TaskPublic[]` | parent or child | 403, 404 | Child home / missions → `childMissionsProvider` (not requested until a child session exists); parent missions | Source, Mocked | `features/repositories_test`, `features/mission_management_test`, `widgets/functional_flows_test` |
| `POST /api/v1/tasks` | `{family_id, category_id?, assigned_child_id?, title 2–180, description?, star_reward 0–10000, xp_reward 0–100000, due_at? (tz required), repeat_rule?}` — the form now sends `due_at` (end of the chosen day, as UTC); `repeat_rule` is not sent | `TaskPublic` 201 | parent | 404 | Parent "New mission" → `MissionsRepository.createMission` | Source, Mocked | `features/missions_state_test`, `widgets/functional_flows_test` |
| `POST /api/v1/tasks/{id}/submissions` | `{proof_type: none\|note\|image\|video\|file, proof_url? (http URL), proof_note? ≤2000}` | `TaskSubmissionPublic` 201 (`status: pending`) | child | 403 `task_not_assigned`, 404 `task_not_found` | Mission submit → `missionSubmitControllerProvider` | Source | `features/repositories_test`, `features/missions_state_test`, `widgets/app_flow_test` |
| `GET /api/v1/progress/children/{id}` | – | `ProgressPublic` | the child itself or a parent in the family | 404 | Child home → `childProgressProvider` | Source | `features/repositories_test` |
| `GET /api/v1/notifications` | `limit ≤100, offset` | `NotificationPublic[]` | any user | 401 | Mission cards, waiting screen → `missionStatusesProvider` | Source | `features/missions_state_test` |

## Operations added with the remaining Stitch screens (2026-10-13)

Status marks as above. None of these wrote to production; tests use the fake
adapter, so they are **Source** + **Mocked**.

| Operation | Request | Response | Auth | Notable errors | Caller (screen → provider) | Status | Flutter tests |
|---|---|---|---|---|---|---|---|
| `GET /api/v1/tasks/{id}/submissions` | `limit ≤100` (the app asks for 50 per task) | `TaskSubmissionPublic[]` | parent | 404 | Approvals → `approvalInboxProvider`. Fan-out is bounded: 5 requests in flight, at most 25 tasks per load. **Partial failures:** a network/5xx error skips that task and is counted (notice + Retry); a 404 is skipped silently; only a 401, or every task failing, fails the inbox | Source, Mocked | `features/batch_repositories_test`, `widgets/batch_screens_test`, `widgets/functional_flows_test` |
| `POST /api/v1/reviews/submissions/{id}` | `{decision: approved\|rejected\|resubmission_requested, review_note? ≤2000}` | `TaskSubmissionPublic` | parent | 404 `submission_not_found`, 409 `submission_already_reviewed` | Approvals → `reviewSubmission` | Source, Mocked | same |
| `GET /api/v1/notifications` (parent) | `limit ≤100` (newest 100; a full page raises a "older submissions may not appear" notice) | `NotificationPublic[]` | any | 401 | One shared `parentNotificationsProvider` feeds the Parent Hub pending count (unread `task_submitted`) **and** the inbox's task list | Source, Mocked | `features/batch_logic_test`, `features/mission_management_test`, `widgets/functional_flows_test` |
| `POST /api/v1/notifications/{id}/read` | – | `NotificationPublic` | any | 404 | After a review, marks that submission's `task_submitted` notification read so the hub count drops. Best effort: a failure never undoes the review | Source, Mocked | `widgets/functional_flows_test` |
| `PATCH /api/v1/tasks/{id}` | `{title, description?, category_id?, assigned_child_id?, star_reward, xp_reward, due_at?}` — **every** field is sent; an explicit `null` clears a description, category, assignee or due date (the server applies only keys that are present). `due_at` is UTC with an offset (a naive timestamp is a 422) | `TaskPublic` | parent | 404 task / child / category, 422 | Mission form (edit) → `MissionsRepository.updateMission` | Source, Mocked | `features/mission_management_test`, `widgets/functional_flows_test` |
| `DELETE /api/v1/tasks/{id}` | – | 204 — **soft deactivate**; submissions and reviews stay | parent | 404 | Mission form (remove) → `MissionsRepository.deactivateMission` | Source, Mocked | same |
| `GET /api/v1/progress/children/{id}` | – | now also parses `activity_days[]`, `badges[]` | child itself or parent | 404 | Reports, Child profile, Rewards, Garden → `childProgressProvider` | Source, Mocked | `features/batch_logic_test`, `widgets/batch_screens_test` |
| `PATCH /api/v1/families/{id}/children/{child_id}` | `{display_name?, date_of_birth?}` (avatar not sent, B7) | `ChildPublic` | parent | 404, 422 | Child profile edit → `FamilyRepository.updateChild` | Source, Mocked | same |
| `DELETE /api/v1/families/{id}/children/{child_id}` | – | 204 (soft deactivate) | parent | 404 | Child profile → `FamilyRepository.deactivateChild` | Source, Mocked | same |
| `GET /api/v1/settings/me` | – | `UserSettingsPublic` | any | 401 | Parent settings → `userSettingsProvider` | Source, Mocked | same |
| `PATCH /api/v1/settings/me` | only the changed fields of `{language_code, push_enabled, email_notifications_enabled}` (a `null` is a 422) | `UserSettingsPublic` | any | 422 | Parent settings → `UserSettingsController.save` (optimistic, rolled back on error) | Source, Mocked | same |
| `GET /api/v1/redemptions/mine` | `limit ≤100` | `RedemptionPublic[]` | child | 403 | Rewards → `myRedemptionsProvider` | Source, Mocked | same |

## Operations available but still not wired

| Area | Operations | Why not |
|---|---|---|
| Rewards (parent) | `POST/GET /rewards`, `approve`/`reject`/`fulfill`/`cancel` on `/redemptions/{id}` | No screen designed, and no parent list of redemption requests (B12), so approvals could not be driven. |
| Rewards (child) | `POST /redemptions` (needs `Idempotency-Key`), `POST /redemptions/{id}/cancel/mine` | A child cannot list rewards (B5), so there is nothing to redeem from. |
| Progress | `GET /progress/children/{id}/activity` | Same data as `activity_days` in the progress response. |
| Family settings | `GET/PATCH /settings/families/{id}` | No Stitch control maps to them honestly (video/mission settings are stored but not enforced, B13). |
| Consent | `POST /settings/consents/{id}/revoke` | The endpoint stamps `revoked_at`, but nothing else in the backend reads it, so a "withdraw consent" button would imply an effect that does not exist (B11). Needs a product/legal decision first. |
| Rewards (parent) and learning content | `POST/GET /rewards`, `GET /educational-content` | Supported by the API but no Stitch design, and without B5/B12 neither completes a user journey. **Product scope approval needed.** |
| Learning | `GET /educational-content` (child), `GET /videos/feed`, `POST /video-access/*` | No Stitch screen; no quiz API (B14). |

## Missing capabilities (blockers) and proposed contracts

These are **proposals only**. No backend code or migrations were changed.

| # | Need (Stitch screen) | Status in backend | Proposed contract |
|---|---|---|---|
| B1 | Phone OTP login, Google sign-in (Parent Authentication) | Not implemented. Only email + password. | `POST /auth/otp/request {phone}` → 202; `POST /auth/otp/verify {phone, code}` → `TokenResponse`. Google: `POST /auth/google {id_token}` → `TokenResponse`. |
| B2 | Photo proof for missions (Complete Your Mission) | `proof_url` must be an existing http(s) URL; there is **no upload endpoint**. | `POST /uploads/task-proofs` (multipart, child auth) → `{proof_url, expires_at}` backed by private object storage with signed URLs. |
| B3 | Child sees "Pending / Approved" on mission cards after restart | Child cannot list its own submissions (`GET /tasks/{id}/submissions` is parent-only). App derives outcomes from review notifications and caches pending ids locally. | `GET /tasks/submissions/mine?status=` (child auth) → `TaskSubmissionPublic[]`. |
| B4 | Parent approval inbox (Mission Approval) | Requires one call per task. | `GET /reviews/pending?family_id=` → submissions joined with task title + child name. |
| B5 | Child reward shop (Rewards & Achievements) | `GET /rewards` is parent-only. | Allow `require_child` on `GET /rewards` scoped to the child's family. |
| B6 | Child session longevity | Child token = same 30-minute expiry, no refresh. A child is signed out every 30 minutes and a parent must restart child mode. | Refresh tokens or a longer-lived, device-bound child session with parent revoke. |
| B7 | Child avatar from built-in set (Create Child Profile) | `avatar_url` must be an `HttpUrl`; bundled assets can't be referenced. App stores the chosen avatar **on device only**. | Accept `avatar_key` (enum of bundled avatars) or host avatars at stable URLs. |
| B8 | Age bracket, interests (Create Child Profile) | Not stored. Only optional `date_of_birth`. | Add `interests: string[]` to `ChildCreate` if the product needs it. |
| B9 | Garden stage, mission duration, mission steps | Not modelled (`garden_progress` JSON exists on `child_progress` but is not exposed). | Expose `garden_progress` in `ProgressPublic`; add `estimated_minutes`, `steps[]` to tasks. |
| B10 | Parent PIN / "Parent Gate" | Not implemented server-side. App requires a parent email/password sign-in to leave child mode. | Optional `POST /auth/parent-pin/verify`. |
| B11 | Consent document version | Backend accepts any `consent_type` / `document_version` strings. The app records `parent_guardian_terms` / `2026-10-draft` — **legal must confirm the real document version** before launch. | Publish the canonical consent types and versions. |
| B12 | Parent approval of reward redemptions (Rewards & Achievements) | A child can create and list their own requests; a parent can approve/reject/fulfil one by id, but **no endpoint lists a family's requests**. | `GET /redemptions?family_id=&status=` (parent) → `RedemptionPublic[]` joined with reward name and child. |
| B13 | Phone number on the parent account; screen-time / bedtime enforcement (Parent Settings) | `UserPublic` has no phone. `video_settings` (`default_daily_limit_seconds`) is stored per family but nothing in the backend reads it. | Add `phone` to the user model if the product needs it; enforce limits server-side in `video_access_service`, or drop the control. |
| B14 | Quizzes, quiz results, learning progress | Not implemented. Only `educational_content` and video access exist. | Define quiz and attempt resources before any quiz screen is built. |
| B15 | Per-day activity in the parent's time zone | `activity_days[].activity_date` is a plain date computed server-side (UTC). The app shows it against the device's local date, so an approval near midnight in India can land on the previous day. | Return an instant or accept a `tz` query parameter on `/progress`. |
| B16 | Pending count per family | Notifications are per account, not per family. With several families the hub count can exceed the inbox. The app uses the newest family only. | Add `family_id` to `NotificationPublic`, or the B4 endpoint. |
