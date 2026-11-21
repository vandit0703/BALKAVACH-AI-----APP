"""The single reward rule for missions.

Product rule (2026-11-21): every mission that is completed and approved earns exactly
``MISSION_STAR_REWARD`` stars and ``MISSION_XP_REWARD`` XP, whatever the mission is (daily catalogue mission,
parent-created mission, surprise mission) and whatever reward value an older row stored.

* Awarded only by ``task_service.review_submission`` when a *pending* submission is approved; that row is
  locked and moved out of ``pending`` in the same transaction, and every ledger row carries an idempotency
  key derived from the submission id, so a retried or repeated approval cannot pay twice.
* Opening, choosing, starting or submitting a mission pays nothing; a rejected submission pays nothing.
* Historical ledger rows are never recalculated: what a child already earned stays as it was recorded.

The stored ``tasks.star_reward`` / ``xp_reward`` and template / snapshot values are kept for history, but
every API that shows "what this mission is worth" shows these constants, so the app displays exactly what the
backend will award.
"""

MISSION_STAR_REWARD = 10
MISSION_XP_REWARD = 15


def effective_star_reward(_stored: int | None = None) -> int:
	"""The stars an approval of this mission earns now (the stored value is history only)."""
	return MISSION_STAR_REWARD


def effective_xp_reward(_stored: int | None = None) -> int:
	"""The XP an approval of this mission earns now (the stored value is history only)."""
	return MISSION_XP_REWARD
