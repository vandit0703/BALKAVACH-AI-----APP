"""Object storage for uploaded proof photos.

``STORAGE_PROVIDER=local`` writes under ``UPLOAD_DIR`` and is for development and
tests only: a hosted web service with an ephemeral disk loses those files on every
deploy. Production should use ``STORAGE_PROVIDER=s3`` (any S3-compatible service:
AWS S3, Cloudflare R2, Backblaze B2, MinIO). Objects are always private; photos
are only ever served through the authorised API endpoint.
"""

import threading
from pathlib import Path, PurePosixPath
from typing import Protocol

from app.core.config import settings
from app.core.exceptions import APIError


class StorageProvider(Protocol):
	def put(self, key: str, data: bytes, content_type: str) -> None: ...

	def get(self, key: str) -> bytes | None: ...

	def delete(self, key: str) -> None: ...


def _safe_key(key: str) -> PurePosixPath:
	path = PurePosixPath(key)
	if not key or path.is_absolute() or "\\" in key or any(part in {"..", ".", ""} for part in key.split("/")):
		raise ValueError("Invalid storage key")
	return path


class LocalDiskStorage:
	def __init__(self, root: str | Path) -> None:
		self._root = Path(root).resolve()

	def _resolve(self, key: str) -> Path:
		target = (self._root / _safe_key(key)).resolve()
		if self._root != target and self._root not in target.parents:
			raise ValueError("Invalid storage key")
		return target

	def put(self, key: str, data: bytes, content_type: str) -> None:
		target = self._resolve(key)
		target.parent.mkdir(parents=True, exist_ok=True)
		target.write_bytes(data)

	def get(self, key: str) -> bytes | None:
		target = self._resolve(key)
		return target.read_bytes() if target.is_file() else None

	def delete(self, key: str) -> None:
		target = self._resolve(key)
		if target.is_file():
			target.unlink()


class S3Storage:
	def __init__(self, client, bucket: str, not_found: tuple[type[BaseException], ...] = ()) -> None:
		self._client = client
		self._bucket = bucket
		self._not_found = not_found

	def put(self, key: str, data: bytes, content_type: str) -> None:
		_safe_key(key)
		self._client.put_object(Bucket=self._bucket, Key=key, Body=data, ContentType=content_type)

	def get(self, key: str) -> bytes | None:
		_safe_key(key)
		try:
			return self._client.get_object(Bucket=self._bucket, Key=key)["Body"].read()
		except self._not_found:
			return None

	def delete(self, key: str) -> None:
		_safe_key(key)
		self._client.delete_object(Bucket=self._bucket, Key=key)


_lock = threading.Lock()
_providers: dict[str, StorageProvider] = {}


def reset_cache() -> None:
	with _lock:
		_providers.clear()


def get_storage_provider() -> StorageProvider:
	name = (settings.storage_provider or "local").lower()
	with _lock:
		cached = _providers.get(name)
		if cached is not None:
			return cached
		if name == "local":
			provider: StorageProvider = LocalDiskStorage(settings.upload_dir)
		elif name == "s3":
			if not settings.s3_bucket:
				raise APIError(503, "storage_unavailable", "Photo storage is not configured")
			try:
				import boto3  # optional dependency: requirements-storage-s3.txt
			except ImportError as error:
				raise APIError(503, "storage_unavailable", "Photo storage is not configured") from error
			client = boto3.client(
				"s3",
				endpoint_url=settings.s3_endpoint_url,
				region_name=settings.s3_region,
				aws_access_key_id=settings.s3_access_key_id,
				aws_secret_access_key=settings.s3_secret_access_key,
			)
			provider = S3Storage(client, settings.s3_bucket, not_found=(client.exceptions.NoSuchKey,))
		else:
			raise APIError(503, "storage_unavailable", "Photo storage is not configured")
		_providers[name] = provider
		return provider
