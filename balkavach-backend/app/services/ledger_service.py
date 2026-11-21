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


def awarded_by_submission(session: Session, submission_ids) -> dict:
	"""Stars and XP each submission actually earned, summed from the ledgers: ``{submission_id: (stars, xp)}``.

	What was recorded is what is shown (history is never recalculated). Submissions that earned nothing are
	absent; spends and refunds are not linked to submissions, so only positive rows count."""
	ids = list(submission_ids)
	if not ids:
		return {}
	StarTransaction = get_model("StarTransaction")
	XPTransaction = get_model("XPTransaction")
	totals: dict = {}
	for submission_id, amount in (
		session.query(StarTransaction.submission_id, func.coalesce(func.sum(StarTransaction.amount), 0))
		.filter(StarTransaction.submission_id.in_(ids), StarTransaction.amount > 0)
		.group_by(StarTransaction.submission_id)
		.all()
	):
		totals[submission_id] = (int(amount), 0)
	for submission_id, amount in (
		session.query(XPTransaction.submission_id, func.coalesce(func.sum(XPTransaction.amount), 0))
		.filter(XPTransaction.submission_id.in_(ids), XPTransaction.amount > 0)
		.group_by(XPTransaction.submission_id)
		.all()
	):
		totals[submission_id] = (totals.get(submission_id, (0, 0))[0], int(amount))
	return totals
