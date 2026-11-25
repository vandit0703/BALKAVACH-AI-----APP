# Reference 24-screen gap audit (Phase 1)

Date: 2026-11-24. Branch `main`, HEAD `a08a243`. Source-level audit only; nothing was run, and no code or data was changed.

## Working tree at start (preserved, not touched)
Modified: `app_router.dart`, `video_detail_player_screen.dart`, `watch_home_screen.dart`, `youtube_player_screen.dart`, `mission_providers.dart`, `watch_home_test.dart`.
Untracked: `lib/shared/diag/`, `test/widgets/youtube_fullscreen_orientation_test.dart`.
The Learning Hub work will edit `app_router.dart` and `watch_home_screen.dart`, so it has to be layered on top of these changes.

## Key architecture facts
- The backend is FastAPI + SQLAlchemy **automap**. Models are reflected from the live DB via `MODEL_TABLES` in `app/db/base.py`. A new table needs an Alembic migration and a `MODEL_TABLES` entry.
- Alembic refuses to run unless `ALLOW_SCHEMA_MIGRATIONS=true`. The latest revision is 0020. Production (Neon) must not be touched.
- No quiz, story, or celebration code exists anywhere (backend, frontend, admin). Confirmed by a file and content search.
- The only "stories" today are the `stories` category of `educational_content` (`article` type) and daily-mission story text.
- Rewards are written to `star_transactions` / `xp_transactions` (`ledger_service`). Missions use 10 Stars + 15 XP (`mission_rewards.py`).
- Child navigation has 5 shell tabs (Home, Missions, Rewards, Garden, Profile). Learn, Watch, Videos and Shorts are routes outside the tabs.

## Matrix (reference screen vs current state)

| # | Reference screen | State | Evidence / gap |
|---|---|---|---|
| 1 | Splash | Built | `splash_screen.dart` |
| 2 | Choose role | Built | `role_selection_screen.dart` |
| 3 | Child sign up | Partial | A parent creates the child (`create_child_screen.dart`), and the child logs in with credentials. This is intentional for child safety, so no self sign-up. |
| 4 | Child home | Built | `child_home_screen.dart`. The Learning Hub tabs (Videos / Quizzes / Stories) are missing. |
| 5 | Mission details | Built | `mission_detail_screen.dart`, `mission_submit_screen.dart` |
| 6 | Mission completed | **Missing** | There is no celebration screen. `mission_waiting_screen.dart` is shown instead. Rewards come only after parent approval. |
| 7 | My World / Garden | Partial | `garden_screen.dart` + `garden_service.py` (stage from XP, items from badges). |
| 8 | Level up | **Missing** | The backend has levels, but there is no level-up event or screen. |
| 9 | Parent sign up | Built | `parent_auth_screen.dart` |
| 10 | Link child (code/QR) | Different | Parents create child accounts, with credentials set via `PUT .../credentials`. There is no code/QR linking. A new linking flow is a security-sensitive design change, so it needs your decision. |
| 11 | Parent dashboard | Built | `parent_home_screen.dart` |
| 12 | Approve mission | Built | `approvals_screen.dart` |
| 13 | Custom mission | Built | `create_mission_screen.dart` |
| 14 | Create reward | Built | `reward_form_screen.dart`, `parent_rewards_screen.dart` |
| 15 | Child reward store | Built | `rewards_screen.dart` and `GET /rewards` (child-scoped). Backend support is confirmed. My older note saying "no child catalogue" is out of date. |
| 16 | Redeem reward | Built | `POST /redemptions`, 409 `insufficient_stars`, cancel/mine |
| 17 | Learn section | Partial | `learning_screen.dart` shows admin content with category chips and `watch_home_screen.dart` shows videos. There are no Videos / Quizzes / Stories tabs. |
| 18 | Take quiz | **Missing** | No tables, API, models, UI or admin. |
| 19 | Quiz result | **Missing** | Same as screen 18. |
| 20 | Achievements | Partial | Badges are returned by `progress_service`. I did not find a dedicated child achievements screen. Streak screen: `streak_screen.dart`. |
| 21 | Weekly progress | Built | `weekly_report_screen.dart`, `GET /progress/children/{id}/weekly` |
| 22 | Progress share | Built | `features/sharing`, `invite_screen.dart`, `card_sharer.dart` |
| 23 | Settings | Built | `parent_settings_screen.dart`, notification and Panda voice settings |
| 24 | Admin panel | Partial | Pages: dashboard, users, families, missions, presets, rewards, badges, content, categories, YouTube reviews, audit, settings. **Missing: quizzes, stories, notifications, reports.** |

## What has to be built, with dependencies
1. **Learning Hub tabs.** Frontend only. It is blocked on nothing but must merge with the uncommitted video changes.
2. **Quiz system.** Needs a migration and new tables: quizzes, questions, options (with a localized text per language), attempts and answers. Also needs child APIs (list, start, submit), admin CRUD with publish/unpublish, and frontend screens. The result is graded on the server. Correct answers are never sent before submission. Idempotent rewards need a unique key per (child, quiz) or per attempt.
3. **Stories.** There is no story model. The options are to reuse `educational_content` rows with `content_type=article` or to add a stories table. This needs your decision.
4. **Panda celebration.** A reusable widget plus an `ActivityCompletion` result model. It is presentation only. Existing Panda assets: `panda_cheering.jpg` and the companion widgets in `features/companion`.
5. **Level-up and achievements.** The backend has levels and badges. The frontend needs a level-up event and an achievements screen. Both must be derived from the server, with no hardcoded values.
6. **Admin.** Quiz and story management, plus a real notifications and reports page.

## Risks
- Backend tests that touch `get_model` need a reflected DB. The local pgserver environment is a reconstruction of the baseline schema, not production. Test results will be labelled that way.
- A migration for the quiz tables can only be applied to a local test DB in this task. Production rollout needs your separate authorization.
- Quiz rewards: no policy exists. A proposal follows in the questions below.

## Open questions for you
1. Quiz rewards: how many Stars/XP, and should they be admin-configurable per quiz (default 0)? I suggest a per-quiz value defaulting to 0, awarded once per child per quiz, on the first passing attempt.
2. Stories: new table, or reuse `educational_content` `article` rows?
3. Screen 10 (link child by code/QR): build it, or keep the current parent-creates-child model?
4. Learning Hub placement: add a "Learn" destination inside the existing Home/Watch screen, or add a sixth bottom-nav tab?
