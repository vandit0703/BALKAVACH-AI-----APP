"""``python -m app.cli seed-daily-missions``: dry-run by default, explicit flags for anything that writes."""

import pytest

from app import cli
from tests.sqlite_world import DailyMissionTemplate, DailyMissionVariation, world_session  # noqa: F401  (fixture)


class _Factory:
	"""A session factory whose sessions are the shared test session (so we can inspect what was written)."""

	def __init__(self, session):
		self.session = session
		self.calls = 0

	def __call__(self):
		self.calls += 1
		return _Context(self.session)


class _Context:
	def __init__(self, session):
		self.session = session

	def __enter__(self):
		return self.session

	def __exit__(self, *exc):
		return False


def test_dry_run_validates_and_reports_without_touching_a_database(capsys):
	assert cli.main(["seed-daily-missions"]) == 0
	out = capsys.readouterr().out
	assert "dry run" in out.lower() and "42 templates" in out and "378 variations" in out


def test_apply_without_a_configured_database_is_refused_clearly(monkeypatch, capsys):
	import app.db.session as db_session

	monkeypatch.setattr(db_session, "SessionLocal", None)
	assert cli.main(["seed-daily-missions", "--apply"]) == 2
	assert "DATABASE_URL" in capsys.readouterr().err


def test_publish_and_retire_flags_need_apply(capsys):
	with pytest.raises(SystemExit):
		cli.main(["seed-daily-missions", "--publish"])
	with pytest.raises(SystemExit):
		cli.main(["seed-daily-missions", "--retire-placeholders"])


def test_apply_writes_unpublished_templates_and_a_second_run_writes_nothing(world_session, capsys):
	factory = _Factory(world_session)
	assert cli._seed_daily_missions(factory, apply=True, publish=False, retire=False) == 0
	assert world_session.query(DailyMissionTemplate).count() == 42
	assert world_session.query(DailyMissionVariation).count() == 378
	assert world_session.query(DailyMissionTemplate).filter(DailyMissionTemplate.is_published.is_(True)).count() == 0
	first = capsys.readouterr().out
	assert "templates_created=42" in first and "variations_created=378" in first
	assert cli._seed_daily_missions(factory, apply=True, publish=False, retire=False) == 0
	second = capsys.readouterr().out
	assert "templates_created=0" in second and "variations_created=0" in second
	assert world_session.query(DailyMissionVariation).count() == 378


def test_apply_with_publish_and_retire(world_session, capsys):
	placeholder = DailyMissionTemplate(slug="sunday_future_inventor_2", theme="sunday_future_inventor", mission_type="offline", is_published=True)
	world_session.add(placeholder)
	world_session.flush()
	world_session.add(
		DailyMissionVariation(
			template_id=placeholder.id, age_band="4_6", locale="en",
			instructions="Try the steps, notice what you discover, and tell a trusted grown-up what you learned.",
		)
	)
	world_session.commit()
	assert cli._seed_daily_missions(_Factory(world_session), apply=True, publish=True, retire=True) == 0
	out = capsys.readouterr().out
	assert "published=42" in out and "unpublished=1" in out
	world_session.refresh(placeholder)
	assert placeholder.is_published is False


def test_an_invalid_catalogue_is_reported_and_nothing_is_written(world_session, monkeypatch, capsys):
	import copy

	import app.services.mission_catalogue_service as service
	from app.content.daily_missions import MISSIONS

	broken = copy.deepcopy(list(MISSIONS))
	broken[0]["ages"]["4_6"]["locales"]["hi"]["title"] = "romanised"
	monkeypatch.setattr(cli, "_catalogue_missions", lambda: broken)
	factory = _Factory(world_session)
	assert cli._seed_daily_missions(factory, apply=True, publish=False, retire=False) == 1
	assert "invalid" in capsys.readouterr().err.lower()
	assert factory.calls == 0 and world_session.query(DailyMissionTemplate).count() == 0
