from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.reward import RewardCreate, RedemptionReview
from app.services.ledger_service import star_balance
from app.utils import utc_naive


def _family_membership(session: Session, family_id: UUID, user_id: UUID) -> None:
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == user_id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Family resource not found")


def create_reward(session: Session, parent, request: RewardCreate):
	_family_membership(session, request.family_id, parent.id)
	if request.reward_type == "video_time":
		if bool(request.video_id) == bool(request.video_collection_id) or not request.access_duration_seconds:
			raise APIError(422, "invalid_video_reward", "Video-time rewards require one video or collection and a duration")
		if request.video_id:
			Video = get_model("Video")
			valid_target = session.query(Video.id).filter(
				Video.id == request.video_id,
				Video.is_published.is_(True),
			).first()
		else:
			VideoCollection = get_model("VideoCollection")
			valid_target = session.query(VideoCollection.id).filter(
				VideoCollection.id == request.video_collection_id,
				VideoCollection.is_published.is_(True),
			).first()
		if not valid_target:
			raise HTTPException(status_code=404, detail="Published video target not found")
	elif (
		request.video_id
		or request.video_collection_id
		or request.access_duration_seconds
		or request.access_validity_seconds
	):
		raise APIError(422, "invalid_reward_target", "Only video-time rewards may grant video access")

	Reward = get_model("Reward")
	reward = Reward(
		family_id=request.family_id,
		created_by=parent.id,
		name=request.name.strip(),
		description=request.description,
		reward_type=request.reward_type,
		star_cost=request.star_cost,
		image_url=str(request.image_url) if request.image_url else None,
		video_id=request.video_id,
		video_collection_id=request.video_collection_id,
		access_duration_seconds=request.access_duration_seconds,
		access_validity_seconds=request.access_validity_seconds,
		max_uses=request.max_uses,
		is_active=True,
	)
	session.add(reward)
	session.commit()
	session.refresh(reward)
	return reward


def request_redemption(session: Session, child, reward_id: UUID, idempotency_key: str):
	ChildProfile = get_model("ChildProfile")
	locked_child = session.query(ChildProfile).filter(
		ChildProfile.id == child.id,
		ChildProfile.is_active.is_(True),
	).with_for_update().one_or_none()
	if locked_child is None:
		raise HTTPException(status_code=404, detail="Child profile not found")

	RedemptionRequest = get_model("RedemptionRequest")
	existing = session.query(RedemptionRequest).filter(
		RedemptionRequest.idempotency_key == idempotency_key
	).one_or_none()
	if existing:
		if existing.child_id != child.id or existing.reward_id != reward_id:
			raise APIError(409, "idempotency_key_conflict", "Idempotency key was already used for another request")
		return existing

	Reward = get_model("Reward")
	reward = session.query(Reward).filter(
		Reward.id == reward_id,
		Reward.family_id == child.family_id,
		Reward.is_active.is_(True),
	).with_for_update().one_or_none()
	if reward is None:
		raise HTTPException(status_code=404, detail="Reward not found")
	if reward.max_uses is not None:
		used = session.query(func.count(RedemptionRequest.id)).filter(
			RedemptionRequest.reward_id == reward.id,
			RedemptionRequest.status.in_(["approved", "fulfilled"]),
		).scalar()
		if used >= reward.max_uses:
			raise APIError(409, "reward_unavailable", "This reward is no longer available")
	balance = star_balance(session, child.id)
	if balance < reward.star_cost:
		raise APIError(409, "insufficient_stars", "There are not enough stars for this reward")

	redemption = RedemptionRequest(
		reward_id=reward.id,
		child_id=child.id,
		star_cost_at_request=reward.star_cost,
		status="pending",
		idempotency_key=idempotency_key,
		requested_at=utc_naive(datetime.now(timezone.utc)),
	)
	session.add(redemption)
	try:
		session.commit()
		session.refresh(redemption)
	except IntegrityError:
		session.rollback()
		existing = session.query(RedemptionRequest).filter(RedemptionRequest.idempotency_key == idempotency_key).one_or_none()
		if existing:
			if existing.child_id == child.id and existing.reward_id == reward_id:
				return existing
			raise APIError(409, "idempotency_key_conflict", "Idempotency key was already used for another request")
		raise APIError(409, "redemption_conflict", "Unable to create the redemption request")
	return redemption


def review_redemption(session: Session, redemption_id: UUID, parent, request: RedemptionReview, approve: bool):
	RedemptionRequest = get_model("RedemptionRequest")
	redemption = session.query(RedemptionRequest).filter(
		RedemptionRequest.id == redemption_id
	).with_for_update().one_or_none()
	if redemption is None:
		raise HTTPException(status_code=404, detail="Redemption not found")
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(ChildProfile.id == redemption.child_id).with_for_update().one()
	_family_membership(session, child.family_id, parent.id)
	if redemption.status != "pending":
		raise APIError(409, "redemption_already_reviewed", "This redemption has already been reviewed")

	now = utc_naive(datetime.now(timezone.utc))
	redemption.reviewed_by = parent.id
	redemption.reviewed_at = now
	redemption.review_note = request.review_note
	if not approve:
		redemption.status = "rejected"
		_notify(session, child.user_id, "reward_rejected", "Reward request declined", request.review_note or "Your reward request was declined.", redemption.id, now)
	else:
		Reward = get_model("Reward")
		reward = session.query(Reward).filter(Reward.id == redemption.reward_id).with_for_update().one()
		if not reward.is_active:
			raise APIError(409, "reward_unavailable", "This reward is no longer available")
		if reward.max_uses is not None:
			used = session.query(func.count(RedemptionRequest.id)).filter(
				RedemptionRequest.reward_id == reward.id,
				RedemptionRequest.status.in_(["approved", "fulfilled"]),
			).scalar()
			if used >= reward.max_uses:
				raise APIError(409, "reward_unavailable", "This reward is no longer available")
		if star_balance(session, child.id) < redemption.star_cost_at_request:
			raise APIError(409, "insufficient_stars", "The child no longer has enough stars")
		StarTransaction = get_model("StarTransaction")
		session.add(
			StarTransaction(
				child_id=child.id,
				amount=-redemption.star_cost_at_request,
				transaction_type="reward_redemption",
				redemption_id=redemption.id,
				idempotency_key=f"redemption:{redemption.id}:debit",
				description=f"Redeemed {reward.name}",
				created_at=now,
			)
		)
		redemption.status = "approved"
		_notify(session, child.user_id, "reward_approved", "Reward request approved", "Your stars were deducted for this reward.", redemption.id, now)
	session.commit()
	session.refresh(redemption)
	return redemption


def fulfill_redemption(session: Session, redemption_id: UUID, parent):
	RedemptionRequest = get_model("RedemptionRequest")
	redemption = session.query(RedemptionRequest).filter(
		RedemptionRequest.id == redemption_id
	).with_for_update().one_or_none()
	if redemption is None:
		raise HTTPException(status_code=404, detail="Redemption not found")
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(ChildProfile.id == redemption.child_id).with_for_update().one()
	_family_membership(session, child.family_id, parent.id)
	if redemption.status != "approved":
		raise APIError(409, "redemption_not_approved", "Only an approved redemption can be fulfilled")
	Reward = get_model("Reward")
	reward = session.query(Reward).filter(Reward.id == redemption.reward_id).one()
	now = utc_naive(datetime.now(timezone.utc))
	if reward.reward_type == "video_time":
		if reward.video_id:
			Video = get_model("Video")
			target = session.query(Video.id).filter(Video.id == reward.video_id, Video.is_published.is_(True)).first()
			if not target:
				raise APIError(409, "video_unavailable", "The reward video is no longer published")
		else:
			VideoCollection = get_model("VideoCollection")
			target = session.query(VideoCollection.id).filter(
				VideoCollection.id == reward.video_collection_id,
				VideoCollection.is_published.is_(True),
			).first()
			if not target:
				raise APIError(409, "video_unavailable", "The reward collection is no longer published")
		VideoAccessEntitlement = get_model("VideoAccessEntitlement")
		expires_at = (
			now + timedelta(seconds=reward.access_validity_seconds)
			if reward.access_validity_seconds
			else None
		)
		session.add(
			VideoAccessEntitlement(
				child_id=child.id,
				redemption_id=redemption.id,
				video_id=reward.video_id,
				video_collection_id=reward.video_collection_id,
				granted_seconds=reward.access_duration_seconds,
				consumed_seconds=0,
				granted_at=now,
				valid_from=now,
				expires_at=expires_at,
				status="active",
			)
		)
	redemption.status = "fulfilled"
	redemption.fulfilled_at = now
	_notify(session, child.user_id, "reward_fulfilled", "Reward ready", "Your reward is ready to use.", redemption.id, now)
	session.commit()
	session.refresh(redemption)
	return redemption


def cancel_redemption(session: Session, redemption_id: UUID, actor, parent_action: bool):
	RedemptionRequest = get_model("RedemptionRequest")
	redemption = session.query(RedemptionRequest).filter(
		RedemptionRequest.id == redemption_id
	).with_for_update().one_or_none()
	if redemption is None:
		raise HTTPException(status_code=404, detail="Redemption not found")
	ChildProfile = get_model("ChildProfile")
	child = session.query(ChildProfile).filter(ChildProfile.id == redemption.child_id).with_for_update().one()
	if parent_action:
		_family_membership(session, child.family_id, actor.id)
	elif child.user_id != actor.user_id:
		raise HTTPException(status_code=404, detail="Redemption not found")

	if redemption.status == "pending":
		redemption.status = "cancelled"
	elif redemption.status == "approved" and parent_action:
		StarTransaction = get_model("StarTransaction")
		session.add(
			StarTransaction(
				child_id=child.id,
				amount=redemption.star_cost_at_request,
				transaction_type="refund",
				redemption_id=redemption.id,
				idempotency_key=f"redemption:{redemption.id}:refund",
				description="Refund for cancelled reward",
				created_at=utc_naive(datetime.now(timezone.utc)),
			)
		)
		redemption.status = "cancelled"
	else:
		raise APIError(409, "redemption_not_cancellable", "This redemption can no longer be cancelled")
	session.commit()
	session.refresh(redemption)
	return redemption


def _notify(session: Session, recipient_id, notification_type: str, title: str, message: str, redemption_id, now) -> None:
	Notification = get_model("Notification")
	session.add(
		Notification(
			recipient_user_id=recipient_id,
			notification_type=notification_type,
			title=title,
			message=message,
			related_redemption_id=redemption_id,
			is_read=False,
			created_at=now,
		)
	)
