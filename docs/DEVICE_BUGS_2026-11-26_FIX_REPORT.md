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
