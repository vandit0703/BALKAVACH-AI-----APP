"""The 378 authored child-facing "what to submit" texts (``submit``): coverage, voice and separation from the reviewer text.

Pure content checks (no database). They prove structure and voice, not language quality: the Hindi and Gujarati wording
has NOT been reviewed by a native speaker (see docs/mission-catalogue-review-status.md).
"""

import re

import pytest

from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, SUBMIT_TEXT, variation_payload
from app.services.mission_catalogue_service import validate_catalogue

_REVIEWER = re.compile(r"^\s*(the\s+)?(child|student|kid|learner)\b|^\s*(बच्चा|बच्चे|बालक|બાળક)", re.IGNORECASE)
_ROWS = [(m, band, locale) for m in MISSIONS for band in AGE_BANDS for locale in LOCALES]


def _text(mission, band, locale):
    return mission["ages"][band]["locales"][locale]


def test_every_localized_variation_has_its_own_submit_text():
    assert len(_ROWS) == 378
    assert all(_text(m, b, l).get("submit", "").strip() for m, b, l in _ROWS)
    assert set(SUBMIT_TEXT) == {m["slug"] for m in MISSIONS}
    for slug, bands in SUBMIT_TEXT.items():
        assert set(bands) == set(AGE_BANDS) and all(set(v) == set(LOCALES) for v in bands.values()), slug


def test_the_catalogue_with_submit_text_validates_cleanly():
    assert validate_catalogue() == []


@pytest.mark.parametrize("locale", LOCALES)
def test_submit_is_never_the_reviewer_sentence_and_never_written_about_the_child(locale):
    for mission in MISSIONS:
        for band in AGE_BANDS:
            text = _text(mission, band, locale)
            assert text["submit"].strip() != text["show"].strip(), (mission["slug"], band, locale)
            assert not _REVIEWER.match(text["submit"]), (mission["slug"], band, locale, text["submit"])


def test_the_reviewer_text_stays_separate_in_the_completion_criteria():
    for mission, band, locale in _ROWS[:: 7]:
        payload = variation_payload(mission, band, locale)
        text = _text(mission, band, locale)
        assert text["show"] in payload["completion_criteria"] and text["parent_check"] in payload["completion_criteria"]
        assert text["submit"] not in payload["completion_criteria"]
        assert payload["submission_requirements"] == text["submit"]


def test_each_age_band_of_a_mission_has_different_submit_text_in_every_language():
    for mission in MISSIONS:
        for locale in LOCALES:
            texts = [_text(mission, band, locale)["submit"] for band in AGE_BANDS]
            assert len(set(texts)) == 3, (mission["slug"], locale)


def test_submit_text_is_localized_not_copied_between_languages():
    for mission in MISSIONS:
        for band in AGE_BANDS:
            en, hi, gu = (_text(mission, band, l)["submit"] for l in ("en", "hi", "gu"))
            assert len({en, hi, gu}) == 3
            assert re.search(r"[ऀ-ॿ]", hi) and re.search(r"[઀-૿]", gu)
            assert not re.search(r"[ऀ-ॿ઀-૿]", en)


def test_younger_children_get_shorter_instructions():
    def words(band):
        values = [len(_text(m, band, "en")["submit"].split()) for m in MISSIONS]
        return sum(values) / len(values)

    assert words("4_6") < words("7_10") < words("11_15")
    assert max(len(_text(m, "4_6", "en")["submit"].split()) for m in MISSIONS) <= 30


def test_private_feelings_work_does_not_ask_children_to_hand_over_their_notes():
    for slug in ("cat1_friday_emotion_detective", "cat1_friday_kind_clues", "cat1_friday_feelings_in_stories"):
        text = _text(next(m for m in MISSIONS if m["slug"] == slug), "11_15", "en")["submit"].lower()
        assert "private" in text or "stays yours" in text
