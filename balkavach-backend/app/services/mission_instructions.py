"""Structured mission instructions: one contract for the child API, the admin API, the seeder and the audit.

Pure functions, no database access. A variation's structured content is:

    learning_objective, steps[], materials[], duration_minutes, observation_guidance,
    submission_requirements, safety_instructions, completion_criteria

``steps`` is the stored JSON list when present. Older rows (and old assignment snapshots) have no ``steps``;
for those the numbered lines already inside ``instructions`` are *extracted* (nothing is invented). The
placeholder text migration 0015 seeded has no numbered lines, so it yields no steps and is reported as
incomplete instead of being shown as if it explained the activity.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

AGE_BANDS = ("4_6", "7_10", "11_15")

# Guideline step counts per age band. Outside the range is a warning, never a hard limit.
STEP_GUIDELINE = {"4_6": (2, 4), "7_10": (3, 5), "11_15": (4, 7)}
MIN_STEPS = 2  # fewer than this is not a sequence of actions
MAX_STEP_CHARS = 400
MIN_TEXT_CHARS = 8
# Average words per step above which a 4-6 step is probably too hard to read aloud.
MAX_AVG_WORDS_4_6 = 18

NOTHING_NEEDED = {
    "en": "Nothing needed",
    "gu": "કંઈ જરૂરી નથી",
    "hi": "कुछ भी ज़रूरी नहीं",
}
_NOTHING_NEEDED_ALL = {value.casefold() for value in NOTHING_NEEDED.values()} | {"nothing needed", "nothing"}

# Text the migration-0015 placeholders (and a lazy admin) use instead of instructions.
PLACEHOLDER_PATTERNS = (
    r"try the steps, notice what you discover",
    r"complete the steps and share one thing you discovered",
    r"learning adventure for ages",
    r"pagala ajmavo",
    r"kadam aazmaiye",
    r"umar mate ek maja nu shikshan sahas",
    r"ke liye ek mazedaar",
    r"^\s*(todo|tbd|lorem ipsum|placeholder|n/?a|\.\.\.)\s*\.?\s*$",
)
_PLACEHOLDER_RE = re.compile("|".join(PLACEHOLDER_PATTERNS), re.IGNORECASE)
_NUMBERED = re.compile(r"^\s*(\d{1,2})[.)]\s+(.+?)\s*$")

# Error codes that mean "there are no real instructions" (classified INCOMPLETE, not merely lacking detail).
FATAL_CODES = frozenset({"steps_missing", "steps_too_few", "placeholder_text", "steps_malformed", "submission_missing"})


def is_placeholder(text: Any) -> bool:
    return isinstance(text, str) and bool(_PLACEHOLDER_RE.search(text))


def parse_numbered_steps(text: Any) -> list[str]:
    """The numbered lines of ``text`` ("1. Do this"), in order. Un-numbered lines (e.g. 'Another way: ...') are ignored."""
    if not isinstance(text, str):
        return []
    steps: list[str] = []
    for line in text.splitlines():
        match = _NUMBERED.match(line)
        if match:
            steps.append(match.group(2))
    return steps


def _clean_text(value: Any) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def normalize_steps(value: Any) -> list[str] | None:
    """A cleaned list of step strings, or None when ``value`` is not a list. Non-string items are kept as-is
    for the validator to flag (malformed); blank strings are kept so an empty step is detectable."""
    if value is None:
        return None
    if not isinstance(value, (list, tuple)):
        return None
    return [step.strip() if isinstance(step, str) else step for step in value]


def structured_content(source: Any) -> dict[str, Any]:
    """The structured view of a variation row, an assignment snapshot or a mapping.

    Reads ``steps`` / ``learning_objective`` / ``observation_guidance`` / ``submission_requirements`` when present;
    otherwise steps are extracted from ``instructions``. Missing fields are None, never filler text."""

    def get(name: str, default: Any = None) -> Any:
        if isinstance(source, dict):
            return source.get(name, default)
        return getattr(source, name, default)

    stored_steps = normalize_steps(get("steps"))
    steps = stored_steps if stored_steps is not None else parse_numbered_steps(get("instructions"))
    materials_raw = get("required_materials")
    if materials_raw is None:
        materials_raw = get("materials")
    materials = [str(item).strip() for item in (materials_raw or []) if str(item).strip()]
    return {
        "learning_objective": _clean_text(get("learning_objective")),
        "steps": steps,
        "materials": materials,
        "duration_minutes": get("duration_minutes"),
        "observation_guidance": _clean_text(get("observation_guidance")),
        "submission_requirements": _clean_text(get("submission_requirements")),
        "safety_instructions": _clean_text(get("safety_instructions")),
        "completion_criteria": _clean_text(get("completion_criteria")),
    }


def instruction_status(content: dict[str, Any]) -> str:
    """'ready' when a child can follow the mission, else 'incomplete'. The child app shows an honest
    incomplete state for the latter instead of generic text."""
    # Only the steps decide this: a legacy row with real steps but no stored submission text is still followable.
    blocking = {"steps_missing", "steps_too_few", "steps_malformed", "placeholder_text"}
    issues = validate_content(content, age_band=None)
    return "incomplete" if any(code in blocking for code, _ in issues["errors"]) else "ready"


def validate_content(
    content: dict[str, Any], *, age_band: str | None, description: str | None = None, instructions: str | None = None
) -> dict[str, list[tuple[str, str]]]:
    """``{'errors': [(code, message)], 'warnings': [...]}`` for one structured variation.

    Errors block publishing. Warnings (no objective, no 'what to observe', step count outside the age guideline,
    long wording for ages 4-6) keep a mission publishable but classify it NEEDS IMPROVEMENT."""
    errors: list[tuple[str, str]] = []
    warnings: list[tuple[str, str]] = []
    steps = content.get("steps")

    if not steps:
        errors.append(("steps_missing", "No numbered steps: the child has nothing to do."))
    else:
        bad = [i for i, step in enumerate(steps, start=1) if not isinstance(step, str) or not step.strip()]
        if bad:
            errors.append(("steps_malformed", f"Step(s) {', '.join(map(str, bad))} are empty or not text."))
        text_steps = [step for step in steps if isinstance(step, str) and step.strip()]
        if len(text_steps) < MIN_STEPS and not bad:
            errors.append(("steps_too_few", f"Only {len(text_steps)} step; a mission needs at least {MIN_STEPS}."))
        if any(len(step) > MAX_STEP_CHARS for step in text_steps):
            warnings.append(("step_too_long", f"A step is longer than {MAX_STEP_CHARS} characters."))
        if any(is_placeholder(step) for step in text_steps):
            errors.append(("placeholder_text", "A step is generic placeholder text."))
        if len(set(step.casefold() for step in text_steps)) < len(text_steps):
            warnings.append(("steps_repeated", "Two steps are identical."))
        if age_band in STEP_GUIDELINE and text_steps:
            low, high = STEP_GUIDELINE[age_band]
            if not low <= len(text_steps) <= high:
                warnings.append(("step_count_guideline", f"{len(text_steps)} steps; ages {age_band.replace('_', '-')} usually use {low}-{high}."))
            if age_band == "4_6":
                average = sum(len(step.split()) for step in text_steps) / len(text_steps)
                if average > MAX_AVG_WORDS_4_6:
                    warnings.append(("wording_too_long_for_age", f"Steps average {average:.0f} words; keep ages 4-6 short."))

    for label, text in (("instructions", instructions), ("description", description), ("completion criteria", content.get("completion_criteria"))):
        if is_placeholder(text) and not any(c == "placeholder_text" for c, _ in errors):
            errors.append(("placeholder_text", f"The {label} is generic placeholder text."))

    if not content.get("materials"):
        errors.append(("materials_missing", "Materials not stated. List them, or write 'Nothing needed'."))

    submission = content.get("submission_requirements")
    if not submission or len(submission) < MIN_TEXT_CHARS:
        errors.append(("submission_missing", "No clear statement of what the child must submit."))
    elif is_placeholder(submission):
        errors.append(("placeholder_text", "The submission requirement is generic placeholder text."))

    if not content.get("safety_instructions"):
        errors.append(("safety_missing", "Safety guidance missing."))
    if not content.get("completion_criteria"):
        errors.append(("completion_missing", "Completion criteria missing."))

    if not content.get("learning_objective"):
        warnings.append(("objective_missing", "No 'what you will learn' sentence."))
    if not content.get("observation_guidance"):
        warnings.append(("observation_missing", "No 'what to observe' guidance."))
    return {"errors": errors, "warnings": warnings}


def band_distinctness_errors(by_band: dict[str, dict[str, Any]]) -> list[tuple[str, str]]:
    """One locale's variations keyed by age band: two bands may not share identical steps."""
    errors: list[tuple[str, str]] = []
    seen: dict[tuple[str, ...], str] = {}
    for band in AGE_BANDS:
        content = by_band.get(band)
        if not content or not content.get("steps"):
            continue
        key = tuple(str(step).casefold() for step in content["steps"])
        if key in seen:
            errors.append(("bands_identical", f"Ages {band.replace('_', '-')} reuse the exact steps of ages {seen[key].replace('_', '-')}."))
        else:
            seen[key] = band
    return errors


def render_task_text(content: dict[str, Any]) -> str:
    """Plain-text preview of what a child sees, used by the admin preview and parent review."""
    lines: list[str] = []
    if content.get("learning_objective"):
        lines += ["What you will learn", content["learning_objective"], ""]
    materials = content.get("materials") or []
    lines += ["What you need", *(f"- {m}" for m in materials), ""]
    if content.get("duration_minutes"):
        lines += [f"Time needed: about {content['duration_minutes']} minutes", ""]
    lines += ["Steps", *(f"{i}. {s}" for i, s in enumerate(content.get("steps") or [], start=1)), ""]
    if content.get("observation_guidance"):
        lines += ["What to observe", content["observation_guidance"], ""]
    if content.get("submission_requirements"):
        lines += ["What to submit", content["submission_requirements"], ""]
    if content.get("safety_instructions"):
        lines += ["Safety", content["safety_instructions"]]
    return "\n".join(lines).strip()


def as_error_details(issues: Iterable[tuple[str, str]]) -> list[dict[str, str]]:
    return [{"code": code, "message": message} for code, message in issues]
