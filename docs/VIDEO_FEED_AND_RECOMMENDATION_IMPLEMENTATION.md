# BALKAVACH — Video Feed & Recommendation Implementation

**Updated:** 2026-11-25  
**Scope:** Child Home Watch & Learn feed, Shorts/regular ranking, parent-approved interests, zero free daily allowance, carry-forward balance.

---

## 1. Feed UX & Navigation Refresh

- **Removed unwanted topic filter chips:** Removed `_TopicChips`, `_categoryId`, and `_selectCategory` from [watch_home_screen.dart](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-frontend/lib/features/learning/presentation/watch_home_screen.dart).
- **Auto-refresh on returning to Home:** Added `appRouteObserver` (`RouteObserver<PageRoute<dynamic>>`) in [app_router.dart](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-frontend/lib/core/routing/app_router.dart) so `PopupRoute` dialogs/sheets do not trigger spurious refreshes, and wired `RouteAware.didPopNext()` + debounced `_refreshOnReturn()` in `watch_home_screen.dart`.

## 2. Interest-Based Recommendation Ranking (`DEC-04`)

- **Backend ranking ([video_service.py](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-backend/app/services/video_service.py)):**
  - `eligible_feed` scores both `regular` and `short` formats using:
    1. Explicit parent-approved `child.interests`
    2. Implicit category affinity from `ChildVideoWatchHistory`
    3. Early-skip deprioritization (`<15%` watched)
    4. Child language preference match
    5. Deterministic seed rotation for fresh ordering on return
  - Pending child interest requests (`pending_interest_requests`) **never** affect recommendation scoring until approved by a parent.
- **Endpoints & UI:**
  - Backend: `GET/PUT /api/v1/families/{family_id}/children/{child_id}/interests` ([families.py](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-backend/app/api/v1/families.py)), `GET /api/v1/videos/interests`, `POST /api/v1/videos/interests/request` ([videos.py](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-backend/app/api/v1/videos.py)).
  - Frontend: `ParentChildInterestsCard` & `ChildInterestsCard` in [child_interests_and_link_cards.dart](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-frontend/lib/features/child_profile/presentation/child_interests_and_link_cards.dart).

## 3. Zero Free Allowance & Carry-Forward (`DEC-02`, `DEC-03`)

- **Backend ([video_entitlement_service.py](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-backend/app/services/video_entitlement_service.py)):**
  - `FREE_DAILY_ALLOWANCE_SECONDS = 0`
  - Qualifying approved missions grant `900` seconds once per mission.
  - Removed midnight expiry (`expires_at = None`) and daily window filters in `get_child_video_allowance_today()` and `consume_video_allowance()` so unused earned seconds carry forward across days.
- **Frontend ([video_feed_repository.dart](file:///c:/Users/PC/BALKAVACH-AI-----APP/balkavach-frontend/lib/features/learning/data/video_feed_repository.dart)):**
  - Changed `freeRemainingSeconds` defaults from `900` to `0`.

## 4. Verification Summary

- Backend: `pytest -q tests/test_video_recommendations_and_integrity.py tests/test_play_ticket_rules.py tests/test_video_classification.py tests/test_youtube_auto_review.py` → **98 passed**.
- Frontend: `flutter test test/widgets/watch_home_test.dart test/features/interests_linking_help_test.dart test/localization/localization_audit_test.dart test/features/video_feed_test.dart --reporter=compact` → **64 passed**.
