from app.db.base import get_model


def __getattr__(name: str):
	if name == "Notification":
		return get_model(name)
	raise AttributeError(name)
