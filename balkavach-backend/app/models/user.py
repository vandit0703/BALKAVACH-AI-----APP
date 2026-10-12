from app.db.base import get_model

_MODELS = {"User", "Family", "FamilyMember", "ChildProfile", "UserSetting", "FamilySetting", "ConsentRecord"}


def __getattr__(name: str):
	if name in _MODELS:
		return get_model(name)
	raise AttributeError(name)
