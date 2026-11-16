# BalKavach Phase B Mission Engine

Status: preparation only. This document contains no production seed data and
does not change the current preset-task implementation.

## Current boundary

The current preset library is stored in `preset_tasks` and exposed through
`GET /api/v1/tasks/presets`. Parents copy a preset into a normal family task.
The existing fields are title, description, language, category, age range and
suggested rewards. Automatic daily assignment, weekday scheduling, estimated
duration, safety metadata, rotation history and duplicate prevention do not yet
exist.

## Proposed mission record

Each canonical mission should have a stable `content_key`, a category, one age
band, an estimated duration, a difficulty, a safety classification and a
translation set. Suggested rewards remain defaults only; parent-created task
rewards remain authoritative.

Recommended age bands:

| Band | Age | Design rule |
|---|---:|---|
| early | 3-5 | Adult-aware, 5-15 minutes, no sharp tools, heat, heights or unsupervised outdoor tasks |
| primary | 6-8 | 5-20 minutes, simple sequencing and tidy-up tasks |
| middle | 9-12 | 10-30 minutes, independent reading, movement and household help |
| teen | 13-15 | 15-40 minutes, planning, responsibility and reflective habits |

The engine should use the child's date of birth and family timezone on the
server. It must never infer an age band from the client or device clock.

## Seven-day schedule draft

This is the initial content plan, not an insert script. Each row represents one
rotation slot per age band; production seeding should expand each slot into at
least three interchangeable missions before assignment is enabled.

| Day | Category focus | early (3-5) | primary (6-8) | middle (9-12) | teen (13-15) |
|---|---|---|---|---|---|
| Mon | Hygiene | Brush teeth with an adult | Brush teeth twice | Prepare a complete morning routine | Plan and complete a personal-care routine |
| Tue | Reading | Look at a picture book for 5 minutes | Read for 10 minutes | Read for 20 minutes and share one idea | Read for 25 minutes and write a reflection |
| Wed | Movement | Play an active game for 10 minutes | Move outdoors for 15 minutes | Complete a safe 20-minute activity | Plan a 30-minute safe exercise session |
| Thu | Helping | Put toys in their places | Help set or clear the table | Complete one agreed household task | Take ownership of one household task |
| Fri | Organisation | Put three items away | Organise a school bag | Tidy a study area and prepare tomorrow's materials | Plan and reset a study/work area |
| Sat | Creativity | Draw a favourite animal | Make a picture or craft | Create something and explain the idea | Complete a creative project and document it |
| Sun | Healthy habits | Drink water and say thank you | Choose a screen-free family activity | Prepare a healthy snack with an adult | Plan a screen-free wellbeing activity |

## Translation dataset contract

Every canonical `content_key` must have `en`, `hi` and `gu` title,
description and instructions before it is active. The following sample
translation keys define the shape; native-speaker review is required before
release.

| Key | English | Hindi | Gujarati |
|---|---|---|---|
| `reading.story.10m` | Read a story for 10 minutes | 10 मिनट कहानी पढ़ें | 10 મિનિટ વાર્તા વાંચો |
| `hygiene.teeth.twice` | Brush your teeth twice today | आज दो बार दाँत साफ करें | આજે બે વાર દાંત સાફ કરો |
| `organisation.school_bag` | Arrange your school bag | अपना स्कूल बैग व्यवस्थित करें | તમારી સ્કૂલ બેગ ગોઠવો |
| `movement.outdoor.15m` | Play outdoors for 15 minutes | 15 मिनट बाहर खेलें | 15 મિનિટ બહાર રમો |
| `helping.small_task` | Help with one small household task | घर के एक छोटे काम में मदद करें | ઘરના એક નાના કામમાં મદદ કરો |
| `creativity.draw` | Draw something creative | कुछ रचनात्मक चित्र बनाएं | કંઈક સર્જનાત્મક દોરો |
| `healthy.water` | Drink water regularly today | आज नियमित रूप से पानी पिएं | આજે નિયમિત પાણી પીવો |

## Assignment and rotation rules

1. A daily assignment is keyed by `(child_id, local_date, slot_key)` and is
   created in one transaction with a unique constraint.
2. The server selects only active, translated, age-compatible and safety-valid
   content for the child.
3. The selector excludes the child's most recent `rotation_window` assignments
   for the same content key. The default window is 14 local days.
4. If the eligible pool is smaller than the requested slots, the engine emits a
   visible low-variety state and chooses the least-recent item; it never creates
   duplicates in the same day.
5. Parent-disabled content is excluded at selection time. Parent replacement
   content is stored as a family override and does not mutate the canonical
   library.
6. Assignment is idempotent on retry. A deployment seed is idempotent on
   `content_key + language_code`, and must never create family tasks directly.
7. Parent-created custom missions remain separate from canonical assignments
   and are never overwritten by the daily engine.
8. Qualifying approval, stars, XP, streaks and video entitlements continue to
   use the existing authoritative review path.

## Required backend changes for Phase B

- Add canonical mission content and translation tables or extend presets with
  stable keys, weekday slots, duration, difficulty and safety fields.
- Add family mission preferences and child assignment/rotation history.
- Add unique constraints and indexes for daily assignment idempotency and
  recent-history lookup.
- Add a transaction-safe assignment service using the family's timezone.
- Add parent endpoints for enable/disable, replacement and schedule choices.
- Keep `GET /tasks/presets` backward compatible while adding explicit metadata.
- Add a reviewed seed command that is dry-run by default; production writes
  require an explicit operator action.

## Required client/admin changes

- Parent Flutter: show age-safe suggestions, enable/disable controls and
  replacement choices; never calculate eligibility locally.
- Child Flutter: display assigned missions and duration/instructions from the
  API, with localized empty and low-variety states.
- Admin Flutter: manage canonical content, translations, safety classification,
  age bands, weekday slots and active status with audit logs.

## Acceptance criteria

- A child receives the correct seven local-calendar-day slots for their age.
- Repeating the assignment request creates no duplicate daily task.
- A disabled or unsafe mission is never assigned.
- The same content key is not repeated inside the configured rotation window
  when eligible alternatives exist.
- Parent replacement and custom missions survive reassignment and deployment
  retries.
- English, Hindi and Gujarati responses have matching translation coverage.
- Existing approval, streak and video-entitlement tests remain unchanged and
  pass.