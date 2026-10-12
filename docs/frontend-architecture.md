# Frontend Architecture

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
  shared/widgets/      design-system components
  features/
    onboarding/        splash, welcome/language, consent, role selection
    authentication/    AuthApi, AuthRepository, Session model, SessionController, parent auth screen
    child_profile/     FamilyApi/Repository, Family & ChildProfile models, create-child screen, consent sync
    parent_dashboard/  parent home (family setup, children, start child mode, new mission)
    missions/          MissionsApi/Repository, Task/Category/Submission models, child home, list, detail, submit, waiting
    progress/          ProgressApi/Repository, ChildProgress model
  l10n/                app_en.arb, app_gu.arb, app_hi.arb (+ generated)
```

Features without code yet (approvals, garden, rewards, learning, settings) have
no empty placeholder folders; they are added when their slice starts.

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
/child (shell: Home | Missions)
  /child/missions/:taskId → /child/missions/:taskId/submit → /child/missions/:taskId/waiting
```

`redirect` reads `AppGateState` (language chosen, consent acknowledged,
session role) so deep links cannot skip onboarding or cross roles.

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

## Security notes

- The Flutter app contains no database URL, JWT secret, or server keys.
- Root `.env` (holds `DATABASE_URL`, `JWT_SECRET_KEY`) is gitignored; verify it
  was never committed and rotate if it was.
- Android release signing is not configured; debug signing only.
- Cleartext HTTP is not enabled; use HTTPS for the API.

## Verification status (2026-10-12)

- `dart format --set-exit-if-changed lib test`: clean. `flutter analyze`: no issues.
- `flutter test`: 260 tests, all passing (unit, repository, controller, widget,
  end-to-end flow, and 170 responsive cases).
- `flutter build apk --debug`: **failed — C: drive had 1.35 GB free** ("There is not
  enough space on the disk"). Not a code error. Free space or set
  `GRADLE_USER_HOME` to a larger drive, then rebuild.
- Not run on a device or emulator. No emulator was running, and some Android SDK
  licences are not accepted (`flutter doctor --android-licenses`).
- Gujarati and Hindi strings were machine-written and need review by a native
  speaker.

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
