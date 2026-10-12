# Bal Kavach AI — Flutter app

Android-first Flutter client for the BalKavach FastAPI backend
(`../balkavach-backend`). Design reference: `../stitch_bal_kavach_ai_mobile_app`.

Architecture, design system, API contracts and blockers are documented in
[`../docs/`](../docs/).

## Run

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=https://balkavach-ai-app.onrender.com
```

`API_BASE_URL` defaults to the deployed API. Point it at a local backend with
e.g. `--dart-define=API_BASE_URL=http://10.0.2.2:8000` (Android emulator →
host machine; cleartext HTTP must then be allowed for debug builds).

Never put database URLs, JWT secrets or other server credentials in this app.

## Check

```sh
dart format --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
```

`flutter gen-l10n` regenerates `lib/l10n/app_localizations*.dart` from the ARB
files (it also runs automatically on `pub get`).
