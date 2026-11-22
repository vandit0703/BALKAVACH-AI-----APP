# Child-facing "what to submit": draft examples

**Status: DRAFT for review. Nothing here is in the catalogue.** The English, Hindi and Gujarati wording below was
written by the assistant, adapting the sentences already in `app/content/daily_missions/monday_sound_detective.py`
(the step vocabulary and the reviewer `show` line). **None of it has had native-speaker review.** Do not publish it
as final until a Hindi and a Gujarati speaker has approved it.

## The two audiences

| Audience | Field | Voice | Where it lives |
|---|---|---|---|
| The child | `submission_requirements` (catalogue key `submit`) | direct ("Show...", "Tell...") | `daily_mission_variations.submission_requirements`, shown as "What to submit" |
| The reviewing parent | `show` + `parent_check` | about the child ("The child names...") | inside `completion_criteria` (unchanged) |

Before this pass the catalogue's `show` sentence was going to be copied into the child's field. It reads as a note to
the reviewer ("The child names three different sounds they heard."), so it is no longer copied: the child's field stays
empty until `submit` is authored, and the audit and the publish check report it. The reviewer keeps `show` and the
parent check exactly as before.

## Example: "Three Sounds Hunt" (`cat1_monday_sound_detective`)

### Ages 4-6

* **Reviewer sees (`show`)**: The child names three different sounds they heard.
* **Child is told (`submit`)**
  * en: Tell a grown-up your three sounds.
  * hi: किसी बड़े को अपनी तीनों आवाज़ें बताओ।
  * gu: કોઈ મોટાને તમારા ત્રણ અવાજ કહો.

### Ages 7-10

* **Reviewer sees (`show`)**: A sound map or list with at least 5 sounds, and a guess for the mystery sound.
* **Child is told (`submit`)**
  * en: Show a grown-up your sound map or list with at least 5 sounds, and tell them your guess for the mystery sound.
  * hi: किसी बड़े को कम से कम 5 आवाज़ों वाला अपना नक्शा या सूची दिखाओ और रहस्यमयी आवाज़ का अपना अनुमान बताओ।
  * gu: કોઈ મોટાને ઓછામાં ઓછા 5 અવાજ સાથેનો તમારો નકશો કે યાદી બતાવો અને રહસ્યમય અવાજનો તમારો અંદાજ કહો.

### Ages 11-15

* **Reviewer sees (`show`)**: A table for three places with sounds sorted by type, a loudness score, and two sentences comparing the quietest and the busiest place.
* **Child is told (`submit`)**
  * en: Share your table for three places, with the sounds sorted by type and a loudness score, and write two sentences comparing the quietest and the busiest place.
  * hi: तीन जगहों की अपनी तालिका दिखाओ, जिसमें आवाज़ें प्रकार के अनुसार छाँटी हों और तेज़ी का अंक हो, और सबसे शांत व सबसे व्यस्त जगह की तुलना के दो वाक्य लिखो।
  * gu: ત્રણ જગ્યાનું તમારું કોષ્ટક બતાવો, જેમાં અવાજ પ્રકાર પ્રમાણે ગોઠવેલા હોય અને તીવ્રતાનો ગુણ હોય, અને સૌથી શાંત તથા સૌથી વ્યસ્ત જગ્યાની સરખામણીનાં બે વાક્ય લખો.

## What the system now checks

* `validate_catalogue` accepts an optional `submit` per locale, requires the right script for Hindi/Gujarati, and rejects
  one written about the child ("The child ...").
* Publishing (admin endpoint and `seed-daily-missions --publish`) is blocked while a variation has no child-facing
  submission. A reviewer-voiced one is a quality warning (NEEDS IMPROVEMENT), not a safety blocker.
* To author for all 126 missions: add a `"submit": "..."` string next to `"show"` in each age and language block, run
  `python -m app.cli audit-daily-missions`, then regenerate the Flutter fixture with
  `python scripts/export_catalogue_fixture.py`.
