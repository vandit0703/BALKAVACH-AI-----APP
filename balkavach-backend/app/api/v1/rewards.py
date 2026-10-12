from uuid import UUID

from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.core.dependencies import require_child, require_parent
from app.db.base import get_model
from app.db.session import get_db
from app.schemas.reward import RedemptionCreate, RedemptionPublic, RedemptionReview, RewardCreate, RewardPublic
from app.services.reward_service import (
	cancel_redemption,
	create_reward,
	fulfill_redemption,
	request_redemption,
	review_redemption,
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
	family_id: UUID,
	limit: int = Query(default=50, ge=1, le=100),
	offset: int = Query(default=0, ge=0),
	parent=Depends(require_parent),
	session: Session = Depends(get_db),
) -> list[RewardPublic]:
	FamilyMember = get_model("FamilyMember")
	if not session.query(FamilyMember.id).filter(
		FamilyMember.family_id == family_id,
		FamilyMember.user_id == parent.id,
		FamilyMember.is_active.is_(True),
	).first():
		raise HTTPException(status_code=404, detail="Family not found")
	Reward = get_model("Reward")
	rewards = session.query(Reward).filter(
		Reward.family_id == family_id,
		Reward.is_active.is_(True),
	).order_by(Reward.created_at.desc()).offset(offset).limit(limit).all()
	return [RewardPublic.model_validate(reward) for reward in rewards]


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
