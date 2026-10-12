from app.db.base import get_model

_MODELS = {
	"Level",
	"StarTransaction",
	"XPTransaction",
	"ChildBadge",
	"Badge",
	"ChildProgress",
	"ChildActivityDay",
	"ChildStreak",
}


def __getattr__(name: str):
	if name in _MODELS:
		return get_model(name)
	raise AttributeError(name)
