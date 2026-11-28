"""Phase 5 on REAL PostgreSQL: three completable daily missions, parent-configured custom mission video time,
and once-per-family-local-day video awards for repeating custom missions (including concurrent approvals).

Needs ``TEST_DATABASE_URL`` (a disposable database whose name contains "test", migrated to
``0026_custom_mission_video_reward``) and ``REDIS_URL``; otherwise every test skips (see ``tests/conftest.py``).
The schema under the migrations is ``tests/schema/reconstructed_baseline.sql`` locally, so this proves the logic and
the constraints added by 0026 on PostgreSQL, not production's own constraints.
"""

from __future__ import annotations

import threading
import time
from datetime import date, datetime, timedelta, timezone
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker

from app.core.exceptions import APIError
from app.db.base import get_model
from app.schemas.task import TaskReviewCreate
from app.services import video_entitlement_service as entitlements
from app.services.mission_catalogue_service import apply_catalogue
from app.services.mission_rewards import MISSION_STAR_REWARD, MISSION_XP_REWARD
from app.services.task_service import review_submission
from app.services.video_entitlement_service import (
	DEFAULT_DAILY_ALLOWANCE_SECONDS,
	FREE_DAILY_ALLOWANCE_SECONDS,
	MISSION_REWARD_ALLOWANCE_SECONDS,
	get_child_video_allowance_today,
)
from app.utils import utc_naive

pytestmark = pytest.mark.usefixtures("standin_submit")

# Any non-null repeat_rule makes a mission repeating; the API stores it as a JSON object (migration 0028).
REPEAT_RULE = {"frequency": "daily"}


# ---- helpers ---------------------------------------------------------------------------------------------------------


def _ledger(session, child_id) -> dict:
	row = session.execute(
		text(
			"""
			select
				(select coalesce(sum(amount), 0) from star_transactions where child_id = :c) as stars,
				(select coalesce(sum(amount), 0) from xp_transactions where child_id = :c) as xp,
				(select count(*) from video_access_entitlements where child_id = :c and source_type = 'mission_reward') as grants,
				(select coalesce(sum(granted_seconds), 0) from video_access_entitlements
					where child_id = :c and source_type = 'mission_reward') as seconds
			"""
		),
		{"c": UUID(str(child_id))},
	).one()
	return dict(row._mapping)


def _set_family(session, family_id, *, tz: str | None = None, cap: int | None = None) -> None:
	FamilySetting = get_model("FamilySetting")
	row = session.query(FamilySetting).filter(FamilySetting.family_id == UUID(str(family_id))).one_or_none()
	if row is None:
		row = FamilySetting(family_id=UUID(str(family_id)), mission_settings={}, video_settings={})
		session.add(row)
	if tz is not None:
		row.mission_settings = {**(row.mission_settings or {}), "timezone": tz}
	if cap is not None:
		row.video_settings = {**(row.video_settings or {}), "daily_limit_seconds": cap}
	session.commit()


def _set_submitted_at(session, submission_id, moment: datetime) -> None:
	session.execute(
		text("update task_submissions set submitted_at = :t where id = :s"),
		{"t": utc_naive(moment), "s": UUID(str(submission_id))},
	)
	session.commit()


def _custom(api, ctx, *, repeating: bool = False, **fields) -> dict:
	if repeating:
		fields["repeat_rule"] = REPEAT_RULE  # through the real create route
	return api.create_task(
		ctx["parent"]["token"], ctx["family"]["id"], assigned_child_id=ctx["child"]["id"], **fields
	)


def _approve(api, ctx, submission_id):
	response = api.review(ctx["parent"]["token"], submission_id, "approved")
	assert response.status_code == 200, response.text
	return response.json()


def _submit(api, ctx, task_id) -> str:
	response = api.submit(ctx["child"]["token"], task_id)
	assert response.status_code == 201, response.text
	return response.json()["id"]


def _years_ago(years: int) -> str:
	birthday = date.today() - timedelta(days=60)
	return birthday.replace(year=birthday.year - years).isoformat()


def _daily_ready(api):
	apply_catalogue(api.session, publish=True)
	api.session.commit()
	ctx = api.family_with_child()
	response = api.patch(
		f"/families/{ctx['family']['id']}/children/{ctx['child']['id']}",
		ctx["parent"]["token"],
		{"date_of_birth": _years_ago(8)},
	)
	assert response.status_code == 200, response.text
	return ctx


# ---- A/B: three offered daily missions, custom missions separate --------------------------------------------------------


def test_all_three_offered_daily_missions_can_be_selected_submitted_and_approved(api):
	ctx = _daily_ready(api)
	kid = ctx["child"]["token"]
	choices = api.get("/daily-missions/today", kid).json()["choices"]
	assert len(choices) == 3
	for choice in choices:
		picked = api.post(f"/daily-missions/{choice['id']}/select", kid)
		assert picked.status_code == 200, picked.text
		assert picked.json()["status"] == "selected" and picked.json()["task_id"]
		submitted = api.post(f"/daily-missions/{choice['id']}/submit", kid, {"proof_type": "note", "proof_note": "done"})
		assert submitted.status_code == 200, submitted.text
	pending = api.get(f"/reviews/pending?family_id={ctx['family']['id']}", ctx["parent"]["token"]).json()
	assert len(pending) == 3
	for item in pending:
		assert item["video_seconds_reward"] == MISSION_REWARD_ALLOWANCE_SECONDS
		result = _approve(api, ctx, item["id"])
		assert result["video_seconds_granted"] == MISSION_REWARD_ALLOWANCE_SECONDS
	today = api.get("/daily-missions/today", kid).json()
	assert sorted(c["status"] for c in today["choices"]) == ["approved"] * 3
	assert _ledger(api.session, ctx["child"]["id"]) == {
		"stars": 3 * MISSION_STAR_REWARD,
		"xp": 3 * MISSION_XP_REWARD,
		"grants": 3,
		"seconds": 3 * MISSION_REWARD_ALLOWANCE_SECONDS,
	}


def test_completing_one_offered_mission_does_not_use_up_another_slot(api):
	ctx = _daily_ready(api)
	kid = ctx["child"]["token"]
	first, second, third = api.get("/daily-missions/today", kid).json()["choices"]
	api.post(f"/daily-missions/{first['id']}/select", kid)
	api.post(f"/daily-missions/{first['id']}/submit", kid, {"proof_type": "none"})
	sid = api.get(f"/reviews/pending?family_id={ctx['family']['id']}", ctx["parent"]["token"]).json()[0]["id"]
	_approve(api, ctx, sid)
	# The other two are still offered (not muted, not replaced) and can each be chosen.
	statuses = {c["id"]: c["status"] for c in api.get("/daily-missions/today", kid).json()["choices"]}
	assert statuses == {first["id"]: "approved", second["id"]: "available", third["id"]: "available"}
	assert api.post(f"/daily-missions/{second['id']}/select", kid).status_code == 200
	assert api.post(f"/daily-missions/{third['id']}/select", kid).status_code == 200


def test_selecting_the_same_choice_twice_creates_one_task(api):
	ctx = _daily_ready(api)
	kid = ctx["child"]["token"]
	choice = api.get("/daily-missions/today", kid).json()["choices"][0]
	one = api.post(f"/daily-missions/{choice['id']}/select", kid).json()
	two = api.post(f"/daily-missions/{choice['id']}/select", kid).json()
	assert one["task_id"] == two["task_id"]


def test_custom_missions_do_not_consume_offered_daily_slots(api):
	ctx = _daily_ready(api)
	kid = ctx["child"]["token"]
	for title in ("Tidy desk", "Water plants"):
		task = _custom(api, ctx, title=title)
		_approve(api, ctx, _submit(api, ctx, task["id"]))
	today = api.get("/daily-missions/today", kid).json()
	assert [c["status"] for c in today["choices"]] == ["available"] * 3
	for choice in today["choices"]:
		assert api.post(f"/daily-missions/{choice['id']}/select", kid).status_code == 200


# ---- C: parent-configured custom mission duration -----------------------------------------------------------------------


def test_parent_configures_and_edits_custom_video_time_and_it_is_stored(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Read 20 pages", reward_video_seconds=1200)
	assert task["reward_video_seconds"] == 1200 and task["is_custom"] is True
	Task = get_model("Task")
	assert api.session.get(Task, UUID(task["id"])).reward_video_seconds == 1200
	edited = api.patch(f"/tasks/{task['id']}", ctx["parent"]["token"], {"reward_video_seconds": 600})
	assert edited.status_code == 200, edited.text
	api.session.expire_all()
	assert api.session.get(Task, UUID(task["id"])).reward_video_seconds == 600
	listed = api.get(f"/tasks?family_id={ctx['family']['id']}", ctx["parent"]["token"]).json()
	assert [t["reward_video_seconds"] for t in listed if t["id"] == task["id"]] == [600]
	# An edit that does not mention it keeps it.
	assert api.patch(f"/tasks/{task['id']}", ctx["parent"]["token"], {"title": "Read 25 pages"}).status_code == 200
	api.session.expire_all()
	assert api.session.get(Task, UUID(task["id"])).reward_video_seconds == 600


def test_a_custom_mission_created_without_a_duration_stores_the_standard_amount(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Old app version")
	assert task["reward_video_seconds"] == MISSION_REWARD_ALLOWANCE_SECONDS


@pytest.mark.parametrize("bad", [-1, 14401, 10**9, "600", 600.5, True, None, [600], {"s": 600}])
def test_invalid_durations_are_rejected_on_create_and_edit(api, bad):
	ctx = api.family_with_child()
	created = api.post(
		"/tasks",
		ctx["parent"]["token"],
		{"family_id": ctx["family"]["id"], "title": "Bad duration", "reward_video_seconds": bad},
	)
	assert created.status_code == 422, created.text
	task = _custom(api, ctx, title="Good", reward_video_seconds=300)
	edited = api.patch(f"/tasks/{task['id']}", ctx["parent"]["token"], {"reward_video_seconds": bad})
	assert edited.status_code == 422, edited.text
	api.session.expire_all()
	assert api.session.get(get_model("Task"), UUID(task["id"])).reward_video_seconds == 300


def test_the_database_rejects_an_out_of_range_duration(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Direct write")
	with pytest.raises(IntegrityError):
		with api.session.begin_nested():
			api.session.execute(
				text("update tasks set reward_video_seconds = 99999 where id = :t"), {"t": UUID(task["id"])}
			)


def test_a_daily_mission_task_cannot_be_given_a_custom_duration(api):
	ctx = _daily_ready(api)
	choice = api.get("/daily-missions/today", ctx["child"]["token"]).json()["choices"][0]
	task_id = api.post(f"/daily-missions/{choice['id']}/select", ctx["child"]["token"]).json()["task_id"]
	response = api.patch(f"/tasks/{task_id}", ctx["parent"]["token"], {"reward_video_seconds": 3600})
	assert response.status_code == 409 and response.json()["error"]["code"] == "video_reward_not_configurable"


def test_a_child_cannot_set_or_override_the_duration(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Practice piano", reward_video_seconds=300)
	# Children cannot create or edit missions.
	assert api.post(
		"/tasks", ctx["child"]["token"], {"family_id": ctx["family"]["id"], "title": "Mine", "reward_video_seconds": 14400}
	).status_code == 403
	assert api.patch(f"/tasks/{task['id']}", ctx["child"]["token"], {"reward_video_seconds": 14400}).status_code == 403
	# A duration sent with the completion is ignored; the stored value is what approval grants.
	response = api.post(
		f"/tasks/{task['id']}/submissions",
		ctx["child"]["token"],
		{"proof_type": "none", "reward_video_seconds": 14400, "granted_seconds": 14400},
	)
	assert response.status_code == 201, response.text
	result = _approve(api, ctx, response.json()["id"])
	assert result["video_seconds_granted"] == 300
	assert _ledger(api.session, ctx["child"]["id"])["seconds"] == 300


def test_parent_approval_grants_the_stored_duration_to_the_right_child_and_mission(api):
	ctx = api.family_with_child()
	sibling = api.create_child(ctx["parent"]["token"], ctx["family"]["id"], "Sib")
	task = _custom(api, ctx, title="Lego build", reward_video_seconds=1500)
	queue_item = None
	sid = _submit(api, ctx, task["id"])
	for item in api.get(f"/reviews/pending?family_id={ctx['family']['id']}", ctx["parent"]["token"]).json():
		if item["id"] == sid:
			queue_item = item
	assert queue_item["video_seconds_reward"] == 1500 and queue_item["video_minutes_reward"] == 25
	result = _approve(api, ctx, sid)
	assert result["video_seconds_reward"] == 1500 and result["video_seconds_granted"] == 1500
	row = api.session.execute(
		text("select child_id, task_id, granted_seconds from video_access_entitlements where submission_id = :s"),
		{"s": UUID(sid)},
	).one()
	assert (str(row.child_id), str(row.task_id), row.granted_seconds) == (ctx["child"]["id"], task["id"], 1500)
	assert _ledger(api.session, sibling["id"])["grants"] == 0


def test_an_edit_after_submission_is_what_approval_grants(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Edit later", reward_video_seconds=600)
	sid = _submit(api, ctx, task["id"])
	assert api.patch(f"/tasks/{task['id']}", ctx["parent"]["token"], {"reward_video_seconds": 900}).status_code == 200
	assert _approve(api, ctx, sid)["video_seconds_granted"] == 900


def test_a_zero_duration_mission_still_pays_stars_and_xp_but_no_video(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="No video", reward_video_seconds=0)
	result = _approve(api, ctx, _submit(api, ctx, task["id"]))
	assert result["video_seconds_granted"] == 0
	assert _ledger(api.session, ctx["child"]["id"]) == {
		"stars": MISSION_STAR_REWARD, "xp": MISSION_XP_REWARD, "grants": 0, "seconds": 0
	}


def test_a_legacy_custom_row_without_a_duration_grants_the_standard_amount(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Legacy")
	api.session.execute(text("update tasks set reward_video_seconds = null where id = :t"), {"t": UUID(task["id"])})
	api.session.commit()
	assert _approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"] == MISSION_REWARD_ALLOWANCE_SECONDS


# ---- E: cap and the established rules ------------------------------------------------------------------------------------


def test_custom_duration_cannot_bypass_the_daily_cap(api):
	ctx = api.family_with_child()
	_set_family(api.session, ctx["family"]["id"], cap=900)  # the smallest cap a family can set
	big = _custom(api, ctx, title="Huge", reward_video_seconds=14400)
	result = _approve(api, ctx, _submit(api, ctx, big["id"]))
	assert result["video_seconds_reward"] == 14400 and result["video_seconds_granted"] == 900
	# Cap reached: a further custom mission and a standard-amount mission grant nothing more today.
	more = _custom(api, ctx, title="More", reward_video_seconds=60)
	assert _approve(api, ctx, _submit(api, ctx, more["id"]))["video_seconds_granted"] == 0
	assert _ledger(api.session, ctx["child"]["id"])["seconds"] == 900


def test_a_custom_grant_is_reduced_to_the_room_left_under_the_cap(api):
	ctx = api.family_with_child()
	_set_family(api.session, ctx["family"]["id"], cap=1000)
	first = _custom(api, ctx, title="First", reward_video_seconds=700)
	second = _custom(api, ctx, title="Second", reward_video_seconds=700)
	assert _approve(api, ctx, _submit(api, ctx, first["id"]))["video_seconds_granted"] == 700
	assert _approve(api, ctx, _submit(api, ctx, second["id"]))["video_seconds_granted"] == 300


def test_standard_amount_free_allowance_and_default_cap_are_unchanged(api):
	assert MISSION_REWARD_ALLOWANCE_SECONDS == 225
	assert FREE_DAILY_ALLOWANCE_SECONDS == 900
	assert DEFAULT_DAILY_ALLOWANCE_SECONDS == 3600
	ctx = api.family_with_child()
	child = api.session.get(get_model("ChildProfile"), UUID(ctx["child"]["id"]))
	before = get_child_video_allowance_today(api.session, child.id, child.family_id)
	assert before["free_allowance_seconds"] == 900 and before["remaining_seconds"] == 900
	assert before["daily_cap_seconds"] == 900 + 3600
	# Sixteen standard-amount approvals fill the 60-minute mission cap exactly; the seventeenth grants nothing.
	granted = []
	for n in range(17):
		task = _custom(api, ctx, title=f"Std {n}")
		api.session.execute(text("update tasks set reward_video_seconds = null where id = :t"), {"t": UUID(task["id"])})
		api.session.commit()
		granted.append(_approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"])
	assert granted == [225] * 16 + [0]
	after = get_child_video_allowance_today(api.session, child.id, child.family_id)
	assert after["mission_remaining_seconds"] == 3600 and after["remaining_seconds"] == 900 + 3600


# ---- D: repeating custom missions ----------------------------------------------------------------------------------------


def test_a_repeating_mission_grants_video_once_per_local_day_but_stars_and_xp_each_time(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Brush teeth", reward_video_seconds=600, repeating=True)
	granted = [_approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"] for _ in range(3)]
	assert granted == [600, 0, 0]
	assert _ledger(api.session, ctx["child"]["id"]) == {
		"stars": 3 * MISSION_STAR_REWARD,  # star repeat behaviour unchanged: every approval pays
		"xp": 3 * MISSION_XP_REWARD,  # XP repeat behaviour unchanged
		"grants": 1,
		"seconds": 600,
	}


def test_the_same_repeating_mission_on_another_local_day_grants_again(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Daily reading", reward_video_seconds=300, repeating=True)
	yesterday = _submit(api, ctx, task["id"])
	_set_submitted_at(api.session, yesterday, datetime.now(timezone.utc) - timedelta(days=1))
	assert _approve(api, ctx, yesterday)["video_seconds_granted"] == 300
	assert _approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"] == 300
	assert _ledger(api.session, ctx["child"]["id"])["grants"] == 2


def test_different_repeating_missions_have_independent_daily_awards(api):
	ctx = api.family_with_child()
	a = _custom(api, ctx, title="Repeat A", reward_video_seconds=300, repeating=True)
	b = _custom(api, ctx, title="Repeat B", reward_video_seconds=420, repeating=True)
	assert _approve(api, ctx, _submit(api, ctx, a["id"]))["video_seconds_granted"] == 300
	assert _approve(api, ctx, _submit(api, ctx, b["id"]))["video_seconds_granted"] == 420
	assert _approve(api, ctx, _submit(api, ctx, a["id"]))["video_seconds_granted"] == 0


def test_a_shared_repeating_mission_awards_each_child_independently(api):
	ctx = api.family_with_child()
	sibling = api.create_child(ctx["parent"]["token"], ctx["family"]["id"], "Sib")
	task = api.create_task(
		ctx["parent"]["token"], ctx["family"]["id"], title="Everyone", reward_video_seconds=300, repeat_rule=REPEAT_RULE
	)
	assert _approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"] == 300
	sib = api.submit(sibling["token"], task["id"])
	assert sib.status_code == 201, sib.text
	assert _approve(api, ctx, sib.json()["id"])["video_seconds_granted"] == 300


def test_the_family_timezone_decides_the_local_day(api):
	"""Asia/Kolkata is UTC+05:30: 18:00Z and 19:00Z on one UTC date are two different local days there."""
	ctx = api.family_with_child()
	_set_family(api.session, ctx["family"]["id"], tz="Asia/Kolkata")
	task = _custom(api, ctx, title="Evening chore", reward_video_seconds=300, repeating=True)
	base = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=2)
	before_midnight = base.replace(hour=18, minute=0)  # 23:30 local
	after_midnight = base.replace(hour=18, minute=45)  # 00:15 local, the next local day
	same_local_day = base.replace(hour=19, minute=30)  # 01:00 local, same day as after_midnight
	seconds = []
	for moment in (before_midnight, after_midnight, same_local_day):
		sid = _submit(api, ctx, task["id"])
		_set_submitted_at(api.session, sid, moment)
		seconds.append(_approve(api, ctx, sid)["video_seconds_granted"])
	assert seconds == [300, 300, 0]
	days = sorted(
		r[0]
		for r in api.session.execute(
			text("select repeat_reward_local_date from video_access_entitlements where task_id = :t"),
			{"t": UUID(task["id"])},
		)
	)
	assert days == [before_midnight.date(), before_midnight.date() + timedelta(days=1)]


def test_in_utc_the_same_moments_are_one_day(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="UTC chore", reward_video_seconds=300, repeating=True)
	base = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=2)
	seconds = []
	for moment in (base.replace(hour=18), base.replace(hour=18, minute=45)):
		sid = _submit(api, ctx, task["id"])
		_set_submitted_at(api.session, sid, moment)
		seconds.append(_approve(api, ctx, sid)["video_seconds_granted"])
	assert seconds == [300, 0]


def test_the_api_creates_persists_returns_and_runs_a_repeating_mission(api):
	ctx = api.family_with_child()
	created = _custom(api, ctx, title="Feed the cat", reward_video_seconds=300, repeating=True)
	assert created["repeat_rule"] == REPEAT_RULE
	stored = api.session.execute(
		text("select repeat_rule, pg_typeof(repeat_rule)::text from tasks where id = :t"), {"t": UUID(created["id"])}
	).one()
	assert stored[0] == REPEAT_RULE and stored[1] in ("jsonb", "json")
	for token in (ctx["parent"]["token"], ctx["child"]["token"]):
		listed = api.get(f"/tasks?family_id={ctx['family']['id']}", token).json()
		assert [t["repeat_rule"] for t in listed if t["id"] == created["id"]] == [REPEAT_RULE]
	# It runs as a repeating mission: completable again after approval, video once that day.
	assert _approve(api, ctx, _submit(api, ctx, created["id"]))["video_seconds_granted"] == 300
	assert _approve(api, ctx, _submit(api, ctx, created["id"]))["video_seconds_granted"] == 0
	# Editing the rule is persisted too; clearing it makes the mission one-time.
	weekly = {"frequency": "weekly", "days": ["mon", "thu"]}
	edited = api.patch(f"/tasks/{created['id']}", ctx["parent"]["token"], {"repeat_rule": weekly})
	assert edited.status_code == 200 and edited.json()["repeat_rule"] == weekly
	cleared = api.patch(f"/tasks/{created['id']}", ctx["parent"]["token"], {"repeat_rule": None})
	assert cleared.status_code == 200 and cleared.json()["repeat_rule"] is None
	again = api.submit(ctx["child"]["token"], created["id"])
	assert again.status_code == 409 and again.json()["error"]["code"] == "task_already_completed"


def test_an_invalid_repeat_rule_is_rejected(api):
	ctx = api.family_with_child()
	for bad in ("daily", ["daily"], 7, {f"k{i}": i for i in range(31)}):
		response = api.post(
			"/tasks", ctx["parent"]["token"], {"family_id": ctx["family"]["id"], "title": "Bad rule", "repeat_rule": bad}
		)
		assert response.status_code == 422, (bad, response.text)


def test_a_one_time_custom_mission_is_not_subject_to_the_repeat_rule(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="One time", reward_video_seconds=300)
	assert _approve(api, ctx, _submit(api, ctx, task["id"]))["video_seconds_granted"] == 300
	again = api.submit(ctx["child"]["token"], task["id"])
	assert again.status_code == 409 and again.json()["error"]["code"] == "task_already_completed"


def test_the_database_refuses_a_second_award_for_the_same_repeating_mission_day(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="DB rule", reward_video_seconds=300, repeating=True)
	_approve(api, ctx, _submit(api, ctx, task["id"]))
	row = api.session.execute(
		text("select child_id, repeat_reward_local_date from video_access_entitlements where task_id = :t"),
		{"t": UUID(task["id"])},
	).one()
	with pytest.raises(IntegrityError):
		with api.session.begin_nested():
			api.session.execute(
				text(
					"insert into video_access_entitlements (id, child_id, source_type, task_id, granted_seconds, "
					"consumed_seconds, granted_at, valid_from, status, repeat_reward_local_date) values "
					"(gen_random_uuid(), :c, 'mission_reward', :t, 300, 0, now(), now(), 'active', :d)"
				),
				{"c": row.child_id, "t": UUID(task["id"]), "d": row.repeat_reward_local_date},
			)


# ---- 20: nothing unapproved grants video time ----------------------------------------------------------------------------


@pytest.mark.parametrize("decision", ["rejected", "resubmission_requested"])
def test_declined_or_retry_custom_missions_grant_no_video_time(api, decision):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Declined", reward_video_seconds=1800, repeating=True)
	sid = _submit(api, ctx, task["id"])
	response = api.review(ctx["parent"]["token"], sid, decision)
	assert response.status_code == 200 and response.json()["video_seconds_granted"] == 0
	assert _ledger(api.session, ctx["child"]["id"]) == {"stars": 0, "xp": 0, "grants": 0, "seconds": 0}


def test_a_pending_or_deactivated_mission_grants_nothing(api):
	ctx = api.family_with_child()
	task = _custom(api, ctx, title="Pending", reward_video_seconds=1800)
	_submit(api, ctx, task["id"])
	assert _ledger(api.session, ctx["child"]["id"])["grants"] == 0
	gone = _custom(api, ctx, title="Removed", reward_video_seconds=1800)
	assert api.delete(f"/tasks/{gone['id']}", ctx["parent"]["token"]).status_code in (200, 204)
	assert api.submit(ctx["child"]["token"], gone["id"]).status_code == 404
	assert _ledger(api.session, ctx["child"]["id"])["grants"] == 0


def test_another_family_cannot_approve_and_nothing_is_granted(api):
	ctx = api.family_with_child()
	other = api.family_with_child("Other")
	task = _custom(api, ctx, title="Mine", reward_video_seconds=1800)
	sid = _submit(api, ctx, task["id"])
	assert api.review(other["parent"]["token"], sid, "approved").status_code == 404
	assert _ledger(api.session, ctx["child"]["id"])["grants"] == 0


# ---- 12: concurrency on committed rows -------------------------------------------------------------------------------------


@pytest.fixture
def repeating_world(isolated_test_engine):
	"""Committed family + repeating custom mission with ``n`` pending submissions on one local day (rows the API would
	not let a child create at once, to put several approvals of one mission-day in flight); cleaned up afterwards."""
	factory = sessionmaker(bind=isolated_test_engine, expire_on_commit=False)
	created: list[tuple[UUID, list[UUID]]] = []

	def make(n: int, *, reward: int = 600):
		tag = uuid4().hex
		User, Family, Member = get_model("User"), get_model("Family"), get_model("FamilyMember")
		Child, Task, Submission = get_model("ChildProfile"), get_model("Task"), get_model("TaskSubmission")
		with factory() as s:
			parent = User(full_name="Parent", email=f"p-{tag}@example.test", password_hash="x", role="parent", preferred_language="en", is_active=True)
			kid = User(full_name="Kid", username=f"k{tag[:20]}", password_hash="x", role="child", preferred_language="en", is_active=True)
			s.add_all([parent, kid])
			s.flush()
			family = Family(family_name="F", created_by=parent.id)
			s.add(family)
			s.flush()
			s.add(Member(family_id=family.id, user_id=parent.id, relationship="parent", is_primary_parent=True, is_active=True))
			child = Child(user_id=kid.id, family_id=family.id, display_name="Kid", date_of_birth=date(2017, 5, 1), is_active=True)
			s.add(child)
			s.flush()
			task = Task(
				family_id=family.id, created_by=parent.id, assigned_child_id=child.id, title="Race", description="d",
				star_reward=MISSION_STAR_REWARD, xp_reward=MISSION_XP_REWARD, is_custom=True, is_active=True,
				reward_video_seconds=reward, repeat_rule=REPEAT_RULE,
			)
			s.add(task)
			s.flush()
			now = utc_naive(datetime.now(timezone.utc))
			subs = []
			for i in range(n):
				sub = Submission(task_id=task.id, child_id=child.id, submission_number=i + 1, proof_type="none", status="pending", submitted_at=now)
				s.add(sub)
				subs.append(sub)
			s.commit()
			ids = {"parent": parent.id, "child": child.id, "task": task.id, "subs": [x.id for x in subs]}
		created.append((family.id, [parent.id, kid.id]))
		return ids

	yield factory, make

	with isolated_test_engine.begin() as connection:
		for family_id, user_ids in created:
			for statement in (
				"delete from notifications where recipient_user_id = any(:u)",
				"delete from families where id = :f",
				"delete from users where id = any(:u)",
			):
				try:
					with connection.begin_nested():
						connection.execute(text(statement), {"f": family_id, "u": user_ids})
				except Exception:  # noqa: BLE001 - cleanup of a disposable database
					pass


def _race_approvals(factory, parent_id, submission_ids, *, hold_seconds=0.6):
	User = get_model("User")
	barrier = threading.Barrier(len(submission_ids))
	results: list = [None] * len(submission_ids)
	real_grant = entitlements.grant_mission_video_entitlement
	started = threading.Event()

	def slow_grant(*args, **kwargs):
		if not started.is_set():
			started.set()
			time.sleep(hold_seconds)
		return real_grant(*args, **kwargs)

	def work(index, sid):
		with factory() as session:
			parent = session.get(User, parent_id)
			barrier.wait()
			try:
				results[index] = ("ok", review_submission(session, sid, parent, TaskReviewCreate(decision="approved")).status)
			except APIError as error:
				results[index] = ("api_error", error.status_code, error.code)
			except Exception as error:  # noqa: BLE001
				results[index] = ("exception", type(error).__name__)

	entitlements.grant_mission_video_entitlement = slow_grant
	try:
		threads = [threading.Thread(target=work, args=(i, sid)) for i, sid in enumerate(submission_ids)]
		for thread in threads:
			thread.start()
		for thread in threads:
			thread.join(timeout=60)
	finally:
		entitlements.grant_mission_video_entitlement = real_grant
	return results


def test_concurrent_approvals_of_one_repeating_mission_day_grant_video_once(repeating_world):
	factory, make = repeating_world
	ids = make(5)
	results = _race_approvals(factory, ids["parent"], ids["subs"])
	assert results == [("ok", "approved")] * 5, results
	with factory() as s:
		ledger = _ledger(s, ids["child"])
	assert ledger == {"stars": 5 * MISSION_STAR_REWARD, "xp": 5 * MISSION_XP_REWARD, "grants": 1, "seconds": 600}


def test_concurrent_duplicate_approval_of_one_submission_grants_once(repeating_world):
	factory, make = repeating_world
	ids = make(1)
	results = _race_approvals(factory, ids["parent"], ids["subs"] * 4)
	assert results == [("ok", "approved")] * 4, results
	with factory() as s:
		assert _ledger(s, ids["child"]) == {"stars": MISSION_STAR_REWARD, "xp": MISSION_XP_REWARD, "grants": 1, "seconds": 600}


def test_on_committed_rows_the_unique_index_refuses_a_second_award_for_the_day(repeating_world):
	"""If a future code path skipped the in-transaction check, the database index is the last line of defence."""
	factory, make = repeating_world
	ids = make(1)
	User = get_model("User")
	with factory() as s:
		assert review_submission(s, ids["subs"][0], s.get(User, ids["parent"]), TaskReviewCreate(decision="approved")).status == "approved"
	with factory() as s:
		Entitlement = get_model("VideoAccessEntitlement")
		first = s.query(Entitlement).filter(Entitlement.task_id == ids["task"]).one()
		s.add(
			Entitlement(
				id=uuid4(), child_id=ids["child"], source_type="mission_reward", task_id=ids["task"],
				granted_seconds=600, consumed_seconds=0, granted_at=first.granted_at, valid_from=first.valid_from,
				status="active", repeat_reward_local_date=first.repeat_reward_local_date,
			)
		)
		with pytest.raises(IntegrityError):
			s.commit()
		s.rollback()
	with factory() as s:
		assert _ledger(s, ids["child"])["grants"] == 1
