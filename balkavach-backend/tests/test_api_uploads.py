"""Mission proof photo upload: validation, authorisation, privacy."""

import io
from uuid import uuid4

import pytest
from PIL import Image

from app.core.config import settings
from app.db.base import get_model
from app.integrations import storage as storage_module


@pytest.fixture(autouse=True)
def local_storage(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "storage_provider", "local")
    monkeypatch.setattr(settings, "upload_dir", str(tmp_path))
    storage_module.reset_cache()
    yield tmp_path
    storage_module.reset_cache()


def _image(fmt="PNG", size=(40, 30), exif=False):
    buffer = io.BytesIO()
    image = Image.new("RGB", size, (200, 30, 30))
    kwargs = {}
    if exif and fmt == "JPEG":
        data = Image.Exif()
        data[0x010F] = "SecretCameraMaker"  # Make
        data[0x8825] = {1: "N", 2: (23.0, 1.0, 1.0)}  # GPS block
        kwargs["exif"] = data
    image.save(buffer, format=fmt, **kwargs)
    return buffer.getvalue()


def _upload(api, token, data, name="photo.png", content_type="image/png"):
    return api.client.post(
        "/api/v1/uploads/task-proofs",
        headers=api.auth(token),
        files={"file": (name, data, content_type)},
    )


def test_child_uploads_png_jpeg_and_webp(api):
    ctx = api.family_with_child()
    for fmt, content_type in [("PNG", "image/png"), ("JPEG", "image/jpeg"), ("WEBP", "image/webp")]:
        response = _upload(api, ctx["child"]["token"], _image(fmt), content_type=content_type)
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["content_type"] == content_type
        assert body["proof_url"].endswith(f"/uploads/task-proofs/{body['upload_id']}")


def test_non_images_are_refused_even_with_an_image_content_type(api):
    ctx = api.family_with_child()
    fake = _upload(api, ctx["child"]["token"], b"<script>alert(1)</script>", "evil.png", "image/png")
    assert fake.status_code == 415
    pdf = _upload(api, ctx["child"]["token"], b"%PDF-1.7 ....", "x.pdf", "application/pdf")
    assert pdf.status_code == 415
    truncated = _upload(api, ctx["child"]["token"], _image("PNG")[:30], "cut.png", "image/png")
    assert truncated.status_code == 415
    empty = _upload(api, ctx["child"]["token"], b"", "empty.png", "image/png")
    assert empty.status_code in {415, 422}


def test_oversized_upload_is_refused(api, monkeypatch):
    monkeypatch.setattr(settings, "max_upload_bytes", 2048)
    ctx = api.family_with_child()
    big = _image("PNG", size=(400, 400))
    assert len(big) > 0
    noisy = io.BytesIO()
    Image.effect_noise((300, 300), 100).convert("RGB").save(noisy, format="PNG")
    assert len(noisy.getvalue()) > 2048
    assert _upload(api, ctx["child"]["token"], noisy.getvalue()).status_code == 413


def test_only_children_can_upload(api):
    ctx = api.family_with_child()
    assert _upload(api, ctx["parent"]["token"], _image()).status_code == 403
    assert api.client.post("/api/v1/uploads/task-proofs", files={"file": ("a.png", _image(), "image/png")}).status_code == 401


def test_exif_and_gps_metadata_are_stripped(api, local_storage):
    ctx = api.family_with_child()
    original = _image("JPEG", exif=True)
    assert b"SecretCameraMaker" in original
    uploaded = _upload(api, ctx["child"]["token"], original, "p.jpg", "image/jpeg").json()
    served = api.client.get(uploaded["proof_url"], headers=api.auth(ctx["child"]["token"]))
    assert served.status_code == 200
    assert b"SecretCameraMaker" not in served.content
    reopened = Image.open(io.BytesIO(served.content))
    assert not reopened.getexif()


def test_large_images_are_downscaled(api):
    ctx = api.family_with_child()
    big = _image("PNG", size=(5000, 100))
    uploaded = _upload(api, ctx["child"]["token"], big).json()
    served = api.client.get(uploaded["proof_url"], headers=api.auth(ctx["child"]["token"]))
    assert max(Image.open(io.BytesIO(served.content)).size) <= 2048


def test_who_can_view_a_proof(api):
    ctx = api.family_with_child("Asha")
    other = api.family_with_child()
    sibling = api.create_child(ctx["parent"]["token"], ctx["family"]["id"], "Ravi")
    uploaded = _upload(api, ctx["child"]["token"], _image()).json()
    url = uploaded["proof_url"]

    def fetch(token):
        return api.client.get(url, headers=api.auth(token) if token else {})

    assert fetch(ctx["child"]["token"]).status_code == 200
    assert fetch(ctx["parent"]["token"]).status_code == 200
    assert fetch(sibling["token"]).status_code == 404
    assert fetch(other["parent"]["token"]).status_code == 404
    assert fetch(other["child"]["token"]).status_code == 404
    assert fetch(None).status_code == 401


def test_served_proof_has_safe_headers(api):
    ctx = api.family_with_child()
    uploaded = _upload(api, ctx["child"]["token"], _image("PNG")).json()
    served = api.client.get(uploaded["proof_url"], headers=api.auth(ctx["child"]["token"]))
    assert served.headers["content-type"] == "image/png"
    assert served.headers["x-content-type-options"] == "nosniff"
    assert "private" in served.headers["cache-control"] and "no-store" in served.headers["cache-control"]


def test_submission_with_photo_links_the_upload_once(api):
    ctx = api.family_with_child()
    parent, child, family = ctx["parent"]["token"], ctx["child"], ctx["family"]
    task = api.create_task(parent, family["id"])
    other_task = api.create_task(parent, family["id"], title="Another mission")
    upload = _upload(api, child["token"], _image()).json()

    created = api.post(
        f"/tasks/{task['id']}/submissions",
        child["token"],
        {"proof_type": "image", "proof_upload_id": upload["upload_id"]},
    )
    assert created.status_code == 201, created.text
    assert created.json()["proof_type"] == "image"
    assert created.json()["proof_url"].endswith(f"/uploads/task-proofs/{upload['upload_id']}")

    reused = api.post(
        f"/tasks/{other_task['id']}/submissions",
        child["token"],
        {"proof_type": "image", "proof_upload_id": upload["upload_id"]},
    )
    assert reused.status_code == 409
    assert reused.json()["error"]["code"] == "upload_already_used"


def test_submission_cannot_use_someone_elses_upload(api):
    a = api.family_with_child()
    b = api.family_with_child()
    foreign = _upload(api, b["child"]["token"], _image()).json()
    task = api.create_task(a["parent"]["token"], a["family"]["id"])
    denied = api.post(
        f"/tasks/{task['id']}/submissions",
        a["child"]["token"],
        {"proof_type": "image", "proof_upload_id": foreign["upload_id"]},
    )
    assert denied.status_code == 404
    missing = api.post(
        f"/tasks/{task['id']}/submissions",
        a["child"]["token"],
        {"proof_type": "image", "proof_upload_id": str(uuid4())},
    )
    assert missing.status_code == 404


def test_image_proof_requires_a_photo_and_a_note_is_never_called_an_image(api):
    ctx = api.family_with_child()
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    bare = api.post(f"/tasks/{task['id']}/submissions", ctx["child"]["token"], {"proof_type": "image"})
    assert bare.status_code == 422
    note = api.post(
        f"/tasks/{task['id']}/submissions", ctx["child"]["token"], {"proof_type": "note", "proof_note": "did it"}
    )
    assert note.status_code == 201
    assert note.json()["proof_type"] == "note" and note.json()["proof_url"] is None


def test_parent_sees_the_photo_through_the_review_queue(api):
    ctx = api.family_with_child()
    task = api.create_task(ctx["parent"]["token"], ctx["family"]["id"])
    upload = _upload(api, ctx["child"]["token"], _image()).json()
    api.post(
        f"/tasks/{task['id']}/submissions",
        ctx["child"]["token"],
        {"proof_type": "image", "proof_upload_id": upload["upload_id"], "proof_note": "look"},
    )
    queue = api.get(f"/reviews/pending?family_id={ctx['family']['id']}", ctx["parent"]["token"]).json()
    assert queue[0]["proof_type"] == "image"
    assert api.client.get(queue[0]["proof_url"], headers=api.auth(ctx["parent"]["token"])).status_code == 200


def test_storage_failure_returns_503_and_leaves_no_row(api, isolated_test_session, monkeypatch):
    ctx = api.family_with_child()

    class Broken:
        def put(self, *args, **kwargs):
            raise OSError("disk full")

    monkeypatch.setattr("app.services.upload_service.get_storage_provider", lambda: Broken())
    response = _upload(api, ctx["child"]["token"], _image())
    assert response.status_code == 503
    assert isolated_test_session.query(get_model("ProofUpload")).count() == 0


def test_unattached_upload_quota(api, monkeypatch):
    monkeypatch.setattr(settings, "max_unattached_uploads", 2)
    ctx = api.family_with_child()
    assert _upload(api, ctx["child"]["token"], _image()).status_code == 201
    assert _upload(api, ctx["child"]["token"], _image()).status_code == 201
    third = _upload(api, ctx["child"]["token"], _image())
    assert third.status_code == 429


# -- storage providers -------------------------------------------------------

def test_local_storage_roundtrip_and_path_traversal_guard(tmp_path):
    store = storage_module.LocalDiskStorage(tmp_path)
    store.put("proofs/f/a.png", b"abc", "image/png")
    assert store.get("proofs/f/a.png") == b"abc"
    assert store.get("proofs/f/missing.png") is None
    with pytest.raises(ValueError):
        store.put("../escape.png", b"x", "image/png")
    with pytest.raises(ValueError):
        store.get("/etc/passwd")


def test_s3_storage_uses_the_client_with_private_objects():
    calls = []

    class FakeBody:
        def read(self):
            return b"bytes"

    class FakeClient:
        def put_object(self, **kwargs):
            calls.append(("put", kwargs))

        def get_object(self, **kwargs):
            if kwargs["Key"] == "missing":
                raise KeyError("NoSuchKey")
            return {"Body": FakeBody()}

        def delete_object(self, **kwargs):
            calls.append(("delete", kwargs))

    store = storage_module.S3Storage(FakeClient(), "bucket", not_found=(KeyError,))
    store.put("proofs/a.png", b"abc", "image/png")
    assert calls[0][1]["Bucket"] == "bucket" and calls[0][1]["ContentType"] == "image/png"
    assert "ACL" not in calls[0][1]
    assert store.get("proofs/a.png") == b"bytes"
    assert store.get("missing") is None
