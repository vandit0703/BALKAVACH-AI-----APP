# Real-device bugs of 2026-11-26: fix report

Date: 2026-11-26 · Branch `main` · HEAD `e4ca3d3` ("fix"). All changes are uncommitted. Nothing was committed, pushed, deployed or migrated, and no production database or service was touched.

## Summary

| Issue | Root cause | Fix | Tests | Status |
|---|---|---|---|---|
| P0 Parent approval fails ("The approval could not be saved") | Production now runs the build that restores the mission video grant. Approvals worked while the grant was removed (22 to 26 Nov) and fail since it came back. The most likely cause is a production database rule that rejects the grant row. **Not confirmed.** | None yet. Migration 0023 waits for production evidence (see [Approval failure](#p0-approval-fails-and-approved-mission-does-not-unlock-video-time)). | 5 new log-signature tests | BLOCKED |
| P0 Approved mission does not unlock video time | Same cause: every approval rolls back as a whole, video grant included. Missions approved during 22 to 26 Nov earned no time. | Same as above. | Same as above | BLOCKED |
| P0 Floating mini-player with music videos | Not produced by BALKAVACH: there is no Picture-in-Picture or overlay code. It is most likely the YouTube app's own floating player. | Children can no longer leave BALKAVACH for YouTube (see YouTube link-out). | 7 tests | NOT A BALKAVACH BUG (no device check) |
| YouTube link-out for children | A child could leave for the YouTube app once a grown-up tapped OK, or share a watch link that opens it. | Blocked in child sessions. Parent sessions keep the grown-up confirmation. | 7 tests | FIXED in code |
| P1 Child interest request never reaches the parent | The request was saved but no notification, push or badge was created. Parents only saw it inside that child's profile. | Every active family parent gets an `interest_requested` notification in the same transaction as the request. | 6 tests | FIXED in code |
| P1 Panda voice needs a grown-up's OK | A one-time parent consent per child (not per session), because the system recogniser can send audio to Google. | Option B: on-device recognition needs no grown-up step. The cloud recogniser still needs consent. A parent who turns voice off still stops all voice. | 14 tests | FIXED in code (needs device check) |

"FIXED in code" means the change is in place and its tests pass. None of it has been verified on a real device.

## P0: approval fails and approved mission does not unlock video time

### What the evidence shows
- The app's message comes from backend error `500 approval_failed`, raised by `_all_or_nothing` in `task_service.py` when an unexpected exception occurs inside the approval transaction. Everything is rolled back, so nothing is half-awarded.
- It is not a missing migration 0013. That case returns `503 video_allowance_unavailable` with a different message.
- Production runs a build with the grant restored. Its public `/openapi.json` (207 operations) has `VideoAllowancePublic.free_allowance_seconds` defaulting to 0, which matches `1d968cf` and `e4ca3d3`.
- Timeline:
  - `960926c` (22 Nov) removed the grant. Approvals then succeeded, which is why the child's screen shows earlier "Approved" missions, but those approvals paid no video time.
  - `e4ca3d3` (26 Nov) restored the grant. Approvals now fail.
- The same approval passes on local PostgreSQL (30/30 approval tests). The difference is therefore in production's schema, which is not in the repository (`docs/parent-approval-troubleshooting.md` lists the assumptions).

### Leading hypothesis (unconfirmed)
A production rule on `video_access_entitlements` requires a video target (`video_id` or `video_collection_id`). The mission grant writes both as NULL, because a mission reward is time for any video. Migration 0013 does not relax such a rule. The star-redemption path always sets a target, so a rule like this would never have shown up before.

### Evidence needed (read-only)
The server already logs the failing rule (SQLSTATE plus constraint, table and column names, never row values) on every rolled-back approval. One line from a failed tap settles it:

```
journalctl -u <balkavach-api-service> --since "2026-11-26 17:45" | grep "Mission approval failed and was rolled back"
```

| Log contains | Cause | What migration 0023 would do |
|---|---|---|
| `sqlstate=23514 constraint=<name> table=video_access_entitlements` | CHECK requiring a video target | Narrow the CHECK so it does not apply to `source_type = 'mission_reward'` |
| `sqlstate=23502 … column=video_id` (or `redemption_id`) | NOT NULL on that column | Drop the NOT NULL |
| `sqlstate=23502 … column=expires_at` | NOT NULL on `expires_at` | Drop the NOT NULL, or have the code set an expiry |
| `sqlstate=23514 … table=notifications` | CHECK on notification types | Widen the allowed types |

Alternatively, an operator can run query B in `docs/parent-approval-troubleshooting.md` (`pg_constraint` for `video_access_entitlements`) with a read-only role.

### Work done
- `tests/test_parent_approval_postgres.py`: `test_each_candidate_production_rule_leaves_a_distinct_log_signature` installs each candidate rule inside a rolled-back transaction on the local test database. For each one it checks that approval returns `500 approval_failed`, writes nothing, and logs the signature in the table above. All 5 pass.
- No migration was drafted, as instructed.
- No back-fill of missions approved without video time. That would be a production data change, which is the owner's decision.

## Floating mini-player

- The BALKAVACH manifest declares no `supportsPictureInPicture` and no `SYSTEM_ALERT_WINDOW`.
- `MainActivity` had no Picture-in-Picture code.
- The Flutter code has no mini-player, floating window or persistent overlay.
- The window floats over every screen, including a modal bottom sheet, and shows T-Series music videos that are not in the catalogue. That is how Android's system Picture-in-Picture looks.
- BALKAVACH cannot control another app's Picture-in-Picture window.
- The one route from BALKAVACH into that app was the grown-up-gated "open in YouTube" link. It is now closed for children (next section).

Not done: no device was attached, so the owning package was not identified. To identify it, run `adb shell dumpsys activity activities | grep -i -A3 pinned` while the window is showing.

What families can do on Android: turn off Picture-in-Picture for the YouTube app (Settings › Apps › Special app access › Picture-in-picture), and use Family Link or YouTube Kids on a child's device.

## YouTube link-out disabled for child sessions

In a child session (`session.isChild`):

| Entry point | Before | Now |
|---|---|---|
| A link inside the YouTube player (feed, Shorts, detail player) | A grown-up confirmed, then the YouTube app opened | Nothing opens; message "Videos play only inside BALKAVACH, so this link stays closed." |
| Share on a video | A grown-up confirmed, then the share sheet offered the watch link (which opens the YouTube app) | Nothing is shared; message "Sharing videos is turned off for children." |
| A YouTube link on the learning detail screen | Opened in the browser or the YouTube app | Nothing opens; the same message is shown |

- If the session is still loading, the check waits for it. If it cannot be read, the check answers "child" (fail closed).
- Parent sessions keep the grown-up confirmation dialog.
- Non-YouTube learning links (for example articles) still open in the browser.

## Interest requests reach the parent

- "Interest request" is the existing flow: the child picks topics on the profile and calls `POST /api/v1/videos/interests/request`. The request is stored in `child_profiles.pending_interest_requests` (migration 0022), and the parent approves or rejects it on the child's profile (`PUT /families/{family}/children/{child}/interests`). No new feature was added.
- New in `request_video_interests`, in the same transaction as the stored request:
  - one `interest_requested` notification for each active parent in the child's family (`family_parent_ids`);
  - in-app text: "{child} asked to watch new topics. Open their profile to review the request.";
  - the notification raises the parent's bell badge.
- Repeating the same request notifies no one again. A different request is new information and does notify.
- The push is staged and sent only after commit. A push failure (for example FCM unavailable) cannot undo the request.
- The push text is generic, so no child name shows on a lock screen: "New topic request / Your child asked to watch new topics." (en, hi, gu).
- The type belongs to the existing **Mission approvals** preference category, so a parent who switched that category off gets no push. The in-app notification is still created.
- Tapping the notification opens the parent home: notifications have no child-id field, so it cannot open that child's profile directly.
- Unchanged: an invalid or empty request is refused (422) and creates no notification, and parents of other families are never notified.

## Panda voice: option B (on-device recognition)

### Rules
| Phone | Parent consent record | Parent turned voice off | Voice allowed? | Recogniser |
|---|---|---|---|---|
| Has on-device recognition | not needed | no | Yes, with no grown-up step | On-device (audio stays on the phone) |
| Has on-device recognition | any | yes | No; message "A grown-up has turned off talking out loud to Panda" | — |
| No on-device recognition | granted | no | Yes | System (cloud) |
| No on-device recognition | none | no | No; the existing "needs a grown-up's OK" message | — |

- Android's microphone permission always applies: the system prompt is shown on first use, and a denial leads to a friendly message plus typed chat.
- Typed chat always works.
- No audio or transcript is stored. Server safety filters and reply rules are unchanged.

### Why a native check was needed
`speech_to_text` 7.5.0 treats `onDevice: true` as a preference. When the phone has no on-device recogniser (Android below 12, or no on-device service installed), it **silently creates the cloud recogniser instead** (`SpeechToTextPlugin.kt`, `createRecognizer`). The app therefore:
- asks Android first, through a new `balkavach/speech` channel in `MainActivity` (`onDeviceAvailable` returns true only when the API level is at least 31 and `SpeechRecognizer.isOnDeviceRecognitionAvailable` is true, the same check the plugin uses);
- passes `onDevice: true` only when that answer is yes;
- checks again right before the mic opens: if on-device recognition is no longer available, the cloud rules apply;
- never retries a failed on-device listen through the cloud recogniser. The child is offered typing instead.

### Backend
- `CompanionChatRequest` has a new `speech` field: `"on_device"` or `"cloud"` (default `"cloud"`, so voice turns from older apps keep the old rule).
- Voice turns:
  - on-device turns are allowed unless a parent turned voice off (`panda_voice_consent_service.is_refused`);
  - cloud turns need the current consent, as before.
  - Both are refused with `403 panda_voice_consent_required`.
- `GET /companion/voice-consent` now also returns `refused`.
- "Refused" means no grant is in force **and** the newest `panda_voice` record was withdrawn. "No record yet" and "grant for an older consent text" are not refusals.
- No schema change: it uses the existing `consent_records`.

**Deployment order:** the backend must be deployed before the new app. An older backend ignores `speech` and refuses every voice turn without consent.

### Copy
When the on-device recogniser will be used, the microphone explanation reads: "Your phone turns your words into text right here on the phone, so your voice is not sent anywhere." Otherwise the existing explanation is shown, which names Google. Both are in en, hi and gu.

### Known limits
- Hindi and Gujarati on-device language packs may be missing. Those children then get typed chat, or the cloud recogniser if a parent consented.
- Whether "on-device recognition needs no parental consent" meets India's DPDP Act and similar rules is a legal question. This change follows the owner's decision (option B) and has had no legal review.

## Files changed

Backend (`balkavach-backend/`)
- `app/api/v1/videos.py`: interest request notifies family parents (deduplicated, same transaction).
- `app/services/push_service.py`: `interest_requested` push text (en/hi/gu).
- `app/services/notification_preferences_service.py`: `interest_requested` added to the `mission_reviews` category.
- `app/schemas/companion.py`: `speech` on chat requests; `refused` on the child consent view.
- `app/services/panda_voice_consent_service.py`: `is_refused`, `voice_turn_allowed`.
- `app/api/v1/companion.py`: voice turns use `voice_turn_allowed`; consent view returns `refused`.
- Tests:
  - `tests/test_parent_interest_management_pg.py`: +6.
  - `tests/test_panda_voice_consent.py`: +6.
  - `tests/test_parent_approval_postgres.py`: +5 parametrised cases.

Frontend (`balkavach-frontend/`)
- `android/app/src/main/kotlin/com/balkavach/balkavach_app/MainActivity.kt`: `balkavach/speech` `onDeviceAvailable` channel.
- `lib/features/companion/data/speech_services.dart`: `onDeviceAvailable()`; `listen(onDevice:)`.
- `lib/features/companion/data/companion_chat_repository.dart`: sends `speech`; `voiceConsentStatus()` returns `PandaVoiceConsent(granted, refused)`.
- `lib/features/companion/domain/panda_interaction.dart`: option B rules, re-check before listening, `voiceTurnedOff` problem, `onDeviceSpeech` state.
- `lib/features/companion/presentation/panda_talk_sheet.dart`: turned-off message; explanation matching the recogniser.
- `lib/features/learning/presentation/widgets/video_actions.dart`: `isChildSession`; leave and share blocked for children.
- `lib/features/learning/presentation/learning_screen.dart`: YouTube links blocked for children.
- `lib/shared/platform/link_opener.dart`: `isYouTubeUri`.
- `lib/l10n/app_{en,hi,gu}.arb` and generated `app_localizations*.dart`: `pandaVoiceTurnedOff`, `pandaMicExplainBodyOnDevice`, `youtubeLeaveBlocked`, `videoShareBlocked`.
- Tests:
  - `test/features/panda_talk_test.dart`: +8; fakes updated.
  - `test/features/home_profile_panda_test.dart`: fake updated.
  - `test/features/shorts_feed_test.dart`: 2 rewritten for child sessions.
  - `test/features/video_feed_test.dart`: 1 rewritten, 1 parent-session test added.
  - `test/widgets/video_detail_player_test.dart`: 1 rewritten.
  - `test/features/learning_test.dart`: +1.

No API route was removed or renamed. New request and response fields have defaults, so older apps and servers keep working. No migration was added.

## Tests and results

Local only, run on 2026-11-26. PostgreSQL is the local `scripts/testenv.py` cluster loaded with `tests/schema/reconstructed_baseline.sql`, which is a reconstruction and **not** production's schema.

```
cd balkavach-backend
TEST_DATABASE_URL=postgresql+psycopg://postgres:@127.0.0.1:55432/balkavach_test REDIS_URL=redis://127.0.0.1:56379/0 \
  .venv/Scripts/python -m pytest <files>
```

| Run | Result |
|---|---|
| `test_parent_interest_management_pg.py`, `test_interests_and_allowance_contract.py`, `test_api_push.py` | 48 passed |
| Every backend test file that references notification types or push templates, plus the interest file | 42 failed, 240 passed. Every failure also fails on HEAD (same files, compared before and after); none is new |
| `test_panda_voice_consent.py` plus every test file that references the companion | 103 passed |
| `test_mission_approval_video_grant.py`, `test_parent_mission_approval.py` | 30 passed |
| `test_parent_approval_postgres.py` | 23 passed, 5 failed. The 5 new signature tests pass. The 5 failures predate this work and are in code this change does not touch: 4 concurrency tests expect fixed 10 stars / 15 XP while approval pays the task's configured amounts (an open product question), and 1 fails because migration 0022 hits `DuplicateColumn` on the reconstructed schema |
| `flutter test test/features/panda_talk_test.dart test/features/home_profile_panda_test.dart` | 85 passed |
| `flutter test` on the shorts feed, video feed, learning and Shorts navigation suites | 114 passed |
| `flutter test test/widgets/video_detail_player_test.dart` | 36 passed |
| `flutter test -j 2` (whole suite) | Completed with 1 failure (the detail-player link test), since rewritten and passing. Two later full runs crashed on this machine's memory and thread limits ("Out of memory", "Could not start thread"), not on a test |
| `flutter analyze` | 2 info-level issues, both in test files this change does not touch |

Not run: no APK build, no integration tests on a device or emulator, and no real-device verification.

## Manual real-device checks
1. Android 12+ phone with on-device recognition, child signed in, no Panda consent:
   - tap the mic and allow the permission;
   - Panda hears and answers;
   - the explanation does not mention Google.
2. Same phone: a parent turns Panda voice off in Settings → the child sees the "turned off" message, and typing works.
3. Phone without on-device recognition (or Android 11): no consent shows the "needs a grown-up's OK" message; after consent, voice works.
4. Deny the microphone permission → friendly message and text box. With "Don't ask again", the same result with no prompt.
5. Child session, playing a video:
   - tap the YouTube logo or title in the player → the message appears and the YouTube app does not open;
   - Share → the message appears and no share sheet opens.
6. Parent session: the same taps show the grown-up dialog.
7. Child sends an interest request → each parent's bell shows "New topic request", and a push arrives if FCM is configured on the server.
8. After migration 0023 (once written): parent approves a mission → the child's Home unlocks with 15 minutes.

## Production steps (each needs the owner's separate approval)
1. Collect the approval log line (or query B) and share it, so migration 0023 can be written for the real rule and tested locally.
2. Deploy the backend, then release the app. The order matters for Panda voice.
3. Run migration 0023 in production once it has been reviewed.
4. Decide whether to back-fill video time for missions approved from 22 to 26 Nov.
5. Configure FCM on the VPS so interest-request pushes are delivered (`docs/FCM_FIREBASE_CLI_AUDIT.md`).

---

# Follow-up review (2026-11-26 evening)

HEAD `8b2090b` ("check", committed by the owner at 18:46; it contains everything above plus `google-services.json`). The changes below are uncommitted on top of it. Nothing was deployed, pushed or migrated, and no production system was touched. The approval/video issue stays **BLOCKED** until the production journal line gives the SQLSTATE, constraint, table and column.

## 1. Reward contract: fixed 10 Stars / 15 XP

**Decision (from the existing product documents and code, not invented here):** one approved mission pays **10 Stars and 15 XP**.
- `mission_rewards.py` defines `MISSION_STAR_REWARD = 10` and `MISSION_XP_REWARD = 15`.
- The custom-task API, daily missions and the mission library all store exactly those amounts on the task.
- `docs/mission-library-plan.md`, `docs/phase-6-parent-audit-and-plan.md` and `docs/SECURITY_AUDIT.md` (SEC-04) state the rule.

Approval pays the amounts stored on the task. Those are exactly what the parent's review queue shows ("Approve & Award +10").

**What the 4 failing concurrency tests showed:** their fixture inserted a task with 5 Stars / 10 XP straight into the database, a state no creation path can produce. The fixture now uses the product constants. No behaviour was changed to make them pass.

**Two real defects found and fixed while checking the contract:**

| Defect | Fix | Test |
|---|---|---|
| `PATCH /tasks/{id}` applied client-sent `star_reward` / `xp_reward`, so a scripted parent client could make approval pay inflated amounts (SEC-04 on the update path). The existing test `test_a_parent_cannot_change_a_missions_reward` had been failing for this reason. | `app/api/v1/tasks.py`: the update ignores reward fields, as creation already did. Clients that send them still get 200. | `test_api_mission_rewards.py` now passes |
| The queue displays `effective_star_reward(...)` (NULL falls back to 10/15) but approval paid `int(task.star_reward or 0)`. A legacy row without amounts would show +10 and pay 0. | `app/services/task_service.py`: approval uses the same `effective_*` helpers, so the amount paid is always the amount shown. | `test_a_legacy_task_without_reward_amounts_pays_the_default_it_displays` (failed before the fix: 0/0 paid), `test_approval_pays_exactly_what_the_review_queue_shows` |

**Open (owner):** production may hold legacy custom tasks with amounts other than 10/15, created before creation was fixed. They are paid as displayed. Normalising them would be a production data change.

## 2. Migration 0022 `DuplicateColumn`

- **Cause:** the local reconstructed baseline (`tests/schema/reconstructed_baseline.sql`), which is meant to be the schema *before* migration 0001, already contained `redemption_requests.cancelled_at`, a column added only by 0022.
- **Ruled out:** the test does not apply migrations twice. It builds a fresh database, loads the baseline once and runs `upgrade head` once.
- A scan of every migration's `add_column` / `create_table` against the baseline found this as the **only** overlap.
- **Fix:** the column was removed from the reconstructed baseline (a local test asset). No migration file or revision id was changed.
- `test_a_database_without_migration_0013_refuses_approval_before_writing_anything` now builds baseline → head cleanly and passes.
- **Production caution (unchanged):** 0022 is not idempotent (plain `add_column`). Before running it in production, check whether `redemption_requests.cancelled_at` already exists. If it does, 0022 needs a reviewed conditional variant.

## 3. Interest-request notification review

| Criterion | Result |
|---|---|
| Authorization | OK. The child comes from the token. Recipients are active members of that child's own family whose user is an active parent. |
| Transaction safety | OK. The request and notifications commit together. The push is staged and discarded on rollback. |
| Duplicate suppression | **Two weaknesses fixed** in `app/api/v1/videos.py`. (a) The same topics in another order notified again; the comparison is now set-based. (b) Two simultaneous identical requests could both notify; the child row is now locked (`FOR UPDATE`, re-read) before comparing. |
| Multiple parents | Each active parent is notified once; an inactive membership gets nothing (new test). |
| FCM failure | Push runs after commit; provider errors are logged and cannot undo the request (tested). |

A mock-based test (`test_video_recommendations_and_integrity.py::test_child_cannot_bypass_parent_approval_on_interest_request`) had been broken by the earlier notification change and was missed by the first, narrower comparison. Its fakes were extended and it passes.

**Remaining uncertainty:** the row-lock fix has no concurrency test (two simultaneous HTTP requests).

## 4. Panda on-device speech review

**Conclusion:** the app does not use the cloud recogniser unless the parent consented, with one narrow residual risk (below).

- There is exactly one route to the microphone: `PandaTalkSheet._mic` → `PandaTalkController.startListening` → `SpeechInput.listen` → `SpeechToText.listen`.
- `startListening` calls `listen(onDevice: true)` only when the native check (`MainActivity` channel `balkavach/speech`: API ≥ 31 and `SpeechRecognizer.isOnDeviceRecognitionAvailable`) returned true for this tap.
- Otherwise voice requires the server-reported parent consent. Availability is re-checked right before listening.
- A failed on-device listen is never retried through the cloud.
- **Plugin (speech_to_text 7.5.0):**
  - `SpeechListenOptions.onDevice` is forwarded to Android.
  - `intentLookup`, which ignores `onDevice`, is only enabled through `initialize(options:)`, which the app never passes.
  - With `onDevice: true` the plugin creates `createOnDeviceSpeechRecognizer` when the same Android check passes.
- **Residual risk:**
  - The plugin repeats the availability check itself. If on-device recognition vanished in the milliseconds between our check and the plugin's, the plugin would create the cloud recogniser. Closing this completely needs a native recogniser of our own or a plugin patch.
  - The server cannot verify the client's `speech: "on_device"` claim. The control is in the app.
- The Kotlin channel **compiles**: `flutter build apk --debug` produced `build/app/tmp/kotlin-classes/debug/com/balkavach/balkavach_app/MainActivity.class`. The build then failed at `:app:mergeDebugNativeLibs` with "Insufficient system resources" (machine memory), so **no APK was produced**. The channel has not been run on a device.

## 5. Child-session YouTube blocking review

| Entry point | Child session |
|---|---|
| Feed, Shorts and detail players: any link the WebView tries to open outside the player (`decidePlayerNavigation` → `onLeaveRequested` → `askGrownUpThenOpen`) | Blocked with a message |
| Another video loading inside the player | Swapped back to the approved id (`onForeignVideo`); existing behaviour |
| Share on a video (Shorts, detail player) | Blocked |
| YouTube links on the learning detail screen | Blocked |
| Non-YouTube learning links | Still open in the browser (admin-curated content) |
| Rewards "share my progress" | Shares text only, no link, via the system share sheet. Not a YouTube route, but it does open other apps |
| Invite screen | Parent settings only |
| Other `url_launcher` use | None outside `PlatformLinkOpener` |

**Remaining uncertainty:**
- A non-YouTube link that redirects to YouTube in the browser is not blocked.
- Nothing has been checked on a device.

## 6. Test runs

All local. PostgreSQL is the `scripts/testenv.py` cluster with the reconstructed baseline, **not** production's schema.

| Run | Result |
|---|---|
| Full backend suite, current tree | 174 failed, 1300 passed, 1 skipped |
| Full backend suite, `e4ca3d3` (before any of today's changes; clean `git archive` copy, same DB and venv) | 182 failed, 1271 passed, 1 skipped |
| Difference | **No new failures.** 6 fixed (4 concurrency, pre-0013 migration, reward PATCH). Two catalogue-fixture tests differ only because the archived copy lacks the Flutter fixture file. The Redis stand-in stayed up in both runs (0 rate-limiter errors). |
| `test_parent_approval_postgres.py` | 30 passed |
| Interest, contract, integrity and push files | all pass |
| **Full Flutter suite:** 79 files in 10 batches of 8, `flutter test -j 1` per batch | **2,777 passed, 0 failed, no crashes** |
| `flutter analyze` | 2 info-level issues, both in test files this work does not touch |
| `flutter build apk --debug` | **Failed** after 6 min at `:app:mergeDebugNativeLibs`: "Insufficient system resources exist to complete the requested service". Kotlin and Dart compiled before that point; no APK was produced. Retry with Chrome closed and no other Gradle daemon running. |

**Memory:** the earlier full runs crashed because the machine's commit limit was nearly exhausted (Chrome about 3.6 GB, a Gradle/Kotlin daemon about 2.8 GB) and three orphaned `flutter_tester` processes from those crashed runs were still alive. The orphans were stopped. Batching restarts the flutter tool's compiler between batches. The batch runner lives outside the repo and records crashes separately from test failures. To free more memory, close Chrome tabs and run `android/gradlew --stop` when not building.

## 7. Real-device verification checklist

Use one phone on Android 12+ with on-device speech (for example a recent Pixel) and one on Android 11 or without on-device speech. Use two parent accounts in one family, one child account, and a backend that has these changes (see the build plan).

**Panda voice**
1. Android 12+ phone, no consent record: tap the mic → the explanation says the voice stays on the phone (no "Google") → allow the permission → Panda hears and answers.
2. A parent turns Panda voice off in Settings → the child sees "A grown-up has turned off talking…"; typing works.
3. The parent turns it on again → voice works.
4. Android 11 phone without consent → "needs a grown-up's OK"; with consent → voice works (cloud recogniser).
5. Deny the permission; then "Don't ask again" → friendly message and text box, no crash.
6. Hindi and Gujarati on the Android 12+ phone: note whether on-device recognition works, or the child gets typed chat.
7. Airplane mode on the Android 12+ phone: recognition should still produce words (proof that it is on-device); the reply needs the network.

**YouTube**
8. Child session: tap the YouTube logo or title in the feed, Shorts and detail players → message, the YouTube app does not open.
9. Child session: Share on a video → message, no share sheet.
10. Child session: a learning item with a YouTube link → message.
11. Parent session: the same taps show the grown-up dialog.

**Interest requests**
12. The child sends a topic request → both parents get "New topic request" in the bell, and a push if FCM is configured on that server.
13. The child sends the same topics again, or reordered → no second notification.
14. A parent approves on the child's profile → the pending list clears.

**Rewards**
15. A parent approves a mission → the child gets exactly what the button showed (+10 Stars, +15 XP). Video time depends on the blocked production fix.

**Mini-player**
16. If a floating window appears: `adb shell dumpsys activity activities | grep -i -A3 pinned` names the owning app.

## 8. APK build plan

Facts:
- `applicationId` is `com.balkavach.balkavach_app`; the version is `1.0.0+1` (pubspec).
- Release signing comes from `android/key.properties`, which exists and is git-ignored. The build refuses an unsigned or debug-signed release.
- Google Services is applied when `google-services.json` exists (it now does, and it is committed).
- **The app's default API is production** (`https://api.balkavach.tech`). Override it with `--dart-define=API_BASE_URL=…`.
- Debug builds have no cleartext exception, so a phone cannot reach a local `http://` backend.

Steps (each build is local; installing on a phone and any deployment need the owner's go-ahead):
1. **Choose the backend for device testing.**
   - (a) **Recommended:** a staging or HTTPS test server running this backend. Build with `--dart-define=API_BASE_URL=https://<staging>`.
   - (b) A local backend through `adb reverse tcp:8000 tcp:8000`. This needs a debug-only `android:usesCleartextTraffic="true"` in `android/app/src/debug/AndroidManifest.xml` (a code change, not made).
   - (c) Production, only after the backend is deployed. Otherwise on-device Panda voice turns are refused by the old server and interest notifications are absent.
2. Debug APK for testers: `flutter build apk --debug --dart-define=API_BASE_URL=<chosen>`. Output: `build/app/outputs/flutter-apk/app-debug.apk`.
3. Release candidate: bump `version:` in `pubspec.yaml` (for example `1.0.1+2`), then `flutter build apk --release --dart-define=API_BASE_URL=https://api.balkavach.tech`, or `flutter build appbundle --release` for Play. Check that the signing report shows the upload key: `cd android && ./gradlew signingReport`.
4. Before release, run the device checklist above on the release build, not only debug.
5. Free memory before building: close Chrome and run `android/gradlew --stop` between builds.
