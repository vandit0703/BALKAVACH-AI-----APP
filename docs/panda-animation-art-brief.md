# Panda animation art brief

The talk panel already drives these slots (`PandaArtSet` in
`lib/features/companion/presentation/panda_character.dart`). Today only the
pose slots are filled, using the five existing scenes. **Keep Panda's existing
identity:** the same character model, face, fur, hoodie with the "K" logo and
lighting as `panda_hoodie.jpg`. Do not reference or imitate any other
franchise's characters.

## Format

* PNG with transparency (or WebP), **512 × 279** (the existing scene size) or
  exactly 2×, with identical framing between the frames of one pose, so frames
  can be swapped without jumping.
* One background plate per pose (may reuse the existing scenes), and the
  character on its own layer if possible.
* Budget: under 1.5 MB total for all frames.

## Frames needed

| Slot | Frames | Used when |
|---|---|---|
| `poses[idle]` | neutral smile, eyes open | resting |
| `blink[idle]`, `blink[curious]`, `blink[listening]` | same pose, eyes closed | blink every 3–6 s (not yet scheduled; added with the frames) |
| `mouthOpen[speaking]` | same as the speaking pose, mouth open (medium "ah") | each word the voice engine starts speaking |
| optional `mouthRound[speaking]` | mouth "oo" | future vowel shaping |
| `poses[listening]` | head tilted, paw near the ear, attentive eyes | mic open |
| `poses[thinking]` | paw on chin, eyes up | waiting for the reply |
| `poses[happy]` + `mouthOpen[happy]` | arms up / thumbs up, big smile | good news |
| `poses[curious]` + `mouthOpen[curious]` | head tilt, raised brow | Panda asked a question |
| `poses[sleepy]` + `mouthOpen[sleepy]` | droopy eyelids, small yawn | video time over |
| `poses[error]` | gentle "oops" expression, paw raised | mic or connection problem |

## Alternative

A single Rive file with a state machine (inputs: `phase`, `talkBeat`
trigger, `blink` trigger) would replace the frame slots with one asset. That
needs the `rive` package, which has not been added yet.
