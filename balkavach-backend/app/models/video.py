from app.db.base import get_model

_MODELS = {"VideoCategory", "Video", "VideoCollection", "VideoCollectionItem", "VideoWatchSession", "EducationalContent"}


def __getattr__(name: str):
	if name in _MODELS:
		return get_model(name)
	raise AttributeError(name)
