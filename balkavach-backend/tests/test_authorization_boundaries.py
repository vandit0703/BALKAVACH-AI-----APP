"""Authorization boundaries that hold even if the Flutter UI is bypassed. Pure tests (no database).

* every API route is either on an explicit public allow-list or sits behind an auth dependency;
* the parent/child/admin guards reject the wrong role;
* the endpoint that issues a parent session from a child device requires a *child* session;
* no route can mint a parent session from email + PIN (the retired verify route is a tombstone).
"""

import logging

import pytest
from fastapi import APIRouter, HTTPException
from fastapi.routing import APIRoute

import app.api.router as api_router_module
from app.core import dependencies as deps

PUBLIC_ROUTES = {
	("POST", "/api/v1/auth/register"),
	("POST", "/api/v1/auth/login"),
	("POST", "/api/v1/auth/refresh"),
	("POST", "/api/v1/auth/logout"),
	("POST", "/api/v1/auth/password/forgot"),
	("POST", "/api/v1/auth/password/reset"),
	("POST", "/api/v1/auth/parent-pin/verify"),  # tombstone: always 410, evaluates nothing
	("GET", "/api/v1/app-config"),
}
AUTH_GUARDS = {deps.get_current_user, deps.require_parent, deps.require_child, deps.require_admin}


def _callables(dependant):
	for sub in dependant.dependencies:
		yield sub.call
		yield from _callables(sub)


def _guards(route) -> set:
	found = set(_callables(route.dependant))
	# require_admin_permission(...) builds closures named check_permission.
	if any(getattr(call, "__name__", "") == "check_permission" for call in found):
		found.add(deps.require_admin)
	return found & AUTH_GUARDS


class _Route:
	"""A route with its full public path (the app mounts every router under /api/v1)."""

	def __init__(self, route: APIRoute) -> None:
		self.route = route
		self.path = "/api/v1" + route.path
		self.methods = route.methods
		self.dependant = route.dependant
		self.body_field = route.body_field
		self.endpoint = route.endpoint


def _api_routes() -> list[_Route]:
	"""Walk the routers the API composes, independent of FastAPI's internal include bookkeeping."""
	routers = [
		value
		for name, value in vars(api_router_module).items()
		if isinstance(value, APIRouter) and name != "api_router"
	]
	return [_Route(r) for router in routers for r in router.routes if isinstance(r, APIRoute)]


def _body_schema(route) -> dict:
	field = route.body_field
	model = getattr(field, "type_", None) or field.field_info.annotation
	return model.model_json_schema()


def test_route_inventory_is_complete():
	paths = {(m, r.path) for r in _api_routes() for m in r.methods}
	assert len(paths) >= 150  # 155 routes at the audited commit; a drop means the walk missed routers


def test_every_api_route_is_public_by_allow_list_or_guarded():
	unguarded = []
	for route in _api_routes():
		for method in route.methods - {"HEAD", "OPTIONS"}:
			if (method, route.path) in PUBLIC_ROUTES:
				continue
			if not _guards(route):
				unguarded.append(f"{method} {route.path}")
	assert unguarded == [], f"Routes with no authentication dependency: {unguarded}"


def test_public_allow_list_has_no_stale_entries():
	existing = {(m, r.path) for r in _api_routes() for m in r.methods}
	assert PUBLIC_ROUTES <= existing


def test_parent_guard_rejects_child_and_admin_tokens():
	class User:
		def __init__(self, role):
			self.role = role

	assert deps.require_parent(User("parent")).role == "parent"
	for role in ("child", "admin", "staff"):
		with pytest.raises(HTTPException) as error:
			deps.require_parent(User(role))
		assert error.value.status_code == 403


def test_child_guard_rejects_parent_tokens_before_touching_the_database():
	class User:
		role = "parent"

	with pytest.raises(HTTPException) as error:
		deps.require_child(User(), session=None)
	assert error.value.status_code == 403


def test_missing_bearer_is_logged_without_credentials(caplog):
	with caplog.at_level(logging.WARNING, logger="app.core.dependencies"):
		with pytest.raises(HTTPException) as error:
			deps.get_current_user(credentials=None, session=None)

	assert error.value.status_code == 401
	assert "reason=missing_bearer authorization_attached=false" in caplog.text


def test_parent_mode_entry_requires_a_child_session():
	route = next(r for r in _api_routes() if r.path == "/api/v1/auth/parent-mode/enter")
	calls = set(_callables(route.dependant))
	assert deps.require_child in calls
	assert deps.require_parent not in calls


def test_parent_mode_entry_takes_email_and_password_only():
	route = next(r for r in _api_routes() if r.path == "/api/v1/auth/parent-mode/enter")
	body = _body_schema(route)
	assert set(body["properties"]) == {"email", "password"}
	assert set(body["required"]) == {"email", "password"}


def test_no_route_accepts_email_and_pin_to_issue_a_session():
	for route in _api_routes():
		if not route.body_field:
			continue
		props = set(_body_schema(route).get("properties", {}))
		assert not ({"email", "pin"} <= props), f"{route.path} accepts email+pin"


def test_retired_verify_route_is_a_tombstone_that_reads_no_body():
	route = next(r for r in _api_routes() if r.path == "/api/v1/auth/parent-pin/verify")
	assert route.body_field is None
	with pytest.raises(Exception) as error:
		route.endpoint()
	assert getattr(error.value, "status_code", None) == 410
