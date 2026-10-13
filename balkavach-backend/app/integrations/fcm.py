"""Firebase Cloud Messaging (HTTP v1) provider.

Configure with ``NOTIFICATION_PROVIDER=app.integrations.fcm:create_provider`` and
one of ``FCM_SERVICE_ACCOUNT_JSON`` (the JSON itself) or ``FCM_SERVICE_ACCOUNT_FILE``
(a path). The service account needs the *Firebase Cloud Messaging API Admin*
role. Nothing here is Flutter-side: the app only holds the public
``google-services.json``, never a server credential.

``send`` returns one of ``"ok"``, ``"invalid_token"`` (stop using that token),
``"retry"`` (rate limit / transient) or ``"error"``. It never raises for
provider problems.
"""

import json
import logging
import threading
import time
from pathlib import Path

import httpx
import jwt

from app.core.config import settings

logger = logging.getLogger(__name__)

_SCOPE = "https://www.googleapis.com/auth/firebase.messaging"
_REQUIRED = ("project_id", "client_email", "private_key")


class FcmProvider:
	def __init__(self, service_account: dict, http_client: httpx.Client | None = None) -> None:
		missing = [key for key in _REQUIRED if not service_account.get(key)]
		if missing:
			raise ValueError(f"FCM service account is missing: {', '.join(missing)}")
		self._account = service_account
		self._project = service_account["project_id"]
		self._token_uri = service_account.get("token_uri") or "https://oauth2.googleapis.com/token"
		self._http = http_client or httpx.Client(timeout=httpx.Timeout(10.0))
		self._lock = threading.Lock()
		self._access_token: str | None = None
		self._access_expires = 0.0

	def _bearer(self) -> str | None:
		with self._lock:
			if self._access_token and time.time() < self._access_expires - 60:
				return self._access_token
			now = int(time.time())
			assertion = jwt.encode(
				{
					"iss": self._account["client_email"],
					"scope": _SCOPE,
					"aud": self._token_uri,
					"iat": now,
					"exp": now + 3600,
				},
				self._account["private_key"],
				algorithm="RS256",
			)
			try:
				response = self._http.post(
					self._token_uri,
					data={"grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer", "assertion": assertion},
				)
			except httpx.HTTPError:
				logger.warning("FCM OAuth request failed")
				return None
			if response.status_code != 200:
				logger.warning("FCM OAuth rejected the service account (HTTP %s)", response.status_code)
				return None
			body = response.json()
			self._access_token = body.get("access_token")
			self._access_expires = time.time() + int(body.get("expires_in", 3300))
			return self._access_token

	def send(self, token: str, title: str, body: str, data: dict[str, str]) -> str:
		bearer = self._bearer()
		if bearer is None:
			return "error"
		message = {
			"message": {
				"token": token,
				"notification": {"title": title, "body": body},
				"data": {str(key): str(value) for key, value in data.items()},
				"android": {"priority": "HIGH"},
			}
		}
		try:
			response = self._http.post(
				f"https://fcm.googleapis.com/v1/projects/{self._project}/messages:send",
				headers={"Authorization": f"Bearer {bearer}"},
				json=message,
			)
		except httpx.HTTPError:
			logger.warning("FCM send failed (network)")
			return "retry"
		if response.status_code == 200:
			return "ok"
		try:
			error = response.json().get("error", {})
		except ValueError:
			error = {}
		codes = {detail.get("errorCode") for detail in error.get("details", []) if isinstance(detail, dict)}
		if response.status_code == 404 or "UNREGISTERED" in codes:
			return "invalid_token"
		if response.status_code == 400 and "INVALID_ARGUMENT" in codes:
			return "invalid_token"
		if response.status_code in {429, 500, 503} or error.get("status") in {"UNAVAILABLE", "RESOURCE_EXHAUSTED"}:
			return "retry"
		if response.status_code in {401, 403}:
			with self._lock:
				self._access_token = None
		logger.warning("FCM rejected a message (HTTP %s, %s)", response.status_code, error.get("status"))
		return "error"


def create_provider() -> FcmProvider:
	raw = settings.fcm_service_account_json
	if not raw and settings.fcm_service_account_file:
		raw = Path(settings.fcm_service_account_file).read_text(encoding="utf-8")
	if not raw:
		raise ValueError("Set FCM_SERVICE_ACCOUNT_JSON or FCM_SERVICE_ACCOUNT_FILE")
	return FcmProvider(json.loads(raw))
