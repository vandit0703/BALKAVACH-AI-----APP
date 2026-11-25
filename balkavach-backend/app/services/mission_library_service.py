"""Quality rules and reports for the Mission Library (``app/content/mission_library``).

The core catalogue checks in ``mission_catalogue_service.validate_catalogue`` run on every library concept too
(script, romanisation, restricted terms, pressure words, admin validator, task text length, unique titles, unique
activity mechanics). This module adds what a 500-concept, category-based library needs on top:

* the category is one of the 24 developmental categories;
* real age adaptation: durations and step counts per band, older bands never shorter, steps of two bands genuinely
  different (not reworded), short steps for ages 4-6;
* objective, observation guidance and submission text present in all three languages;
* localisation consistency: no Latin letters anywhere in hi/gu, the same numbers in every language, the same number of
  steps and materials (core check), implausible length ratios flagged for a human;
* near-duplicate detection against the **whole** catalogue (core + library), in every age band;
* translation review status: a concept whose hi/gu text is not approved is listed for review and is not published.

``library_problems`` returns blocking problems (the seeder refuses to write while any exist). ``review_flags`` returns
non-blocking items for a human (native speaker or educator). The report helpers are read-only.
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from typing import Any, Iterable

from app.content.mission_library import AGE_BANDS, CATEGORIES, LIBRARY_PREFIX, LOCALES, is_publishable_translation

# Active minutes per band (the DB allows 1-180; these are the library's age rules).
DURATION_RANGE = {"4_6": (5, 10), "7_10": (8, 15), "11_15": (10, 20)}
STEP_RANGE = {"4_6": (3, 4), "7_10": (4, 5), "11_15": (5, 7)}
MAX_AVG_WORDS_4_6 = 14
# Share of English step words two bands of one concept may have in common (above = a rewording, not an adaptation).
MAX_BAND_OVERLAP = 0.5
# Share of English step words two different concepts may have in common in one age band (above = near-duplicate).
MAX_CONCEPT_OVERLAP = 0.4
LENGTH_RATIO = (0.5, 2.2)  # hi/gu length vs English, per field; outside is flagged for review
REVIEW_STATUSES = ("pending", "approved")
REQUIRED_EXTRA = ("objective", "observe", "submit")
_ALL_FIELDS = ("title", "description", "objective", "alt", "safety", "observe", "submit", "show", "parent_check")

_STOP = frozenset(
	"a an the and to of in it you your for on with at is are or then that this each one do can as about until every "
	"from by up out them they be if into so what which how when who its their there have has not no".split()
)
_LATIN = re.compile(r"[A-Za-z]")
_PATTERN_SYMBOLS = re.compile(r"\b[XO]\b")
_SCRIPT = {"gu": re.compile(r"[઀-૿]"), "hi": re.compile(r"[ऀ-ॿ]")}
_DIGITS = str.maketrans("०१२३४५६७८९૦૧૨૩૪૫૬૭૮૯", "01234567890123456789")
_NUMBER = re.compile(r"\d+")

# Restricted on top of the core list: no internet-dependent activity, no speed races.
_LIBRARY_RESTRICTED = {
	"en": (r"internet", r"websites?", r"social media", r"download(ing)?", r"search online", r"as fast as", r"race", r"racing"),
	"hi": ("इंटरनेट", "वेबसाइट", "सोशल मीडिया", "डाउनलोड", "दौड़ लगाओ"),
	"gu": ("ઇન્ટરનેટ", "વેબસાઇટ", "સોશિયલ મીડિયા", "ડાઉનલોડ", "હરીફાઈ"),
}


def _words(steps: Iterable[str]) -> set[str]:
	return set(re.findall(r"[a-z]+", " ".join(steps).lower())) - _STOP


def _jaccard(a: set[str], b: set[str]) -> float:
	return len(a & b) / len(a | b) if a and b else 0.0


def _numbers(text: str) -> list[str]:
	return sorted(_NUMBER.findall(text.translate(_DIGITS)))


def _texts(mission: dict[str, Any], band: str, locale: str) -> dict[str, Any]:
	return mission["ages"].get(band, {}).get("locales", {}).get(locale) or {}


def library_problems(library: Iterable[dict[str, Any]], core: Iterable[dict[str, Any]] = ()) -> list[str]:
	"""Blocking problems for library concepts (``to_mission`` dicts). Empty means fit to seed."""
	from app.services.mission_catalogue_service import _has

	library, core = list(library), list(core)
	problems: list[str] = []
	for mission in library:
		slug = mission["slug"]
		if not slug.startswith(LIBRARY_PREFIX):
			problems.append(f"{slug}: library slugs start with {LIBRARY_PREFIX!r}")
		if mission["theme"] not in CATEGORIES:
			problems.append(f"{slug}: unknown category {mission['theme']!r}")
		review = mission.get("review") or {}
		for locale in LOCALES:
			if review.get(locale) not in REVIEW_STATUSES:
				problems.append(f"{slug}: review status for {locale} must be one of {REVIEW_STATUSES}")
		minutes, step_counts = [], []
		for band in AGE_BANDS:
			age = mission["ages"].get(band)
			if not age:
				continue  # reported by the core validator
			low, high = DURATION_RANGE[band]
			if not low <= age.get("minutes", 0) <= high:
				problems.append(f"{slug}/{band}: duration {age.get('minutes')} min outside {low}-{high}")
			minutes.append(age.get("minutes", 0))
			en_steps = _texts(mission, band, "en").get("steps", [])
			step_counts.append(len(en_steps))
			low, high = STEP_RANGE[band]
			if not low <= len(en_steps) <= high:
				problems.append(f"{slug}/{band}: {len(en_steps)} steps; ages {band} use {low}-{high}")
			if band == "4_6" and en_steps:
				average = sum(len(step.split()) for step in en_steps) / len(en_steps)
				if average > MAX_AVG_WORDS_4_6:
					problems.append(f"{slug}/4_6: steps average {average:.1f} words (max {MAX_AVG_WORDS_4_6})")
			for locale in LOCALES:
				text = _texts(mission, band, locale)
				spot = f"{slug}/{band}/{locale}"
				for field in REQUIRED_EXTRA:
					if not str(text.get(field, "")).strip():
						problems.append(f"{spot}: {field} missing")
				if locale != "en":
					for field in _ALL_FIELDS:
						value = str(text.get(field, ""))
						if _LATIN.search(_PATTERN_SYMBOLS.sub("", value)):
							problems.append(f"{spot}: Latin letters in {field}: {value[:40]!r}")
						if value and not _SCRIPT[locale].search(value):
							problems.append(f"{spot}: {field} has no {locale} script")
					for list_field in ("steps", "materials"):
						for item in text.get(list_field, []):
							s_item = str(item)
							if _LATIN.search(_PATTERN_SYMBOLS.sub("", s_item)):
								problems.append(f"{spot}: Latin letters in {list_field}: {s_item[:40]!r}")
							if s_item.strip() and not _SCRIPT[locale].search(s_item):
								problems.append(f"{spot}: {list_field} item has no {locale} script")
				asked = " ".join([*text.get("steps", []), text.get("alt", ""), text.get("submit", ""), *text.get("materials", [])])
				hit = _has(_LIBRARY_RESTRICTED[locale], asked, regex=locale == "en")
				if hit:
					problems.append(f"{spot}: restricted library term {hit!r}")
			# The same numbers in every language (a dropped or changed number changes the instructions).
			en = _texts(mission, band, "en")
			reference = _numbers(" ".join([*en.get("steps", []), *en.get("materials", [])]))
			for locale in ("hi", "gu"):
				other = _texts(mission, band, locale)
				found = _numbers(" ".join([*other.get("steps", []), *other.get("materials", [])]))
				if found != reference:
					problems.append(f"{slug}/{band}/{locale}: numbers in steps/materials {found} differ from English {reference}")
		if minutes != sorted(minutes):
			problems.append(f"{slug}: an older age band has a shorter duration {minutes}")
		if step_counts != sorted(step_counts):
			problems.append(f"{slug}: an older age band has fewer steps {step_counts}")
		for i, first in enumerate(AGE_BANDS):
			for second in AGE_BANDS[i + 1:]:
				overlap = _jaccard(_words(_texts(mission, first, "en").get("steps", [])), _words(_texts(mission, second, "en").get("steps", [])))
				if overlap > MAX_BAND_OVERLAP:
					problems.append(f"{slug}: {first} and {second} steps overlap {overlap:.2f}; adapt the activity, do not reword it")
	problems.extend(near_duplicates(library, core))
	return problems


def near_duplicates(library: Iterable[dict[str, Any]], core: Iterable[dict[str, Any]] = ()) -> list[str]:
	"""Pairs (at least one from the library) whose English steps in one age band share too many words."""
	library, core = list(library), list(core)
	everything = library + core
	words = {(m["slug"], band): _words(_texts(m, band, "en").get("steps", [])) for m in everything for band in AGE_BANDS}
	problems: list[str] = []
	for i, first in enumerate(library):
		for second in everything[i + 1:]:
			for band in AGE_BANDS:
				overlap = _jaccard(words[(first["slug"], band)], words[(second["slug"], band)])
				if overlap >= MAX_CONCEPT_OVERLAP:
					problems.append(f"near-duplicate: {first['slug']} and {second['slug']} share {overlap:.2f} of their {band} step words")
	return problems


def review_flags(library: Iterable[dict[str, Any]]) -> list[dict[str, str]]:
	"""Non-blocking items for a human reviewer: pending translations and suspicious length ratios."""
	flags: list[dict[str, str]] = []
	for mission in library:
		slug = mission["slug"]
		review = mission.get("review") or {}
		for locale in ("hi", "gu"):
			if review.get(locale) != "approved":
				flags.append({"slug": slug, "locale": locale, "reason": "translation_pending_native_review"})
		for band in AGE_BANDS:
			en = _texts(mission, band, "en")
			for locale in ("hi", "gu"):
				other = _texts(mission, band, locale)
				for field in _ALL_FIELDS:
					a, b = len(str(en.get(field, ""))), len(str(other.get(field, "")))
					if a >= 20 and b and not LENGTH_RATIO[0] <= b / a <= LENGTH_RATIO[1]:
						flags.append({"slug": slug, "locale": locale, "reason": f"length_ratio:{band}:{field}:{b / a:.2f}"})
	return flags


def coverage_report(library: Iterable[dict[str, Any]]) -> dict[str, Any]:
	"""Category distribution, age-band coverage and language completeness of the library source (read-only)."""
	library = list(library)
	per_category = Counter(m["theme"] for m in library)
	age_cover = {band: sum(1 for m in library if band in m["ages"]) for band in AGE_BANDS}
	language = {
		locale: sum(
			1
			for m in library
			for band in AGE_BANDS
			if all(str(_texts(m, band, locale).get(f, "")).strip() for f in _ALL_FIELDS) and _texts(m, band, locale).get("steps")
		)
		for locale in LOCALES
	}
	durations = defaultdict(list)
	for m in library:
		for band in AGE_BANDS:
			if band in m["ages"]:
				durations[band].append(m["ages"][band]["minutes"])
	return {
		"concepts": len(library),
		"age_specific_variations": sum(len(m["ages"]) for m in library),
		"localized_records": sum(len(m["ages"][b]["locales"]) for m in library for b in m["ages"]),
		"categories_covered": len(per_category),
		"categories_total": len(CATEGORIES),
		"per_category": {key: per_category.get(key, 0) for key in CATEGORIES},
		"age_bands": age_cover,
		"complete_variations_per_language": language,
		"duration_minutes": {band: {"min": min(v), "max": max(v), "avg": round(sum(v) / len(v), 1)} for band, v in durations.items() if v},
		"publishable_translations": sum(1 for m in library if is_publishable_translation(m)),
		"mission_types": dict(Counter(m["mission_type"] for m in library)),
	}


def validate_library_catalogue(
	library: Iterable[dict[str, Any]] | None = None,
	core: Iterable[dict[str, Any]] | None = None,
) -> dict[str, Any]:
	"""Run full core + library + schema + audit validation and separate hard errors from review warnings."""
	from app.content.daily_missions import MISSIONS, variation_payload
	from app.content.mission_library import LIBRARY_ACTIVITIES, LIBRARY_MISSIONS
	from app.schemas.daily_mission import DailyMissionVariationCreate
	from app.services.mission_audit_service import audit_catalogue
	from app.services.mission_catalogue_service import validate_catalogue

	lib_list = list(LIBRARY_MISSIONS if library is None else library)
	core_list = list(MISSIONS if core is None else core)
	errors: list[str] = []
	errors.extend(
		validate_catalogue(
			lib_list,
			allowed_themes=set(CATEGORIES),
			activities=LIBRARY_ACTIVITIES,
			duration_ranges=DURATION_RANGE,
		)
	)
	errors.extend(library_problems(lib_list, core_list))
	# Verify no slug or mechanic collisions between core and library
	core_slugs = {m["slug"] for m in core_list}
	for m in lib_list:
		if m["slug"] in core_slugs:
			errors.append(f"{m['slug']}: collides with core catalogue slug")
		for band in AGE_BANDS:
			for locale in LOCALES:
				try:
					DailyMissionVariationCreate(**variation_payload(m, band, locale))
				except Exception as exc:
					errors.append(f"{m['slug']}/{band}/{locale}: schema invalid: {exc}")
	audit = audit_catalogue(lib_list)
	for row in audit.get("variations", []):
		if row.get("status") in {"INCOMPLETE", "SAFETY REVIEW"}:
			errors.append(f"{row['slug']}/{row['age_band']}/{row['locale']}: audit={row['status']} ({row.get('issues')})")
	return {
		"errors": errors,
		"warnings": review_flags(lib_list),
		"coverage": coverage_report(lib_list),
		"audit_summary": audit.get("summary", {}),
	}
