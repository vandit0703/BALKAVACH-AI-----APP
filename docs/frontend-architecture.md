# Frontend Architecture

> **Update 2026-10-13 (second pass).** Additions not described below: refresh-token
> sessions with a single-flight renewal interceptor (`core/network`), a push-token seam
> (`core/push`) with defensive Firebase initialisation, a runtime-config provider for the
> server-controlled consent version and maintenance banner (`core/config/runtime_config.dart`),
> platform seams for the photo picker, share sheet, link opener and device time zone
> (`shared/media`, `shared/platform`), and the `learning`, `notifications` and
> `rewards` (parent) features. The separate admin panel lives in `balkavach-admin/`.
> Full status: `feature-implementation-matrix.md`.


Flutter app in `balkavach-frontend/` (package `balkavach_app`), Android-first.
Toolchain at creation: Flutter 3.44.6, Dart 3.12.2, Android SDK 36, JDK 17.

## Stack

| Concern | Choice | Why |
|---|---|---|
| State | `flutter_riverpod` 3.x, hand-written providers (no codegen) | Testable overrides without a build_runner step. |
| Navigation | `go_router` 18, routes centralised in `core/routing/` | Redirects drive onboarding → auth → role-specific home. |
| HTTP | `dio` 5 with interceptors | Timeouts, auth header, redacted logging, typed errors. |
| Models | Immutable Dart classes with `fromJson`/`toJson` | Small payloads; avoids Freezed codegen. |
| Token storage | `flutter_secure_storage` | Android Keystore-backed. |
| Preferences | `shared_preferences` | Language, consent acknowledgement, local avatar choice, pending submission cache. |
| i18n | `flutter_localizations` + ARB (`lib/l10n/`, en / gu / hi) | |
| Tests | `flutter_test`, `mocktail`, a fake Dio `HttpClientAdapter` | No network in tests. |

## Layout

```
lib/
  main.dart            → bootstrap()
  bootstrap.dart       → loads prefs + secure storage, builds ProviderScope
  app.dart             → MaterialApp.router (theme, locale, router)
  core/
    config/            AppConfig (API_BASE_URL dart-define)
    network/           dio factory, AuthInterceptor, RedactingLogInterceptor, ApiException, health API
    storage/           SessionStorage (secure), AppPreferences
    routing/           AppRoutes, router + redirect rules
    theme/             colours, typography, spacing, ThemeData, BalKavachColors extension
    responsive/        breakpoints, ResponsiveContent
    localization/      LocaleController
  shared/widgets/      design-system components; shared building blocks: AdaptiveWrap (equal tiles that
                       stack by width and text scale), NavTile (icon row with chevron), LazyListPage
                       (header + lazily built rows + footer, centred and width-capped)
  shared/async/        refreshQuietly (pull-to-refresh that never throws)
  features/
    onboarding/        splash, welcome/language, consent, role selection
    authentication/    AuthApi, AuthRepository, Session model, SessionController, parent auth screen
    child_profile/     FamilyRepository, Family & ChildProfile models, create-child, child profile (edit / remove), child-mode launcher, consent sync
    parent_dashboard/  parent home (family setup, children, quick actions, start child mode, new mission)
    missions/          MissionsRepository, Task/Category/Submission models, child home, list, detail, submit, waiting; child shell (4 tabs)
    approvals/         ApprovalsRepository, ApprovalInbox model, inbox providers + screen
    progress/          ProgressRepository, ChildProgress (activity days, badges), weekly report screen
    rewards/           RewardsRepository (the child's own requests), rewards & badges screen
    garden/            garden screen (stage and milestones derived from progress; no repository)
    settings/          SettingsRepository, UserSettingsController, parent settings screen
  l10n/                app_en.arb, app_gu.arb, app_hi.arb (+ generated)
```

Learning and quizzes have no folder: there is no Stitch design and no backend
API for them (see `stitch-screen-implementation-matrix.md`).

Each feature: `data/` (API class = raw Dio calls; repository = maps to models and
`ApiException`), `domain/` (models, and logic only where it exists, e.g.
mission status derivation), `presentation/` (screens, widgets, providers).
Widgets never touch Dio.

## Session and roles

The backend has two client roles. Both use the same bearer-token mechanism:

1. **Parent** registers or logs in with email + password → parent token.
2. **Child** has no credentials. A signed-in parent picks a child and calls
   `POST /auth/children/{id}/session`, which returns a child token. The app then
   *replaces* the parent session with the child session on the device
   ("child mode"). The parent token is discarded, so a child cannot reach parent
   screens. Leaving child mode ("Parent Gate") clears the child session and
   requires the parent to sign in again.

`Session` = token, expiry, `UserPublic`, and `childId` (child mode only), stored
as one JSON blob in secure storage. On launch, an expired session is dropped
locally; a valid one is confirmed with `GET /auth/me`. Any 401 from the API
clears the session and the router returns to the role screen. There is no
refresh token (see blocker B6).

## Routing

```
/splash → /welcome → /consent → /role ─┬─ /parent/auth → /parent ─┬─ /parent/children/new
                                       │                          └─ /parent/missions/new
                                       └─ /child/start (explains child mode)
/parent/children/:childId · /parent/missions/:taskId/edit · /parent/approvals · /parent/reports?child= · /parent/settings
/child (shell: Home | Missions | Rewards | Garden)
  /child/missions/:taskId → /child/missions/:taskId/submit → /child/missions/:taskId/waiting
```

`redirect` reads `AppGateState` (language chosen, consent acknowledged,
session role) so deep links cannot skip onboarding or cross roles. A signed-in
**parent** whose stored consent version is outdated is sent to `/consent` before
anything else; a child session never is. When the server ends a session (401) the
user lands on role selection with a "session has ended" notice
(`sessionEndedProvider`); a deliberate sign-out shows none.

## Networking rules

- Base URL: `--dart-define=API_BASE_URL=https://balkavach-ai-app.onrender.com`
  (default is the deployed URL; nothing secret goes in a dart-define).
- Timeouts: connect 20 s, receive 45 s, send 30 s (cold Render instance + DB).
- `RedactingLogInterceptor` logs method, path, status and duration in debug
  builds only; never headers, bodies, or query values for auth routes.
- `ApiException` subtypes: `NetworkException`, `TimeoutException`,
  `UnauthorizedException`, `ForbiddenException`, `NotFoundException`,
  `ConflictException`, `ValidationException` (field errors from `details`),
  `ServerException`, `UnknownApiException`. All carry the backend `code`.

## Data loading rules

- Lists that can exceed the server page size are paged (`GET /tasks`: 100 per page,
  up to 5 pages) and a failing later page fails the load, so there are no silent gaps.
- A provider does not request anything until the session it needs exists
  (`childMissionsProvider` waits for a child session).
- Aggregated requests tolerate partial failure: the approval inbox fetches submissions
  per task (5 at a time, 25 tasks max), skips and counts failures, and fails as a whole
  only on 401 or when every request failed.
- Mutations are guarded against duplicates: submit (provider-level), settings saves
  (one at a time, controls disabled), and every form's primary button shows a spinner
  and ignores taps while its request runs.
- Long collections use `LazyListPage` (child missions, approvals); the Parent Hub
  collapses missions to the first 20.

## Security notes

- The Flutter app contains no database URL, JWT secret, or server keys.
- Root `.env` (holds `DATABASE_URL`, `JWT_SECRET_KEY`) is gitignored; verify it
  was never committed and rotate if it was.
- Android release signing is not configured; debug signing only.
- Cleartext HTTP is not enabled; use HTTPS for the API.

## Verification status (2026-10-13, second pass)

- `dart format --set-exit-if-changed lib test`: clean (100 files).
- `flutter analyze`: no issues.
- `flutter test`: **576 tests, all passing** (260 in the first slice, +135 for the
  Stitch screens, +181 in the functional-completion pass).
- The responsive suite covers 20 screens at 320 / 360 / 393 / 600 / 840 px at 1× and
  2× text, Gujarati and Hindi at 320 px, two short landscape windows (740×360,
  568×320) at 1× and 2×, the tap-target / labelled-target / text-contrast guidelines
  at 393 px, and the keyboard-open check on four forms. It has caught real defects
  each time it was extended (overflows, an unlabelled radio, low contrast over photos).
- `localization/localization_audit_test` keeps en/gu/hi in step and fails on
  hard-coded visible text.
- Not run on a device or emulator.
- Gujarati and Hindi strings (all 364 per language) were machine-written and need
  review by a native speaker.

See `frontend-functional-audit.md` for the action-by-action audit.

## Commands

```
cd balkavach-frontend
flutter pub get
flutter gen-l10n
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run --dart-define=API_BASE_URL=https://balkavach-ai-app.onrender.com
flutter build apk --debug
```
