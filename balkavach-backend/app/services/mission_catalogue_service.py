"""Validate and idempotently seed the daily-mission catalogue (``app/content/daily_missions``).

Uses the existing tables only (``daily_mission_templates`` / ``daily_mission_variations``) and the same
``DailyMissionVariationCreate`` validator the admin API uses. Seeding is:

* **non-destructive**: a template or variation that already exists (matched by slug, or by
  template + age band + locale + ``variation_key``) is never modified, whatever it contains, so admin edits
  survive; a differing existing variation is only reported;
* **idempotent**: running it twice creates nothing the second time;
* **unpublished by default**: new templates are created unpublished and published only on request, and only
  when all nine age/locale variations exist (the same rule the admin publish endpoint enforces).
"""

from __future__ import annotations

import re
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable

from pydantic import ValidationError
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.content.daily_missions import (
	ACTIVITIES,
	AGE_BANDS,
	CATALOGUE_VARIATION_KEY,
	LABELS,
	LOCALES,
	MISSIONS,
	template_payload,
	variation_payload,
)
from app.db.base import get_model
from app.schemas.daily_mission import DailyMissionTemplateCreate, DailyMissionVariationCreate
from app.services.daily_mission_service import THEMES_BY_WEEKDAY, has_complete_localized_variations
from app.services.mission_rotation_service import MIN_ELIGIBLE_PER_THEME

MIN_MINUTES, MAX_MINUTES = 5, 15
TARGET_TEMPLATES_PER_THEME = 6  # the catalogue target: 7 themes x 6 = 42 templates (see docs/mission-catalogue-inventory.md)
MAX_STEP_SIMILARITY = 0.4  # two missions of one theme may share at most this share of English step words (per age band)
_STEP_STOP_WORDS = frozenset(
	"a an the and to of in it you your for on with at is are or then that this each one do can as about until every from by up out them they".split()
)
MAX_STORED_TASK_TEXT = 1900  # description + instructions + completion are copied into the Task description
MIN_STEPS = 3

_SCRIPT = {
	"en": re.compile(r"^[\x20-\x7e\n]*$"),
	"gu": re.compile(r"[઀-૿]"),
	"hi": re.compile(r"[ऀ-ॿ]"),
}
_LATIN = re.compile(r"[A-Za-z]")
_PATTERN_SYMBOLS = re.compile(r"\b[XO]\b")  # rhythm notation (X = clap, O = tap) is allowed inside gu/hi text
_TEXT_FIELDS = ("title", "description", "alt", "safety", "show", "parent_check")

# Things a mission must never ask a child to do or to have. Checked in the instructions, materials,
# completion text and parent check (the safety text may *forbid* them, e.g. "no scissors are needed").
_UNSAFE = {
	"en": (
		r"scissors?", r"knife|knives", r"blades?", r"fire", r"flames?", r"candles?", r"matches", r"lighters?",
		r"chemicals?", r"stove", r"oven", r"cook(ing)?", r"climb(ing)?", r"camera", r"photos?", r"microphone",
		r"location", r"upload", r"post(ing)? online", r"buy", r"purchase", r"stranger",
	),
	"gu": ("કાતર", "છરી", "બ્લેડ", "આગ", "દીવાસળી", "મીણબત્તી", "રસાયણ", "ચૂલો", "ચડવું", "કેમેરા", "ફોટો", "ખરીદ"),
	"hi": ("कैंची", "चाकू", "ब्लेड", "आग", "माचिस", "मोमबत्ती", "रसायन", "चूल्हा", "चढ़", "कैमरा", "फ़ोटो", "फोटो", "खरीद"),
}
# Wording that would add pressure or shame.
_PRESSURE = {
	"en": (r"winner", r"loser", r"fastest", r"best in", r"hurry", r"stupid", r"lazy"),
	"gu": ("વિજેતા", "હારનાર", "આળસુ"),
	"hi": ("विजेता", "हारने वाला", "आलसी"),
}

# The placeholder rows migration 0015 seeded; used only by ``retire_placeholders``.
_PLACEHOLDER_SLUGS = tuple(
	f"{theme}{suffix}"
	for theme in (
		"monday_sound_detective", "tuesday_memory_master", "wednesday_magic_story_maker",
		"thursday_paper_architect", "friday_emotion_detective", "saturday_rhythm_rockstar", "sunday_future_inventor",
	)
	for suffix in ("", "_2", "_3")
) + ("daily_surprise_spark",)
_PLACEHOLDER_INSTRUCTIONS = {
	"en": "Try the steps, notice what you discover, and tell a trusted grown-up what you learned.",
	"gu": "Pagala ajmavo, shu malyu te dhyanthi juo ane vishvasu mota vyaktine kaho.",
	"hi": "Kadam aazmaiye, jo dekha use dhyan se samajhiye aur kisi bharosemand bade ko batayiye.",
}


_INDIC_SUFFIXES = ("", "માં", "ને", "થી", "નો", "ની", "में", "को", "से", "का", "की")
_INDIC_TOKEN = re.compile(r"[ऀ-ॿ઀-૿]+")


def _has(patterns: Iterable[str], text: str, *, regex: bool) -> str | None:
	"""First restricted term found. English: whole words. Gujarati/Hindi: short terms must be whole words
	(so 'આગલી' / 'आगे', which merely start with 'fire', do not match); longer ones match anywhere."""
	tokens = _INDIC_TOKEN.findall(text)
	for pattern in patterns:
		if regex:
			if re.search(rf"\b(?:{pattern})\b", text, re.IGNORECASE):
				return pattern
		elif len(pattern) <= 3:
			if any(token == pattern or token in {pattern + suffix for suffix in _INDIC_SUFFIXES} for token in tokens):
				return pattern
		elif pattern in text:
			return pattern
	return None


def validate_catalogue(missions: Iterable[dict[str, Any]] = MISSIONS) -> list[str]:
	"""Every problem found, as readable strings. Empty means the catalogue is fit to seed."""
	missions = list(missions)
	problems: list[str] = []
	slugs: set[str] = set()
	titles: dict[tuple[str, str], str] = {}

	weekday_themes = set(THEMES_BY_WEEKDAY.values())
	covered = {mission["theme"] for mission in missions}
	for theme in sorted(weekday_themes - covered):
		problems.append(f"theme {theme}: no mission")
	for theme in sorted(covered - weekday_themes):
		problems.append(f"theme {theme}: not one of the seven weekday themes")

	for mission in missions:
		slug = mission["slug"]
		where = f"{slug}"
		try:
			DailyMissionTemplateCreate(**template_payload(mission))
		except ValidationError as error:
			problems.append(f"{where}: template invalid: {error.errors()[0]['msg']}")
		if slug in slugs:
			problems.append(f"{where}: duplicate slug")
		if slug in _PLACEHOLDER_SLUGS:
			problems.append(f"{where}: slug collides with a migration placeholder")
		slugs.add(slug)
		if not mission.get("skill"):
			problems.append(f"{where}: skill category missing")
		if sorted(mission["ages"]) != sorted(AGE_BANDS):
			problems.append(f"{where}: age bands are {sorted(mission['ages'])}, expected {list(AGE_BANDS)}")
		for age_band in AGE_BANDS:
			age = mission["ages"].get(age_band)
			if age is None:
				continue
			spot = f"{where}/{age_band}"
			if not MIN_MINUTES <= age.get("minutes", 0) <= MAX_MINUTES:
				problems.append(f"{spot}: duration {age.get('minutes')} min outside {MIN_MINUTES}-{MAX_MINUTES}")
			for field in ("rationale", "parent_involvement"):
				if not str(age.get(field, "")).strip():
					problems.append(f"{spot}: {field} missing")
			locales = age.get("locales", {})
			if sorted(locales) != sorted(LOCALES):
				problems.append(f"{spot}: locales are {sorted(locales)}, expected {list(LOCALES)}")
			step_counts = {locale: len(locales[locale].get("steps", [])) for locale in locales}
			material_counts = {locale: len(locales[locale].get("materials", [])) for locale in locales}
			if len(set(step_counts.values())) > 1:
				problems.append(f"{spot}: step counts differ between locales {step_counts}")
			if len(set(material_counts.values())) > 1:
				problems.append(f"{spot}: material counts differ between locales {material_counts}")
			for locale in LOCALES:
				text = locales.get(locale)
				if text is None:
					continue
				problems.extend(_validate_text(f"{spot}/{locale}", locale, mission, age_band, text))
				key = (locale, text.get("title", "").strip().casefold())
				if key in titles:
					problems.append(f"{spot}/{locale}: title also used by {titles[key]}")
				titles[key] = f"{spot}/{locale}"
	problems.extend(distinct_activity_problems(missions))
	return problems


def _step_words(mission: dict[str, Any], age_band: str) -> set[str]:
	steps = " ".join(mission["ages"][age_band]["locales"]["en"]["steps"]).lower()
	return set(re.findall(r"[a-z]+", steps)) - _STEP_STOP_WORDS


def distinct_activity_problems(missions: Iterable[dict[str, Any]]) -> list[str]:
	"""Problems that mean two templates are really one activity (or that nobody recorded what the activity is).

	Every mission needs an entry in ``activities.ACTIVITIES``; every ``mechanic`` must be unique across the catalogue;
	and two missions in one theme must not share more than ``MAX_STEP_SIMILARITY`` of their English step words in any
	age band (a rewritten title or reworded steps cannot make a repeat look new)."""
	missions = list(missions)
	problems: list[str] = []
	seen: dict[str, str] = {}
	for mission in missions:
		slug = mission["slug"]
		entry = ACTIVITIES.get(slug)
		if not entry or not str(entry.get("mechanic", "")).strip() or not str(entry.get("summary", "")).strip():
			problems.append(f"{slug}: no activity entry (mechanic and summary) in activities.py")
			continue
		if entry.get("evidence") not in ("guide_activity_type", "design_assumption"):
			problems.append(f"{slug}: activity evidence must be 'guide_activity_type' or 'design_assumption'")
		mechanic = entry["mechanic"]
		if mechanic in seen:
			problems.append(f"{slug}: same activity mechanic {mechanic!r} as {seen[mechanic]}")
		seen.setdefault(mechanic, slug)
	by_theme: dict[str, list[dict[str, Any]]] = defaultdict(list)
	for mission in missions:
		by_theme[mission["theme"]].append(mission)
	for theme, group in by_theme.items():
		for index, first in enumerate(group):
			for second in group[index + 1:]:
				for age_band in AGE_BANDS:
					if age_band not in first["ages"] or age_band not in second["ages"]:
						continue
					a, b = _step_words(first, age_band), _step_words(second, age_band)
					if a and b and len(a & b) / len(a | b) >= MAX_STEP_SIMILARITY:
						problems.append(f"{theme}: {first['slug']} and {second['slug']} have near-identical {age_band} steps")
	return problems


def target_problems(missions: Iterable[dict[str, Any]] = MISSIONS, per_theme: int = TARGET_TEMPLATES_PER_THEME) -> list[str]:
	"""Shortfalls against the catalogue target (exactly ``per_theme`` distinct activities in every weekday theme)."""
	missions = list(missions)
	problems: list[str] = []
	for theme in THEMES_BY_WEEKDAY.values():
		group = [m for m in missions if m["theme"] == theme]
		mechanics = {ACTIVITIES.get(m["slug"], {}).get("mechanic") for m in group} - {None}
		if len(group) != per_theme:
			problems.append(f"{theme}: {len(group)} templates, target {per_theme}")
		elif len(mechanics) != per_theme:
			problems.append(f"{theme}: {len(group)} templates but only {len(mechanics)} distinct activities")
	return problems


def _validate_text(spot: str, locale: str, mission: dict[str, Any], age_band: str, text: dict[str, Any]) -> list[str]:
	problems: list[str] = []
	for field in _TEXT_FIELDS:
		if not str(text.get(field, "")).strip():
			problems.append(f"{spot}: {field} missing")
	steps = text.get("steps", [])
	if len(steps) < MIN_STEPS:
		problems.append(f"{spot}: only {len(steps)} steps (need {MIN_STEPS}+)")
	if any(not str(step).strip() for step in steps):
		problems.append(f"{spot}: an empty step")
	if not text.get("materials"):
		problems.append(f"{spot}: materials missing")

	everything = [text.get(f, "") for f in _TEXT_FIELDS] + list(steps) + list(text.get("materials", []))
	for value in everything:
		if locale == "en":
			if not _SCRIPT["en"].match(value):
				problems.append(f"{spot}: non-ASCII text in English: {value[:40]!r}")
		else:
			bare = _PATTERN_SYMBOLS.sub("", value)
			if _LATIN.search(bare):
				problems.append(f"{spot}: Latin letters (romanised?) in {locale}: {value[:50]!r}")
	for field in ("title", "description", "alt", "safety", "show", "parent_check"):
		if locale != "en" and not _SCRIPT[locale].search(str(text.get(field, ""))):
			problems.append(f"{spot}: {field} has no {locale} script")
	for step in steps:
		if locale != "en" and not _SCRIPT[locale].search(step):
			problems.append(f"{spot}: a step has no {locale} script")

	# Children-facing text must not ask for unsafe things, purchases, permissions or pressure.
	asked = " ".join([*steps, text.get("alt", ""), text.get("show", ""), text.get("parent_check", ""), *text.get("materials", [])])
	hit = _has(_UNSAFE[locale], asked, regex=locale == "en")
	if hit:
		problems.append(f"{spot}: unsafe or restricted term {hit!r} in the activity text")
	hit = _has(_PRESSURE[locale], " ".join([asked, text.get("description", "")]), regex=locale == "en")
	if hit:
		problems.append(f"{spot}: pressure/shaming term {hit!r}")
	if "http" in asked.lower() or "www." in asked.lower():
		problems.append(f"{spot}: contains a link")

	try:
		payload = variation_payload(mission, age_band, locale)
		DailyMissionVariationCreate(**payload)
		stored = len(payload["description"]) + len(payload["instructions"]) + len(payload["completion_criteria"])
		if stored > MAX_STORED_TASK_TEXT:
			problems.append(f"{spot}: {stored} characters of task text (limit {MAX_STORED_TASK_TEXT})")
		for label in (LABELS["parent_check"][locale], LABELS["another_way"][locale]):
			if label not in payload["instructions"] + payload["completion_criteria"]:
				problems.append(f"{spot}: label {label!r} missing")
	except ValidationError as error:
		problems.append(f"{spot}: rejected by the admin validator: {error.errors()[0]['msg']}")
	return problems


def apply_catalogue(session: Session, missions: Iterable[dict[str, Any]] = MISSIONS, *, publish: bool = False) -> dict[str, Any]:
	"""Create what is missing. Never updates or deletes. The caller commits."""
	problems = validate_catalogue(missions := list(missions))
	if problems:
		raise ValueError("catalogue is invalid: " + "; ".join(problems[:5]))
	Template = get_model("DailyMissionTemplate")
	Variation = get_model("DailyMissionVariation")
	report: dict[str, Any] = {
		"templates_created": 0,
		"templates_existing": 0,
		"variations_created": 0,
		"variations_existing": 0,
		"variations_differing": [],
		"published": 0,
	}
	for mission in missions:
		template = session.query(Template).filter(Template.slug == mission["slug"]).one_or_none()
		created = template is None
		if created:
			template = Template(**template_payload(mission), is_published=False)
			session.add(template)
			session.flush()
			report["templates_created"] += 1
		else:
			report["templates_existing"] += 1
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				existing = (
					session.query(Variation)
					.filter(
						Variation.template_id == template.id,
						Variation.age_band == age_band,
						Variation.locale == locale,
						Variation.variation_key == CATALOGUE_VARIATION_KEY,
					)
					.one_or_none()
				)
				if existing is None:
					session.add(Variation(template_id=template.id, **payload))
					report["variations_created"] += 1
				else:
					report["variations_existing"] += 1
					if any(getattr(existing, field) != value for field, value in payload.items() if field != "variation_key"):
						report["variations_differing"].append(f"{mission['slug']}/{age_band}/{locale}")
		session.flush()
		if publish and created:
			rows = session.query(Variation.age_band, Variation.locale).filter(Variation.template_id == template.id).all()
			if has_complete_localized_variations(rows):
				template.is_published = True
				report["published"] += 1
	session.flush()
	return report


def retire_placeholders(session: Session) -> dict[str, list[str]]:
	"""Unpublish (never delete) the migration-0015 placeholder templates that still carry their original text.

	A placeholder whose text an administrator has changed is left alone and reported."""
	Template = get_model("DailyMissionTemplate")
	Variation = get_model("DailyMissionVariation")
	report: dict[str, list[str]] = {"unpublished": [], "kept_edited": [], "already_unpublished": []}
	for slug in _PLACEHOLDER_SLUGS:
		template = session.query(Template).filter(Template.slug == slug).one_or_none()
		if template is None:
			continue
		if not template.is_published:
			report["already_unpublished"].append(slug)
			continue
		rows = session.query(Variation).filter(Variation.template_id == template.id).all()
		untouched = bool(rows) and all(
			row.variation_key == "v1" and row.instructions == _PLACEHOLDER_INSTRUCTIONS.get(row.locale) for row in rows
		)
		if untouched:
			template.is_published = False
			report["unpublished"].append(slug)
		else:
			report["kept_edited"].append(slug)
	session.flush()
	return report


def missing_combinations(rows: Iterable[tuple[str, str]]) -> list[str]:
	"""The age/locale pairs a template still lacks, as ``"4_6:gu"`` (the publish rule needs all nine)."""
	present = set(rows)
	return [f"{age}:{locale}" for age in AGE_BANDS for locale in LOCALES if (age, locale) not in present]


FALLBACK_WINDOW_DAYS = 14


def assignment_counts(session: Session) -> dict:
	"""How many times each template has ever been assigned to any child (offered, chosen or skipped)."""
	Assignment = get_model("DailyMissionAssignment")
	return {
		template_id: int(count)
		for template_id, count in session.query(Assignment.template_id, func.count(Assignment.id)).group_by(Assignment.template_id).all()
	}


def catalogue_health(session: Session, now_utc: datetime | None = None, *, min_eligible: int = MIN_ELIGIBLE_PER_THEME) -> dict[str, Any]:
	"""Rotation capacity per weekday theme, assignment frequency and recent cooldown fallbacks (read-only).

	*Eligible* = published and complete (all nine age-band x language versions). A theme with fewer than
	``min_eligible`` eligible templates will repeat missions, so it is flagged with its shortfall."""
	now_utc = now_utc or datetime.now(timezone.utc)
	Template = get_model("DailyMissionTemplate")
	Variation = get_model("DailyMissionVariation")
	Assignment = get_model("DailyMissionAssignment")
	combos: dict = defaultdict(set)
	for template_id, age_band, locale in session.query(Variation.template_id, Variation.age_band, Variation.locale).all():
		combos[template_id].add((age_band, locale))
	counts = assignment_counts(session)

	window_start = now_utc.date() - timedelta(days=FALLBACK_WINDOW_DAYS)
	fallback_by_template: Counter = Counter()
	fallback_children: set = set()
	for template_id, child_id, snapshot in (
		session.query(Assignment.template_id, Assignment.child_id, Assignment.snapshot).filter(Assignment.local_date >= window_start).all()
	):
		if ((snapshot or {}).get("rotation") or {}).get("tier") == "cooldown_fallback":
			fallback_by_template[template_id] += 1
			fallback_children.add(child_id)

	templates = session.query(Template).order_by(Template.theme, Template.slug).all()
	per_theme: dict[str, list] = defaultdict(list)
	for template in templates:
		per_theme[template.theme].append(template)
	last_assigned = {
		template_id: last
		for template_id, last in session.query(Assignment.template_id, func.max(Assignment.local_date)).group_by(Assignment.template_id).all()
	}

	themes, warnings, activity_warnings = [], [], []
	for theme in THEMES_BY_WEEKDAY.values():
		rows = per_theme.get(theme, [])
		published = [t for t in rows if t.is_published]
		complete = lambda t: not missing_combinations(combos.get(t.id, set()))  # noqa: E731
		eligible = [t for t in published if complete(t)]
		age_bands = {age: sum(any(a == age for a, _ in combos.get(t.id, ())) for t in published) for age in AGE_BANDS}
		locales = {
			locale: sum(all((age, locale) in combos.get(t.id, set()) for age in AGE_BANDS) for t in published) for locale in LOCALES
		}
		shortfall = max(0, min_eligible - len(eligible))
		if shortfall:
			warnings.append(
				f"{theme}: {len(eligible)} eligible published template(s), fewer than {min_eligible}; missions will repeat (publish {shortfall} more)"
			)
		# Six rows are not six activities: count distinct *activities* among the eligible templates the catalogue source knows about.
		by_mechanic: dict[str, list[str]] = defaultdict(list)
		unverified = []
		for template in eligible:
			entry = ACTIVITIES.get(template.slug)
			if entry:
				by_mechanic[entry["mechanic"]].append(template.slug)
			else:
				unverified.append(template.slug)
		duplicate_activities = [{"mechanic": mechanic, "slugs": slugs} for mechanic, slugs in sorted(by_mechanic.items()) if len(slugs) > 1]
		verified_distinct = len(by_mechanic)
		healthy = not shortfall and verified_distinct >= min_eligible and not duplicate_activities
		if not shortfall and not healthy:
			activity_warnings.append(
				f"{theme}: {len(eligible)} eligible templates but only {verified_distinct} verified distinct activities"
				+ (f" ({len(unverified)} not in the catalogue source, so not checked)" if unverified else "")
				+ ("; duplicate activities: " + ", ".join(d["mechanic"] for d in duplicate_activities) if duplicate_activities else "")
			)
		themes.append(
			{
				"theme": theme,
				"templates": len(rows),
				"published": len(published),
				"eligible": len(eligible),
				"insufficient": bool(shortfall),
				"shortfall": shortfall,
				"verified_distinct": verified_distinct,
				"unverified": unverified,
				"duplicate_activities": duplicate_activities,
				"healthy": healthy,
				"age_bands": age_bands,
				"locales": locales,
				"unpublished": [t.slug for t in rows if not t.is_published],
				"incomplete": [t.slug for t in rows if not complete(t)],
			}
		)
	slug_of = {t.id: t.slug for t in templates}
	return {
		"min_eligible_per_theme": min_eligible,
		"themes": themes,
		"templates": [
			{
				"slug": t.slug,
				"theme": t.theme,
				"is_published": bool(t.is_published),
				"is_complete": not missing_combinations(combos.get(t.id, set())),
				"assignment_count": counts.get(t.id, 0),
				"last_assigned": last_assigned[t.id].isoformat() if last_assigned.get(t.id) else None,
				"fallback_count": fallback_by_template.get(t.id, 0),
			}
			for t in templates
		],
		"totals": {
			"templates": len(templates),
			"published": sum(1 for t in templates if t.is_published),
			"unpublished": sum(1 for t in templates if not t.is_published),
			"complete": sum(1 for t in templates if not missing_combinations(combos.get(t.id, set()))),
			"incomplete": sum(1 for t in templates if missing_combinations(combos.get(t.id, set()))),
			"never_assigned": sum(1 for t in templates if t.is_published and not counts.get(t.id)),
			"most_assigned": max((counts.get(t.id, 0) for t in templates if t.is_published), default=0),
		},
		"fallbacks": {
			"days": FALLBACK_WINDOW_DAYS,
			"count": sum(fallback_by_template.values()),
			"children": len(fallback_children),
			"by_template": [
				{"slug": slug_of.get(template_id, str(template_id)), "count": count}
				for template_id, count in fallback_by_template.most_common()
			],
		},
		"warnings": warnings,
		"activity_warnings": activity_warnings,
	}


def catalogue_summary(missions: Iterable[dict[str, Any]] = MISSIONS) -> dict[str, int]:
	missions = list(missions)
	return {
		"templates": len(missions),
		"themes": len({m["theme"] for m in missions}),
		"distinct_activities": len({ACTIVITIES.get(m["slug"], {}).get("mechanic") for m in missions} - {None}),
		"variations": sum(len(m["ages"]) * len(LOCALES) for m in missions),
		"age_specific_missions": sum(len(m["ages"]) for m in missions),
		**{f"variations_{loc}": sum(len(m["ages"]) for m in missions) for loc in LOCALES},
	}
