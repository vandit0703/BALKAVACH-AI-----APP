"""Tests for the Mission Library validator, loader, seeder idempotency, and non-weekday rotation."""

from __future__ import annotations

from datetime import date

from app.content.daily_missions import MISSIONS
from app.content.mission_library import CATEGORIES, CONCEPTS, LIBRARY_ACTIVITIES, LIBRARY_MISSIONS, is_publishable_translation
from app.services.mission_catalogue_service import apply_catalogue, validate_catalogue
from app.services.mission_library_service import DURATION_RANGE, library_problems, validate_library_catalogue
from app.services.mission_rotation_service import Candidate, ChildHistory, rank_candidates
from tests.sqlite_world import world_session  # noqa: F401


def test_library_batches_001_and_002_pass_all_hard_checks():
	result = validate_library_catalogue()
	assert result["errors"] == []
	assert result["coverage"]["concepts"] == 12
	assert result["coverage"]["age_specific_variations"] == 36
	assert result["coverage"]["localized_records"] == 108
	assert result["coverage"]["categories_covered"] == 12
	assert len(CONCEPTS) == 12


def test_pending_translations_are_flagged_and_never_published(world_session):
	session = world_session
	assert all(not is_publishable_translation(m) for m in LIBRARY_MISSIONS)
	report = apply_catalogue(session, LIBRARY_MISSIONS, publish=True)
	assert report["templates_created"] == len(LIBRARY_MISSIONS)
	assert report["variations_created"] == len(LIBRARY_MISSIONS) * 9
	assert report["published"] == 0
	assert len(report["publish_blocked"]) == len(LIBRARY_MISSIONS)
	assert all(b["problems"] == ["translation_pending_native_review"] for b in report["publish_blocked"])


def test_library_seeding_is_idempotent_and_preserves_existing(world_session):
	session = world_session
	first = apply_catalogue(session, [*MISSIONS, *LIBRARY_MISSIONS], publish=False)
	second = apply_catalogue(session, [*MISSIONS, *LIBRARY_MISSIONS], publish=False)
	assert first["templates_created"] == len(MISSIONS) + len(LIBRARY_MISSIONS)
	assert second["templates_created"] == 0
	assert second["variations_created"] == 0
	assert second["templates_existing"] == len(MISSIONS) + len(LIBRARY_MISSIONS)
	assert second["variations_existing"] == (len(MISSIONS) + len(LIBRARY_MISSIONS)) * 9


def test_library_validator_rejects_romanised_and_unsafe_terms():
	broken = dict(LIBRARY_MISSIONS[0])
	broken_ages = {k: dict(v) for k, v in broken["ages"].items()}
	broken_locales = {k: dict(v) for k, v in broken_ages["4_6"]["locales"].items()}
	broken_locales["hi"] = {**broken_locales["hi"], "title": "Alag cheez"}
	broken_ages["4_6"]["locales"] = broken_locales
	broken["ages"] = broken_ages
	errs = library_problems([broken], MISSIONS)
	assert any("Latin letters in title" in e for e in errs)


def test_rotation_has_no_weekday_bias():
	from uuid import uuid4

	c1 = Candidate(id=uuid4(), theme="monday_sound_detective", is_surprise=False)
	c2 = Candidate(id=uuid4(), theme="logic_problem_solving", is_surprise=False)
	history = ChildHistory(offered_count={c1.id: 3, c2.id: 1})
	picks_monday = rank_candidates([c1, c2], history, date(2026, 11, 23), "monday_sound_detective", "seed", limit=2)
	picks_friday = rank_candidates([c1, c2], history, date(2026, 11, 23), "friday_emotion_detective", "seed", limit=2)
	assert picks_monday == picks_friday
	assert picks_monday[0].candidate.id == c2.id


def test_validate_catalogue_accepts_library_categories():
	errs = validate_catalogue(
		LIBRARY_MISSIONS,
		allowed_themes=set(CATEGORIES),
		activities=LIBRARY_ACTIVITIES,
		duration_ranges=DURATION_RANGE,
	)
	assert errs == []
