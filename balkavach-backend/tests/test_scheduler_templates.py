"""The example scheduler files in ``deploy/`` must call real commands with valid arguments and hold no secrets.

Local check only: it parses the files; it does not install, run or contact anything.
"""

import re
from pathlib import Path

import pytest

from app import cli

DEPLOY = Path(__file__).resolve().parents[1] / "deploy"
FILES = sorted(p for p in DEPLOY.rglob("*") if p.is_file())
COMMAND = re.compile(r"python -m app\.cli (?P<args>[^\n#]+)")


def test_the_example_files_exist():
	names = {p.name for p in FILES}
	assert {
		"render-cron-jobs.example.yaml",
		"balkavach-youtube-recheck.service",
		"balkavach-youtube-recheck.timer",
		"balkavach-youtube-recheck-health.service",
		"balkavach-youtube-recheck-health.timer",
	} <= names


@pytest.mark.parametrize("path", [p for p in FILES if p.suffix in {".yaml", ".service"}], ids=lambda p: p.name)
def test_every_scheduled_command_is_a_real_command_with_valid_arguments(path, monkeypatch):
	import app.db.session as db_session

	monkeypatch.setattr(db_session, "SessionLocal", None)  # a valid command then stops at "no database" (exit 2)
	found = COMMAND.findall(path.read_text(encoding="utf-8"))
	assert found, f"{path.name} schedules no app.cli command"
	for arguments in found:
		# argparse exits the process on a bad command or argument; a good one reaches the database check.
		assert cli.main(arguments.split()) == 2, arguments


@pytest.mark.parametrize("path", FILES, ids=lambda p: p.name)
def test_the_examples_hold_no_secret_and_do_not_enable_play_tickets(path):
	text = path.read_text(encoding="utf-8")
	assert not re.search(r"postgres(ql)?(\+\w+)?://", text, re.IGNORECASE)
	assert not re.search(r"AIza[0-9A-Za-z_-]{20,}", text)  # a Google API key
	assert not re.search(r"^\s*-?\s*(value|Environment=)\S*\s*.*(SECRET|PASSWORD|API_KEY)\s*=\s*\S", text, re.MULTILINE)
	assert "VIDEO_PLAY_TICKETS" not in re.sub(r"(?m)^\s*#.*$", "", text)  # only a comment may mention it


def test_the_recheck_job_runs_hourly_and_the_health_check_runs_too():
	yaml_text = (DEPLOY / "render-cron-jobs.example.yaml").read_text(encoding="utf-8")
	assert 'schedule: "0 * * * *"' in yaml_text and 'schedule: "15 * * * *"' in yaml_text
	assert "OnCalendar=hourly" in (DEPLOY / "systemd" / "balkavach-youtube-recheck.timer").read_text(encoding="utf-8")
