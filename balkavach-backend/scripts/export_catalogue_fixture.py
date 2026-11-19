"""Write the daily-mission catalogue as JSON for the Flutter layout/localization tests.

    python scripts/export_catalogue_fixture.py            # (re)generate
    python scripts/export_catalogue_fixture.py --check    # exit 1 when the committed file is stale

The output has the same shape as the ``content`` object of ``GET /api/v1/daily-missions/today``. It contains
only catalogue text (no personal data). ``tests/test_mission_catalogue_fixture.py`` keeps it in sync.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, variation_payload  # noqa: E402

FIXTURE = ROOT.parent / "balkavach-frontend" / "test" / "fixtures" / "daily_mission_catalogue.json"


def build() -> str:
	entries = []
	for mission in MISSIONS:
		for age_band in AGE_BANDS:
			for locale in LOCALES:
				payload = variation_payload(mission, age_band, locale)
				entries.append(
					{
						"slug": mission["slug"],
						"theme": mission["theme"],
						"age_band": age_band,
						"locale": locale,
						"content": {
							"title": payload["title"],
							"description": payload["description"],
							"instructions": payload["instructions"],
							"required_materials": payload["required_materials"],
							"duration_minutes": payload["duration_minutes"],
							"safety_instructions": payload["safety_instructions"],
							"completion_criteria": payload["completion_criteria"],
							"mission_type": mission["mission_type"],
							"theme": mission["theme"],
							"star_reward": mission["star_reward"],
							"xp_reward": mission["xp_reward"],
							"is_surprise": False,
							"locale": locale,
						},
					}
				)
	return json.dumps(entries, ensure_ascii=False, indent=1) + "\n"


def main(argv: list[str]) -> int:
	text = build()
	if "--check" in argv:
		current = FIXTURE.read_text(encoding="utf-8") if FIXTURE.exists() else ""
		if current != text:
			print(f"{FIXTURE} is out of date; run scripts/export_catalogue_fixture.py", file=sys.stderr)
			return 1
		return 0
	FIXTURE.parent.mkdir(parents=True, exist_ok=True)
	FIXTURE.write_text(text, encoding="utf-8", newline="\n")
	print(f"wrote {FIXTURE} ({len(text)} bytes)")
	return 0


if __name__ == "__main__":
	raise SystemExit(main(sys.argv[1:]))
