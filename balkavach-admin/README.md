# Bal Kavach Admin (Flutter Web)

Administration panel for the Bal Kavach AI backend. English-only, desktop-first,
responsive down to phone width.

## What it manages

Users and administrator roles · families and children · missions · mission
categories · preset mission ideas · rewards and (read-only) reward requests ·
learning content (admin-curated https links, per language) · badges · app
settings (consent document version, maintenance notice) · audit log · dashboard
with activity analytics.

Every section is hidden unless the signed-in administrator holds its permission
(`GET /admin/me`), and the server enforces the same permissions independently.
Every change is recorded in the audit log by the server.

## Run

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
flutter build web --release --dart-define=API_BASE_URL=https://your-api-host
```

The backend must list the panel's origin in `CORS_ORIGINS`. Create the first
administrator with `python -m app.cli create-admin` (see `docs/backend-operations.md`).

## Security notes

- Tokens are held **in memory only**; reloading the page signs out. Nothing
  sensitive is written to browser storage.
- Parent and child accounts are refused at sign-in (`not_admin`) before any admin
  request is made.
- Access tokens renew with the refresh token; a refused renewal returns to sign-in.

## Tests

```bash
flutter analyze && flutter test          # 30 tests with a fake HTTP layer
flutter test test/live_contract_test.dart \
  --dart-define=LIVE_API_BASE_URL=http://127.0.0.1:8765 \
  --dart-define=LIVE_ADMIN_EMAIL=… --dart-define=LIVE_ADMIN_PASSWORD=…
```

The second command is opt-in and drives the real API layer against a disposable
backend.
