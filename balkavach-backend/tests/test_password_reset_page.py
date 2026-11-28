"""Password-reset landing page served by the API (no database needed)."""

import re

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
SECRET = "reset-token-that-must-never-be-echoed-0123456789"


def test_page_is_served_with_strict_headers_for_both_paths():
	for path in ("/reset-password", "/reset-password/"):
		response = client.get(path, params={"token": SECRET})
		assert response.status_code == 200
		assert response.headers["content-type"].startswith("text/html")
		assert response.headers["cache-control"] == "no-store"
		assert response.headers["referrer-policy"] == "no-referrer"
		assert response.headers["x-frame-options"] == "DENY"
		assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
		assert "connect-src 'self'" in response.headers["content-security-policy"]


def test_token_is_never_rendered_into_the_page_or_headers():
	response = client.get("/reset-password", params={"token": SECRET})
	assert SECRET not in response.text
	assert SECRET not in str(response.headers)


def test_csp_nonce_is_fresh_and_matches_the_inline_script_and_style():
	first = client.get("/reset-password")
	second = client.get("/reset-password")
	nonces = []
	for response in (first, second):
		nonce = re.search(r"script-src 'nonce-([^']+)'", response.headers["content-security-policy"]).group(1)
		assert f'<script nonce="{nonce}">' in response.text
		assert f'<style nonce="{nonce}">' in response.text
		nonces.append(nonce)
	assert nonces[0] != nonces[1]


def test_page_posts_to_the_reset_api_and_removes_the_token_from_the_url():
	text = client.get("/reset-password").text
	assert "/api/v1/auth/password/reset" in text
	assert "history.replaceState" in text
	assert "credentials:'omit'" in text
	assert 'type="password"' in text  # with show/hide toggles wired in script


def test_page_has_english_hindi_and_gujarati_text_in_real_script():
	text = client.get("/reset-password").text
	assert "Reset your BALKAVACH password" in text
	assert "अपना BALKAVACH पासवर्ड रीसेट करें" in text
	assert "તમારો BALKAVACH પાસવર્ડ રીસેટ કરો" in text


def test_page_is_not_part_of_the_published_api_schema():
	assert "/reset-password" not in app.openapi()["paths"]
	assert "/.well-known/assetlinks.json" not in app.openapi()["paths"]


def test_assetlinks_returns_404_when_unconfigured(monkeypatch):
	from app.core.config import settings

	monkeypatch.setattr(settings, "android_assetlinks_sha256", [])
	response = client.get("/.well-known/assetlinks.json")
	assert response.status_code == 404


def test_assetlinks_returns_valid_manifest_when_configured(monkeypatch):
	from app.core.config import settings

	fp = "AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
	monkeypatch.setattr(settings, "android_assetlinks_sha256", [fp])
	monkeypatch.setattr(settings, "android_package_name", "com.balkavach.balkavach_app")
	response = client.get("/.well-known/assetlinks.json")
	assert response.status_code == 200
	data = response.json()
	assert data == [
		{
			"relation": ["delegate_permission/common.handle_all_urls"],
			"target": {
				"namespace": "android_app",
				"package_name": "com.balkavach.balkavach_app",
				"sha256_cert_fingerprints": [fp],
			},
		}
	]
