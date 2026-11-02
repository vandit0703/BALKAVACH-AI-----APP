"""Short vs regular video classification: the one place this rule lives.

A video is a **short** when its real duration is known and is between
``SHORT_MIN_SECONDS`` and ``SHORT_MAX_SECONDS`` inclusive. Everything else is
**regular**, including videos whose duration is unknown: the app never guesses
that something is short.

Unknown duration
----------------
``videos.duration_seconds`` is NOT NULL, and YouTube imports store ``1`` when
the YouTube API returned no usable duration (see
``youtube_review_service._create_candidate``: ``min(duration or 1, 86400)``).
A one-second YouTube video does not exist in practice, so for YouTube rows a
stored value of ``1`` or less means "unknown". For other sources the admin
typed the duration (the API requires ``> 0``), so it is trusted as entered.

Only the duration is used. Titles, descriptions and URLs (for example a
``/shorts/`` link) are never consulted. There is no aspect-ratio column, so
orientation cannot take part in eligibility; a landscape video of 1-60 s is a
short too.
"""

from typing import Literal

from sqlalchemy import and_, or_

SHORT_MIN_SECONDS = 1
SHORT_MAX_SECONDS = 60

# YouTube imports store this when YouTube returned no duration.
_YOUTUBE_UNKNOWN_DURATION_MAX = 1

VideoFormat = Literal["short", "regular", "unknown"]


def duration_is_known(video_source: str | None, duration_seconds: int | None) -> bool:
	if duration_seconds is None or duration_seconds < SHORT_MIN_SECONDS:
		return False
	if video_source == "youtube" and duration_seconds <= _YOUTUBE_UNKNOWN_DURATION_MAX:
		return False
	return True


def video_format(video_source: str | None, duration_seconds: int | None) -> VideoFormat:
	"""``unknown`` is shown with regular videos, but is reported as unknown."""
	if not duration_is_known(video_source, duration_seconds):
		return "unknown"
	return "short" if duration_seconds <= SHORT_MAX_SECONDS else "regular"


def known_duration_or_none(video_source: str | None, duration_seconds: int | None) -> int | None:
	return duration_seconds if duration_is_known(video_source, duration_seconds) else None


def short_clause(Video):
	"""SQL twin of ``video_format(...) == "short"``."""
	return and_(
		Video.duration_seconds.is_not(None),
		Video.duration_seconds >= SHORT_MIN_SECONDS,
		Video.duration_seconds <= SHORT_MAX_SECONDS,
		or_(
			Video.video_source.is_(None),
			Video.video_source != "youtube",
			Video.duration_seconds > _YOUTUBE_UNKNOWN_DURATION_MAX,
		),
	)


def regular_clause(Video):
	"""SQL twin of ``video_format(...) != "short"``.

	Written out explicitly rather than as ``NOT short_clause`` so a NULL never
	makes a row vanish from both feeds.
	"""
	return or_(
		Video.duration_seconds.is_(None),
		Video.duration_seconds < SHORT_MIN_SECONDS,
		Video.duration_seconds > SHORT_MAX_SECONDS,
		and_(
			Video.video_source == "youtube",
			Video.duration_seconds <= _YOUTUBE_UNKNOWN_DURATION_MAX,
		),
	)
