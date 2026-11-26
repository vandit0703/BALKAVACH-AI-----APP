# Parent interest management and child interest requests: fix report

Date: 2026-11-26. Branch `main`, HEAD `1d968cf` ("quiz"). Nothing was committed, pushed, deployed or migrated.
No production or staging database was read or written.

## Summary

| Question | Answer |
|---|---|
| Root cause, Parent Mode | Same as Parent Account (see below). Parent Mode is not a separate implementation: `POST /auth/parent-mode/enter` returns an ordinary **parent** access token, the router lands on the same Parent Hub, and the child's profile is the same `ChildProfileScreen` → `ParentChildInterestsCard` → `FamilyRepository` → `GET/PUT /families/{f}/children/{c}/interests`. |
| Root cause, Parent Account | 1. **Deployment.** Earlier today the production API had no interest routes at all (404, see `QUIZ_AND_INTERESTS_FIX_REPORT.md`). They are now deployed: production `/openapi.json` matches local code (207 operations, identical request bodies). Whether production has the migration 0022 columns could not be checked; without them, saves return 503. 2. **Client defects in the parent card**: *Approve* sent the union of the parent's **unsaved** chip edits and the child's request, so unsaved edits were saved without the parent asking and a request to *remove* a topic could never be approved. *Dismiss* also saved unsaved edits. There was no guard against a second tap. When the card was reused for another child, it kept the previous child's state, and a late response could land on the wrong child. 404 and 503 showed a generic error. |
| Child requests affected? | Yes. A request that was empty or held only unknown/inactive topics was stored as `[]` and answered **200**. The app said "Interest request sent to parent", but the parent saw nothing, and any earlier request was wiped. There was also no guard against a second tap. |
| Authorization model changed? | No. |

## Parent Mode vs Parent Account (traced)

| Aspect | Parent Account (email sign-in) | Parent Mode (from child device) |
|---|---|---|
| Session | `POST /auth/login` → parent token | `POST /auth/parent-mode/enter` with the child's bearer + parent email/password → parent token (`device_label = "parent_mode"`) |
| Server dependency | `require_parent` | `require_parent` (same; parent-mode sessions are only refused for account-wide actions in `account_security_service`) |
| Route | `/parent/children/:childId` | same |
| Family id | `currentFamilyProvider` (newest family of the parent; rebuilt on session change) | same |
| Child id | route path parameter | same |
| Repository/provider | `FamilyRepository.getChildInterests / updateChildInterests` via `apiDioProvider` | same |
| Entry points to a child's interests | Parent Hub child card, Parent Settings child row, sibling card on a child profile | same |

So one fix covers both. Note: when a parent belongs to several families, the app only manages children of the newest family (existing behaviour). A child from another family shows "This profile is no longer available."

## API contracts (verified locally and against production OpenAPI)

| Endpoint | Auth | Request | Response | Errors |
|---|---|---|---|---|
| `GET /api/v1/families/{family_id}/children/{child_id}/interests` | parent + active membership of `family_id`; child must belong to that family | — | `{child_id, interests: [slug], pending_requests: [slug], available_categories: [{slug, name}]}` | 401, 403 (not a parent), 404 (not a member / child not in family) |
| `PUT /api/v1/families/{family_id}/children/{child_id}/interests` | same | `{interests: [slug], clear_pending: bool = true}`; unknown/inactive slugs dropped, lower-cased, de-duplicated | same shape, after commit | 401, 403, 404, 422 (bad body), 503 (columns missing) |
| `GET /api/v1/videos/interests` | child (`require_child`) | — | `{interests, pending_requests, available_categories}` | 401, 403 |
| `POST /api/v1/videos/interests/request` | child | `{interests: [slug]}` = the **full set** the child wants (the picker starts from the approved topics) | same shape; only `pending_requests` changes | 401, 403 (parent token), 422 (not a list; **new:** no valid topic, code `interest_request_empty`), 503 |

Approval and rejection reuse the parent `PUT` (no duplicate approval logic):

- **Approve**: `PUT {interests: pending_requests, clear_pending: true}`.
- **Dismiss**: `PUT {interests: <server's approved list>, clear_pending: true}`.
- **Parent's own Save**: `PUT {interests: <selection>, clear_pending: false}`. This leaves a waiting child request in place.

Recommendations: `video_service.eligible_feed` reads only `child.interests` (`_child_interest_slugs`) and ranks matching categories first among unseen/in-progress videos. `pending_interest_requests` is never read by ranking. The feed is computed server-side on every page request, and feed pagers are created per screen. So the next feed load after a parent save uses the new interests, including after switching back to child mode on the same device.

## Authorization findings

- A parent who is not a member of the family gets 404 on GET and PUT. So does a member whose family does not contain the child (tested on PostgreSQL).
- A child token gets 403 on the parent GET/PUT, so a child cannot approve their own request (tested).
- A parent token gets 403 on the child request endpoint (tested).
- Requests without a token get 401 (tested).
- Nothing was weakened.

## Database schema and migrations

Migration `0022_production_readiness` adds `child_profiles.interests` (JSONB, default `[]`), `pending_interest_requests` (JSONB, default `[]`), `interests_updated_at`, `interests_updated_by` (FK users). It is the single Alembic head. When the columns are missing, PUT and POST refuse with 503 instead of claiming success. GET then returns empty lists.

**Deployment risk found:** the same migration also runs `ADD COLUMN redemption_requests.cancelled_at`. The repository's reconstructed baseline (`tests/schema/reconstructed_baseline.sql`) already contains that column. On the test database, `alembic upgrade head` failed on it and rolled back the whole migration, interest columns included. If production already has `cancelled_at`, migration 0022 will fail there the same way, and interests will stay at 503. Check before migrating (read-only):

```sql
SELECT column_name FROM information_schema.columns
WHERE table_name IN ('child_profiles','redemption_requests','users')
  AND column_name IN ('interests','pending_interest_requests','interests_updated_at','interests_updated_by',
                      'deleted_at','reward_title_snapshot','reward_description_snapshot','cancelled_at');
SELECT version_num FROM alembic_version;
```

If `cancelled_at` already exists and `alembic_version` is below `0022_production_readiness`, the migration must be made conditional (`ADD COLUMN IF NOT EXISTS`) before it is run. That decision is the owner's; the migration was not edited.

Also: the backend reflects the schema at start-up (automap). After the migration runs, the API process must be **restarted**, or it keeps answering 503.

## Files changed

Backend
- `balkavach-backend/app/api/v1/videos.py`: `POST /videos/interests/request` answers 422 `interest_request_empty` instead of storing `[]` with 200. Added the missing `APIError` import (it was also referenced, unimported, in the trusted-channel `except APIError:` handler).
- `balkavach-backend/tests/feed_world.py`: nullable `slug` column on the SQLite `VideoCategory` test model (needed for ranking tests).
- `balkavach-backend/tests/test_parent_interest_management_pg.py` (new, 15 tests, real PostgreSQL).
- `balkavach-backend/tests/test_interest_recommendation_ranking.py` (new, 3 tests, real `eligible_feed`).

Frontend
- `balkavach-frontend/lib/features/child_profile/presentation/child_interests_and_link_cards.dart`
  - Parent card:
    - Shows approved topics, pending requests and the topic picker as separate sections.
    - Approve applies exactly the requested set. Dismiss keeps the server's approved set.
    - Save is enabled only when the selection differs from the saved topics, shows a spinner and accepts one request at a time.
    - Success is shown only after the server confirms. On any failure the selection is kept.
    - State is reset and reloaded when the family or child id changes; responses for a previous child are dropped.
    - 404 shows "not linked to your account", 503 shows "not ready yet", and an empty catalogue has its own state.
  - Child card:
    - Accepts one request at a time and shows progress while sending.
    - An empty selection cannot be sent ("Pick at least one topic to ask for.").
    - A 503 or the new 422 code gets a specific message.
- `balkavach-frontend/lib/l10n/app_{en,hi,gu}.arb` and the regenerated `app_localizations*.dart`: `interestsChildNotLinked`, `interestsApproveHint`, `interestsRequestPickOne`, `interestsParentActiveTitle`, `interestsParentChooseTitle` in English, Hindi and Gujarati.
- `balkavach-frontend/test/features/parent_interest_management_test.dart` (new, 19 tests).
- `balkavach-frontend/test/features/interests_linking_help_test.dart`: the approve test asserted the old union behaviour. It now asserts that the requested set is applied exactly and `clear_pending` is true.

Not touched: the pre-existing uncommitted changes to `task_service.py`, `video_entitlement_service.py`, `test_parent_mission_approval.py` and `test_mission_approval_video_grant.py`. During this session, another process also created or edited `mission_approval_celebrator.dart`, `approval_unlocks_video_test.dart` and `docs/VIDEO_ENTITLEMENT_APPROVAL_FIX_REPORT.md`. Those are not part of this fix.

## Tests

| Suite | Result |
|---|---|
| `tests/test_parent_interest_management_pg.py` on PostgreSQL 16 (local disposable cluster) | 15 passed (3 failed before the backend fix: empty / unknown / inactive request returned 200) |
| `tests/test_interest_recommendation_ranking.py` + existing interest tests (`test_interests_and_allowance_contract.py`, `test_video_recommendations_and_integrity.py`) | 18 passed |
| Full backend suite on PostgreSQL | see "Full backend run" below |
| `test/features/parent_interest_management_test.dart` | 19 passed |
| Existing interest widget tests (`child_interests_states_test.dart`, `interests_linking_help_test.dart`) | all passed (1 assertion updated as described) |
| Full Flutter suite | 2767 passed, 2 skipped, 0 failed |
| `flutter analyze` | 2 infos, both in files not touched here (`shorts_navigation_regression_test.dart`, `watch_home_test.dart`) |

Coverage against the brief:

- **Parent account**
  - load ✔, save ✔, persists to PostgreSQL ✔ (re-read with the identity map expired), reload after restart / re-login ✔ (fresh GET)
  - sees pending ✔, approve ✔, reject ✔
  - other family's parent refused ✔
- **Parent Mode**
  - parent bearer token used ✔, family/child ids in the path ✔, correct endpoint and body ✔
  - success and error states (500, 403, 422, network) ✔
  - switching children reloads and never saves to the old child ✔
- **Child**
  - loads catalogue ✔, submits with the child token ✔, pending persists ✔
  - failure keeps the selection ✔, cannot approve own request ✔
  - duplicate taps send one request ✔
- **Recommendations**
  - approved interests rank first ✔, pending interests have no effect ✔
  - a parent change applies on the next feed request ✔

### PostgreSQL setup used (local only)

`scripts/testenv.py` cluster on 127.0.0.1:55432, database `balkavach_test`. Setup steps:

1. Loaded `tests/schema/reconstructed_baseline.sql`.
2. Created `alembic_version(varchar(64))`.
3. Dropped the baseline's `redemption_requests.cancelled_at` so 0022 could apply (the conflict above).
4. Ran `alembic upgrade head` with psycopg JSONB dumpers registered.
5. Added an `audit_logs` table, which the reconstructed baseline lacks and `record_audit` needs.

This is a reconstruction, not production's schema.

### Full backend run

Run on the local PostgreSQL with the Redis stand-in. A first attempt is void: the Redis stand-in died part-way through, producing 322 failures and 15 errors.

| Run | Result |
|---|---|
| With this fix (whole `tests/`) | 180 failed, 1273 passed, 1 skipped |
| Baseline: the same tree with the pre-fix `videos.py` and `feed_world.py` and without the two new test files | 179 failed, 1256 passed, 1 skipped |

Every failure in the fix run also fails in the baseline, except `test_mission_catalogue.py::test_the_weekday_theme_is_offered`. That test also fails on its own with the pre-fix files in place, so it is unrelated to this change (it depends on daily-mission rotation and test-DB state). The ~179 failures were already there. Earlier notes put them down to admin, YouTube, quiz and parent-mode tests needing tables and seed data the reconstructed schema lacks, plus real regressions (`docs/phase-6-closeout-report.md`). They are not triaged here. All 18 new backend tests pass.

## Production

- Checked read-only and unauthenticated. `/openapi.json` on `https://api.balkavach.tech` lists all three interest paths. Unauthenticated GETs answer 401, which means the routes are deployed.
- Not checkable without credentials: whether migration 0022 ran, and whether `video_categories` has active rows. With an empty catalogue, both cards show "No topics available yet."

## Remaining deployment blockers (owner's actions)

1. Deploy this backend change (the 422 for empty requests).
2. Confirm migration `0022_production_readiness` is applied in production, using the SQL above. If it is not applied and `redemption_requests.cancelled_at` already exists, make that `ADD COLUMN` conditional first. Then run the migration and **restart the API**.
3. Make sure `video_categories` has active rows with slugs. Otherwise there is nothing to choose.
4. Test on a device after deployment. No Android device was available here. Steps:
   1. Parent Account → child profile → change topics → Save → kill the app → reopen: the topics are still saved.
   2. Child → ask for a change → Parent Mode → approve → child mode: the feed favours the approved topics.
