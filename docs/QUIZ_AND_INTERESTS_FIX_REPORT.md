# Quiz entry point, Video interests error, and video allowance: fix report

Date: 2026-11-26 · Branch `main` · HEAD `a1d19f5` (working tree was clean at start; nothing committed, pushed or deployed).

## Summary

| Issue | Root cause | Fixed in code? | Still needed |
|---|---|---|---|
| A. Quiz not reachable | The Learning Hub (Videos/Quizzes/Stories) and quiz routes existed, but Home's **only** link into the hub sat under the "Grown-up picks" header, which renders only when curated picks exist. With no picks the hub was unreachable. Separately, the deployed API has no `/quizzes` routes at all. | Yes: always-visible "Learn & play" tiles on Home; hub tabs are now **Videos, Quizzes, Shorts** (product owner's request: Shorts replaces Stories). | Deploy backend `a1d19f5` + migration `0021_quiz_system` |
| B. "We couldn't find that." on Video interests | The **production API returns 404** for `GET /api/v1/videos/interests`: the route (and the columns from migration `0022`) were added in commit `a1d19f5` and are not deployed. The app correctly mapped 404 to its generic not-found text. | Clearer states: 404 says the feature isn't ready yet, plus a working Retry; separate approved / pending / ask sections; empty catalogue state. Backend refuses (503) instead of faking success when the columns are missing. | Deploy backend `a1d19f5` + migration `0022_production_readiness` |
| C. "15m left / Daily free video: 15 of 15" | Production still runs the old `FREE_DAILY_ALLOWANCE_SECONDS = 900` (commit `d905466` era); local code is `0`. The client also **hard-coded "of 15"** and always showed the free line. Backend schema defaulted free fields to 900. | Free line shows only when the server reports a free allowance, using the server's total; model defaults to 0; backend schema defaults are now 0. | Deploying `a1d19f5` sets free time to 0 in production |

## Evidence: production API vs local code

Unauthenticated, read-only GETs against `https://api.balkavach.tech` (the app's default `API_BASE_URL`). A route that exists answers 401; a route that is missing answers 404:

```
GET /api/v1/videos/interests   -> 404 {"error":{"code":"http_error","message":"Not Found"}}
GET /api/v1/quizzes            -> 404
GET /api/v1/progress/children/<id>/achievements -> 404
GET /api/v1/videos/feed        -> 401 (exists)
GET /api/v1/video-access/allowance -> 401 (exists)
```

The deployed `/openapi.json` has 186 operations and local `app.openapi()` has 207. All 21 missing operations come from commit `a1d19f5`:
`/quizzes` (list, detail, attempts, submit, history, child history, attempt result), `/admin/quizzes` (CRUD, publish), `GET/POST /videos/interests(/request)`, `GET/PUT /families/{f}/children/{c}/interests`, `/progress/children/{id}/achievements`, `POST /families/{f}/children/{c}/link-code`, `POST /auth/child-link/redeem`, `DELETE /auth/account`.

## Contracts verified (local code)

| Endpoint | Auth | Response |
|---|---|---|
| `GET /api/v1/videos/interests` | child bearer (`require_child`, 401/403 only, never 404) | `{interests: [slug], pending_requests: [slug], available_categories: [{slug, name}]}`; empty catalogue = 200 with `[]` |
| `POST /api/v1/videos/interests/request` | child | body `{interests: [slug]}` → same shape; only `pending_requests` changes; unknown slugs dropped; **now 503** if the column is missing (was: reported success, stored nothing) |
| `GET /api/v1/families/{f}/children/{c}/interests` | parent + family membership | adds `child_id`; 404 only if the child isn't in the family |
| `PUT /api/v1/families/{f}/children/{c}/interests` | parent + membership | body `{interests, clear_pending=true}` → sets active, clears pending, audits; **now 503** if the column is missing |
| Recommendations | — | `video_service._child_interest_slugs` reads `child.interests` only; pending requests never affect ranking |

The frontend sends these through the shared Dio client (`/api/v1/...` on `AppConfig.apiBaseUrl`, bearer from the session), and its model (`ChildInterests.fromJson`) matches the shape above. No authorization requirement was changed.

## Video allowance findings

- Local backend: `FREE_DAILY_ALLOWANCE_SECONDS = 0`, `MISSION_REWARD_ALLOWANCE_SECONDS = 900`. `remaining_seconds = free_remaining + Σ(active mission grants − consumed)` across days, so carry-forward is intact. None of these rules were changed.
- Production: the screenshot's numbers match the old 900-second free allowance exactly. Backend is authoritative, so the headline "15m left" will read correctly once `a1d19f5` is deployed. The client does not hide or alter server-reported time.
- Client bug (fixed): `VideoAllowanceCard` always printed `Daily free video: X of 15 minutes left`, with 15 hard-coded. Under the zero-free rule that falsely advertised a free allowance.
- Latent fallback (fixed): `VideoAllowancePublic.free_allowance_seconds` / `free_remaining_seconds` defaulted to `900`. They are now `0`. Stale docstring corrected.

## Files changed

Backend
- `app/schemas/video.py`: free-allowance defaults 900 → 0
- `app/services/video_entitlement_service.py`: docstring only
- `app/api/v1/videos.py`: interest request returns 503 instead of a fake success when the column is missing
- `app/api/v1/families.py`: same for the parent PUT
- `tests/test_interests_and_allowance_contract.py` (new, 9 tests)

Frontend (`balkavach-frontend/`)
- `lib/features/learning/presentation/learning_hub_screen.dart`: tabs Videos / Quizzes / **Shorts**; stories now listed in Videos → "More to explore" and still open in the in-app reader
- `lib/features/learning/presentation/shorts_tab.dart` (new): paged grid from `GET /videos/shorts`; tap checks the allowance with the server, then opens the existing full-screen Shorts player; loading / empty / error + retry
- `lib/features/learning/presentation/widgets/short_card.dart` (new): Home's private Shorts card, made shared (same keys on Home)
- `lib/features/learning/presentation/widgets/learn_hub_entry.dart` (new): Home "Learn & play" tiles → `/child/learn?tab=videos|quizzes|shorts` (pushed inside the child shell; Back returns Home)
- `lib/features/learning/presentation/watch_home_screen.dart`: adds the entry; uses the shared card
- `lib/features/quizzes/presentation/quizzes_tab.dart`: a 404 shows "Quizzes aren't ready yet" (with Retry) instead of "We couldn't find that."
- `lib/features/child_profile/presentation/child_interests_and_link_cards.dart`: `ChildInterestsCard` rebuilt with loading, approved topics, pending requests (separate), ask-for-changes, empty catalogue, 404-specific error, Retry = fresh request; a failed request keeps the child's selection
- `lib/shared/widgets/state_views.dart`: optional `message` on `ErrorView`
- `lib/features/learning/data/video_feed_repository.dart`: `VideoAllowance.freeAllowanceSeconds` (default 0)
- `lib/features/learning/presentation/widgets/video_allowance_card.dart`: free line only when the server reports one, with the server total
- `lib/l10n/app_{en,hi,gu}.arb` + generated `app_localizations*.dart`: `hubTabShorts`, `hubShortsEmpty`, `learnHubEntryTitle`, `quizzesUnavailable`, `interestsUnavailable`, `interestsActiveTitle`, `interestsActiveNone`, `interestsPendingChildTitle`, `interestsAskTitle`
- Tests: `test/features/learning_hub_quiz_test.dart` (Stories-tab assertions replaced by Shorts per the product change; new 404, retry, Shorts grid/empty/error, story-via-Videos, overflow tests), `test/features/video_allowance_test.dart` (assertions of the hard-coded "of 15" replaced by zero-free / 900-earned / carry-forward / server-total tests), `test/features/child_interests_states_test.dart` (new, 10 tests), `test/widgets/watch_home_test.dart` (new Home → Quizzes → Back test)

Unchanged: quiz screens, routes, grading and rewards (server-graded, first pass only, admin-set Stars/XP default 0, client sends option ids only), mission reward rules, entitlement rules, `stories_tab.dart` (kept, no longer mounted).

## Tests run

| Suite | Result |
|---|---|
| `flutter analyze` | 2 infos, both from before this change (`test/features/shorts_navigation_regression_test.dart:88` unawaited_futures, `test/widgets/watch_home_test.dart:351` prefer_const); 0 in changed code |
| Focused frontend (hub/quiz 28, interests 15, allowance 8, Home 16, responsive 528) | all passed |
| Full frontend `flutter test` (final run) | **2744 passed, 2 skipped, 0 failed** |
| Focused backend (`test_interests_and_allowance_contract.py` + `test_video_recommendations_and_integrity.py`) | 15 passed |
| Full backend, working tree (no `TEST_DATABASE_URL`) | 52 failed, 1090 passed, 284 skipped |
| Full backend, clean `git archive HEAD` copy, same venv | 53 failed, 1081 passed, 284 skipped |

Backend failure comparison: the sets are identical except
- `test_mission_catalogue.py::test_the_weekday_theme_is_offered`, which is **flaky on both trees** (re-run 3×: working tree failed 1/3, HEAD failed 2/3);
- two `test_mission_catalogue_fixture.py` tests that fail only in the HEAD copy because the archived backend copy has no sibling Flutter fixture.

The remaining shared failures (play tickets, video time alerts, metering, entitlements, feed filters, etc.) exist at HEAD and are untouched by this change. No assertion was weakened or removed to get a pass.

The first full frontend run (before a colour fix) had 2743 passed, 2 skipped, 1 failed: `responsive_screens_test.dart: child home 393 px text contrast`. The new Shorts tile used `secondaryFixed`, which this theme doesn't define, so it falls back to `secondary` (ratio 1.0). Fixed with defined pairs; the responsive suite then passed 528/528, and the final full run passed.

## Manual / device verification

**Pending.** No Android device or emulator was available (`adb` not installed; `flutter devices` lists only Windows/Chrome/Edge). Also, until the backend is deployed, a device build against production will show the new "Quizzes / Video interests aren't ready yet" messages rather than working quizzes and interests. The full checklist still to run on a device after deployment:
1. Child sign-in → Home shows "Learn & play" → Quizzes opens the hub on Quizzes.
2. Complete a published quiz; check result and first-pass reward.
3. Shorts tab opens the Shorts player; Videos tab lists videos and stories.
4. Profile → Video interests loads; request a change; it shows as pending.
5. Parent approves → child's approved topics update.
6. With no earned time: card says "Video time locked" with no free minutes.

## Remaining blockers

1. **Deploy the backend at `a1d19f5` or later** and run migrations `0021_quiz_system` and `0022_production_readiness` on production. This is the owner's action; nothing was run against production or staging. Until then, quizzes, interests and achievements return 404 and production keeps granting 900 s of free video time.
2. Pre-existing backend failures at HEAD (52–53, listed above) remain; see `docs/phase-6-closeout-report.md` for their triage.
3. Device verification (above).
