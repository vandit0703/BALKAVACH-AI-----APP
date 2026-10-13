from uuid import UUID

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.db.base import get_model
from app.db.session import get_db
from app.core.permissions import expand_permissions
from app.core.security import decode_access_token
from app.services.session_service import is_session_revoked

bearer_scheme = HTTPBearer(auto_error=False)


def get_current_user(
	credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
	session: Session = Depends(get_db),
):
	if credentials is None:
		raise HTTPException(status_code=401, detail="Authentication required", headers={"WWW-Authenticate": "Bearer"})
	payload = decode_access_token(credentials.credentials)
	try:
		user_id = UUID(payload["sub"])
	except (KeyError, TypeError, ValueError) as error:
		raise HTTPException(status_code=401, detail="Invalid access token") from error

	sid = payload.get("sid")
	if sid is not None and is_session_revoked(session, sid):
		raise HTTPException(status_code=401, detail="Session has ended", headers={"WWW-Authenticate": "Bearer"})

	User = get_model("User")
	user = session.query(User).filter(User.id == user_id, User.is_active.is_(True)).one_or_none()
	if user is None:
		raise HTTPException(status_code=401, detail="Invalid or inactive account")
	return user


def require_parent(user=Depends(get_current_user)):
	if user.role != "parent":
		raise HTTPException(status_code=403, detail="Parent access required")
	return user


def require_child(user=Depends(get_current_user), session: Session = Depends(get_db)):
	if user.role != "child":
		raise HTTPException(status_code=403, detail="Child access required")
	ChildProfile = get_model("ChildProfile")
	child = (
		session.query(ChildProfile)
		.filter(ChildProfile.user_id == user.id, ChildProfile.is_active.is_(True))
		.one_or_none()
	)
	if child is None:
		raise HTTPException(status_code=403, detail="Active child profile required")
	return child


def require_admin(user=Depends(get_current_user), session: Session = Depends(get_db)):
	if user.role not in {"admin", "staff"}:
		raise HTTPException(status_code=403, detail="Administrator access required")
	UserAdminRole = get_model("UserAdminRole")
	if not session.query(UserAdminRole.user_id).filter(UserAdminRole.user_id == user.id).first():
		raise HTTPException(status_code=403, detail="Administrator role assignment required")
	return user


def require_admin_permission(permission: str):
	def check_permission(user=Depends(get_current_user), session: Session = Depends(get_db)):
		if user.role not in {"admin", "staff"}:
			raise HTTPException(status_code=403, detail="Administrator access required")
		UserAdminRole = get_model("UserAdminRole")
		AdminRole = get_model("AdminRole")
		assignments = (
			session.query(AdminRole.permissions)
			.join(UserAdminRole, UserAdminRole.admin_role_id == AdminRole.id)
			.filter(UserAdminRole.user_id == user.id)
			.all()
		)
		granted: set[str] = set()
		for (permissions,) in assignments:
			granted |= expand_permissions(permissions)
		if permission not in granted and "*" not in granted:
			raise HTTPException(status_code=403, detail="Required administrator permission is missing")
		return user

	return check_permission
