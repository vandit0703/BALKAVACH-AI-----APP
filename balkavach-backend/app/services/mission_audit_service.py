"""Read-only audit of mission instruction quality, for the code catalogue and for database rows.

Classes (one per age-specific, localized variation):

* COMPLETE          real steps, objective, materials, observation, submission, safety, completion; no warnings
* NEEDS IMPROVEMENT usable steps but something important is missing or off (objective, observation, safety, age fit...)
* INCOMPLETE        no real instructions: no steps, placeholder text, malformed steps, or no submission requirement
* SAFETY REVIEW     the activity text asks for something on the restricted list; a human must review it first
                    (takes precedence over the other classes)

Nothing here writes. Nothing is invented: an INCOMPLETE row whose activity cannot be told from its text is marked
``admin_review`` so a person authors it.
"""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any, Iterable

from app.db.base import get_model
from app.content.daily_missions import AGE_BANDS, LOCALES, MISSIONS, variation_payload
from app.services.mission_catalogue_service import _UNSAFE, _has
from app.services.mission_instructions import (
    ADVISORY_CODES,
    ENRICHMENT_CODES,
    FATAL_CODES,
    band_distinctness_errors,
    structured_content,
    validate_content,
)

COMPLETE = "COMPLETE"
NEEDS_IMPROVEMENT = "NEEDS IMPROVEMENT"
INCOMPLETE = "INCOMPLETE"
SAFETY_REVIEW = "SAFETY REVIEW"
CLASSES = (COMPLETE, NEEDS_IMPROVEMENT, INCOMPLETE, SAFETY_REVIEW)


def _safety_hit(locale: str, content: dict[str, Any]) -> str | None:
    """A restricted term the child is asked to do or have (steps, materials, submission). The safety text may forbid them."""
    asked = " ".join(
        [
            *(s for s in content.get("steps") or [] if isinstance(s, str)),
            *content.get("materials", []),
            content.get("submission_requirements") or "",
        ]
    )
    return _has(_UNSAFE.get(locale, _UNSAFE["en"]), asked, regex=locale == "en")


def _label(errors: list[str], warnings: list[str], hit: str | None) -> str:
    """SAFETY REVIEW beats everything. INCOMPLETE only when the child cannot act (no real steps). Essential publish
    blockers (materials, submission, safety text, completion) and quality warnings give NEEDS IMPROVEMENT. Enrichment
    (objective, observation) and advisory guidelines never change the class."""
    if hit:
        return SAFETY_REVIEW
    if any(code in FATAL_CODES for code in errors):
        return INCOMPLETE
    quality = [w for w in warnings if w not in ENRICHMENT_CODES and w not in ADVISORY_CODES]
    return NEEDS_IMPROVEMENT if errors or quality else COMPLETE


def _facts(row: dict[str, Any], content: dict[str, Any], locale: str) -> None:
    """The per-variation answers the review asked for, derived from the codes (call after the cross checks)."""
    errors, warnings = row["errors"], row["warnings"]
    label = _label(errors, warnings, row["safety_term"])
    row.update(
        classification=label,
        actionable=not any(code in FATAL_CODES for code in errors),
        steps_ok=not any(c in errors for c in ("steps_missing", "steps_too_few", "steps_malformed", "placeholder_text"))
        and "wording_too_long_for_age" not in warnings,
        materials_clear="materials_missing" not in errors,
        duration_present=bool(content.get("duration_minutes")),
        safety_guidance_present="safety_missing" not in errors,
        submission_clear_to_child="submission_missing" not in errors and "submission_reviewer_voice" not in warnings,
        completion_clear_to_reviewer="completion_missing" not in errors,
        learning_objective_missing="objective_missing" in warnings,
        observation_guidance_missing="observation_missing" in warnings,
        publish_blockers=list(errors),
        publish_ready=not errors and not row["safety_term"],
        needs_safety_review=bool(row["safety_term"]),
        # No review record exists for Gujarati/Hindi text; the catalogue docs say it is not native-reviewed.
        needs_native_review=locale != "en",
        admin_review=label == INCOMPLETE and not content.get("steps"),
    )


def classify_variation(
    content: dict[str, Any], *, age_band: str, locale: str, description: str | None = None, instructions: str | None = None
) -> dict[str, Any]:
    issues = validate_content(content, age_band=age_band, description=description, instructions=instructions)
    row = {
        "errors": [code for code, _ in issues["errors"]],
        "warnings": [code for code, _ in issues["warnings"]],
        "safety_term": _safety_hit(locale, content),
        "classification": COMPLETE,
    }
    _facts(row, content, locale)
    return row


def _summarise(rows: list[dict[str, Any]], extra: dict[str, Any]) -> dict[str, Any]:
    by_band: dict[str, Counter] = defaultdict(Counter)
    by_locale: dict[str, Counter] = defaultdict(Counter)
    for row in rows:
        by_band[row["age_band"]][row["classification"]] += 1
        by_locale[row["locale"]][row["classification"]] += 1
    counts = Counter(row["classification"] for row in rows)
    return {
        "variations_audited": len(rows),
        "classification": {label: counts.get(label, 0) for label in CLASSES},
        "by_age_band": {band: {label: by_band[band].get(label, 0) for label in CLASSES} for band in AGE_BANDS},
        "by_locale": {loc: {label: by_locale[loc].get(label, 0) for label in CLASSES} for loc in LOCALES},
        "admin_review": sum(1 for row in rows if row["admin_review"]),
        "publish_ready": sum(1 for row in rows if row["publish_ready"]),
        "actionable": sum(1 for row in rows if row["actionable"]),
        "enrichment_missing": {
            "learning_objective": sum(1 for row in rows if row["learning_objective_missing"]),
            "observation_guidance": sum(1 for row in rows if row["observation_guidance_missing"]),
        },
        "submission_not_clear_to_child": sum(1 for row in rows if not row["submission_clear_to_child"]),
        "needs_native_review": sum(1 for row in rows if row["needs_native_review"]),
        "needs_safety_review": sum(1 for row in rows if row["needs_safety_review"]),
        "issue_codes": dict(Counter(code for row in rows for code in row["errors"] + row["warnings"]).most_common()),
        "rows": rows,
        **extra,
    }


def _cross_checks(rows: list[dict[str, Any]], contents: dict[tuple, dict[str, Any]]) -> None:
    """Locale parity and per-band distinctness, folded into the rows (in place)."""
    index = {(r["template"], r["age_band"], r["locale"]): r for r in rows}
    groups: dict[tuple, dict[str, int]] = defaultdict(dict)
    for (template, age_band, locale), content in contents.items():
        groups[(template, age_band)][locale] = len(content.get("steps") or [])
    for (template, age_band), counts in groups.items():
        if len(set(counts.values())) > 1:
            for locale in counts:
                index[(template, age_band, locale)]["warnings"].append("locale_step_count_mismatch")
    by_locale: dict[tuple, dict[str, dict]] = defaultdict(dict)
    for (template, age_band, locale), content in contents.items():
        by_locale[(template, locale)][age_band] = content
    for (template, locale), bands in by_locale.items():
        if band_distinctness_errors(bands):
            for band in bands:
                index[(template, band, locale)]["errors"].append("bands_identical")
    for row in rows:
        _facts(row, contents[(row["template"], row["age_band"], row["locale"])], row["locale"])


def audit_catalogue(missions: Iterable[dict[str, Any]] = MISSIONS) -> dict[str, Any]:
    missions = list(missions)
    rows, contents = [], {}
    for mission in missions:
        for age_band in AGE_BANDS:
            for locale in LOCALES:
                if age_band not in mission["ages"] or locale not in mission["ages"][age_band]["locales"]:
                    continue
                payload = variation_payload(mission, age_band, locale)
                content = structured_content({**payload, "materials": payload["required_materials"]})
                result = classify_variation(
                    content, age_band=age_band, locale=locale, description=payload["description"], instructions=payload["instructions"]
                )
                rows.append({"template": mission["slug"], "age_band": age_band, "locale": locale, "title": payload["title"], **result})
                contents[(mission["slug"], age_band, locale)] = content
    _cross_checks(rows, contents)
    return _summarise(
        rows,
        {
            "source": "catalogue",
            "templates": len(missions),
            "age_specific_missions": sum(len(m["ages"]) for m in missions),
            "missing_localizations": [],
        },
    )


def audit_database(session: Any) -> dict[str, Any]:
    """SELECT-only audit of the template and variation tables (call with a session that is rolled back, never committed)."""
    Template = get_model("DailyMissionTemplate")
    Variation = get_model("DailyMissionVariation")
    templates = {t.id: t for t in session.query(Template).all()}
    rows, contents, present = [], {}, defaultdict(set)
    for v in session.query(Variation).all():
        template = templates.get(v.template_id)
        slug = template.slug if template else str(v.template_id)
        content = structured_content(v)
        result = classify_variation(
            content, age_band=v.age_band, locale=v.locale, description=v.description, instructions=v.instructions
        )
        rows.append(
            {
                "template": slug,
                "age_band": v.age_band,
                "locale": v.locale,
                "title": v.title,
                "variation_key": v.variation_key,
                "published": bool(template and template.is_published),
                **result,
            }
        )
        contents[(slug, v.age_band, v.locale)] = content
        present[slug].add((v.age_band, v.locale))
    _cross_checks(rows, contents)
    missing = [
        {"template": slug, "missing": [f"{a}:{loc}" for a in AGE_BANDS for loc in LOCALES if (a, loc) not in combos]}
        for slug, combos in sorted(present.items())
        if len(combos) < len(AGE_BANDS) * len(LOCALES)
    ]
    blocked = sorted({r["template"] for r in rows if r["published"] and r["classification"] in (INCOMPLETE, SAFETY_REVIEW)})
    return _summarise(
        rows,
        {
            "source": "database",
            "templates": len(templates),
            "missing_localizations": missing,
            "published_templates_with_incomplete_or_safety_rows": blocked,
        },
    )


def format_report(report: dict[str, Any]) -> str:
    lines = [
        f"Source: {report['source']}",
        f"Templates: {report['templates']}   Variations audited: {report['variations_audited']}",
        "Classification: " + ", ".join(f"{label}={report['classification'][label]}" for label in CLASSES),
        f"Needs admin review (no steps to build on): {report['admin_review']}",
        f"Actionable by a child: {report['actionable']}   Publish-ready (no blockers): {report['publish_ready']}",
        f"Submission not clear to the child: {report['submission_not_clear_to_child']}",
        "Enrichment missing (never blocks): objective={learning_objective}, observation={observation_guidance}".format(**report["enrichment_missing"]),
        f"Needs native-language review: {report['needs_native_review']}   Needs safety review: {report['needs_safety_review']}",
        "By age band:",
    ]
    for band, counts in report["by_age_band"].items():
        lines.append(f"  {band}: " + ", ".join(f"{label}={counts[label]}" for label in CLASSES))
    lines.append("By language:")
    for loc, counts in report["by_locale"].items():
        lines.append(f"  {loc}: " + ", ".join(f"{label}={counts[label]}" for label in CLASSES))
    if report["issue_codes"]:
        lines.append("Issue codes: " + ", ".join(f"{k}={v}" for k, v in report["issue_codes"].items()))
    if report.get("missing_localizations"):
        lines.append(f"Templates missing age/language versions: {len(report['missing_localizations'])}")
    if report.get("published_templates_with_incomplete_or_safety_rows"):
        lines.append(
            "Published templates with INCOMPLETE/SAFETY REVIEW rows: "
            + ", ".join(report["published_templates_with_incomplete_or_safety_rows"])
        )
    return "\n".join(lines)
