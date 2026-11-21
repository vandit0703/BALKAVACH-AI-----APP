"""How a mission title is shown to a child.

The migration-0015 placeholder missions (and any admin-authored title) may end with the age band the
mission was written for, e.g. ``Saturday Rhythm Rockstar 2 (4 to 6)``. That is eligibility metadata, not
something a child should read. Age eligibility itself is stored in ``age_band`` on the assignment and in the
template's variations; this module only changes the *displayed* text and never touches stored values.
"""

import re

# A trailing "(4 to 6)", "(Ages 4-6)", "[11 – 15]" or "(7 to 10 years)". Only a bracketed pair of numbers
# counts, so "(and a dog)", "Plan for 3 (kids)" or "Level (2)" are left alone.
_TRAILING_AGE_RANGE = re.compile(
	r"\s*[(\[]\s*(?:ages?\s+)?\d{1,2}\s*(?:to|-|–|—)\s*\d{1,2}\s*\+?\s*(?:years?(?:\s+old)?)?\s*[)\]]\s*$",
	re.IGNORECASE,
)


def child_facing_title(title: str) -> str:
	"""``title`` without a trailing age range. Never returns an empty string for a non-empty title."""
	if not title:
		return title
	cleaned = _TRAILING_AGE_RANGE.sub("", title).strip()
	return cleaned or title.strip()
