"""The Flutter test fixture must be the catalogue as it stands (see scripts/export_catalogue_fixture.py)."""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import export_catalogue_fixture as exporter  # noqa: E402


def test_the_flutter_fixture_exists_and_matches_the_catalogue():
	assert exporter.FIXTURE.exists(), "run python scripts/export_catalogue_fixture.py"
	assert exporter.FIXTURE.read_text(encoding="utf-8") == exporter.build()


def test_the_fixture_holds_all_126_variations_in_the_api_content_shape():
	entries = json.loads(exporter.FIXTURE.read_text(encoding="utf-8"))
	assert len(entries) == 378
	keys = {
		"title", "description", "instructions", "required_materials", "duration_minutes", "safety_instructions",
		"completion_criteria", "mission_type", "theme", "star_reward", "xp_reward", "is_surprise", "locale",
		"learning_objective", "steps", "materials", "observation_guidance", "submission_requirements", "instruction_status",
	}
	assert all(set(entry["content"]) == keys for entry in entries)
