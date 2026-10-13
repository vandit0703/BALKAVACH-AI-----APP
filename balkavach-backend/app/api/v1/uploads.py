from uuid import UUID

from fastapi import APIRouter, Depends, File, Response, UploadFile, status
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import get_current_user, require_child
from app.core.exceptions import APIError
from app.db.session import get_db
from app.schemas.upload import ProofUploadPublic
from app.services.upload_service import create_proof_upload, load_proof, proof_url

router = APIRouter(prefix="/uploads", tags=["uploads"])


@router.post("/task-proofs", response_model=ProofUploadPublic, status_code=status.HTTP_201_CREATED)
def upload_task_proof(
	file: UploadFile = File(...),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> ProofUploadPublic:
	"""Upload one photo, then send its id as ``proof_upload_id`` when submitting the mission."""
	data = file.file.read(settings.max_upload_bytes + 1)
	if len(data) > settings.max_upload_bytes:
		raise APIError(413, "upload_too_large", "That photo is too large")
	row = create_proof_upload(session, child, child.user_id, data)
	return ProofUploadPublic(
		upload_id=row.id,
		content_type=row.content_type,
		size_bytes=row.size_bytes,
		proof_url=proof_url(row.id),
	)


@router.get("/task-proofs/{upload_id}")
def get_task_proof(
	upload_id: UUID,
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> Response:
	data, content_type = load_proof(session, user, upload_id)
	return Response(
		content=data,
		media_type=content_type,
		headers={
			"X-Content-Type-Options": "nosniff",
			"Cache-Control": "private, no-store",
			"Content-Disposition": "inline",
			"Content-Security-Policy": "default-src 'none'; sandbox",
		},
	)
