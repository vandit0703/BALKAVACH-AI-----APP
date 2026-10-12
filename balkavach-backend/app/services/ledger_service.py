from sqlalchemy import func
from sqlalchemy.orm import Session

from app.db.base import get_model


def star_balance(session: Session, child_id) -> int:
	StarTransaction = get_model("StarTransaction")
	balance = session.query(func.coalesce(func.sum(StarTransaction.amount), 0)).filter(
		StarTransaction.child_id == child_id
	).scalar()
	return int(balance or 0)


def xp_total(session: Session, child_id) -> int:
	XPTransaction = get_model("XPTransaction")
	total = session.query(func.coalesce(func.sum(XPTransaction.amount), 0)).filter(
		XPTransaction.child_id == child_id
	).scalar()
	return int(total or 0)
