from uuid import UUID

from fastapi import APIRouter, Depends, Query, Response, status
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.schemas.notification import DeviceRegistration, DeviceUnregistration, NotificationPublic
from app.services.device_service import register_device, unregister_device
from app.services.notification_service import list_notifications, mark_notification_read

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get("", response_model=list[NotificationPublic])
def get_notifications(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> list[NotificationPublic]:
	return [
		NotificationPublic.model_validate(item)
		for item in list_notifications(session, user.id, limit, offset)
	]


@router.post("/{notification_id}/read", response_model=NotificationPublic)
def mark_read(
	notification_id: UUID,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> NotificationPublic:
	notification = mark_notification_read(session, user.id, notification_id)
	return NotificationPublic.model_validate(notification)


@router.put("/devices", status_code=status.HTTP_204_NO_CONTENT)
def put_device(
	request: DeviceRegistration,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> Response:
	"""Register or refresh this device's push token for the signed-in user."""
	register_device(session, user.id, request.token, request.platform, request.app_version)
	return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.post("/devices/unregister", status_code=status.HTTP_204_NO_CONTENT)
def delete_device(
	request: DeviceUnregistration,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> Response:
	unregister_device(session, user.id, request.token)
	return Response(status_code=status.HTTP_204_NO_CONTENT)
