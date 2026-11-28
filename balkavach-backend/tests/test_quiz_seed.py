"""Tests for the localized quiz content pack and idempotent ``seed-quizzes`` CLI."""

from __future__ import annotations

from datetime import date, timedelta
from uuid import uuid4

import pytest

from app import cli
from app.content.quizzes import QUIZ_PACK, quiz_uuid
from app.db.base import get_model
from app.services.quiz_seed_service import seed_quizzes, validate_quiz_pack
from tests.harness import PASSWORD


# -- pack validation & CLI dry-run (no database) -------------------------------------------------


def test_quiz_pack_counts_languages_difficulties_and_types():
	valid, errors = validate_quiz_pack(QUIZ_PACK)
	assert errors == []
	assert len(valid) == 30

	by_lang: dict[str, int] = {}
	by_diff: dict[tuple[str, str], int] = {}
	types: set[str] = set()
	min_ages, max_ages = [], []

	for _slug, quiz in valid:
		by_lang[quiz.language_code] = by_lang.get(quiz.language_code, 0) + 1
		key = (quiz.language_code, quiz.difficulty)
		by_diff[key] = by_diff.get(key, 0) + 1
		assert len(quiz.questions) == 10
		min_ages.append(quiz.age_min)
		max_ages.append(quiz.age_max)
		for q in quiz.questions:
			types.add(q.question_type)

	assert by_lang == {"en": 10, "hi": 10, "gu": 10}
	for lang in ("en", "hi", "gu"):
		for diff in ("easy", "medium", "hard"):
			assert by_diff.get((lang, diff), 0) >= 2, f"Missing {lang}/{diff}"
	assert types == {"single", "multiple", "true_false"}
	assert min(min_ages) == 4
	assert max(max_ages) == 15


def test_cli_seed_quizzes_dry_run_and_flag_validation(capsys):
	assert cli.main(["seed-quizzes", "--dry-run"]) == 0
	out = capsys.readouterr().out
	assert "created=30, updated=0, skipped=0, invalid=0" in out

	with pytest.raises(SystemExit):
		cli.main(["seed-quizzes", "--publish"])
	with pytest.raises(SystemExit):
		cli.main(["seed-quizzes", "--dry-run", "--apply"])


def test_invalid_pack_is_rejected_without_writes():
	bad_pack = [
		{"slug": "bad-quiz", "quiz": {"title": "x", "questions": []}},
		{"slug": "dup", "quiz": QUIZ_PACK[0]["quiz"]},
		{"slug": "dup", "quiz": QUIZ_PACK[0]["quiz"]},
	]
	report = seed_quizzes(None, bad_pack, apply=False)
	assert report["invalid"] == 2
	assert report["created"] == 0


# -- PostgreSQL integration (skipped without TEST_DATABASE_URL) ----------------------------------


def _child(api, *, language: str = "en", age_years: int = 8):
	parent = api.register_parent()
	family = api.create_family(parent["token"])
	dob = (date.today() - timedelta(days=age_years * 365 + 30)).isoformat()
	username = f"kid_{uuid4().hex[:8]}"
	res = api.post(
		f"/families/{family['id']}/children",
		parent["token"],
		{
			"display_name": "Aarav",
			"username": username,
			"password": PASSWORD,
			"date_of_birth": dob,
			"preferred_language": language,
		},
	)
	assert res.status_code == 201, res.text
	created = res.json()
	session = api.post(f"/auth/children/{created['id']}/session", parent["token"])
	assert session.status_code == 200, session.text
	return {"id": created["id"], "token": session.json()["access_token"]}


def test_postgres_seed_idempotency_and_preservation(isolated_test_session):
	Quiz = get_model("Quiz")
	QuizQuestion = get_model("QuizQuestion")
	QuizOption = get_model("QuizOption")

	# Manually authored quiz must survive untouched.
	manual = Quiz(
		title="Manual Parent Quiz",
		subject="general",
		difficulty="easy",
		language_code="en",
		age_min=4,
		age_max=15,
		pass_percent=60,
		star_reward=5,
		xp_reward=10,
		allow_retry=True,
		is_published=True,
		revision=1,
	)
	isolated_test_session.add(manual)
	isolated_test_session.commit()

	first = seed_quizzes(isolated_test_session, QUIZ_PACK, apply=True, publish=False)
	assert first == {"created": 30, "updated": 0, "skipped": 0, "invalid": 0, "errors": []}
	assert isolated_test_session.query(Quiz).count() == 31
	assert isolated_test_session.query(QuizQuestion).count() == 300
	assert isolated_test_session.query(QuizOption).count() >= 600

	# Unpublished by default unless --publish is given.
	seeded_sample = isolated_test_session.query(Quiz).filter(Quiz.id == quiz_uuid("en-animal-friends-easy")).one()
	assert seeded_sample.is_published is False

	# Second run is 100% idempotent.
	second = seed_quizzes(isolated_test_session, QUIZ_PACK, apply=True, publish=False)
	assert second == {"created": 0, "updated": 0, "skipped": 30, "invalid": 0, "errors": []}

	# Publishing updates is_published without duplicating rows.
	pub = seed_quizzes(isolated_test_session, QUIZ_PACK, apply=True, publish=True)
	assert pub == {"created": 0, "updated": 30, "skipped": 0, "invalid": 0, "errors": []}
	assert isolated_test_session.query(Quiz).count() == 31

	# Invalid pack rolls back and leaves DB untouched.
	bad = [{"slug": "invalid-1", "quiz": {"title": "Bad", "language_code": "fr", "questions": []}}]
	bad_res = seed_quizzes(isolated_test_session, bad, apply=True, publish=True)
	assert bad_res["invalid"] == 1
	assert isolated_test_session.query(Quiz).count() == 31
	assert isolated_test_session.query(Quiz).filter(Quiz.id == manual.id).one().title == "Manual Parent Quiz"

	# Dry-run against populated DB leaves counts and values unchanged.
	dry = seed_quizzes(isolated_test_session, QUIZ_PACK, apply=False, publish=False)
	assert dry == {"created": 0, "updated": 0, "skipped": 30, "invalid": 0, "errors": []}
	assert isolated_test_session.query(Quiz).count() == 31


def test_postgres_rollback_on_mid_import_failure(isolated_test_session, monkeypatch):
	Quiz = get_model("Quiz")
	before = isolated_test_session.query(Quiz).count()

	import app.services.quiz_seed_service as svc

	calls = 0
	orig = svc.replace_questions

	def boom(session, quiz_id, questions):
		nonlocal calls
		calls += 1
		if calls == 2:
			raise RuntimeError("simulated DB failure")
		return orig(session, quiz_id, questions)

	monkeypatch.setattr(svc, "replace_questions", boom)
	with pytest.raises(RuntimeError, match="simulated DB failure"):
		seed_quizzes(isolated_test_session, QUIZ_PACK, apply=True, publish=False)
	assert isolated_test_session.query(Quiz).count() == before


def test_postgres_child_api_filtering_submission_and_preserves_attempts(api):
	Quiz = get_model("Quiz")
	QuizAttempt = get_model("QuizAttempt")
	QuizRewardGrant = get_model("QuizRewardGrant")
	QuizQuestion = get_model("QuizQuestion")
	QuizOption = get_model("QuizOption")

	# Zero-question published quiz and unpublished quiz must remain excluded.
	empty_pub = Quiz(
		title="Empty Published",
		subject="general",
		difficulty="easy",
		language_code="en",
		age_min=4,
		age_max=15,
		pass_percent=60,
		star_reward=5,
		xp_reward=10,
		allow_retry=True,
		is_published=True,
		revision=1,
	)
	api.session.add(empty_pub)
	api.session.commit()

	# Seed unpublished first: child sees nothing.
	res = seed_quizzes(api.session, QUIZ_PACK, apply=True, publish=False)
	assert res["created"] == 30
	child_en_8 = _child(api, language="en", age_years=8)
	assert api.get("/quizzes", child_en_8["token"]).json() == []

	# Publish the pack: English child sees only English quizzes matching age 8 (never hi/gu or age 10+/11+).
	pub = seed_quizzes(api.session, QUIZ_PACK, apply=True, publish=True)
	assert pub["updated"] == 30
	en_items = api.get("/quizzes", child_en_8["token"]).json()
	assert en_items
	assert all(item["language_code"] == "en" for item in en_items)
	assert all(item["age_min"] <= 8 <= item["age_max"] for item in en_items)
	assert all(item["id"] != str(empty_pub.id) for item in en_items)

	# Child aged 6 in Hindi sees Hindi + English quizzes matching age 6, not age 11+ hard quizzes.
	child_hi_6 = _child(api, language="hi", age_years=6)
	listed = api.get("/quizzes", child_hi_6["token"])
	assert listed.status_code == 200
	items = listed.json()
	assert items
	assert all(item["language_code"] in {"hi", "en"} for item in items)
	assert all(item["age_min"] <= 6 <= item["age_max"] for item in items)

	# Pick an easy Hindi quiz, start, answer all correctly, submit and earn reward.
	target_id = str(quiz_uuid("hi-animal-friends-easy"))
	started = api.post(f"/quizzes/{target_id}/attempts", child_hi_6["token"])
	assert started.status_code == 201
	attempt = started.json()
	answers = []
	for q in attempt["questions"]:
		correct_ids = [
			str(o.id)
			for o in api.session.query(QuizOption).filter(QuizOption.question_id == q["id"], QuizOption.is_correct.is_(True)).all()
		]
		answers.append({"question_id": q["id"], "option_ids": correct_ids})
	submitted = api.post(f"/quizzes/attempts/{attempt['attempt_id']}/submit", child_hi_6["token"], {"answers": answers})
	assert submitted.status_code == 200
	result = submitted.json()
	assert result["passed"] is True
	assert result["score_percent"] == 100
	assert result["stars_awarded"] == 5
	assert result["xp_awarded"] == 10

	# Re-running seed with modified title/question preserves existing quiz with attempts, attempts, and rewards.
	modified_pack = list(QUIZ_PACK)
	for idx, entry in enumerate(modified_pack):
		if entry["slug"] == "hi-animal-friends-easy":
			q_copy = {**entry["quiz"], "questions": list(entry["quiz"]["questions"])}
			q_copy["questions"][0] = {**q_copy["questions"][0], "prompt": "Changed Prompt Should Be Skipped"}
			modified_pack[idx] = {"slug": entry["slug"], "quiz": q_copy}
			break

	again = seed_quizzes(api.session, modified_pack, apply=True, publish=True)
	assert again["skipped"] == 30
	assert api.session.query(QuizAttempt).count() == 1
	assert api.session.query(QuizRewardGrant).count() == 1
	first_q = (
		api.session.query(QuizQuestion)
		.filter(QuizQuestion.quiz_id == quiz_uuid("hi-animal-friends-easy"), QuizQuestion.position == 1)
		.one()
	)
	assert first_q.prompt != "Changed Prompt Should Be Skipped"
