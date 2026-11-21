# Panda lip-sync, mission history and Home feed (2026-11-21)

Nothing here is device-verified. No database was touched, nothing was deployed, committed or pushed.

## 1. Talking Panda

**Root cause of the static image.** `PandaCharacter` swapped between five flat 512x279 JPG scenes and scaled/hopped the whole picture
on each word ("talk beat"). The art has no separate mouth or eyes, so a mouth could not move. The "Panda is talking" label was true
only of the audio.

**What was built** (`lib/features/companion/`):

| Piece | File | Role |
|---|---|---|
| Mouth shapes | `domain/viseme.dart` | 8 visemes (rest, mbp, fv, oo, oh, ah, ee, tl) with geometry |
| Word to shapes | `domain/viseme_mapper.dart` | English letters, Hindi (Devanagari) and Gujarati (same layout, offset 0x180) to a viseme sequence |
| Timeline | `domain/lip_sync.dart` | `LipSyncController`: follows the voice engine's start and word callbacks; closes the mouth synchronously on `cancel()` / `finish()` |
| Performance | `domain/panda_performer.dart` | eases between 9 phase poses, blinks, glances, breathes; reduced-motion aware; stops its own ticker when idle |
| Rig | `presentation/panda_rig_painter.dart` | layered vector Panda: backdrop, legs, hoodie, arms, ears, head, cheeks, eye patches, eyes, brows, nose, per-viseme mouth |
| Widget | `presentation/panda_character.dart` | one ticker, woken by phase changes and mouth events |
| Lifecycle | `domain/panda_interaction.dart` | `PandaTalkController.lipSync` is started in `_say` and cancelled by stop, interrupt, new message, error, watchdog and dispose |
| Speech | `data/speech_services.dart` | `speak(onStart, onWord(SpokenWord))` (the word's text now reaches the mouth) |

**Is the sync real, and how exact?** The platform TTS (`flutter_tts`) reports only the audio start, each word start (Android 8+
`onRangeStart`, iOS `willSpeakRange`) and completion. It gives **no phonemes, no audio samples, no amplitude.** So this is a
**word-boundary viseme approximation**, not phoneme-level sync:

* `LipSyncMode.boundaries`: each word signal starts that word's shapes (from its spelling), spread over the time the word is expected to take (learned from earlier gaps). The next real signal always takes over, so drift cannot build up.
* `LipSyncMode.estimated`: if the engine sends no word callbacks, the line is laid out from its text and a default rate, **anchored to the real audio start and ended by real completion or stop**. Less accurate: it cannot follow pauses or speed changes inside a line. The first real word signal switches to `boundaries`.
* No audio-start and no word signals: the mouth does not move (nothing real to anchor to). A failed or unsupported voice never moves the mouth.

The product owner's test phone uses `sia.netttsengine.ttslexx`, whose word callbacks are unknown. **Whether a real engine on a real device
sends them is not verified**; the unit and widget tests use a fake clock and fake engine.

**Art status (honest).** The existing artwork is five flattened JPG scenes: it cannot be split into layers, and painting a mouth onto it was
ruled out (2026-11-19 decision). The rig is therefore a **new vector character drawn in code from the existing design** (white head, black
ears and eye patches, blush, royal-blue hoodie with drawstrings and the yellow K, pastel sky). It keeps the identity at the level of colours
and features but it is a flat 2D stand-in, **not the soft 3D-rendered look of the original illustrations**. Rendered checks of every phase
and every mouth shape were inspected by eye. For production-quality art an artist should deliver layered frames or a Rive rig
(`docs/panda-animation-art-brief.md`); the viseme and performer layers do not change when that happens, only the painter.
The original JPG Panda is kept (`PandaStill`) on the video lock screen, which only shows a mood.

**Not done / limits:** no real-device run; engine word callbacks unconfirmed; Hindi/Gujarati letter-to-shape rules are an approximation and
unreviewed by a native speaker; no phoneme alignment; the face has no lip-corner animation beyond the smile value.

Consent is unchanged: the microphone gate (`checkVoiceConsent`, parent consent record) was not touched.

## 2. Home / Watch & Learn feed

**Finding: there is no grown-up permission gate in the app.** `WatchHomeScreen` renders the Shorts row and video list whenever the
server returns videos; the only gate is `ensureVideoAllowance` when a child taps a video (server-confirmed daily allowance). The
screenshot's "No videos here yet. A grown-up checks every video before it appears." is the **empty state** (`watch.empty`, shown when Shorts,
videos and picked items are all empty). It was empty because `GET /videos/shorts` and `/videos/feed` returned nothing for that child.

**Why the server can return nothing** (`app/services/video_service.eligible_feed`, `youtube_review_service.youtube_visibility_clause`).
Exactly one or more of these, which production data decides:

1. the child's birth date is missing or outside 3-15;
2. no published video matches the child's age, language (preferred + English) or content rating;
3. **every approved YouTube video is hidden once its `last_verified_at` is older than `YOUTUBE_REVERIFY_HOURS` (72)**. `docs/youtube-operations.md`
   says no re-check job is known to run, and an earlier database sample suggested none;
4. today's allowance is exhausted (both feeds return `[]` by design).

The log event `videos.feed.empty` (age, published, age-eligible, YouTube-visible, format, language and category counts) names the filter that
removed everything. Operator checks (read-only): `python -m app.cli youtube-report` (`approved_stale`, `oldest_approved_verification`), and the
Render logs for `videos.feed.empty`. **This was not run: production access is out of scope, so the actual cause for that child is unconfirmed.**

> **Superseded by `docs/video-feed-restoration.md`** (diagnosis, tests, recheck scheduling, `video-feed-diagnose`). The wording change below did not restore any content and was never claimed to.

**Changed:** only the wording of `watchNothingYet` (en/hi/gu) so the empty state no longer reads as a permission gate:
"No videos here right now. Check back soon, or try a mission!". Nothing else about the feed, allowance charging, tickets or parental
controls changed. `VIDEO_PLAY_TICKETS*` untouched.

**Removed (requested):** the Panda avatar + greeting bubble on Home (`WatchHomeScreen._Greeting` replaced by a plain `_Heading`; spacing
re-set: 24 above the heading, 16 to the allowance card) and on Profile (`ChildDashboard`). Talk to Panda (app-bar button) and Panda in
Missions and mission detail remain.

## 3. Missions

**"(4 to 6)" in titles.** The cards in the report are not the real catalogue: they are the **placeholder templates migration 0015 seeded**
(`slug.replace('_',' ').title() + ' (' + age_label + ')'`, description "A interactive learning adventure for ages 4 to 6.", generic
instructions). "Saturday"/"Thursday" are weekday *themes*, not days they were scheduled. They are still published in that database; the
real 42-template catalogue is applied/published separately.

* Backend: `app/services/mission_titles.child_facing_title` strips a trailing age range; used when serving assignments
  (`public_assignment`) and when creating the Task at selection. `age_band`, the stored snapshot and variation titles are unchanged.
* Flutter: `childFacingMissionTitle` (`Mission.childTitle`, `DailyMissionContent.childTitle`) on cards, detail, submit screen, daily
  choices, Profile mission rows. Tasks created before this change keep the suffix in the database and are cleaned on display. Notification
  texts already stored still contain it.
* **Operator step (not done, needs a database):** `python -m app.cli seed-daily-missions --apply --publish --retire-placeholders` after a
  dry run, so children get real instructions instead of the generic placeholder text. This writes data (no schema change).

**"Start Mission" failed: root cause (reproduced by a failing test first).** `_DailyChoicesState._select` created the Task on the server and
then pushed the mission detail screen, but only invalidated `dailyMissionChoicesProvider`. The detail reads `childMissionProvider`, which looks
the task up in the **cached** `childMissionsProvider` list loaded before the Task existed, so it showed "This mission is no longer
available." Fixed in two places: the list and statuses are refreshed before navigating, and `childMissionProvider` re-queries the server once
when the id is not in the cached list (also helps notification deep links).

**Older unfinished missions.** Before, only today's three choices were returned by `/daily-missions/today`; a chosen mission survived only as
a row of the general task list. Now `GET /daily-missions/unfinished` (read-only, no schema change) returns the child's chosen missions from
earlier family-local days in status `selected`, `in_progress` or `rejected` whose Task is active, newest first (max 20). Flutter shows them
first on Missions under "Still to finish" with a **Continue** button that opens the same Task, so progress, submissions, parent approval and
rewards use the unchanged flow. They are not repeated in the general list. Not listed: `approved`, `pending_parent_approval` (nothing for the
child to do), `skipped`, and **`available` (offered but never chosen: that was a menu, not an unfinished mission)**. This reading of
"unfinished" is a product interpretation, not a stated rule.

Reopening never calls select/start, so no assignment is created or reset (tested). Rotation, cooldowns, skips, age bands and reward values are
untouched.

**Observed, not changed:** the general task list still offers "Do it again" on an approved daily mission; the server refuses a second
submission (`task_already_completed`) for non-repeating tasks.

## 4. Tests

See the final report for exact counts. New: `balkavach-backend/tests/test_unfinished_missions.py` (SQLite world and HTTP routes with overridden
dependencies; **not PostgreSQL**), `test/features/lip_sync_test.dart` (fake clock), `test/features/missions_history_test.dart`,
`test/features/home_profile_panda_test.dart` (fake backend and fake speech, 3 languages x 3 sizes), and rewritten character/lifecycle groups in
`test/features/panda_talk_test.dart`.
