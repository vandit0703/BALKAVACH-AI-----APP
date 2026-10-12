# API Integration Matrix

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
| `GET /api/v1/tasks` | `family_id?, limit ≤100, offset` | `TaskPublic[]` | parent or child | 403, 404 | Child home / missions → `childMissionsProvider`; parent missions | Source | `features/repositories_test`, `widgets/app_flow_test` |
| `POST /api/v1/tasks` | `{family_id, category_id?, assigned_child_id?, title 2–180, description?, star_reward 0–10000, xp_reward 0–100000, due_at? (tz required), repeat_rule?}` | `TaskPublic` 201 | parent | 404 | Parent "New mission" → `MissionsRepository.createMission` | Source | `features/missions_state_test` |
| `POST /api/v1/tasks/{id}/submissions` | `{proof_type: none\|note\|image\|video\|file, proof_url? (http URL), proof_note? ≤2000}` | `TaskSubmissionPublic` 201 (`status: pending`) | child | 403 `task_not_assigned`, 404 `task_not_found` | Mission submit → `missionSubmitControllerProvider` | Source | `features/repositories_test`, `features/missions_state_test`, `widgets/app_flow_test` |
| `GET /api/v1/progress/children/{id}` | – | `ProgressPublic` | the child itself or a parent in the family | 404 | Child home → `childProgressProvider` | Source | `features/repositories_test` |
| `GET /api/v1/notifications` | `limit ≤100, offset` | `NotificationPublic[]` | any user | 401 | Mission cards, waiting screen → `missionStatusesProvider` | Source | `features/missions_state_test` |

## Operations available but not yet wired (next slices)

| Area | Operations | Notes |
|---|---|---|
| Parent approvals | `GET /tasks/{id}/submissions` (parent), `POST /reviews/submissions/{id}` `{decision: approved\|rejected\|resubmission_requested, review_note?}` | No family-wide "pending submissions" list — must fan out per task (N+1). |
| Rewards | `POST/GET /rewards` (parent only), `POST /redemptions` (child, `Idempotency-Key` header 8–180 chars), `GET /redemptions/mine`, approve/reject/fulfill/cancel | **Children cannot list rewards** — `GET /rewards` is parent-only. |
| Progress reports | `GET /progress/children/{id}/activity` | Returns `activity_days[:limit]`. |
| Settings | `GET/PATCH /settings/me`, `GET/PATCH /settings/families/{id}`, `POST /settings/consents/{id}/revoke` | |
| Learning | `GET /educational-content` (child), `GET /videos/feed`, `POST /video-access/*` | |
| Child profile edit | `PATCH /families/{id}/children/{child_id}`, `DELETE` (soft) | |

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
