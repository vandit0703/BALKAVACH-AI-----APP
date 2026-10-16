"""HTTP-level helpers for API tests running on the isolated test database.

Every test using ``ApiHarness`` runs inside the rolled-back transaction owned by
``isolated_test_session``, so no data survives a test.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi.testclient import TestClient

from app.db.base import get_model

PASSWORD = "a-long-integration-password"


class ApiHarness:
    def __init__(self, client: TestClient, session) -> None:
        self.client = client
        self.session = session

    # -- low level ---------------------------------------------------------
    @staticmethod
    def auth(token: str, **extra: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}", **extra}

    def get(self, path: str, token: str | None = None, **kwargs):
        headers = self.auth(token) if token else None
        return self.client.get(f"/api/v1{path}", headers=headers, **kwargs)

    def post(self, path: str, token: str | None = None, json=None, headers=None, **kwargs):
        merged = dict(self.auth(token)) if token else {}
        merged.update(headers or {})
        return self.client.post(f"/api/v1{path}", headers=merged, json=json, **kwargs)

    def patch(self, path: str, token: str, json=None):
        return self.client.patch(f"/api/v1{path}", headers=self.auth(token), json=json)

    def delete(self, path: str, token: str):
        return self.client.delete(f"/api/v1{path}", headers=self.auth(token))

    # -- accounts ----------------------------------------------------------
    def register_parent(self, name: str = "Test Parent") -> dict:
        email = f"parent-{uuid4().hex}@example.com"
        response = self.post("/auth/register", json={"full_name": name, "email": email, "password": PASSWORD})
        assert response.status_code == 201, response.text
        body = response.json()
        return {"email": email, "token": body["access_token"], "id": body["user"]["id"]}

    def create_family(self, parent_token: str, name: str = "Test Family") -> dict:
        response = self.post("/families", parent_token, {"family_name": name})
        assert response.status_code == 201, response.text
        return response.json()

    def create_child(self, parent_token: str, family_id: str, name: str = "Kid") -> dict:
        username = f"kid-{uuid4().hex[:12]}"
        response = self.post(
            f"/families/{family_id}/children",
            parent_token,
            {"display_name": name, "username": username, "password": PASSWORD},
        )
        assert response.status_code == 201, response.text
        child = response.json()
        session = self.post(f"/auth/children/{child['id']}/session", parent_token)
        assert session.status_code == 200, session.text
        child["token"] = session.json()["access_token"]
        child["user_id"] = session.json()["user"]["id"]
        child["username"] = username
        child["password"] = PASSWORD
        return child

    def family_with_child(self, child_name: str = "Kid") -> dict:
        parent = self.register_parent()
        family = self.create_family(parent["token"])
        child = self.create_child(parent["token"], family["id"], child_name)
        return {"parent": parent, "family": family, "child": child}

    def create_task(self, parent_token: str, family_id: str, **overrides) -> dict:
        payload = {"family_id": family_id, "title": "Make the bed", "star_reward": 5, "xp_reward": 20}
        payload.update(overrides)
        response = self.post("/tasks", parent_token, payload)
        assert response.status_code == 201, response.text
        return response.json()

    def submit(self, child_token: str, task_id: str, note: str | None = "done"):
        body = {"proof_type": "note", "proof_note": note} if note else {"proof_type": "none"}
        return self.post(f"/tasks/{task_id}/submissions", child_token, body)

    def review(self, parent_token: str, submission_id: str, decision: str = "approved", note: str | None = None):
        return self.post(
            f"/reviews/submissions/{submission_id}", parent_token, {"decision": decision, "review_note": note}
        )

    def create_reward(self, parent_token: str, family_id: str, **overrides):
        payload = {"family_id": family_id, "name": "Extra story", "reward_type": "custom", "star_cost": 3}
        payload.update(overrides)
        return self.post("/rewards", parent_token, payload)

    def grant_stars(self, child_id: str, amount: int) -> None:
        """Direct ledger insert; the only way to give stars without a full approval round trip."""
        StarTransaction = get_model("StarTransaction")
        self.session.add(
            StarTransaction(
                child_id=child_id,
                amount=amount,
                transaction_type="admin_adjustment",
                idempotency_key=f"test-grant:{uuid4()}",
                description="test grant",
            )
        )
        self.session.commit()

    # -- admins ------------------------------------------------------------
    def make_admin(self, role_name: str = "super_admin") -> dict:
        from app.core.security import create_access_token, hash_password

        User = get_model("User")
        AdminRole = get_model("AdminRole")
        UserAdminRole = get_model("UserAdminRole")
        user = User(
            full_name="Test Admin",
            email=f"admin-{uuid4().hex}@example.com",
            password_hash=hash_password(PASSWORD),
            role="admin",
            preferred_language="en",
            is_active=True,
        )
        self.session.add(user)
        self.session.commit()
        role = self.session.query(AdminRole).filter(AdminRole.name == role_name).one()
        self.session.add(UserAdminRole(user_id=user.id, admin_role_id=role.id))
        self.session.commit()
        token, _ = create_access_token(str(user.id))
        return {"id": str(user.id), "token": token, "email": user.email}


def in_days(days: int) -> str:
    return (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()
