import hashlib
import io
import logging
from uuid import UUID, uuid4

from PIL import Image, ImageOps, UnidentifiedImageError
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.exceptions import APIError
from app.db.base import get_model
from app.integrations.storage import get_storage_provider

logger = logging.getLogger(__name__)

Image.MAX_IMAGE_PIXELS = 40_000_000
MAX_EDGE = 2048
_FORMATS = {
	"JPEG": ("image/jpeg", "jpg", {"quality": 85, "optimize": True}),
	"PNG": ("image/png", "png", {"optimize": True}),
	"WEBP": ("image/webp", "webp", {"quality": 85}),
}
PROOF_URL_PREFIX = "/api/v1/uploads/task-proofs"


def proof_url(upload_id: UUID) -> str:
	return f"{PROOF_URL_PREFIX}/{upload_id}"


def clean_image(data: bytes) -> tuple[bytes, str, str]:
	"""Decode fully, drop all metadata (EXIF/GPS), cap size and re-encode.

	Trusting a client-declared type or a file signature alone would let a renamed
	script through and would leak a child's location from the photo metadata.
	"""
	if not data:
		raise APIError(422, "empty_upload", "The file is empty")
	try:
		with Image.open(io.BytesIO(data)) as probe:
			detected = probe.format
			probe.load()
			image = ImageOps.exif_transpose(probe)
			image.load()
	except (UnidentifiedImageError, OSError, Image.DecompressionBombError, SyntaxError, ValueError) as error:
		raise APIError(415, "unsupported_image", "Upload a JPEG, PNG or WebP photo") from error
	if detected not in _FORMATS:
		raise APIError(415, "unsupported_image", "Upload a JPEG, PNG or WebP photo")
	content_type, extension, options = _FORMATS[detected]
	image.thumbnail((MAX_EDGE, MAX_EDGE))
	if detected == "JPEG" and image.mode not in {"RGB", "L"}:
		image = image.convert("RGB")
	image.info = {}  # no ICC/EXIF/XMP carried over; metadata is only written when passed explicitly
	output = io.BytesIO()
	image.save(output, format=detected, **options)
	return output.getvalue(), content_type, extension


def create_proof_upload(session: Session, child, user_id: UUID, data: bytes):
	ProofUpload = get_model("ProofUpload")
	if len(data) > settings.max_upload_bytes:
		raise APIError(413, "upload_too_large", "That photo is too large")
	unattached = (
		session.query(func.count(ProofUpload.id))
		.filter(ProofUpload.child_id == child.id, ProofUpload.submission_id.is_(None))
		.scalar()
	)
	if int(unattached or 0) >= settings.max_unattached_uploads:
		raise APIError(429, "too_many_uploads", "Send your earlier photos with a mission first")
	cleaned, content_type, extension = clean_image(data)
	key = f"proofs/{child.family_id}/{uuid4()}.{extension}"
	try:
		get_storage_provider().put(key, cleaned, content_type)
	except APIError:
		raise
	except Exception as error:
		logger.exception("Proof photo storage failed")
		raise APIError(503, "storage_unavailable", "Photos cannot be saved right now") from error
	row = ProofUpload(
		family_id=child.family_id,
		child_id=child.id,
		uploaded_by=user_id,
		content_type=content_type,
		size_bytes=len(cleaned),
		sha256=hashlib.sha256(cleaned).hexdigest(),
		storage_key=key,
	)
	session.add(row)
	try:
		session.commit()
	except Exception:
		session.rollback()
		try:
			get_storage_provider().delete(key)
		except Exception:
			logger.warning("Could not remove an orphaned upload object")
		raise
	session.refresh(row)
	return row


def load_proof(session: Session, user, upload_id: UUID) -> tuple[bytes, str]:
	ProofUpload = get_model("ProofUpload")
	row = session.query(ProofUpload).filter(ProofUpload.id == upload_id).one_or_none()
	allowed = False
	if row is not None:
		if user.role == "child":
			ChildProfile = get_model("ChildProfile")
			allowed = (
				session.query(ChildProfile.id)
				.filter(ChildProfile.id == row.child_id, ChildProfile.user_id == user.id, ChildProfile.is_active.is_(True))
				.first()
				is not None
			)
		elif user.role == "parent":
			FamilyMember = get_model("FamilyMember")
			allowed = (
				session.query(FamilyMember.id)
				.filter(
					FamilyMember.family_id == row.family_id,
					FamilyMember.user_id == user.id,
					FamilyMember.is_active.is_(True),
				)
				.first()
				is not None
			)
	if not allowed:
		raise APIError(404, "upload_not_found", "Photo not found")
	try:
		data = get_storage_provider().get(row.storage_key)
	except APIError:
		raise
	except Exception as error:
		raise APIError(503, "storage_unavailable", "Photos cannot be loaded right now") from error
	if data is None:
		raise APIError(404, "upload_not_found", "Photo not found")
	return data, row.content_type


def claim_upload_for_submission(session: Session, child, upload_id: UUID, submission_id: UUID) -> None:
	"""Attach a child's own, unused upload to a submission (row-locked against double use)."""
	ProofUpload = get_model("ProofUpload")
	row = (
		session.query(ProofUpload)
		.filter(ProofUpload.id == upload_id, ProofUpload.child_id == child.id)
		.with_for_update()
		.one_or_none()
	)
	if row is None:
		raise APIError(404, "upload_not_found", "Photo not found")
	if row.submission_id is not None:
		raise APIError(409, "upload_already_used", "That photo was already sent with a mission")
	row.submission_id = submission_id
