from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.schemas.admin_manage import AppConfigPublic
from app.services.app_settings_service import read_all

router = APIRouter(tags=["app config"])


@router.get("/app-config", response_model=AppConfigPublic)
def app_config(session: Session = Depends(get_db)) -> AppConfigPublic:
	"""Non-sensitive runtime configuration the app reads at start-up (no sign-in needed)."""
	values, overridden = read_all(session)
	return AppConfigPublic(
		consent_versions=values["consent_versions"],
		consent_source="admin" if "consent_versions" in overridden else "default",
		maintenance=values["maintenance"],
	)
