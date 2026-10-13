from uuid import UUID

from pydantic import BaseModel


class ProofUploadPublic(BaseModel):
	upload_id: UUID
	content_type: str
	size_bytes: int
	proof_url: str
