# Talk to Panda: voice companion (Phase 6 upgrade)

Status 2026-11-19: implemented and covered by automated tests; **not yet verified on a real Android device**.

## Decisions (product owner, 2026-11-19)

| Topic | Decision |
|---|---|
| Replies | Server-side **rule-based intent engine** with authored en/hi/gu lines. No LLM, no third-party AI. |
| Speech | `speech_to_text` (platform recogniser) + `flutter_tts` (platform voice). Tap-to-talk only, with a text-box fallback. This replaces roadmap decision D7 (text + SFX first). |
| Animation | A state-driven controller with **art slots**. The existing Panda artwork is used unchanged, with nothing painted over it. New frames are specified in `panda-animation-art-brief.md`. |
| Database | No schema change. Nothing is persisted (see `deferred-database-integration.md`). |

## Flow

```
tap Panda / mic ─▶ (first time, no permission) explain ─▶ system permission prompt
      │                                                    │ denied ─▶ ERROR + text box
      ▼                                                    ▼
  LISTENING (≤10 s, 3 s pause, 14 s watchdog) ── no words ─▶ ERROR "couldn't hear you"
      │ final words
      ▼
  THINKING ─ POST /api/v1/companion/chat (10 s timeout, 12 s watchdog) ─ fail ─▶ ERROR
      ▼
  SPEAKING (voice word boundaries drive the talk beat; watchdog by line length)
      ▼
  HAPPY (2.5 s ─▶ IDLE) │ CURIOUS (awaits answer) │ SLEEPY (video time over) │ IDLE
```

* The opening line (GREETING) is authored on the device and chosen from real state: a sleepy line when today's video time is over, otherwise a hello by first name.
* **Interrupt:** tapping the mic while Panda talks stops the voice and starts listening. **Stop** ends everything. Closing the panel, or the app leaving the foreground, cancels listening and silences Panda.
* **No overlap or duplicates:** one turn at a time. Every async step carries an epoch, and late results from a stopped turn are dropped. The transition table (`pandaTransitions`) rejects impossible moves. Each turn has a `turn_id`, and the server answers a repeated id once.

## API contract

`POST /api/v1/companion/chat` needs a **child** bearer token (`require_child`). It reads data and writes nothing.

Request:
```json
{ "text": "tell me a joke", "locale": "gu", "turn_id": "uuid-v4", "context_intent": "joke" }
```
* `text`: 1–300 characters, trimmed. `locale`: `en|hi|gu`, or omitted to use the account's preferred language. `context_intent`: the previous reply's `follow_up` (`^[a-z_]{1,40}$`).

Reply 200:
```json
{ "reply": "…", "locale": "gu", "mood": "talking|happy|curious|sleepy|concerned",
  "intent": "joke", "follow_up": "joke", "safety": "ok|redirected",
  "suggestions": ["fact", "draw", "mission"] }
```
Errors: 401/403 (not a child), 422 (validation), 429 (more than 20 turns a minute per child; `Retry-After`).

## Safety and privacy

* **Order of rules:** distress → personal information (including any phone-like number or email) → unsafe activity → "more video" → parental settings → unkind words → normal topics.
* Panda **never repeats the child's words**, so nothing the child says can become Panda's speech.
* Each reply passes `validate_reply`: length limit, no URL or email, no leftover placeholder, no line asking for private details, and only numbers that come from real data. A failing line is replaced by a safe fallback.
* **Video time and parental controls stay authoritative:** Panda reports the real allowance, mission status, stars and streak. It cannot grant time, promise rewards or change a setting. The playback gate on the server is unchanged.
* The child's first name is the parent-set display name, letters only. The text is used once and is **not stored or logged**; only the intent and safety category are logged.
* The app keeps **no audio**. Recognition uses the device's speech service. On many Android devices that is Google's recogniser, which may process audio online under Google's terms. **The privacy policy and parental consent text must say this before release.** On-device-only recognition is not forced, because Gujarati and Hindi on-device models are often missing.
* The duplicate-turn cache and the rate limiter are **per process**. Multiple API instances would need a shared store (Redis) for strict limits.

## Languages

English, Hindi and Gujarati for both the UI and the reply catalogue. Keywords are matched in native script and common romanised forms (for example "kem cho"). When a device lacks recognition for the language, Panda says so and opens the text box. When it lacks a voice, Panda's line is shown with a "read along" note. **Hindi and Gujarati lines need review by a native speaker (pending).** The Gujarati replies were changed on 2026-11-19 from the informal "તું" to the respectful "તમે" to match the app UI, and a test now guards this. Points for the reviewer: Panda refers to itself in the masculine ("શકતો", "सकता"), and the Hindi replies address the child with masculine forms ("कर सकते हो").

## Files

Backend: `app/services/companion_chat_service.py`, `app/api/v1/companion.py`, `app/schemas/companion.py`, `tests/test_companion_chat.py`.
Flutter: `lib/features/companion/data/{companion_chat_repository,speech_services}.dart`, `domain/panda_interaction.dart`, `presentation/{panda_character,panda_talk_sheet}.dart`, the entry button in `child_shell.dart`, `test/features/panda_talk_test.dart`.
Android: `RECORD_AUDIO` permission, plus `RecognitionService` and `TTS_SERVICE` package-visibility queries.

## Status matrix (2026-11-19)

| Item | Implemented | Automated tests | Device verified | External review | Deferred |
|---|---|---|---|---|---|
| Talk panel, 9-state controller, interrupt/stop/watchdogs | yes | yes | panel opens and text sending reaches the network (Android 14, 22041219I) | n/a | |
| `POST /companion/chat` | yes (local code) | yes | **no: not deployed**; production returned 404 | child-safety review of keyword lists | |
| Speech recognition en/hi/gu | yes | fakes only | **no** | | |
| Text-to-speech en/hi/gu | yes | fakes only | **no** | | |
| Word-boundary talk beat | yes (Android 8.0+ via `onRangeStart`; Android 7.x gets one beat per line) | yes | **no**; engine support varies (the test phone's default engine is `sia.netttsengine.ttslexx`, not Google TTS) | | layered mouth/blink art |
| Gujarati replies in the respectful તમે form | yes | yes (regression test) | | **native-speaker review pending** | |
| Microphone disclosure (platform/Google recogniser) | yes (en/hi/gu explainer) | yes | | **privacy-policy and consent text pending** | |
| Parent voice switch / parent consent gate | **no** | | | product decision | yes |

Device run so far (by the product owner, 2026-11-19): the app was built against the **production** API (the default `API_BASE_URL`), and `POST /api/v1/companion/chat` returned **404** because the endpoint is not deployed. Nothing else on hardware has been verified.

**To test end to end without touching production:** run this backend locally against a **non-production** database, then
`adb reverse tcp:8000 tcp:8000` and `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`.
Do not point a local backend's `DATABASE_URL` at the live database.

## Release blockers (privacy and parent control)

1. **Privacy policy:** state that Talk to Panda uses the device's speech recognition and text-to-speech; that on many Android phones these are Google services that may process audio online under Google's terms; that BalKavach keeps no audio and no conversation text; and that only the intent and safety category are logged.
2. **Parent consent before the microphone:** today the child sees an explainer and then the Android permission prompt. Before release, a parent should opt in. This needs **no schema change**: record it in the existing `consent_records` (`consent_type = "panda_voice"`, per `child_id`, versioned, revocable through the existing endpoints). It does need a new child-readable read endpoint, a parent toggle screen and the gate in the panel, which is a small follow-up feature.
3. **Parent switch for voice output:** the same consent record (or a second type) can cover it, also without schema. A dedicated `companion_preferences` table is only needed if per-setting audit history is wanted (see `deferred-database-integration.md`).
4. **Safety events to parents:** not built. It needs a consent decision and the optional `companion_safety_events` table.

## Still required before claiming "works on devices"

1. Real-device runs on at least two Android devices (one budget device): permission prompt, recognition in en/hi/gu, voice availability for hi/gu, and whether the TTS engine sends word-boundary callbacks (some engines don't, in which case the talk beat does not move).
2. Behaviour with the mic busy (calls, other apps) and over Bluetooth headsets.
3. Battery and CPU while the panel stays open.
4. Native-speaker review of the Hindi and Gujarati replies, and child-safety review of the keyword lists.
5. Privacy policy and consent copy for the platform speech service.
6. Layered art per the art brief, for real mouth and blink frames.
