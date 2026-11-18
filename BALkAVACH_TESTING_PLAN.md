# BalKavach AI — Testing Plan

**Baseline:** commit `58b3545`, audit dated 2026-11-18.
**Status of evidence:** every test count in this document is a **static count of test functions/files**. **No test was executed during the audit** (`pytest` not installed here, `TEST_DATABASE_URL` unset, Flutter suites not run to avoid `pub get` side effects). The first deliverable of Phase 0 is a real baseline run; until then nothing below may be described as "passing".
Finding IDs refer to `BALkAVACH_GAP_ANALYSIS.md`.

---

## 1. Ground rules

1. **Never run tests against the production database.** The backend harness already refuses a `TEST_DATABASE_URL` that equals `DATABASE_URL` or whose database name lacks "test" (`tests/conftest.py`). Keep that guard.
2. DB tests run inside a rolled-back transaction (`isolated_test_session`); no data survives. Tests that need time travel inject `now_utc` (services already accept it) — do not `sleep`.
3. A skipped DB test counts as a **failure in CI** (Phase 0). Skips caused by missing migrations (`pytest.skip("Migration 00xx is not applied…")`) mean the test DB is stale.
4. Each fixed bug gets a regression test written **first** and shown failing.
5. Evidence log: for every manual test, record date, build/commit, device, OS version, locale, result, screenshot/video path.
6. Do not claim a phase done on mocked tests alone for playback, push and fullscreen: those need real devices (§6).

## 2. Environments and commands (to be run in Phase 0 — not yet run)

| Target | Setup | Command |
|---|---|---|
| Backend unit + DB | Python 3.12 venv; `pip install -r requirements.txt`; disposable Postgres `balkavach_test`; `ALLOW_SCHEMA_MIGRATIONS=true alembic upgrade head` **against the test DB only**; set `TEST_DATABASE_URL`, `JWT_SECRET_KEY` (test value) | `pytest -q -rs` (read the skip summary) |
| Backend with Redis | local Redis for limiter tests, `REDIS_URL` | `pytest -q tests/test_rate_limit.py tests/test_auth_security.py` plus new limiter tests |
| Frontend | `flutter pub get` | `flutter analyze` then `flutter test` |
| Admin | `flutter pub get` | `flutter analyze` then `flutter test` (the live-contract test stays opt-in, local disposable backend only) |
| Contract | OpenAPI baseline `tests/contracts/openapi_baseline.json` | `pytest tests/test_api_contract.py`; update baseline only in deliberate API-change PRs |

## 3. Backend tests

### 3.1 Existing suite (static inventory)

337 test functions in 30 files. Highlights: `test_api_auth_sessions.py` (14: refresh rotation, reuse revoke, logout, child-never-parent, deactivated child), `test_streak_system.py` (17), `test_mission_video_entitlements.py` (17), `test_video_access_rules.py` (12), `test_api_push.py` (15), `test_api_youtube.py` (38), `test_youtube_rules.py` (47), `test_youtube_auto_review.py` (36), `test_api_mission_flow.py` (12), `test_api_rewards_flow.py` (10). Pure tests that need no DB: `test_daily_mission_service.py`, `test_rate_limit.py`, `test_auth_security.py`, `test_video_classification.py`, parts of streak/video rules.

### 3.2 New: mission lifecycle (MIS-01…MIS-12) — `tests/test_daily_mission_lifecycle.py`

| Test | Proves |
|---|---|
| `test_today_returns_three_choices_for_each_age_band_and_locale` | choice building, locale fallback, snapshot content |
| `test_choices_are_stable_within_a_day_and_differ_across_days` | determinism seed |
| `test_select_creates_one_task_and_blocks_second_selection` | unique selected-per-day constraint (409) |
| `test_skip_returns_replacement_in_same_response` | **MIS-03** (write first; expected to fail today if the autoflush suspicion is right) |
| `test_skip_limit_per_day` | new cap |
| `test_pool_never_exhausts_over_60_approved_days` | **MIS-02** with a simulated clock |
| `test_template_not_repeated_within_cooldown_but_returns_after` | rotation |
| `test_surprise_cadence` | surprise rule |
| `test_variation_key_rotation_avoids_recent` | MIS-06 |
| `test_approval_after_midnight_counts_for_mission_day` | **MIS-04**, with `Asia/Kolkata` and a DST zone |
| `test_late_approval_entitlement_still_usable` | VID-05 minimum validity |
| `test_streak_and_badges_use_single_source` | **MIS-05** (inline calculation removed; badge streak == `get_streak_summary`) |
| `test_only_daily_mission_tasks_grant_video_time` | **MIS-08** (per decision D3) |
| `test_child_without_dob_gets_clear_error`, `test_age_3_and_16_behaviour` | MIS-09 |
| `test_concurrent_select_requests_are_serialised` | row-lock correctness (two sessions) |
| `test_double_submit_is_rejected_and_not_double_rewarded` | idempotency keys |
| `test_publish_requires_nine_complete_variations_and_edit_unpublishes` | admin rules |
| `test_published_content_is_in_correct_script` | script-range lint for gu/hi (**MIS-01**) |

### 3.3 New: video entitlement and playback anti-bypass — `tests/test_playback_enforcement.py`

Maps one-to-one to the §4 "must not allow" list:

| Threat | Test |
|---|---|
| Restart app | `test_remaining_time_survives_new_session_and_new_token` |
| Switch device | `test_second_device_cannot_hold_a_ticket_while_first_active` |
| Switch account | `test_each_child_has_independent_budget_and_sibling_cannot_use_it` |
| Background/paused counted | `test_no_heartbeat_for_45s_closes_ticket_and_stops_credit`; `test_is_playing_false_does_not_credit` |
| Repeated calls mint time | `test_grant_is_idempotent_per_submission`, `test_daily_cap_blocks_extra_grants`, `test_repeated_play_calls_do_not_extend_ticket` |
| Clock manipulation | `test_client_supplied_timestamps_are_ignored` (no client time accepted) |
| Double deduction | `test_only_one_code_path_mutates_consumed_seconds` (grep-style structural test + behavioural test using both endpoints, must be impossible) |
| Server hands out IDs when exhausted | `test_feed_and_play_withhold_playable_id_when_remaining_zero` (**VID-01**) |
| Expiry | `test_entitlement_expiry_midnight_dst_asia_kolkata_and_us_dst` |
| Exhausted position saved | `test_exhausted_progress_still_saves_position` (VID-08) |
| Notifications | `test_low_time_and_time_up_created_once_per_day` (VID-07) |
| Free allowance rule | `test_free_allowance_per_decision_D1` |
| Timezone default | `test_registration_captures_timezone`, `test_unset_timezone_warns` (VID-04) |

### 3.4 New: authentication and authorisation — `tests/test_security_parent_mode.py`

| Test | Proves |
|---|---|
| `test_parent_mode_requires_child_bearer_and_pin` | SEC-01 |
| `test_no_endpoint_mints_parent_session_from_email_and_pin_only` | removal of the old route (or deprecated alias returns 410) |
| `test_pin_lockout_is_per_account_not_per_ip` | rotate `X-Forwarded-For` / client IPs, still locked |
| `test_lockout_expires_and_doubles` | backoff |
| `test_wrong_pin_attempts_notify_parent_and_write_audit` | alert/audit |
| `test_child_mode_cannot_start_without_pin` | SEC-02 |
| `test_pin_change_requires_current_secret` | SEC-07 |
| `test_child_token_gets_403_on_every_parent_route` | generated from `app.routes`: every route depending on `require_parent` is called with a child token |
| `test_parent_token_gets_403_on_child_only_routes` | reverse |
| `test_admin_routes_require_permissions_matrix` | permission mapping, including aliases (`videos.create`→`video:write`) |
| `test_ownership_idor_matrix` | for each `{child_id}/{family_id}/{upload_id}/{notification_id}` route, a second family's parent/child gets 404 |
| `test_tokens_without_sid_rejected_in_production` | SEC-06 |
| `test_password_reset_flow_and_session_revocation`, `test_reset_token_single_use_and_expiry`, `test_forgot_does_not_reveal_account_existence` | SEC-04 |
| `test_change_password_revokes_other_sessions`, `test_logout_all`, `test_account_delete_and_export` | SEC-05 |
| `test_limiter_fails_closed_without_redis` (exists as unit) + `test_limiter_keys_use_forwarded_ip_only_from_trusted_proxy` | SEC-03 |
| `test_register_login_do_not_leak_timing_or_messages` | enumeration |

### 3.5 New: trusted-channel moderation

Extend `test_youtube_rules.py` / `test_api_youtube.py`: status transitions (pending→approved→suspended→revoked), `approved_by/at`, counts match the underlying reviews, **a trusted channel cannot auto-publish** a video that is flagged, not made-for-kids, age-restricted, too long or region-blocked, suspend hides items from `/videos/feed|shorts` in the next request, revoke quarantines automatic publications, history endpoint order, duplicate channel/video prevention, recheck moves changed videos to quarantine, scheduler-health flag after 48 h, Hindi/Gujarati denylist hits.

### 3.6 New: notifications

Dispatcher with a fake provider (`ok`, `invalid_token`, `retry`, `error`): delivery rows, retry/backoff, token deactivation; scheduler idempotency (same job twice = one notification), per-family-timezone send times incl. DST, quiet hours and category preferences, parent vs child audience mapping, localised rendering (en/gu/hi), payload has `route` and no personal data, notification list is recipient-scoped.

### 3.7 Contract and migration tests

* `tests/test_api_contract.py` OpenAPI baseline: updated deliberately in Phases 1, 3, 8.
* Migration test: upgrade empty DB to head, `downgrade -1`/`upgrade head` for each new migration, and assert `get_model` resolves every `MODEL_TABLES` name (OPS-03). Single-head assertion (`alembic heads` == 1).
* Seed/content test: no template published unless 9 complete variations (see §3.2).

## 4. Flutter (child/parent app) tests

Existing: 41 test files (`test/core`, `features`, `widgets`, `responsive`, `localization`, `integration`, helpers incl. fake backend and fake video players). Add:

| Area | New tests |
|---|---|
| Parent gate | PIN pad widget test (no email field, lock-out message, offline error, large text), router test that child session can never navigate to `/parent/*` (extends `route_guard_test.dart`), "no PIN → cannot start child mode" flow |
| Session | token refresh during playback, sign-out hooks, push unregister on mode switch |
| Missions | `/active`, skip, history, weekly widgets; 503/422 states; choice cards at widths 320/360/412/600 (no overflow) |
| Lock UI | pre-launch gate, exhausted dialog, resume, mascot message per language |
| Player | YouTube embed fake: ended → suggestions overlay; fullscreen enter/exit changes layout for both MP4 and embed fakes; orientation change keeps playback position; description not rendered |
| Companion | state machine unit tests (anti-repeat, cooldown, event mapping), golden per locale, reduced-motion |
| Notifications | deep-link routing from `RemoteMessage`, cold start (`getInitialMessage`), role mismatch fallback, inbox rendering, permission-denied banner |
| Share | share card golden (en/gu/hi), WhatsApp availability fallback, privacy toggle |
| Localization | extend `localization_audit_test.dart`: ARB key parity (632/632/632 today), no English fallback strings on key screens, pseudo-locale with +40 % text length |

## 5. Admin tests

Existing: 5 files (`admin_test.dart`, `localization_ui_test.dart`, `youtube_reviews_test.dart`, helpers, opt-in `live_contract_test.dart`). Add: Trusted Channels page (list/filter/detail/suspend/revoke/history/counts), mission editor (create/preview/locale completeness/publish), notification admin page, **hard-coded-string guard** (fails on new literals in `lib/pages`), permission gating of each action, width tests at 360/768/1280/1920.

## 6. Device, responsive, accessibility and performance (manual + automated)

### 6.1 Device matrix (minimum)

| Class | Example | OS | Notes |
|---|---|---|---|
| Low-end phone | 2–3 GB RAM, 720×1600 | Android 9–10 | performance baseline, animation fps |
| Mainstream phone | 6 GB, 1080×2400 | Android 13/14 | primary target |
| Small phone | 320–360 dp wide | any | overflow checks |
| Tablet | 600–840 dp | Android 12+ | navigation rail, 2-column layouts |
| Foldable / split-screen | resizing window | Android 13+ | rotate + resize |
| Admin browsers | Chrome, Edge, Firefox, Safari | desktop widths 1024/1280/1920, 768 tablet | |
| Notification device | real device with Google Play services | | FCM requires real device |

### 6.2 Responsive/overflow sweep

For each primary screen — child Home/Watch, Missions, Mission detail/submit/waiting, Rewards, Garden, Profile, Streak, Weekly report, Parent Hub, Approvals, Create mission, Rewards, Settings, Auth, Onboarding, Admin Dashboard/Missions/Trusted Channels/Users — test at widths **320, 360, 412, 600, 840 dp**, portrait and landscape, **text scale 1.0 / 1.3 / 2.0**, **locales en/gu/hi**. Pass = no overflow stripes, no clipped buttons, all actions reachable by scroll, touch targets ≥ 48 dp. Capture screenshots into the evidence log. Automate via the existing `responsive_screens_test.dart` pattern plus golden tests where stable.

### 6.3 Playback, orientation and fullscreen reproduction matrix (answers FEED-03)

Run **before** Phase 8 changes (during 3-QW) and after.

| Content | Duration | Source | Player | Rotate device | Fullscreen | Expected |
|---|---|---|---|---|---|---|
| Landscape 16:9 | 45 s | YouTube | Shorts feed | portrait/landscape | n/a | currently expected to be letterboxed; after Phase 8 it appears in the regular feed |
| Landscape 16:9 | 8 min | YouTube | Detail | yes | embed button and app button | video fills width, controls usable, exits cleanly |
| Landscape | 8 min | MP4 | Detail | yes | app button | landscape lock applied/released |
| Portrait 9:16 | 40 s | YouTube | Shorts feed | yes | n/a | fills screen |
| Portrait 9:16 | 5 min | YouTube | Detail | yes | yes | not tiny; sensible layout |
| Non-embeddable | any | YouTube | Detail | — | — | friendly blocked notice, can report, continue to next |
| Exhausted allowance | any | any | any | — | — | pre-launch gate; no playback |
For each case record: plays? correct aspect? controls reachable? layout after rotate? position preserved? heartbeat sent (check server log)? Collect screen recording and device/OS/WebView versions (the Android System WebView version matters for the IFrame player).

### 6.4 Localization

Native Gujarati and Hindi reviewers walk the golden path with the companion lines and mission content; check script correctness (no romanised text), line breaks, clipped diacritics, numerals and date formats.

### 6.5 Accessibility

TalkBack walkthrough of login, parent gate, mission select/submit, lock screen; contrast check; focus order; reduced-motion; dynamic text scale 2.0.

### 6.6 Performance

Profile mode on the low-end device: cold start time, feed scroll jank (frame build/raster times), memory while swiping 30 Shorts, battery/thermal during 15 min playback, companion animation fps, network calls per screen (record with a proxy; flag duplicates such as repeated allowance fetches), image cache size.

## 7. End-to-end scenarios (scripted, run on staging with a disposable family)

1. **Golden path:** parent registers → sets timezone/PIN → adds child (with DOB) → child logs in → companion greets → picks mission → submits → parent approval push → approves → child sees "15 minutes unlocked" → watches → low-time warning → time-up lock → next-day new missions and streak shows correct state.
2. **Late approval:** submit 23:50, approve 08:00 → streak/time per decision D2.
3. **Parent mode attack:** child tries PIN guesses from several IPs → lockout, parent alert.
4. **Device swap mid-play:** play on A, start on B → B refused with friendly message.
5. **Offline/airplane during playback:** credit stops; resume works.
6. **Trusted channel:** add → review → approve → sync → counts → suspend → videos disappear → revoke.
7. **Notification schedule:** set a test timezone, observe morning/waiting/weekly pushes and deep links.
8. **Referral:** share → install via link → register → single reward.
9. **Data lifecycle:** export, delete account, verify sessions revoked and data purged per policy.

## 8. Security test checklist

OWASP ASVS-aligned manual checks: authentication (brute force, lockout, enumeration, reset flows), session management (rotation, reuse detection, logout, revocation on password change), access control (IDOR matrix in §3.4), input validation (uploads: EXIF stripping/size/type — existing `test_api_uploads.py` 16 tests), rate limiting behind the real proxy (verify client IP derivation on staging), CORS exact origins, secrets handling (no keys in the app bundle; Firebase config public only), dependency scan (`pip-audit`, `flutter pub outdated`), transport security (HTTPS only, no cleartext), logging (no tokens/PIN/PII in logs), admin permission matrix. Re-test SEC-08 remediation (SSH hardening).

## 9. Release gates

| Gate | Condition |
|---|---|
| G0 | Baseline run recorded; DB suite 0 skipped |
| G1 (after Phase 1) | All SEC tests pass; manual parent-mode attack scenario passed on staging; no P0 security items |
| G2 (after Phase 2–3) | Mission lifecycle + playback enforcement suites pass; manual §6.3 matrix recorded; double-writer test present |
| G3 (before store release) | §6.2 sweep clean on the device matrix; localization sign-off; accessibility pass; performance budget met; scheduler monitoring verified in production; Firebase push verified on a real device |
| Evidence | A table of test name → run date → commit → result is attached to each release; unrun items are listed as **not run**, never omitted |

## 10. Evidence log template

| Date | Commit/build | Area | Test / scenario | Device & OS | Locale | Result | Evidence link | Notes |
|---|---|---|---|---|---|---|---|---|
