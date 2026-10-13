from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user, require_child, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.reward import (
	RedemptionCreate,
	RedemptionDetailPublic,
	RedemptionPublic,
	RedemptionReview,
	RewardCreate,
	RewardPublic,
	RewardUpdate,
)
from app.services.reward_service import (
	cancel_redemption,
	create_reward,
	fulfill_redemption,
	request_redemption,
	review_redemption,
	update_reward,
)

router = APIRouter(tags=["rewards"])


@router.post("/rewards", response_model=RewardPublic, status_code=status.HTTP_201_CREATED)
def add_reward(
	request: RewardCreate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RewardPublic:
	return RewardPublic.model_validate(create_reward(session, parent, request))


@router.get("/rewards", response_model=list[RewardPublic])
def list_rewards(
	family_id: UUID | None = None,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	user=Depends(get_current_user),
	session: Session = Depends(get_db),
) -> list[RewardPublic]:
	"""Parents list a family catalog (family_id required); a child sees its own family catalog."""
	if user.role == "child":
		ChildProfile = get_model("ChildProfile")
		child = session.query(ChildProfile).filter(
			ChildProfile.user_id == user.id, ChildProfile.is_active.is_(True)
		).one_or_none()
		if child is None or (family_id is not None and family_id != child.family_id):
			raise HTTPException(status_code=404, detail="Family not found")
		family_id = child.family_id
	elif user.role == "parent":
		if family_id is None:
			raise HTTPException(status_code=422, detail="family_id is required")
		FamilyMember = get_model("FamilyMember")
		if not session.query(FamilyMember.id).filter(
			FamilyMember.family_id == family_id,
			FamilyMember.user_id == user.id,
			FamilyMember.is_active.is_(True),
		).first():
			raise HTTPException(status_code=404, detail="Family not found")
	else:
		raise HTTPException(status_code=403, detail="Reward access denied")
	Reward = get_model("Reward")
	rewards = session.query(Reward).filter(
		Reward.family_id == family_id,
		Reward.is_active.is_(True),
	).order_by(Reward.created_at.desc(), Reward.id).offset(offset).limit(limit).all()
	return [RewardPublic.model_validate(reward) for reward in rewards]


@router.patch("/rewards/{reward_id}", response_model=RewardPublic)
def edit_reward(
	reward_id: UUID,
	request: RewardUpdate,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RewardPublic:
	return RewardPublic.model_validate(update_reward(session, parent, reward_id, request))


@router.delete("/rewards/{reward_id}", status_code=status.HTTP_204_NO_CONTENT)
def deactivate_reward(
	reward_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> None:
	update_reward(session, parent, reward_id, RewardUpdate(is_active=False))


@router.get("/redemptions", response_model=list[RedemptionDetailPublic])
def list_family_redemptions(
	family_id: UUID,
	status_filter: Literal["pending", "approved", "rejected", "fulfilled", "cancelled"] | None = Query(
		default=None, alias="status"
	),
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[RedemptionDetailPublic]:
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Family not found")
	RedemptionRequest = get_model("RedemptionRequest")
	Reward = get_model("Reward")
	ChildProfile = get_model("ChildProfile")
	query = (
		session.query(RedemptionRequest, Reward.name, ChildProfile.display_name)
		.join(Reward, Reward.id == RedemptionRequest.reward_id)
		.join(ChildProfile, ChildProfile.id == RedemptionRequest.child_id)
		.filter(ChildProfile.family_id == family_id)
	)
	if status_filter:
		query = query.filter(RedemptionRequest.status == status_filter)
	rows = query.order_by(RedemptionRequest.requested_at.desc(), RedemptionRequest.id).offset(offset).limit(limit).all()
	return [
		RedemptionDetailPublic(
			**RedemptionPublic.model_validate(redemption).model_dump(),
			family_id=family_id,
			reward_name=reward_name,
			child_name=child_name,
		)
		for redemption, reward_name, child_name in rows
	]


@router.post("/redemptions", response_model=RedemptionPublic, status_code=status.HTTP_201_CREATED)
def redeem_reward(
	request: RedemptionCreate,
	idempotency_key: str = Header(alias="Idempotency-Key", min_length=8, max_length=180),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	redemption = request_redemption(session, child, request.reward_id, idempotency_key)
	return RedemptionPublic.model_validate(redemption)


@router.get("/redemptions/mine", response_model=list[RedemptionPublic])
def my_redemptions(
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> list[RedemptionPublic]:
	RedemptionRequest = get_model("RedemptionRequest")
	requests = session.query(RedemptionRequest).filter(
		RedemptionRequest.child_id == child.id
	).order_by(RedemptionRequest.requested_at.desc()).offset(offset).limit(limit).all()
	return [RedemptionPublic.model_validate(item) for item in requests]


@router.post("/redemptions/{redemption_id}/approve", response_model=RedemptionPublic)
def approve_redemption(
	redemption_id: UUID,
	request: RedemptionReview,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	return RedemptionPublic.model_validate(review_redemption(session, redemption_id, parent, request, True))


@router.post("/redemptions/{redemption_id}/reject", response_model=RedemptionPublic)
def reject_redemption(
	redemption_id: UUID,
	request: RedemptionReview,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	return RedemptionPublic.model_validate(review_redemption(session, redemption_id, parent, request, False))


@router.post("/redemptions/{redemption_id}/fulfill", response_model=RedemptionPublic)
def fulfill_reward(
	redemption_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	return RedemptionPublic.model_validate(fulfill_redemption(session, redemption_id, parent))


@router.post("/redemptions/{redemption_id}/cancel", response_model=RedemptionPublic)
def cancel_reward(
	redemption_id: UUID,
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	return RedemptionPublic.model_validate(cancel_redemption(session, redemption_id, parent, True))


@router.post("/redemptions/{redemption_id}/cancel/mine", response_model=RedemptionPublic)
def child_cancel_reward(
	redemption_id: UUID,
	child=Depends(require_child),
	session: Session = Depends(get_db),
) -> RedemptionPublic:
	return RedemptionPublic.model_validate(cancel_redemption(session, redemption_id, child, False))
