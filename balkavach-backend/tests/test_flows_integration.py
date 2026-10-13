from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest
from fastapi import HTTPException

from app.core.config import settings
from app.core.dependencies import require_parent
from app.core.exceptions import APIError
from app.core.security import decode_access_token
from app.db.base import get_model
from app.schemas.auth import LoginRequest, RegistrationRequest
from app.schemas.reward import RedemptionReview
from app.schemas.task import TaskReviewCreate
from app.schemas.video import PlaybackStartRequest
from app.services.auth_service import authenticate_user, register_parent
from app.services.ledger_service import star_balance, xp_total
from app.services.reward_service import (
    cancel_redemption,
    fulfill_redemption,
    request_redemption,
    review_redemption,
)
from app.services.task_service import review_submission
from app.services.video_access_service import record_heartbeat, start_playback
from app.utils import utc_naive


def _seed_family(session):
    User = get_model("User")
    Family = get_model("Family")
    FamilyMember = get_model("FamilyMember")
    ChildProfile = get_model("ChildProfile")
    parent = User(
        full_name="Integration Parent",
        email=f"parent-{uuid4().hex}@example.test",
        password_hash=None,
        role="parent",
        preferred_language="en",
        is_active=True,
    )
    session.add(parent)
    session.flush()
    family = Family(family_name="Isolated Test Family", created_by=parent.id)
    session.add(family)
    session.flush()
    child_user = User(
        full_name="Integration Child",
        role="child",
        preferred_language="en",
        is_active=True,
    )
    session.add(child_user)
    session.flush()
    child = ChildProfile(
        user_id=child_user.id,
        family_id=family.id,
        display_name="Integration Child",
        date_of_birth=None,
        is_active=True,
    )
    session.add_all(
        [
            child,
            FamilyMember(
                family_id=family.id,
                user_id=parent.id,
                relationship="parent",
                is_primary_parent=True,
                is_active=True,
            ),
            FamilyMember(
                family_id=family.id,
                user_id=child_user.id,
                relationship="child",
                is_primary_parent=False,
                is_active=True,
            ),
        ]
    )
    session.flush()
    return parent, family, child, child_user


def _seed_video(session, actor_id):
    Video = get_model("Video")
    now = utc_naive(datetime.now(timezone.utc))
    video = Video(
        title="Isolated Test Video",
        video_source="hosted",
        video_url="https://media.example.test/video.mp4",
        duration_seconds=60,
        language_code="en",
        age_min=4,
        age_max=18,
        content_rating="educational",
        is_published=True,
        published_at=now,
        display_order=0,
        uploaded_by=actor_id,
        created_at=now,
        updated_at=now,
    )
    session.add(video)
    session.flush()
    return video


def _grant_stars(session, child_id, amount=50):
    StarTransaction = get_model("StarTransaction")
    session.add(
        StarTransaction(
            child_id=child_id,
            amount=amount,
            transaction_type="admin_adjustment",
            idempotency_key=f"test-grant:{uuid4()}",
            description="Isolated integration test grant",
        )
    )
    session.flush()


def test_auth_registration_and_login_on_isolated_database(isolated_test_session, monkeypatch):
    monkeypatch.setattr(settings, "jwt_secret_key", "integration-test-secret-that-is-long-enough")
    email = f"registration-{uuid4().hex}@example.com"
    registration = RegistrationRequest(full_name="Test Parent", email=email, password="a-long-integration-password")

    created = register_parent(isolated_test_session, registration)
    login = authenticate_user(
        isolated_test_session,
        LoginRequest(email=email, password="a-long-integration-password"),
    )

    assert created.user.role == "parent"
    assert decode_access_token(login.access_token)["sub"] == str(created.user.id)


def test_parent_authorization_rejects_child_role():
    parent = SimpleNamespace(role="parent")
    child = SimpleNamespace(role="child")

    assert require_parent(parent) is parent
    with pytest.raises(HTTPException) as error:
        require_parent(child)
    assert error.value.status_code == 403


def test_task_approval_awards_once_and_retries_do_not_duplicate(isolated_test_session):
    parent, family, child, _ = _seed_family(isolated_test_session)
    Task = get_model("Task")
    TaskSubmission = get_model("TaskSubmission")
    task = Task(
        family_id=family.id,
        created_by=parent.id,
        assigned_child_id=child.id,
        title="Integration task",
        is_custom=True,
        star_reward=5,
        xp_reward=12,
        is_active=True,
    )
    isolated_test_session.add(task)
    isolated_test_session.flush()
    submission = TaskSubmission(
        task_id=task.id,
        child_id=child.id,
        submission_number=1,
        proof_type="none",
        status="pending",
        submitted_at=utc_naive(datetime.now(timezone.utc)),
    )
    isolated_test_session.add(submission)
    isolated_test_session.flush()

    reviewed = review_submission(
        isolated_test_session,
        submission.id,
        parent,
        TaskReviewCreate(decision="approved"),
    )

    assert reviewed.status == "approved"
    assert star_balance(isolated_test_session, child.id) == 5
    assert xp_total(isolated_test_session, child.id) == 12
    with pytest.raises(APIError) as error:
        review_submission(isolated_test_session, submission.id, parent, TaskReviewCreate(decision="approved"))
    assert error.value.status_code == 409
    assert star_balance(isolated_test_session, child.id) == 5
    assert xp_total(isolated_test_session, child.id) == 12


def test_redemption_is_idempotent_and_approved_cancel_refunds_once(isolated_test_session):
    parent, family, child, _ = _seed_family(isolated_test_session)
    Reward = get_model("Reward")
    reward = Reward(
        family_id=family.id,
        created_by=parent.id,
        name="Test reward",
        reward_type="gift",
        star_cost=10,
        is_active=True,
    )
    isolated_test_session.add(reward)
    isolated_test_session.flush()
    _grant_stars(isolated_test_session, child.id, 20)
    key = f"test-redemption:{uuid4()}"

    redemption = request_redemption(isolated_test_session, child, reward.id, key)
    assert request_redemption(isolated_test_session, child, reward.id, key).id == redemption.id
    with pytest.raises(APIError) as reused_key:
        request_redemption(isolated_test_session, child, uuid4(), key)
    assert reused_key.value.status_code == 409
    review_redemption(isolated_test_session, redemption.id, parent, RedemptionReview(), True)
    assert star_balance(isolated_test_session, child.id) == 10
    cancelled = cancel_redemption(isolated_test_session, redemption.id, parent, True)
    assert cancelled.status == "cancelled"
    assert star_balance(isolated_test_session, child.id) == 20
    with pytest.raises(APIError):
        cancel_redemption(isolated_test_session, redemption.id, parent, True)
    assert star_balance(isolated_test_session, child.id) == 20


def test_video_entitlement_is_created_only_when_fulfilled(isolated_test_session):
    parent, family, child, _ = _seed_family(isolated_test_session)
    video = _seed_video(isolated_test_session, parent.id)
    Reward = get_model("Reward")
    reward = Reward(
        family_id=family.id,
        created_by=parent.id,
        name="Video time",
        reward_type="video_time",
        star_cost=10,
        video_id=video.id,
        access_duration_seconds=120,
        access_validity_seconds=600,
        is_active=True,
    )
    isolated_test_session.add(reward)
    isolated_test_session.flush()
    _grant_stars(isolated_test_session, child.id)
    redemption = request_redemption(isolated_test_session, child, reward.id, f"test-video:{uuid4()}")
    review_redemption(isolated_test_session, redemption.id, parent, RedemptionReview(), True)
    Entitlement = get_model("VideoAccessEntitlement")
    assert isolated_test_session.query(Entitlement).filter(Entitlement.redemption_id == redemption.id).count() == 0

    fulfill_redemption(isolated_test_session, redemption.id, parent)
    entitlement = isolated_test_session.query(Entitlement).filter(Entitlement.redemption_id == redemption.id).one()
    assert entitlement.status == "active"
    assert entitlement.granted_seconds == 120
    assert entitlement.video_id == video.id


def test_playback_heartbeat_consumes_no_more_than_entitlement(isolated_test_session, monkeypatch):
    parent, family, child, _ = _seed_family(isolated_test_session)
    video = _seed_video(isolated_test_session, parent.id)
    Reward = get_model("Reward")
    reward = Reward(
        family_id=family.id,
        created_by=parent.id,
        name="Playback test reward",
        reward_type="video_time",
        star_cost=1,
        video_id=video.id,
        access_duration_seconds=20,
        is_active=True,
    )
    isolated_test_session.add(reward)
    isolated_test_session.flush()
    Redemption = get_model("RedemptionRequest")
    now = utc_naive(datetime.now(timezone.utc))
    redemption = Redemption(
        reward_id=reward.id,
        child_id=child.id,
        star_cost_at_request=1,
        status="approved",
        requested_at=now,
    )
    isolated_test_session.add(redemption)
    isolated_test_session.flush()
    Entitlement = get_model("VideoAccessEntitlement")
    entitlement = Entitlement(
        child_id=child.id,
        redemption_id=redemption.id,
        video_id=video.id,
        granted_seconds=20,
        consumed_seconds=0,
        granted_at=now,
        valid_from=now - timedelta(minutes=1),
        status="active",
    )
    isolated_test_session.add(entitlement)
    isolated_test_session.flush()
    WatchSession = get_model("VideoWatchSession")
    watch = WatchSession(
        child_id=child.id,
        video_id=video.id,
        entitlement_id=entitlement.id,
        started_at=now - timedelta(seconds=90),
        last_heartbeat_at=now - timedelta(seconds=90),
        watched_seconds=0,
        status="active",
        device_session_id=f"device-{uuid4()}",
        created_at=now,
    )
    isolated_test_session.add(watch)
    isolated_test_session.flush()

    class TestProvider:
        def revoke_playback(self, session_id):
            return None

    monkeypatch.setattr("app.services.video_access_service.get_video_playback_provider", lambda: TestProvider())
    result = record_heartbeat(isolated_test_session, child, watch.id)

    assert result.accepted_seconds == 20
    assert result.remaining_seconds == 0
    assert result.status == "completed"
    assert entitlement.consumed_seconds == 20
    assert entitlement.status == "exhausted"