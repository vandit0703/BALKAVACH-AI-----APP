"""Mission rotation and repeat prevention (milestone C2).

Pure ranking tests need nothing. The rest run on the in-memory SQLite "world" (``tests/sqlite_world.py``):
they prove the logic, **not** PostgreSQL behaviour (row locks, the partial unique indexes' exact semantics).
"""

from collections import Counter
from datetime import date, datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy.exc import IntegrityError

from app.core.exceptions import APIError
from app.services.daily_mission_service import (
	THEMES_BY_WEEKDAY,
	ensure_daily_choices,
	select_assignment,
	skip_assignment,
)
from app.services.mission_rotation_service import (
	Candidate,
	ChildHistory,
	load_child_history,
	rank_candidates,
)
from app.services.timezone_service import local_today
from tests.sqlite_world import (
	DailyMissionAssignment,
	DailyMissionTemplate,
	DailyMissionVariation,
	User,
	make_family,
	make_pool,
	world_session,  # noqa: F401  (fixture)
)

DAY0 = datetime(2026, 11, 2, 9, 0, tzinfo=timezone.utc)  # a Monday


def at(days: int, hour: int = 9) -> datetime:
	return (DAY0 + timedelta(days=days)).replace(hour=hour)


def run_day(session, child, days: int, *, pick: int | None = 0, status: str = "approved"):
	"""Fetch the day's choices; optionally choose one and move it to ``status`` (the parent's verdict)."""
	_, _, choices = ensure_daily_choices(session, child, at(days))
	chosen = None
	if pick is not None:
		chosen = select_assignment(session, child, choices[pick].id)
		chosen.status = status
	session.commit()
	return choices, chosen


def ids(choices):
	return {c.template_id for c in choices}


# -- the pure ranking -----------------------------------------------------------------------------------

def candidate(theme="monday_sound_detective", surprise=False):
	return Candidate(id=uuid4(), theme=theme, is_surprise=surprise)


TODAY = date(2026, 11, 20)


def test_cooldown_is_42_days_for_engaged_missions_and_7_for_rejected():
	a, b = candidate(), candidate()
	history = ChildHistory(
		last_engaged={a.id: TODAY - timedelta(days=41)},
		last_rejected={b.id: TODAY - timedelta(days=6)},
	)
	picks = {p.candidate.id: p for p in rank_candidates([a, b], history, TODAY, "x", "seed", limit=2)}
	assert picks[a.id].tier == 1 and picks[b.id].tier == 1
	later = ChildHistory(
		last_engaged={a.id: TODAY - timedelta(days=42)},
		last_rejected={b.id: TODAY - timedelta(days=7)},
	)
	picks = {p.candidate.id: p for p in rank_candidates([a, b], later, TODAY, "x", "seed", limit=2)}
	assert picks[a.id].tier == 0 and picks[b.id].tier == 0


def test_fresh_candidates_always_beat_cooldown_ones_even_in_the_weekday_theme():
	in_theme_cooling = candidate("monday_sound_detective")
	other_fresh = [candidate("tuesday_memory_master"), candidate("friday_emotion_detective"), candidate("sunday_future_inventor")]
	history = ChildHistory(last_engaged={in_theme_cooling.id: TODAY - timedelta(days=3)})
	picks = rank_candidates([in_theme_cooling, *other_fresh], history, TODAY, "monday_sound_detective", "s", limit=3)
	assert in_theme_cooling.id not in {p.candidate.id for p in picks}
	assert all(p.tier == 0 for p in picks)


def test_weekday_theme_then_not_recent_then_least_shown_then_deterministic():
	theme = [candidate("monday_sound_detective") for _ in range(3)]
	other = [candidate("tuesday_memory_master")]
	history = ChildHistory(
		recent_offered={theme[0].id},  # shown on one of the last two offered days
		offered_count={theme[1].id: 5, theme[2].id: 1},
	)
	picks = rank_candidates([*other, *theme], history, TODAY, "monday_sound_detective", "s", limit=4)
	order = [p.candidate.id for p in picks]
	# first pick: weekday theme, not recent, least shown
	assert order[0] == theme[2].id
	assert order.index(theme[0].id) > order.index(theme[1].id)  # a recent one ranks below a non-recent one
	assert rank_candidates([*other, *theme], history, TODAY, "monday_sound_detective", "s", limit=4) == picks  # deterministic


def test_a_different_seed_gives_a_different_but_stable_tie_break():
	pool = [
		Candidate(id=UUID(int=index), theme=theme, is_surprise=False)
		for index, theme in enumerate(t for t in THEMES_BY_WEEKDAY.values() for _ in range(6))
	]
	one = rank_candidates(pool, ChildHistory(), TODAY, "monday_sound_detective", "child-1:2026-11-20", limit=3)
	two = rank_candidates(pool, ChildHistory(), TODAY, "monday_sound_detective", "child-2:2026-11-20", limit=3)
	assert one == rank_candidates(pool, ChildHistory(), TODAY, "monday_sound_detective", "child-1:2026-11-20", limit=3)
	assert [p.candidate.id for p in one] != [p.candidate.id for p in two]


def test_choices_prefer_different_themes_when_available():
	pool = [candidate("monday_sound_detective") for _ in range(4)] + [candidate("tuesday_memory_master"), candidate("friday_emotion_detective")]
	picks = rank_candidates(pool, ChildHistory(), TODAY, "monday_sound_detective", "s", limit=3)
	assert len({p.candidate.theme for p in picks}) == 3


def test_fallback_orders_by_oldest_shown_then_least_frequent():
	old, newer, never_engaged = candidate(), candidate(), candidate()
	history = ChildHistory(
		last_engaged={old.id: TODAY - timedelta(days=30), newer.id: TODAY - timedelta(days=3), never_engaged.id: TODAY - timedelta(days=10)},
		offered_count={old.id: 4, newer.id: 1, never_engaged.id: 1},
	)
	picks = rank_candidates([newer, never_engaged, old], history, TODAY, "x", "s", limit=3)
	assert [p.candidate.id for p in picks] == [old.id, never_engaged.id, newer.id]
	assert all(p.tier == 1 for p in picks)


def test_pending_active_and_same_day_missions_are_never_candidates_even_as_fallback():
	active, today_issued, ok = candidate(), candidate(), candidate()
	history = ChildHistory(active={active.id}, issued_today={today_issued.id})
	picks = rank_candidates([active, today_issued, ok], history, TODAY, "x", "s", limit=3)
	assert [p.candidate.id for p in picks] == [ok.id]


def test_nothing_eligible_returns_nothing():
	assert rank_candidates([], ChildHistory(), TODAY, "x", "s", limit=3) == []


def test_surprise_leads_only_when_fresh_and_not_recently_offered():
	surprise, normal = candidate("tuesday_memory_master", surprise=True), [candidate("tuesday_memory_master") for _ in range(2)]
	first = rank_candidates([*normal, surprise], ChildHistory(), TODAY, "monday_sound_detective", "s", limit=3)
	assert first[0].candidate.id == surprise.id
	second = rank_candidates([*normal, surprise], ChildHistory(recent_offered={surprise.id}), TODAY, "monday_sound_detective", "s", limit=3)
	assert second[0].candidate.id != surprise.id


# -- through the service (SQLite world) ------------------------------------------------------------------------

def test_approved_mission_is_not_offered_again_for_42_days_while_alternatives_exist(world_session):
	make_pool(world_session, per_theme=1)  # 7 templates: only the cooldown can keep the mission out
	child = make_family(world_session)
	_, chosen = run_day(world_session, child, 0)
	for day in range(1, 42):
		choices, _ = run_day(world_session, child, day, pick=None)
		assert chosen.template_id not in ids(choices), f"repeated on day {day}"


def test_the_mission_returns_once_the_cooldown_has_passed(world_session):
	make_pool(world_session, per_theme=1)  # 7 templates: after 42 days all history has expired
	child = make_family(world_session)
	run_day(world_session, child, 0)
	choices, _ = run_day(world_session, child, 42, pick=None)
	assert all(c.snapshot["rotation"]["tier"] == "fresh" for c in choices)


def test_skipped_missions_count_as_recently_shown(world_session):
	make_pool(world_session, per_theme=4)
	child = make_family(world_session)
	_, _, choices = ensure_daily_choices(world_session, child, at(0))
	skipped_template = choices[0].template_id
	skip_assignment(world_session, child, choices[0].id, at(0))
	world_session.commit()
	for day in range(1, 10):
		later, _ = run_day(world_session, child, day, pick=None)
		assert skipped_template not in ids(later)


def test_rejected_missions_may_return_after_a_week_not_before(world_session):
	make_pool(world_session, per_theme=4)
	child = make_family(world_session)
	_, chosen = run_day(world_session, child, 0, status="rejected")
	for day in range(1, 7):
		choices, _ = run_day(world_session, child, day, pick=None)
		assert chosen.template_id not in ids(choices)


def test_a_mission_waiting_for_review_is_never_reassigned_even_with_a_tiny_catalogue(world_session):
	make_pool(world_session, per_theme=1)
	only_four = world_session.query(DailyMissionTemplate).all()[4:]
	for template in only_four:
		template.is_published = False
	world_session.commit()  # four published templates remain
	child = make_family(world_session)
	_, pending = run_day(world_session, child, 0, status="pending_parent_approval")
	for day in range(1, 4):
		choices, _ = run_day(world_session, child, day, pick=None)
		assert pending.template_id not in ids(choices)
		assert len(choices) == 3


def test_offered_but_ignored_choices_do_not_come_straight_back(world_session):
	make_pool(world_session, per_theme=3)  # 21 templates
	child = make_family(world_session)
	shown, _ = run_day(world_session, child, 0, pick=None)
	again, _ = run_day(world_session, child, 1, pick=None)
	assert not (ids(shown) & ids(again))


def test_assignment_frequency_is_balanced_when_the_child_ignores_everything(world_session):
	make_pool(world_session, per_theme=2)  # 14 templates
	child = make_family(world_session)
	counts = Counter()
	for day in range(28):
		choices, _ = run_day(world_session, child, day, pick=None)
		counts.update(c.template_id for c in choices)
	assert len(counts) == 14
	assert max(counts.values()) - min(counts.values()) <= 2


def test_same_day_requests_are_idempotent_and_never_duplicate_a_template(world_session):
	make_pool(world_session, per_theme=2)
	child = make_family(world_session)
	_, _, first = ensure_daily_choices(world_session, child, at(0))
	_, _, second = ensure_daily_choices(world_session, child, at(0, hour=20))
	assert [c.id for c in first] == [c.id for c in second]
	assert len(ids(first)) == 3
	assert world_session.query(DailyMissionAssignment).count() == 3


def test_a_skip_replacement_is_never_a_template_already_issued_today(world_session):
	make_pool(world_session, per_theme=2)
	child = make_family(world_session)
	_, _, choices = ensure_daily_choices(world_session, child, at(0))
	_, replaced = skip_assignment(world_session, child, choices[0].id, at(0))
	assert len(ids(replaced)) == 3
	assert choices[0].template_id not in ids(replaced)


def test_a_concurrent_duplicate_row_is_stopped_by_the_database_index(world_session):
	"""On PostgreSQL the child-row lock serialises requests; the partial unique index is the second guard."""
	make_pool(world_session, per_theme=2)
	child = make_family(world_session)
	_, _, rows = ensure_daily_choices(world_session, child, at(0))
	world_session.commit()
	clone = DailyMissionAssignment(
		child_id=child.id, family_id=child.family_id, local_date=rows[0].local_date, choice_slot=rows[0].choice_slot,
		age_band=rows[0].age_band, template_id=rows[0].template_id, variation_id=rows[0].variation_id, snapshot={}, is_current=True,
	)
	world_session.add(clone)
	with pytest.raises(IntegrityError):
		world_session.flush()
	world_session.rollback()


def test_the_family_timezone_decides_the_local_day_and_the_cooldown_boundary(world_session):
	make_pool(world_session, per_theme=1)
	child = make_family(world_session, timezone_name="Asia/Kolkata")
	late = datetime(2026, 11, 2, 18, 29, tzinfo=timezone.utc)  # 23:59 IST on the 2nd
	local, _, choices = ensure_daily_choices(world_session, child, late)
	assert local == date(2026, 11, 2)
	chosen = select_assignment(world_session, child, choices[0].id)
	chosen.status = "approved"
	world_session.commit()
	template = world_session.get(DailyMissionTemplate, chosen.template_id)
	same = Candidate(id=template.id, theme=template.theme, is_surprise=False)
	# 41 local days later the template is still cooling down; one minute of UTC later it is the 42nd local day.
	for instant, expected_day, expected_tier in (
		(datetime(2026, 12, 13, 18, 29, tzinfo=timezone.utc), date(2026, 12, 13), 1),
		(datetime(2026, 12, 13, 18, 30, tzinfo=timezone.utc), date(2026, 12, 14), 0),
	):
		day = local_today(world_session, child.family_id, instant)
		assert day == expected_day
		history = load_child_history(world_session, child.id, day)
		assert rank_candidates([same], history, day, "x", "s", limit=1)[0].tier == expected_tier


def test_languages_are_not_separate_missions_for_repeat_prevention(world_session):
	make_pool(world_session, per_theme=3, locales=("en", "gu", "hi"))
	child = make_family(world_session, language="en")
	_, chosen = run_day(world_session, child, 0)
	for day, language in ((1, "gu"), (2, "hi"), (3, "en"), (4, "gu")):
		world_session.query(User).filter(User.id == child.user_id).one().preferred_language = language
		choices, _ = run_day(world_session, child, day, pick=None)
		assert chosen.template_id not in ids(choices)
		assert {c.snapshot["locale"] for c in choices} == {language}


# -- fallback and errors ---------------------------------------------------------------------------------------

def test_a_catalogue_of_three_never_returns_503_after_approvals_but_flags_the_fallback(world_session):
	make_pool(world_session, per_theme=1)
	for template in world_session.query(DailyMissionTemplate).all()[3:]:
		template.is_published = False
	world_session.commit()
	child = make_family(world_session)
	run_day(world_session, child, 0)
	choices, _ = run_day(world_session, child, 1, pick=None)
	assert len(choices) == 3
	tiers = Counter(c.snapshot["rotation"]["tier"] for c in choices)
	assert tiers == {"fresh": 2, "cooldown_fallback": 1}
	fallback = next(c for c in choices if c.snapshot["rotation"]["tier"] == "cooldown_fallback")
	assert fallback.snapshot["rotation"]["last_shown"] == "2026-11-02"


def test_fallback_uses_the_oldest_shown_mission_first(world_session):
	make_pool(world_session, per_theme=1)
	for template in world_session.query(DailyMissionTemplate).all()[4:]:
		template.is_published = False
	world_session.commit()  # four templates
	child = make_family(world_session)
	_, first = run_day(world_session, child, 0)
	_, second = run_day(world_session, child, 1)
	choices, _ = run_day(world_session, child, 2, pick=None)
	assert len(choices) == 3
	fallback = [c for c in choices if c.snapshot["rotation"]["tier"] == "cooldown_fallback"]
	assert fallback and fallback[0].template_id in {first.template_id, second.template_id}


def test_an_empty_or_fully_unpublished_catalogue_gives_a_clear_error(world_session):
	child = make_family(world_session)
	with pytest.raises(APIError) as error:
		ensure_daily_choices(world_session, child, at(0))
	assert error.value.status_code == 503 and error.value.code == "daily_missions_unavailable"
	assert error.value.details["eligible"] == 0
	make_pool(world_session, per_theme=1)
	for template in world_session.query(DailyMissionTemplate).all():
		template.is_published = False
	world_session.commit()
	with pytest.raises(APIError) as error:
		ensure_daily_choices(world_session, child, at(0))
	assert error.value.code == "daily_missions_unavailable"


def test_a_template_without_a_variation_for_the_childs_age_is_not_eligible(world_session):
	make_pool(world_session, per_theme=1, age_bands=("7_10",))
	child = make_family(world_session, birth=date(2021, 3, 1))  # ages 4-6
	with pytest.raises(APIError) as error:
		ensure_daily_choices(world_session, child, at(0))
	assert error.value.code == "daily_missions_unavailable" and error.value.details["age_band"] == "4_6"


def test_unpublished_templates_are_ignored_but_history_is_kept(world_session):
	make_pool(world_session, per_theme=2)
	child = make_family(world_session)
	_, chosen = run_day(world_session, child, 0)
	template = world_session.get(DailyMissionTemplate, chosen.template_id)
	template.is_published = False
	world_session.commit()
	choices, _ = run_day(world_session, child, 50, pick=None)
	assert chosen.template_id not in ids(choices)
	assert world_session.get(DailyMissionAssignment, chosen.id).status == "approved"


# -- the child cannot exhaust the catalogue ------------------------------------------------------------------------

def test_a_child_completing_a_mission_every_day_for_a_year_never_hits_an_error(world_session):
	make_pool(world_session, per_theme=2)  # 14 templates: far fewer than the cooldown needs
	child = make_family(world_session)
	chosen_by_day = []
	for day in range(365):
		choices, chosen = run_day(world_session, child, day)
		assert len(choices) == 3 and len(ids(choices)) == 3
		chosen_by_day.append(chosen.template_id)
	assert all(chosen_by_day[i] != chosen_by_day[i - 1] for i in range(1, 365))
	assert len(set(chosen_by_day)) == 14
	counts = Counter(chosen_by_day)
	assert max(counts.values()) - min(counts.values()) <= 4


def test_with_42_templates_no_chosen_mission_repeats_inside_42_days(world_session):
	make_pool(world_session, per_theme=6)  # the target catalogue size
	child = make_family(world_session)
	last = {}
	for day in range(150):
		_, chosen = run_day(world_session, child, day)
		if chosen.template_id in last:
			assert day - last[chosen.template_id] >= 42, (day, last[chosen.template_id])
		last[chosen.template_id] = day
