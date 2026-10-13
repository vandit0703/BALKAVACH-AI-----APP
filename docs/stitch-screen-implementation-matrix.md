# Stitch Screen Implementation Matrix

Source: `stitch_bal_kavach_ai_mobile_app/`. Inventory re-done 2026-10-13 against
the export, the Flutter source in `balkavach-frontend/lib/`, the FastAPI source in
`balkavach-backend/app/`, and the live OpenAPI document
(`https://balkavach-ai-app.onrender.com/openapi.json`, 68 operations — same
routes as the source tree).

## What the export contains

15 screen folders (each with `code.html` + `screen.png`), plus three non-screen
items:

| Item | What it is |
|---|---|
| `bal_kavach_safe/DESIGN.md` | Design tokens (already ported — see `design-system.md`). |
| `bal_kavach_shield_logo/` | Logo SVG (ported to `ShieldLogo`). |
| `3d_cute_cartoon_avatar_…aarav…/screen.png` | A 1.1 MB avatar image, not a screen. Not bundled. |

There are **no** separate folders for the screens the brief lists as "illustrative"
(learning content, quizzes, quiz results, achievements/level-up, weekly progress
sharing, reward redemption dialog, role selection, waiting-for-approval,
custom-mission creation, parent dashboard "home"). The local export determines the
inventory, so those are **not Stitch screens**:

- *Role selection, Parent Hub, New mission, Waiting for approval* already exist in
  the app from slice 1 and are listed below under "Built without a Stitch
  reference". Their layout is the team's own, not a Stitch design.
- *Learning content, quizzes, quiz results, level-up, sharing* have no design and
  are **not built**. The backend has `GET /educational-content` and the
  `/videos` and `/video-access` operations, but no quiz endpoints at all.

Different visual states are not counted as separate screens: the approval screen's
three tabs are one screen; "Redeemed / Pending Parent Approval" cards on the
rewards screen are states of one screen.

## Matrix — the 15 Stitch screens

Status: **Done** = real, navigable, backend-connected where the API allows, tested.
**Partial** = built, but design elements are omitted because the backend cannot
support them (listed in the last column).

| # | Stitch folder | Screen / role | Flutter route | Status | Omitted or adapted (and why) |
|---|---|---|---|---|---|
| 1 | `welcome_language` | Welcome + language (all) | `/welcome` | Done | – |
| 2 | `parent_safety_consent` | Parent consent (parent) | `/consent` | Done | Document version is a draft string (B11). |
| 3 | `parent_authentication` | Parent login / register | `/parent-auth` | Partial | Phone OTP and Google sign-in not offered (B1); email + password only. |
| 4 | `create_child_profile` | Create child (parent) | `/parent/children/new` | Partial | Age bracket and interests not stored (B8); avatar is device-local (B7). |
| 5 | `child_home_dashboard` | Child home | `/child` | Partial | Garden card and quest hub tiles left out on this screen (B9). Garden has its own tab now. |
| 6 | `today_s_missions` | Missions list (child) | `/child/missions` | Done | – |
| 7 | `mission_details_custom_mission` | Mission details (child) | `/child/missions/:taskId` | Partial | Duration and step list not in the API (B9). |
| 8 | `complete_your_mission` | Submit mission (child) | `/child/missions/:taskId/submit` | Partial | Photo proof not possible — no upload endpoint (B2); note proof only. |
| 9 | `parent_mission_approval` | Approval inbox (parent) | `/parent/approvals` | **Done** | Lazily built list; tolerates partial failures when fetching submissions (notice + Retry); marks the notification read after a review. Photo shown only if the submission has an `image` proof URL (none can be created yet, B2). "Parent Guardian Verification" badge and the "Aarav (Age 7)" dropdown replaced by child filter chips. |
| 10 | `parent_dashboard_reports` | Weekly report (parent) | `/parent/reports?child=` | **Partial (new)** | "Hours of learning/reading", "outdoor days goal" and the Learn/Move/Help/Create split are not tracked. PDF export replaced by "Copy weekly summary". Numbers shown are real, from `activity_days`. |
| 11 | `child_profile_family_management` | Child profile (parent) | `/parent/children/:childId` | **Partial (new)** | Interests, daily target, reward multiplier not stored (B8). "Delete profile" is a soft deactivate; permanent DPDP deletion has no API. Edit changes name, date of birth (server) and avatar (device). Per-child "Switch" toggle not shown (no active/inactive toggle UI). |
| 12 | `child_rewards_achievements` | Rewards + badges (child) | `/child/rewards` | **Partial (new)** | Treasure catalog and "Redeem" buttons **not shown**: `GET /rewards` is parent-only (B5) and parents cannot list pending redemptions (B12). Balance, streak, badges and the child's own redemption requests are real. |
| 13 | `my_garden` | Garden (child) | `/child/garden` | **Partial (new)** | Watering, sunlight, soil, decorations placement not in the API (B9). Growth stage = approved missions this week; milestones = longest streak. Both are presentation only and labelled as such. |
| 14 | `parent_settings_security` | Parent settings | `/parent/settings` | **Partial (new)** | No parent PIN, screen-time/bedtime lock, data export, family wipe, or phone number — none have an API (B10, B13). Real: account, linked children, push/email prefs (`/settings/me`), language, consent records, log out. |
| 15 | `bal_kavach_shield_logo` | Logo asset | – | Done | – |

## Built without a Stitch reference

| Screen | Route | Notes |
|---|---|---|
| Splash | `/splash` | Session restore. |
| Role selection | `/role` | |
| Child start (explains child mode) | `/child-start` | |
| Parent Hub | `/parent` | Links to Approvals (with a one-request pending count), Reports, Settings, child profiles; mission tiles open the editor; long mission lists collapse to 20. |
| New mission | `/parent/missions/new` | Optional due date. |
| Edit / remove mission | `/parent/missions/:taskId/edit` | `PATCH` and soft `DELETE /tasks/{id}`; removal is confirmed. |
| Mission waiting / approved / rejected | `/child/missions/:taskId/waiting` | |

## Navigation and role protection

- Redirect rules live in `core/routing/route_guard.dart` (unchanged). A child
  session can only reach `/child/**`; a parent session only `/parent/**`; signed-out
  users are sent to role selection. `test/core/batch_route_guard_test.dart` checks
  every new route for all three states.
- Child bottom bar / rail: Home · Missions · Rewards · Garden.
- An unknown child id on `/parent/children/:childId` shows a "profile no longer
  available" state with a way back, not a crash.
- Reports with a missing or unknown `?child=` fall back to the first child.

## Backend operations used by the new screens

| Screen | Operation | Notes |
|---|---|---|
| Approvals | `GET /notifications` (parent) | Finds tasks that received a `task_submitted` notification (B4 workaround). |
| Approvals | `GET /tasks/{id}/submissions` | One call per submitted task, 5 at a time, capped at 25 tasks per load; the UI says when the cap hides older ones. |
| Approvals | `POST /reviews/submissions/{id}` | `approved` / `rejected` / `resubmission_requested` + optional note. 409 on a second review is handled and refreshes the list. |
| Reports, profile, rewards, garden | `GET /progress/children/{id}` | Now parses `activity_days` and `badges`. |
| Child profile | `PATCH /families/{id}/children/{child_id}` | `display_name`, `date_of_birth`. |
| Child profile | `DELETE /families/{id}/children/{child_id}` | Soft deactivate. |
| Settings | `GET/PATCH /settings/me` | Only changed fields sent (null is a 422). Optimistic, rolled back on failure. |
| Settings | `GET /settings/families/{id}/consents` | Display only. |
| Rewards | `GET /redemptions/mine` | Child's own requests. |

No backend code, schema or migration was changed.

## Backend limitations — re-verified against source and live schema

| Limitation in the brief | Still true? |
|---|---|
| No phone OTP / Google sign-in | Yes — only `/auth/register`, `/auth/login`, `/auth/me`, `/auth/children/{id}/session`. |
| No photo upload for proof | Yes — no upload route; `proof_url` must already be an http(s) URL. |
| No child endpoint listing own submissions | Yes — `GET /tasks/{id}/submissions` is parent-only. |
| No combined parent pending-submissions endpoint | Yes (B4). |
| No child rewards-list endpoint | Yes — `GET /rewards` uses `require_parent` (B5). |
| Child tokens expire after 30 min, no refresh | Yes — `access_token_expire_minutes` default 30; no refresh route (B6). |
| Child avatar, age bracket, interests not persisted | Yes (B7, B8). |

New gaps found in this pass (add to `api-integration-matrix.md` blockers):

| # | Need | Status |
|---|---|---|
| B12 | Parent cannot list a child's reward redemption requests, so approve/reject/fulfil in `rewards.py` cannot be driven from a screen. | Only `GET /redemptions/mine` (child) exists. |
| B13 | Parent profile has no phone number; family-level video/screen-time settings are stored but not enforced anywhere in the backend. | Settings screen does not present them as working controls. |
| B14 | No quiz or learning-progress endpoints. | Learning/quiz screens cannot be built honestly. |

## Functional pass (2026-10-13)

The 2026-10-13 pass audited behaviour behind the screens, not just their layout.
The full action-by-action matrix is in `frontend-functional-audit.md`. Changes that
affect this matrix:

- Mission editing, removal and due dates (rows 9, Parent Hub).
- Approvals tolerate a failing task request instead of failing as a whole.
- A server-ended session shows a notice; an outdated consent re-prompts a signed-in parent.
- Accessibility fixes found by Flutter's guideline checks: unlabelled language radios (row 1), insufficient text contrast over photos on mission detail and parent sign-in (rows 3, 7).
- No screen was added. The remaining gaps are backend/product blockers B1–B16 in `api-integration-matrix.md`.

## Test status

576 tests pass (`flutter test`), `flutter analyze` is clean and formatting is clean
(see `frontend-functional-audit.md` for the verification table).

Test files added across the two passes: `features/batch_logic_test`,
`features/batch_repositories_test`, `features/mission_management_test`,
`core/batch_route_guard_test`, `widgets/batch_screens_test`,
`widgets/functional_flows_test`, `localization/localization_audit_test`; six
screens added to `responsive/responsive_screens_test`, which now also covers
landscape/short windows, the keyboard, and the Flutter accessibility guidelines.
