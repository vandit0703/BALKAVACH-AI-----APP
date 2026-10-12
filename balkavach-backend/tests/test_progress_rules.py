from app.services.progress_service import badge_qualifies


def test_badge_criteria_match_supported_thresholds() -> None:
    values = {"approved_tasks": 5, "total_stars": 12, "total_xp": 90, "current_streak": 3}

    assert badge_qualifies("approved_tasks", {"threshold": 5}, values)
    assert badge_qualifies("total_stars", {"threshold": 10}, values)
    assert not badge_qualifies("total_xp", {"threshold": 100}, values)


def test_badge_criteria_reject_unknown_or_invalid_thresholds() -> None:
    values = {"approved_tasks": 10}

    assert not badge_qualifies("custom_rule", {"threshold": 1}, values)
    assert not badge_qualifies("approved_tasks", {"threshold": True}, values)
    assert not badge_qualifies("approved_tasks", {"threshold": 0}, values)