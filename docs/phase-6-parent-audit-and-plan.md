# Phase 6 audit and plan: parent workflows and remaining reference features

Date: 2026-11-24. Branch `main`, HEAD `e4c528f` ("fixes"). This supersedes the matrix in `reference-24-screen-gap-audit.md`, which was written before Phases 2-5. Source-level audit; no code changed in this step. Backend statements about the production schema are unverified (the local database is reconstructed).

## 0. Repository state
- HEAD moved from `a08a243` to `e4c528f` during the session: that commit already contains most Phase 3/4 files (celebration widgets, localization, quiz tests).
- Still uncommitted (45 entries): quiz backend and migration `0021`, `achievement_service`, progress endpoint changes, admin quizzes page, Phase 5 child-app files, the `0017` revision-id fix, and `docs/reference-24-screen-gap-audit.md`.

## 1. Reference screens, current state

| # | Screen | Implementation now | Missing | Backend / DB | Admin | l10n | Tests | Blockers |
|---|---|---|---|---|---|---|---|---|
| 1 | Splash | Built | none | none needed | n/a | en/hi/gu | yes | none |
| 2 | Choose role | Built | none | none | n/a | yes | yes | none |
| 3 | Child sign up | Parent creates the child (decision: kept) | self sign-up by design not built | `POST /families/{id}/children` | Users page | yes | yes | none |
| 4 | Child home | Built; Learning Hub (Videos/Quizzes/Stories) in the Learn area | none | existing | n/a | yes | yes | none |
| 5 | Mission details | Built | none | tasks API | Missions page | yes | yes | none |
| 6 | Mission completed | Submission cheer + approval celebration (server Stars/XP) | none | `/tasks/submissions/mine` | n/a | yes | yes | none |
| 7 | My World | Garden, level progress card, decorations, locked badges | garden stage rule inconsistent (see 3.1) | `/progress/...`, `/achievements` | Badges page | yes | partial (widgets tested, screens not) | decision 3.1 |
| 8 | Level up | Celebration for level-up and new badge | none | derived from progress | n/a | yes | yes | none |
| 9 | Parent sign up | Built | none | auth | Users page | yes | yes | none |
| 10 | Link child | Parent-created account (decision: no code/QR) | code/QR linking | n/a | n/a | n/a | n/a | not requested |
| 11 | Parent dashboard | Built | no per-child progress/achievement summary | existing | Dashboard | yes | yes | none |
| 12 | Approve mission | Built | none | `/reviews/...` | Missions page | yes | yes | none |
| 13 | Custom mission | Built (create/edit; reward fixed at 10 Stars/15 XP) | none | `/tasks` | Presets page | yes | yes | none |
| 14 | Create reward | Built | none | `/rewards` | Rewards page | yes | yes | none |
| 15 | Child reward store | Built | none | `/rewards`, `/redemptions` | Rewards | yes | yes | none |
| 16 | Redeem reward | Built | none | idempotent `POST /redemptions` | Redemptions | yes | yes | none |
| 17 | Learn section | Built | none | existing + quizzes | Content/Quizzes | yes | yes | none |
| 18-19 | Quiz / result | Built, server-graded, first-pass rewards | none | migration `0021` (local only) | Quizzes page | yes | yes | production schema unverified |
| 20 | Achievements | Child: earned + locked with progress (Rewards tab). Parent: earned only (weekly report) | parent view of locked and level progress; no dedicated screen | `/achievements` is already parent-authorized | Badges page | yes | partial | none for parent view |
| 21 | Weekly progress | Built (missions only) | quiz activity absent (see 3.3) | `/progress/children/{id}/weekly` | Reports missing | yes | yes | decision 3.3 |
| 22 | Progress share | Built | none | n/a | n/a | yes | yes | none |
| 23 | Settings | Parent settings (timezone, language, notifications, Panda voice, consents, linked children) | video daily-limit control; "Help & Support" not verified | `video_settings.daily_limit_seconds` exists, no UI | Settings page | yes | partial | decision (4.5) |
| 24 | Admin panel | Dashboard, users, families, missions, presets, rewards, redemptions, content (articles = stories), quizzes, badges, YouTube, audit, settings | notifications page, reports page, moderation beyond YouTube | existing | partly | yes | yes | Phase 7 |

## 2. Parent workflow audit

| Workflow | Exists | Gap | API support | Needs |
|---|---|---|---|---|
| Child progress and achievements | Level, streak, week, earned badges (report, child profile) | Locked badges, progress towards them, distance to next level | `GET /progress/children/{id}/achievements` already allows the family's parent | Frontend only |
| Mission review and approval | Inbox, approve/reject/resubmit, celebrations, tests | none | complete | nothing |
| Reward history | Parent sees only **pending and approved** requests | Fulfilled, rejected and cancelled history is invisible | `GET /redemptions?status=` already supports all five statuses | Frontend only |
| Star transparency (earned vs spent) | Balance only | No list of earned/spent entries for a parent | none (ledger is not exposed to parents) | New read endpoint, product confirmation |
| Child learning history | Mission history (reports), video watch history | **Quiz history invisible to parents**; stories not tracked | `GET /quizzes/history` is child-only | One new read-only endpoint |
| Custom missions | Create/edit | none | complete | nothing |
| Settings and safety | Timezone, notification prefs, consents, Panda voice, child credentials, parent mode | Daily video limit has server support but no UI | `video_settings.daily_limit_seconds` (900-14400 s, default 3600) | Product decision (policy file says do not change without approval) |
| Parent notifications | Approval needed, redemption requests, video alerts, streaks | Nothing tells a parent about a child's quiz pass, badge or level-up | creating them is a server change | Product decision |

## 3. Progression inconsistencies (not changed; options below)

### 3.1 Garden stage: weekly missions vs XP
**Today:** the garden card stage comes from the app (`GardenStage.forWeeklyMissions`): 0 missions seed, 1 sprout, 3 sapling, 6 blooming tree, counted over the last 7 days. The server independently computes a garden from lifetime XP (`garden_service`: seed 0, sprout 100, sapling 300, young-tree 700, blossom 1500, orchard 3000 XP) and the decorations come from badges; the screen mixes the two.
- **Option A, keep weekly missions:** stage can shrink after a quiet week; ignores quiz XP; not server-authoritative; differs from the level shown right above it.
- **Option B, server XP stage:** never shrinks, same source as levels, includes quiz XP, already implemented and tested server-side; needs two more stage names and icons (6 stages instead of 4) and new copy; the "missions to next stage" line is replaced by "XP to next stage".
- **Option C, hybrid:** XP stage plus a separate "this week" line from the weekly missions.
- **Recommendation: C** (growth is permanent and consistent with levels; weekly missions stay visible as encouragement).

### 3.2 Badge `total_stars`: current balance vs lifetime earned
**Today:** `criteria_values` and the mission-approval path both use the *current ledger balance* (earned minus spent). A badge, once unlocked, is never removed.
- **Option A, balance:** spending Stars on a reward lowers the progress bar of a locked "Star" badge and can stop it ever unlocking; a child is penalised for redeeming.
- **Option B, lifetime earned:** the sum of positive Star entries from missions and quizzes, excluding refunds and manual adjustments. Progress never goes down. It changes which children qualify for new unlocks (more of them); existing unlocks are untouched. It needs the mission-approval badge line in `task_service.py` to use the same value (a one-line change to mission code).
- **Recommendation: B**, with an explicit list of counted transaction types.

### 3.3 Quiz in weekly activity, reports and streaks
**Today:** the weekly report and activity days are built only from approved mission submissions, and the streak counts only an approved mission. A quiz pays Stars/XP into the ledger, so the report's Stars/XP no longer matches the ledger for quiz-active children, and quizzes never extend a streak.
- **Option A, leave as is:** label the report "missions"; ledger and report disagree.
- **Option B, add a separate "Quizzes" section to the parent report** (attempts, pass, Stars/XP paid, from existing quiz tables and ledger; no schema change). Activity days and streak unchanged.
- **Option C, quiz counts for streak/activity:** changes the streak rule (parent-approved today); a self-served quiz would let a child keep a streak without any approval.
- **Recommendation: B**; keep streaks parent-approval based.

## 4. Implementation plan

**Can start now (no product decision; reuses existing contracts)**
1. Parent child-progress view: level progress, earned and locked badges with progress, in the child profile (existing `/achievements`, frontend only).
2. Parent reward history: add fulfilled/rejected/cancelled history beside open requests (existing `GET /redemptions?status=`, frontend only).
3. Parent quiz history: one new read-only endpoint `GET /quizzes/children/{child_id}/history` (family-authorized, no migration) plus a card in the child profile.
4. Tests, Hindi/Gujarati strings, small screen / large text / reduced motion checks for all of the above.

**Needs your decision first**
- Section 3.1, 3.2, 3.3 choices (each changes existing behavior).
- Parent notifications for a child's quiz pass, badge or level-up (new notification types).
- Parent-visible Star ledger (new endpoint and what it may reveal).
- Daily video-limit control in parent settings (exposes an existing safety policy).
- "Help & Support" screen content, and the admin notifications/reports pages (Phase 7).

## 5. Constraints kept
Mission rewards stay 10 Stars and 15 XP once per approved mission; quiz rewards stay admin-set and first-pass-only; reward idempotency and family authorization are unchanged; no migration is planned for the items above; any future migration runs only on the isolated local database.

## 6. Product decisions recorded (2026-11-24) - NOT implemented in the parent-views pass

| Topic | Decision | Status | Notes before implementing |
|---|---|---|---|
| Garden stage | Permanent XP-based stage plus a separate weekly-missions indicator (option C) | Approved, not built | Needs 6 stage names/icons/strings; server `garden_service` thresholds already exist. |
| Badge `total_stars` | Lifetime Stars earned, excluding refunds and manual adjustments | Approved, not built | The exact transaction types counted must be established first. In this repository's code: `task_approved` (+) and `quiz_passed` (+) are earnings, `reward_redemption` (-) is spending, `refund` (+) and `admin_adjustment` (+/-) are excluded. Production may hold other types (unverified: needs a read-only `SELECT DISTINCT transaction_type`). Progress display and badge awarding (including the mission-approval path in `task_service.py`) must use one shared calculation. |
| Weekly report | Add a separate quiz-activity section; streaks stay parent-approval based | Approved, not built | Read-only from existing quiz tables; activity days and streaks unchanged. |
| Parent notifications | Approved for quiz pass, new badge, level-up | Approved, not built | Must respect notification preferences and quiet hours (new notification types and templates). |
| Parent-visible Star ledger | Approved, read-only: earned, spent, refunds, adjustments | Approved, not built | New read endpoint, family-authorized. |
| Daily video-limit control | Deferred pending safety-policy review | Deferred | Server setting `video_settings.daily_limit_seconds` (900-14400 s) exists; the policy file says do not change without approval. |
| Help & Support | Deferred pending defined content | Deferred | No screen to be built until content is defined. |

## 7. Implemented in the parent-views pass
Parent child-progress view (level, earned and locked badges with server-measured progress), parent reward history (fulfilled, rejected, cancelled), and parent quiz history (`GET /quizzes/children/{child_id}/history`, read-only, family-authorized, no migration).

### 7.1 Corrections from the 2026-11-25 audit pass
- Quiz history shows the newest 10 and a "Show more" button; the endpoint gained `offset` (`limit` 1-100, default 50), so every attempt is reachable.
- Reward history follows `GET /redemptions` pages (100 rows each) to the end instead of stopping at the first page per status.
- Attempt dates (`submitted_at`) are now sent with a UTC offset; without it the app showed the UTC day as the local day.
- Parent history and badge dates include the year. The parent quiz score no longer says "You got".
- Achievements, quiz history and reward history are fetched again when reopened; mission approval and redemption decisions also refresh achievements.
- The reward tabs scroll on phones instead of clipping their labels.

### 7.2 Known gaps
- A redemption carries no reward description. The history shows the current catalog's description, so a removed reward has none. Returning `reward_description` from `GET /redemptions` would close this (additive API change, not made).
- No cancellation date is recorded: a cancelled request shows its request date and, if it had been approved, the approval date, and is ordered by that.
- "Show more" pages by offset: an attempt submitted while the list is open appears after a refresh.
- The parent view reuses the child's heading "Keep going!" for locked badges.
- In Hindi and Gujarati the level card title uses स्तर / સ્તર while the line below uses लेवल / લેવલ.
- Quiz endpoints need migration `0021` in any environment before they work. Production schema is unverified; all database tests ran on a reconstructed local PostgreSQL.
