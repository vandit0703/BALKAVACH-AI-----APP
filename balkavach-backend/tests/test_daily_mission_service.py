from datetime import date

import pytest
from pydantic import ValidationError

from app.schemas.daily_mission import DailyMissionVariationCreate
from app.services.daily_mission_service import age_band_for_birth_date


def test_age_band_uses_server_date_and_birthday_boundary():
    assert age_band_for_birth_date(date(2020, 11, 16), date(2026, 11, 15)) == "4_6"
    assert age_band_for_birth_date(date(2020, 11, 16), date(2026, 11, 16)) == "4_6"
    assert age_band_for_birth_date(date(2016, 11, 16), date(2026, 11, 15)) == "7_10"
    assert age_band_for_birth_date(date(2011, 11, 16), date(2026, 11, 15)) == "11_15"
    assert age_band_for_birth_date(date(2022, 11, 16), date(2026, 11, 15)) is None


def test_variation_rejects_ordinary_mission_personal_data_requirements():
    with pytest.raises(ValidationError):
        DailyMissionVariationCreate(
            age_band="7_10",
            locale="en",
            title="Location Hunt",
            description="Find a place.",
            instructions="Share your location with the app.",
            safety_instructions="Ask a grown-up.",
            completion_criteria="Send the location.",
            duration_minutes=10,
        )


def test_variation_accepts_safe_completion_contract():
    variation = DailyMissionVariationCreate(
        age_band="4_6",
        locale="gu",
        title="Sound Hunt",
        description="Listen for safe sounds.",
        instructions="Listen beside a trusted grown-up.",
        safety_instructions="Use safe household objects only.",
        completion_criteria="Tell a grown-up one sound you noticed.",
        duration_minutes=8,
    )
    assert variation.age_band == "4_6"
