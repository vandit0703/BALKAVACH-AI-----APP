# Mission catalogue: language and safety review status

Last updated 2026-11-22. This file records what has and has not been reviewed. **Nothing here is an approval.**

## Native-language review (Hindi, Gujarati)

| Content | Languages | Versions | Written by | Native-speaker review |
|---|---|---|---|---|
| Steps, materials, safety, `show`, parent check, alternative | hi, gu | 126 + 126 | project authors | **PENDING** (no reviewer assigned, no record exists) |
| Child-facing `submit` (added 2026-11-22) | hi, gu | 126 + 126 | the assistant, adapted from each mission's own steps | **PENDING** |
| Interface strings for the mission guide and admin editor | hi, gu | ~50 each | the assistant | **PENDING** |
| All of the above | en | 126 | project authors / assistant | not applicable (plain English; no child pilot) |

The audit marks all 252 Hindi and Gujarati variations `needs_native_review = true`. That flag is derived from the
language, not from a record: **adding a review record is a human action that has not happened**. Do not mark these as
reviewed until a Hindi speaker and a Gujarati speaker (ideally an early-years or primary educator) have signed off,
and keep their names in your own records, not invented here.

Language-quality risks to ask the reviewers about:
* Loanwords used for simplicity: pattern (पैटर्न), score (स्कोर), checklist (चेकलिस्ट), flowchart (ફ્લોચાર્ટ), shaker
  (शेकर / શેકર), tally chart. A reviewer may prefer native words for ages 4-6.
* Register: Hindi uses the informal *tum* form (बताओ, दिखाओ); Gujarati uses the respectful *tame* form (કહો, બતાવો).
  Confirm both are right for the intended ages.
* Gujarati rhymes and sound words in the 4-6 missions (`જોડકણું`, `ટિક-ટોક`) are not translations of the English ones.
* Long sentences in the 11-15 `submit` text (several asks in one sentence) may be hard to read aloud; consider splitting.
* Automatic checks passed (right script, no Latin letters, same step counts across languages, no restricted terms);
  they say nothing about naturalness.

## Safety review

* `audit-daily-missions` reports **0** variations needing safety review (no restricted term is asked of the child).
  That is a keyword screen, **not** a safety approval, and nothing here records one.
* Missions that involve water (Sunday water saver: cups, tap, pouring on a plant, careful hand-washing), paper
  structures and household objects tested with a spoon or cup rely on the stated safety text and the grown-up's
  presence; a person should confirm those texts before relying on them.
* The feelings missions (Friday) ask children not to hand over private notes; the `submit` text says so.
