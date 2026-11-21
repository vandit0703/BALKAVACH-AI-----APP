# Talk to Panda: voice companion (Phase 6 upgrade)

Status 2026-11-19: implemented and covered by automated tests; **not yet verified on a real Android device**.

## Decisions (product owner, 2026-11-19)

| Topic | Decision |
|---|---|
| Replies | Server-side **rule-based intent engine** with authored en/hi/gu lines. No LLM, no third-party AI. |
| Speech | `speech_to_text` (platform recogniser) + `flutter_tts` (platform voice). Tap-to-talk only, with a text-box fallback. This replaces roadmap decision D7 (text + SFX first). |
| Animation | **Superseded 2026-11-21:** a layered vector rig with a viseme lip-sync driven by the TTS word callbacks (see `panda-lip-sync-missions-feed-2026-11-21.md`). The old plan (art slots over the flat JPGs) could not give a moving mouth. The original JPG Panda remains on the video lock screen. |
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
| Lip-sync (viseme approximation from word boundaries; estimated fallback anchored to audio start) | yes | yes (fake clock and fake engine) | **no**; engine support varies (the test phone's default engine is `sia.netttsengine.ttslexx`, not Google TTS) | | production-quality layered art |
| Gujarati replies in the respectful તમે form | yes | yes (regression test) | | **native-speaker review pending** | |
| Microphone disclosure (platform/Google recogniser) | yes (en/hi/gu explainer) | yes | | **privacy-policy and consent text pending** | |
| Parent consent gate for the microphone (2026-11-20) | yes: `consent_records` (`panda_voice`, per child, versioned); parent screen; mic closed until granted | yes: backend SQLite (`tests/test_panda_voice_consent.py`), Flutter fakes (`panda_voice_consent_test.dart`, `panda_talk_test.dart`) | **no** | **legal review of the disclosure text pending** | |
| Parent switch for Panda's *voice output* (TTS) | **no** (consent covers the microphone only) | | | product decision | |

Device run so far (by the product owner, 2026-11-19): the app was built against the **production** API (the default `API_BASE_URL`), and `POST /api/v1/companion/chat` returned **404** because the endpoint is not deployed. Nothing else on hardware has been verified.

**To test end to end without touching production:** run this backend locally against a **non-production** database, then
`adb reverse tcp:8000 tcp:8000` and `flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000`.
Do not point a local backend's `DATABASE_URL` at the live database.

## Release blockers (privacy and parent control)

1. **Privacy policy:** state that Talk to Panda uses the device's speech recognition and text-to-speech; that on many Android phones these are Google services that may process audio online under Google's terms; that BalKavach keeps no audio and no conversation text; and that only the intent and safety category are logged.
2. **Parent consent before the microphone: implemented 2026-11-20 (not device verified, not legally reviewed).**
   * Storage: existing `consent_records`, `consent_type = "panda_voice"`, one row per grant, per family and child, with
     `document_version` = `PANDA_VOICE_CONSENT_VERSION` (`app/services/panda_voice_consent_service.py`; the app sends
     `kPandaVoiceConsentVersion`, which must match). A newer text version makes older grants stale.
   * Parent: `GET/PUT /api/v1/settings/families/{family}/children/{child}/panda-voice-consent` (active family members only;
     404 otherwise). Granting needs the version shown; **any** parent of the family can withdraw. Screen: Parent settings →
     "Talk to Panda: microphone" (`PandaVoiceConsentScreen`), confirmation dialog with the full disclosure before granting.
   * Child: `GET /api/v1/companion/voice-consent` (read-only). The panel checks it on every mic tap **before** the Android
     permission explainer, so a child without consent is never asked for the permission and the microphone never opens.
     Typing to Panda always works.
   * Withdrawal: `POST /companion/chat` refuses turns sent with `input = "voice"` without consent (403
     `panda_voice_consent_required`); the app then cancels listening, stops speaking and switches to typing. **Limits:** the
     `input` field is declared by the client, and older app builds do not send it (treated as typed). The real control is the
     on-device gate; a modified app could still use the platform recogniser itself.
   * **Text needing owner/legal review:** `pandaConsentDisclosure`, `pandaConsentIntro`, `pandaVoiceNeedsParent` (en/hi/gu),
     the existing `pandaMicExplainBody`, and the privacy policy (item 1). Hindi and Gujarati need native-speaker review.
3. **Parent switch for voice output:** not built (product decision: the consent above covers the microphone only; Panda's
   replies are still spoken by the device's TTS). The same consent record (or a second type) can cover it, also without schema. A dedicated `companion_preferences` table is only needed if per-setting audit history is wanted (see `deferred-database-integration.md`).
4. **Safety events to parents:** not built. It needs a consent decision and the optional `companion_safety_events` table.

## Still required before claiming "works on devices"

1. Real-device runs on at least two Android devices (one budget device): permission prompt, recognition in en/hi/gu, voice availability for hi/gu, and whether the TTS engine sends word-boundary callbacks (some engines don't, in which case the talk beat does not move).
2. Behaviour with the mic busy (calls, other apps) and over Bluetooth headsets.
3. Battery and CPU while the panel stays open.
4. Native-speaker review of the Hindi and Gujarati replies, and child-safety review of the keyword lists.
5. Privacy policy and legal sign-off of the consent copy for the platform speech service (the in-app consent gate exists).
7. Device check of the consent gate: grant on the parent phone, mic opens on the child device; withdraw while the child is
   talking, the next voice turn is refused and the panel falls back to typing.
6. Production-quality layered art (the current rig is a flat vector stand-in), and a device check that the engine sends word callbacks (otherwise the mouth runs in `estimated` mode).
