# Mission rotation and repeat prevention (milestone C2)

Code: `app/services/mission_rotation_service.py` (policy and ranking), `daily_mission_service.ensure_daily_choices` (uses it),
`mission_catalogue_service.catalogue_health` and `GET /admin/daily-missions/catalogue-health` (admin view).
Tests: `tests/test_mission_rotation.py`, `tests/test_catalogue_health.py`, `tests/test_mission_catalogue.py`.

## What was wrong (audit of the previous algorithm)

| Assignment status | Old treatment |
|---|---|
| approved | excluded **for ever** (this exhausted the catalogue: at fewer than 3 left, HTTP 503) |
| skipped | excluded on the same local date only, so it could be offered again the next day |
| rejected | no memory across days |
| selected / in progress / **pending review** | not excluded on later days, so a mission still waiting for a parent could be offered again |
| offered but not chosen | no memory; the surprise template was forced into slot 1 every day |
| unpublished / no variation for the child's age | filtered out; fewer than 3 left meant 503 |

No schema change was needed: the history is already in `daily_mission_assignments`.

## Policy (all dates are family-local dates)

A *mission* is a template. The same template in another language or age band is the same mission, so changing language never
bypasses repeat prevention.

| Rule | Value |
|---|---|
| Cooldown after a mission the child **engaged with** (selected, in progress, pending review, approved) or **skipped** | 42 days |
| Cooldown after a **rejected** mission (the parent said "try again") | 7 days |
| Missions **offered but never chosen** | no cooldown; ranked lower if shown on either of the two most recent earlier offer days ("previous two"), and lower the more often they were shown |
| Same template twice on one local date (including a skipped one) | never |
| A mission still **active** (selected / in progress / pending review) within the last 42 days | never, even as a fallback |
| Hard filters | published, and has a variation for the child's age band in the child's language or English |

Why offered-but-ignored missions do not get the 42-day cooldown: a child sees 3 choices a day and picks 1. Cooling down everything
shown would need 126 templates. Cooling down what was engaged with or skipped needs 42, which is the catalogue target.

### Ranking (lower is better)

1. **Fresh** (outside cooldown) before **cooldown fallback**.
2. Among fresh: a surprise mission that was not shown recently, then the weekday theme, then not shown on the previous two offer days,
   then the least often shown, then a stable hash of child + date (so a retry returns the same choices).
3. Among cooldown fallbacks: shown longest ago first, then least often shown.
4. **Variety:** within a tier the three choices come from different themes when enough themes exist.

The spec lists "weekday theme" above "not in the last 42 days"; cooldown is applied first because a theme mission that the child did
last week should not beat a fresh one from another theme ("no repeat within 42 days when alternatives exist").

## Fallback and errors

* If fewer than 3 fresh candidates exist, the remaining slots take cooldown fallbacks, **oldest first**. This never turns into an error
  while at least 3 distinct eligible published missions exist.
* Every assignment records `snapshot.rotation = {policy, tier: "fresh" | "cooldown_fallback", last_shown}`; the API ignores the key.
* With fewer than 3 eligible missions (empty catalogue, everything unpublished, no variation for the age band, or the only candidates are
  pending review) the request returns **503 `daily_missions_unavailable`** with `details {eligible, age_band}`, the server logs an
  error naming the child and the count, and the admin health view shows the shortfall. A skip with no replacement returns 409
  `daily_mission_no_replacement`.

## Admin

* `GET /admin/daily-missions/catalogue-health` (permission `tasks:read`): per weekday theme the number of templates, published,
  eligible (published and complete), per-age-band and per-language capacity, unpublished and incomplete slugs; per template the assignment count,
  last assigned date and fallback count; fallbacks in the last 14 days (count, distinct children, by template); and a warning for every theme with
  fewer than **6** eligible templates, including the shortfall.
  **Added in C2 part 2 (the rotation rules above are unchanged):** per theme `verified_distinct`, `unverified`, `duplicate_activities` and `healthy`;
  top-level `totals` (templates, published, unpublished, complete, incomplete, never assigned, most assigned) and `activity_warnings`.
  *Eligible* still means published and complete (capacity). *Healthy* additionally needs at least 6 **distinct activities**, counted from
  `app/content/daily_missions/activities.py`: two eligible templates that share one activity count once, and eligible templates that are not in the
  catalogue source (admin-authored, or the migration placeholders) are listed as `unverified` and do not count towards `healthy`, so six database rows
  are not reported healthy unless they are six different known activities. The existing `warnings` list is unchanged; activity problems are in `activity_warnings`.
* The admin panel (Missions, daily missions card) shows these per theme with a warning icon, the fallback count, and "shown N times" per template.
* **Retiring** a mission is unpublishing it (existing publish switch). Assignments keep their frozen content snapshot and foreign keys, so history is
  never deleted; rotation and the health view treat it as unpublished.
* An incomplete template cannot be published (the panel names the missing versions).

## Database

**No migration.** Everything is derived from `daily_mission_assignments` (`child_id`, `template_id`, `local_date`, `status`, `is_current`, `snapshot`).

| Query | Index / cost |
|---|---|
| a child's last 42 days | `ix_daily_assignment_history (child_id, local_date, status)`: a range scan of at most ~126 rows |
| a child's per-template count | grouped over that child's rows by `child_id` (same index prefix); at most about 1,100 rows a year |
| admin: assignments per template, last assigned | grouped over the whole table; fine at this scale; if it grows large, add `(template_id)` in a later additive migration |
| admin: recent fallbacks | window on `local_date`, filtered in Python from `snapshot` (no JSONB index needed for a 14-day window) |

Existing history is untouched; children who already approved missions simply start their cooldown from those dates.

## Verification status

* **Not run against PostgreSQL**: the baseline schema (`tests/schema/baseline.sql`) is still missing. The rotation tests run on an in-memory SQLite
  "world" that reproduces `autoflush=False` and the partial unique slot index. SQLite proves the logic, **not** PostgreSQL behaviour.
* **Concurrency:** two simultaneous first requests are serialised by the existing `SELECT ... FOR UPDATE` on the child row (unchanged); the partial
  unique index on the current slot is the second guard, and a test shows the index rejects a duplicate row. The row lock itself is **not** exercised by
  SQLite and is unverified.
* Mutation checks were run on the policy numbers, the recent/frequency ranking and the active-mission filter; each made the tests fail.

## Known limits

* The catalogue now has 42 templates (6 per theme), so a child who chooses one mission a day sees no repeat for 42 days (tested on the real catalogue in SQLite). After day 42 every mission repeats; 42 days is not a year of fresh content. Until the 28 new templates are published (they are seeded unpublished) the capacity warning still applies.
* "Previous two" is defined as the two most recent earlier days on which the child was offered missions, not the previous two *chosen* ones.
* A mission left selected for more than 42 days stops blocking that template (it is outside the history window).
* Surprise templates (the migration placeholder `daily_surprise_spark`) now lead only when fresh and not shown recently; they no longer lead every day.
