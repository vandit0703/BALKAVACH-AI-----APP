from __future__ import annotations

from typing import Iterable

from fastapi import Request

SUPPORTED_LOCALES = ("en", "gu", "hi")


def normalize_locale(value: str | None) -> str | None:
    if not value:
        return None
    tag = value.strip().replace("_", "-").lower()
    if not tag:
        return None
    primary = tag.split("-", 1)[0]
    return primary if primary in SUPPORTED_LOCALES else None


def _parse_accept_language(header: str | None) -> str | None:
    if not header:
        return None
    # e.g. "gu-IN,gu;q=0.9,en;q=0.8"
    for part in header.split(","):
        token = part.split(";", 1)[0].strip()
        locale = normalize_locale(token)
        if locale:
            return locale
    return None


def resolve_display_locale(request: Request | None, user=None, fallback: str | None = None) -> str:
    """Resolve the content/display locale for a request.

    Priority: explicit app header, Accept-Language, authenticated/user preferred
    language, provided fallback, then English. Only supported locales are
    returned.
    """
    header_locale = None
    if request is not None:
        header_locale = normalize_locale(request.headers.get("x-app-language"))
        if header_locale is None:
            header_locale = _parse_accept_language(request.headers.get("accept-language"))
    if header_locale:
        return header_locale

    preferred = normalize_locale(getattr(user, "preferred_language", None))
    if preferred:
        return preferred

    fallback_locale = normalize_locale(fallback)
    if fallback_locale:
        return fallback_locale

    return "en"
