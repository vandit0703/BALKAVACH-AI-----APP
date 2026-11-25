# BALKAVACH — Responsive UI & Accessibility Audit

**Audit Date:** 2026-11-25
**Repository:** `C:\Users\PC\BALKAVACH-AI-----APP`
**Platforms:** Flutter Android (`balkavach-frontend`) & Flutter Web Admin (`balkavach-admin`)

---

## 1. Executive Summary

- **Flutter Mobile App (`balkavach-frontend`):** Strong responsive engineering foundation (`WindowSize` breakpoints at `<600` compact, `600..839` medium, `>=840` expanded; `ResponsiveContent`, `ScrollablePage`, `AdaptiveWrap`, `ChildShell` switching from `NavigationBar` to `NavigationRail` at 840px). Our widget test run of `responsive_screens_test.dart`, `oem_foldable_compatibility_test.dart`, and `video_responsive_test.dart` passed **1,000 / 1,000** test cases across widths 320px–840px, landscape short windows (`740x360`, `568x320`), OEM/foldable sizes, font scales `1.0x` and `2.0x`, and `en`/`hi`/`gu` locales.
- **Important Caveat (Not Tested on Real Devices/Emulators):** No live Android emulator or physical device screenshots were captured in this audit; all responsive verification is via Flutter widget tests and static layout inspection. Additionally, **some newer Phase 5/6 screens** (e.g. `LearningHubScreen`, `QuizIntroScreen`, `QuizTakeScreen`, `QuizResultScreen`, `ChildProfileScreen` quiz history/achievements sections, `StreakScreen`) are not yet in `responsive_screens_test.dart` and require explicit responsive matrix coverage.
- **Admin Panel (`balkavach-admin`):** **COMPILES (NO RESPONSIVE TESTS)** — The syntax error in `lib/pages/youtube_reviews_page.dart:26` was fixed (`flutter analyze`: 0 errors, 1 warning), and `flutter test` now runs (**94 passed, 1 skipped, 5 failed**). Statically, `AdminShell` (`lib/pages/shell.dart`) uses `kSidebarBreakpoint = 900.0` (drawer < 900px, icon rail 900–1199px, full sidebar >= 1200px), but **no responsive browser tests** exist for 320px–1920px viewports.

---

## 2. Flutter Mobile App — Responsive Test Matrix

### Breakpoints & Architecture (`lib/core/responsive/breakpoints.dart`)
- `WindowSize.compact`: `< 600` dp (`pageMargin = AppSpacing.marginCompact`)
- `WindowSize.medium`: `600 .. 839` dp (`pageMargin = AppSpacing.marginWide`)
- `WindowSize.expanded`: `>= 840` dp (`ChildShell` switches from `NavigationBar` to `NavigationRail`)
- `ContentWidth`: `form = 560.0`, `list = 720.0`, `wide = 960.0`

### Verified Screen Matrix (via `responsive_screens_test.dart`, `oem_foldable_compatibility_test.dart`, `video_responsive_test.dart` — 1,000/1,000 Passed)

| Screen | Route | Viewports Tested (Widget Tests) | Font Scales | Locales | Status | Notes / Remaining Risk |
|---|---|---|---|---|---|---|
| `SplashScreen` | `/splash` | 320, 360, 393, 600, 840; 740x360, 568x320 | 1.0x, 2.0x | en, hi, gu | **PASS** | `settle: false` due to animation |
| `WelcomeScreen` | `/welcome` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ScrollablePage` |
| `ConsentScreen` | `/consent` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ScrollablePage` |
| `RoleSelectionScreen` | `/role` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ScrollablePage` |
| `ChildLoginScreen` | `/child-login` | 320..840 + keyboard-open | 1.0x, 2.0x | en, hi, gu | **PASS** | `SingleChildScrollView` |
| `ParentAuthScreen` | `/parent-auth` | 320..840 + keyboard-open | 1.0x, 2.0x | en, hi, gu | **PASS** | `SingleChildScrollView` |
| `ParentModeScreen` | `/child/parent-gate` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Verified in `parent_mode_test.dart` too |
| `ResetPasswordScreen` | `/reset-password` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Tested in en/hi/gu |
| `ParentHomeScreen` | `/parent` | 320..840 + OEM/foldable | 1.0x, 2.0x | en, hi, gu | **PASS** | `ListView` + `ResponsiveContent` |
| `CreateChildScreen` | `/parent/children/new` | 320..840 + keyboard-open | 1.0x, 2.0x | en, hi, gu | **PASS** | Focused field stays above keyboard |
| `ChildProfileScreen` | `/parent/children/:childId` | 320..840 + 340x500 | 1.0x, 2.0x | en, hi, gu | **PARTIAL** | Newer quiz history & achievement sections need explicit 320px/2.0x test |
| `CreateMissionScreen` | `/parent/missions/new` | 320..840 + keyboard-open | 1.0x, 2.0x | en, hi, gu | **PASS** | Focused field stays above keyboard |
| `ApprovalsScreen` | `/parent/approvals` | 320..840 + tap-target check | 1.0x, 2.0x | en, hi, gu | **PASS** | Verified >=48dp tap targets at 393px |
| `WeeklyReportScreen` | `/parent/reports` | 320..840 + 340x500 | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ResponsiveContent` |
| `ParentRewardsScreen` & `RewardFormScreen` | `/parent/rewards` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ScrollablePage` |
| `ParentSettingsScreen` | `/parent/settings` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ScrollablePage` |
| `WatchHomeScreen` (`ChildShell`) | `/child` | 320..840 + landscape + video tests | 1.0x, 2.0x | en, hi, gu | **PASS** | `ParentGateButton` switches to icon-only when `usableWidth / textScale < 420` |
| `MissionsScreen` | `/child/missions` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | Choice cards use `Wrap` (`width: 280`) |
| `MissionDetailScreen`, `MissionSubmitScreen`, `MissionWaitingScreen` | `/child/missions/:id*` | 320..840 + keyboard-open | 1.0x, 2.0x | en, hi, gu | **PASS** | Focused field stays above keyboard |
| `RewardsScreen` | `/child/rewards` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | Uses `ResponsiveContent` |
| `GardenScreen` | `/child/garden` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | `ListView` + `ResponsiveContent` |
| `ChildHomeProfileScreen` | `/child/profile` | 320..840 | 1.0x, 2.0x | en, hi, gu | **PASS** | Language `ChoiceChip`s use `Wrap` |
| `ShortsFeedScreen`, `VideoDetailPlayerScreen`, `VideoFeedScreen`, `YouTubePlayerScreen` | `/child/shorts`, `/child/watch`, `/child/videos` | 320..840 + landscape | 1.0x, 2.0x | en, hi, gu | **PASS** | Verified in `video_responsive_test.dart` |
| `LearningHubScreen`, `QuizzesTab`, `StoriesTab` | `/child/learn` | Default test viewport | 1.0x | en | **PARTIAL** | Covered in `learning_hub_quiz_test.dart`, not yet in 320px/2.0x/hi/gu matrix |
| `QuizIntroScreen`, `QuizTakeScreen`, `QuizResultScreen` | `/child/quizzes/*` | Default test viewport | 1.0x | en | **PARTIAL** | Covered in `learning_hub_quiz_test.dart`, not yet in 320px/2.0x/hi/gu matrix |
| `StreakScreen` | `/streak` | Default test viewport | 1.0x | en | **PARTIAL** | Covered in `streak_test.dart`, not yet in `responsive_screens_test.dart` |

---

## 3. Admin Panel (`balkavach-admin`) — Responsive Audit

- **Runtime Verification Status:** **COMPILES — 5 NON-RESPONSIVE TESTS FAILING** — `youtube_reviews_page.dart:26` was fixed; `flutter analyze` has 0 errors (1 unused-element warning) and `flutter test` passes 94/100 (1 skipped, 5 failed in `localization_ui_test.dart` and `youtube_reviews_test.dart`).
- **Static Responsive Architecture (`lib/pages/shell.dart`):**
  - `< 900 px`: `Drawer` navigation.
  - `900 .. 1199 px`: Compact icon-only rail.
  - `>= 1200 px`: Extended sidebar.
- **Gaps:**
  1. **P0:** Fix the 5 failing tests in `balkavach-admin` (`youtube_reviews_test.dart`, `localization_ui_test.dart`) and verify `flutter build web`.
  2. **P1:** Add explicit responsive browser/widget tests at `320px`, `360px`, `390px`, `430px`, `768px`, `1024px`, `1280px`, `1440px`, `1920px` for tables, forms, dialogs (`_QuizEditorDialog`), and horizontal overflow.
