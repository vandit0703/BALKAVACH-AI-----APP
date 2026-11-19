# Daily mission content: research notes (catalogue `c1`)

Written 2026-11-18 for milestone C1; extended 2026-11-19 for the C2 expansion from 14 to 42 templates (see the last sections). It records what the mission content is based on, **what was actually read**, and
how far the evidence goes. It does not claim that any mission improves intelligence or guarantees a developmental
outcome. Every mission is framed as an *opportunity to practise* a skill.

## What was read, and how closely

| # | Source | What was done | Used for |
|---|---|---|---|
| 1 | Center on the Developing Child at Harvard University (2014). *Enhancing and Practicing Executive Function Skills with Children from Infancy to Adolescence* (activities guide, 16 pp.). <https://developingchild.harvard.edu/resources/handouts-tools/activities-guide-enhancing-and-practicing-executive-function-skills/> | **Read in full** (PDF text extracted). | The skill vocabulary (working memory, attention, flexible thinking, self-control), the age bands, and the activity types (copy games, rounds and clapping rhythms, memory-location games, imaginary play with self-made props, planning, self-talk, journaling, perspective-taking for teens). |
| 2 | Center on the Developing Child, *Brain-Building Through Play* handouts. <https://developingchild.harvard.edu/brainbuildingthroughplay> | **Landing page read**: list of handouts (4-7, 8-12, 13-17 years) and the skills it names (focusing attention, working memory, basic self-control). The individual handouts were **not** opened. | Confirms the age grouping and that play-based practice is the intended mode. No specific activity was taken from the handouts. |
| 3 | Yogman M, et al. *The Power of Play: A Pediatric Role in Enhancing Development in Young Children.* AAP clinical report, **Pediatrics 2018;142(3):e20182058**. | **Not read.** The publisher page returned HTTP 403 and an AAP news page returned 404. Only search-result summaries and news coverage were seen (play supports executive function and can buffer stress; "prescription for play"). | General framing only (that play is worth protecting). **No mission design decision depends on it.** Read the report itself before quoting it. |
| 4 | CASEL, *What is the CASEL Framework?* (five competencies: self-awareness, self-management, social awareness, relationship skills, responsible decision-making). <https://casel.org/fundamentals-of-sel/what-is-the-casel-framework/> | **Fetched 2026-11-19 (C2 part 2)**: the competency definitions were taken from the fetch tool's summary of the whole page; the page text itself was not saved. The C1 note said "not opened"; that is superseded for this page only. | The labels "emotional awareness" and "self-regulation" used for Friday's skill categories, and the aims of the Friday missions: naming one's own feelings (self-awareness), calming strategies (self-management), noticing others (social awareness), asking, listening and offering help (relationship skills). It supplies vocabulary, not evidence that any mission works. |
| 5 | NAAEE, *Early Childhood Environmental Education Programs: Guidelines for Excellence* (2010). | **Not read**; search listing only. | Nothing. Environmental awareness in the Sunday mission follows common-sense reuse and saving-resources ideas, not this document. |

The brief named Harvard (activities guide and Brain-Building Through Play) and the AAP report. Of those, only the Harvard
activities guide was available in full. The remaining rows are listed so nobody mistakes them for fully checked references.
On 2026-11-19 the Brain-Building Through Play landing page was fetched again: it still lists only handout titles (6 months
to 17 years, e.g. "5 Games and Activities for Children" for ages 4-7), with the activities themselves inside PDFs that were **not**
opened. It remains *partially reviewed* and no activity was taken from it.

## What the evidence does and does not say

* The Harvard guide itself states: *"scientific studies have not yet proven the effectiveness of all these suggestions,
  their presence here reflects the judgment of experts in the field about activities that allow children to practice
  their executive function skills. Practice leads to improvement."* The catalogue inherits exactly that status:
  expert-judgement activities for practice, not proven interventions.
* The guide describes activities **for adults to do with children** at younger ages and more independent play later.
  The catalogue follows that: a grown-up is present and involved for ages 4-6, lightly involved at 7-10, and mostly a
  listener and checker at 11-15.
* No outcome (school results, IQ, attention scores) is claimed anywhere in the app text, and none should be added.
* **Not done:** no pilot with children, no review by a child-development specialist or a teacher. Durations and difficulty
  are informed judgement.

## Skill categories used

| Category (key) | Meaning in the app | Mission |
|---|---|---|
| attention and observation (`attention_observation`) | Focusing on, noticing and sorting what is perceived | Monday: Sound Detective |
| working memory (`working_memory`) | Holding items or positions in mind for a few seconds, then using them | Tuesday: Memory Master |
| language and storytelling (`language_storytelling`) | Organising ideas into a spoken or written story; revising | Wednesday: Magic Story Maker |
| problem-solving and planning (`problem_solving_planning`) | Plan, build, test, change one thing, test again | Thursday: Paper Architect |
| emotional awareness and self-regulation (`emotional_awareness_self_regulation`) | Naming feelings, noticing body signals, trying a calming strategy | Friday: Emotion Detective |
| self-regulation through rhythm (`self_regulation_rhythm`) | Copying, holding a pattern, stopping on a signal, taking turns | Saturday: Rhythm Rockstar |
| creative problem-solving (`creative_problem_solving`) | Spot a real problem, imagine and compare fixes; a small real action | Sunday: Future Inventor |

Secondary practice (in `also_practises`): communication, creativity, flexible thinking, persistence, empathy,
cooperation, practical responsibility and environmental awareness.

## Why each mission suits its ages

The full per-age rationale, materials, minutes and parent involvement are in `docs/mission-catalogue-inventory.md`
(generated from the same data). In short:

* **Ages 4-6:** very short (6-10 min), concrete, about three items or three steps, one grown-up beside the child, a
  gentle second attempt, and sharing is optional. Mirrors the Harvard preschool and early-school advice to use simple
  games and to support rule-following with adult help.
* **Ages 7-10:** more items (six), a small record (list, map, symbols), a trick or strategy to try, self-comparison only
  ("beat your own count"), and explaining reasoning aloud. Harvard's 7-12 section favours steadily increasing
  complexity, strategy and monitoring.
* **Ages 11-15:** open briefs with constraints, written planning, testing and revising, reflection on one's own state, and
  perspective-taking. Harvard's adolescent section stresses meaningful goals, planning steps, monitoring, self-talk
  and journaling. Private notes stay private.

## Rules applied to every mission (checked by `validate_catalogue()` and the tests)

* Done at home with free household things; no purchase, no app, no camera, microphone or location permission, no link.
* No scissors, knives, blades, fire, chemicals, cooking, climbing or going out alone; electrical, gas and hot things are
  explicitly left to an adult. Only light test objects; small items avoided for the youngest.
* No public posting, no contact with strangers, no real names of people in stories.
* No ranking or competition against other people; progress is compared with the child's own earlier attempt.
* Feelings missions never require sharing a reason or a diary; the parent check for teens asks only about the
  strategy, not the notes.
* 6-15 minutes each; a built-in "Another way:" line gives an accessible alternative (hearing, sight, movement, writing).
* Gujarati in Gujarati script, Hindi in Devanagari, English in plain ASCII; verified character by character in the tests.

## Known limits of this work

1. Gujarati and Hindi were written for this milestone and **need review by a native-speaking educator** before use.
2. Sources 3-5 above were not read in full. Re-check before citing them in any parent-facing material.
3. The skill, rationale and parent-involvement notes are not stored in the database (no column); they live in the catalogue
   source and the inventory document.
4. Superseded by C2: the catalogue now has six templates per theme (42). That supports a 42-day cooldown but is still not a year of fresh content.

## C2 expansion (14 to 42 templates): sources and status

### Review status of every source used in this milestone

| Status | Source | Notes |
|---|---|---|
| **Read in full** | Harvard Center on the Developing Child, *Enhancing and Practicing Executive Function Skills ... from Infancy to Adolescence* (2014) | Read in an earlier session (C1). **Not re-read in this session**; the C2 text relies on what C1 recorded from it (activity *types*: copy games, rounds and clapping rhythms, memory-location games, add-on and call-and-response games, I-spy style guessing, imaginary play, planning, perspective-taking for teens). No new quotation was added. |
| **Fetched page** | CASEL, *What is the CASEL Framework?* | Fetched 2026-11-19; definitions taken from the fetch tool's summary of the whole page. Used for Friday vocabulary only. |
| **Partially reviewed** | Harvard, *Brain-Building Through Play* landing page | Handout titles only; PDFs not opened. |
| **Not reviewed** | AAP clinical report on play (Yogman et al., Pediatrics 2018;142(3):e20182058); NAAEE early-childhood environmental-education guidelines (2010) | Access failed or never attempted (see the C1 table). No mission depends on either. |
| **Design assumption** | Everything tagged `design_assumption` below | The activity is this project's own design; no source was consulted for it. |

### What is a design assumption and what only borrows an activity *type*

Each template has an `evidence` tag in `app/content/daily_missions/activities.py` (checked by the validator):

* `guide_activity_type` (18 templates): the *kind* of activity is one the Harvard guide lists for practising a skill (for example clapping
  rhythms, memory-location games, imaginary play, perspective-taking). The tag says nothing about the specific wording, the age fit or any outcome.
* `design_assumption` (24 templates): written by this project with no source. These include the water, waste, routine and brainstorming
  missions on Sunday, the paper-engineering missions (shape strength, boat, shelter, weave), and the tempo, calm-words, listen-and-help,
  feelings-in-stories, pattern, list-trick, day-replay, sound-comparison, sound-words, story-order and new-ending missions.

Missions are opportunities to practise a skill. None claims to improve a skill, and no outcome is promised in any text.

### Small facts the new missions rely on

None was taken from a source; each is either arithmetic that was checked by hand or ordinary physics that the text never states (the child
predicts and tests):

| Mission | Fact the activity relies on | Basis |
|---|---|---|
| Pitch and Water Cups (Mon 11-15) | A tapped cup holding more water gives a lower note | Everyday physics; the answer is not in the text |
| Sound Barrier Test (Mon 11-15) | Soft and hard barriers change how much sound passes | The child rates and ranks; no value is asserted |
| Growing Patterns (Tue 11-15) | 1, 3, 6, 10 grows by +2, +3, +4 | Arithmetic |
| Steps and Claps (Sat 11-15) | Counts of 3 and 4 meet again after 12 steps | Arithmetic; the number is not in the child text |
| Folded Beam Challenge (Thu 11-15) | Folding can make paper stiffer | Everyday engineering; framed as a prediction to test |
| Cup Count, Home Water Check (Sun) | Water can be measured by catching it in a jug; clean rinse water can go on plants | Everyday practice; text forbids drinking collected water and using soapy water on plants |

### Safety rules added or restated for the new missions

* No scissors, knives or cutting: paper is **torn along folds**; the validator still blocks the restricted words in every language.
* Water missions: a grown-up stays beside the child (4-6 and 7-10), shallow basins on a towel, no glass cups, spills wiped, collected water never drunk.
* Waste missions: only clean, dry items handed over by a grown-up; the child never touches a dustbin, dirty waste, glass or sharp items.
* Friday missions: "a face is only a clue"; the child never decides what a real person feels or has; story characters replace real people;
  every sharing step can be skipped or passed; teen notes stay private and the parent check says not to read them.
* Household sound-makers: closed shakers are sealed by a grown-up with tape; volume is kept gentle.
* Routine and checklist missions: gas, electricity and locks are left to a grown-up.

### Native-speaker review

**No Gujarati or Hindi text has been reviewed by a native-speaking educator**, in either the first 14 or the 28 new templates. Script, numerals and
structure are machine-checked (Gujarati characters only in Gujarati, Devanagari only in Hindi, no Latin letters except the rhythm symbols X and O,
equal step and material counts, matching numerals). Wording, register, regional usage and cultural fit are **unreviewed** and must be reviewed
before the content is shown to children. The inventory records this status per language.
