"""Admin permission vocabulary.

Canonical permissions are ``resource:action`` (``users:write``). The production
``content_manager`` role was seeded with dotted names (``videos.create``), so
those are mapped here instead of editing production role data.
Any ``x:write`` also grants ``x:read``; ``*`` grants everything.
"""

from typing import Any

_ALIASES: dict[str, set[str]] = {
	"videos.read": {"video:read"},
	"videos.create": {"video:write"},
	"videos.update": {"video:write"},
	"videos.publish": {"video:write"},
	"videos.delete": {"video:write"},
	"categories.manage": {"content:write", "video:write"},
	"collections.manage": {"video:write"},
}


def expand_permissions(raw: Any) -> set[str]:
	if isinstance(raw, dict):
		items = [key for key, enabled in raw.items() if enabled is True and isinstance(key, str)]
	elif isinstance(raw, (list, tuple, set)):
		items = [item for item in raw if isinstance(item, str)]
	else:
		items = []
	granted: set[str] = set()
	for item in items:
		name = item.strip().lower()
		if name == "*":
			granted.add("*")
			continue
		granted.add(name.replace(".", ":"))
		granted |= _ALIASES.get(name, set())
	granted |= {f"{name[:-6]}:read" for name in list(granted) if name.endswith(":write")}
	return granted
