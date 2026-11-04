# Videos stored with the unsupported 4-12 age band

Read-only report generated 2026-11-04 12:20 UTC from the production database. **No record was modified.**
Supported bands are 3-5, 6-8, 9-12 and 13-15 (see `docs/youtube-operations.md`, section 3, for the strategy).
The "starting-point band" column is a heuristic from the topic, offered only to speed up a human decision. A reviewer must watch and confirm each video.

## Summary

| Status | Videos at 4-12 |
|---|---|
| Approved and published | 5 |
| Pending review | 34 (11 from a trusted channel, 23 from other channels) |
| Quarantined | 50 (blocked by screening; a band is irrelevant until the flags clear) |

Earlier readings said 35 pending and 24 non-trusted. The figures are now 34 and 23: one pending video was acted on in the admin panel after the first reading (see the audit-log summary in the release checklist).

## A. Approved and published at 4-12 (5): needs a per-video decision

These are visible to children aged 4-12 today. Moving a video to one band only narrows its audience.

| # | YouTube id | Title | Channel | Topic | Length | Lang | Starting-point band (to confirm) |
|---|---|---|---|---|---|---|---|
| 1 | sSAsJ5pHQ0k | English Stories For Kids / The Cap Seller And The Monkeys / English St | Anon Animation Rhymes for Kids | stories | 2:23 | en | 3-5? |
| 2 | c8EO32b6bzA | Visualising Surface Tension / Science Experiments at Home / #Experimen | BYJU'S | science | 0:59 | en | 6-8? |
| 3 | o04HM1InBIM | Learn Colors🔴🟠🟡🟢🔵🟣 with Balls! Uh oh! Catch that ball! #shorts #cocome | Cocomelon - Nursery Rhymes | academic_explainers | 0:22 | en | 9-12? |
| 4 | HsXaVV6fFDY | Unplugged - What is Computer Science? | CodeAI | coding | 2:05 | en | 9-12? |
| 5 | NYQl9-5FpQM | Intro to Cool Science Experiments / Nat Geo Kids Cool Science Experime | Nat Geo Kids | science | 1:19 | en | 6-8? |

## B. Pending, from a trusted channel (11): no manual band needed

All trusted channels are 3-5. When one of these is approved (automatically or by hand) it takes the channel's band, replacing 4-12.

| # | YouTube id | Title | Channel | Topic | Length | Lang | Starting-point band (to confirm) |
|---|---|---|---|---|---|---|---|
| 1 | jlnSo2uDNps | Toddler Learning Videos For 5 Year Olds / ABCs, 123s Shapes, and Nurse | Bairn Learning | early_learning | 543:47 | en | 3-5 (channel's band) |
| 2 | 9M4wV4B5fUI | Toddler Learning Videos For 5 Year Olds / ABCs, 123s Shapes, and Nurse | Bairn Learning | early_learning | 112:18 | en | 3-5 (channel's band) |
| 3 | ZF2NHhCR9o0 | Toddler Learning Videos For 5 Year Olds / ABCs, 123s Shapes, and Nurse | Bairn Learning | early_learning | 98:05 | en | 3-5 (channel's band) |
| 4 | Uuk974lF2gw | Toddler Learning Videos For 5 Year Olds / ABCs, 123s Shapes, and Nurse | Bairn Learning | early_learning | 714:59 | en | 3-5 (channel's band) |
| 5 | JlImzTL0IUA | Toddler Learning Videos For 5 Year Olds / ABCs, 123s Shapes, and Nurse | Bairn Learning | early_learning | 715:00 | en | 3-5 (channel's band) |
| 6 | jpQnKYXr1vo | Learning About Nature On A Hike With Blippi / Educational Videos For K | Blippi - Educational Videos for Kids | nature | 16:14 | en | 3-5 (channel's band) |
| 7 | NLEJ_flShDo | Train Chook Chook Song + Wheels On The Bus / Emma And Joey - Nursery R | Emma And Joey - Nursery Rhymes | early_learning | 7:37 | en | 3-5 (channel's band) |
| 8 | TNnpeDEH5Lg | Your Toddler Will Ask for This Potato Every Day #toddlers | Emma And Joey - Nursery Rhymes | early_learning | 0:19 | en | 3-5 (channel's band) |
| 9 | DCNtW4dCg4I | English Stories for Kids / Learning Stories / Tia & Tofu / Best Storie | T-Series Kids Hut | stories | 38:11 | en | 3-5 (channel's band) |
| 10 | AjZBZFuos8Q | THE WISE CHILD : Learning Lesson for Kids / Tia & Tofu / English Stori | T-Series Kids Hut | stories | 6:39 | en | 3-5 (channel's band) |
| 11 | Ejj6V_9pCH0 | School Routine with Mom & Child / Kindness Story for Kids / Easy Engli | This Story English | stories | 8:08 | en | 3-5 (channel's band) |

## C. Pending, from other channels (23): approve by hand with a chosen band

Approving by hand forces a choice of one of the four bands. Automatic approval will not publish these unless `YOUTUBE_AUTO_PUBLISH_AGE_BAND` is deliberately set, and then it applies that single band to all of them.

| # | YouTube id | Title | Channel | Topic | Length | Lang | Starting-point band (to confirm) |
|---|---|---|---|---|---|---|---|
| 1 | YLmTvwjJ9qo | Educational Video for Kids / Animal Video for Kids / Atrin & Soren Exp | Atrin and Soren with Nikan | nature | 6:57 | en | 6-8? |
| 2 | 0AWi3JL1jhU | How to Build a Rocket / Science Experiments for Kids /  #DIYRocket | BYJU'S - Class 6, 7 & 8 | science | 0:54 | en | 6-8? |
| 3 | 91O6GELfdhI | ABC Toddler Learning I Educational Videos, Kids Songs, Cocomelon Style | BlinkBlink TV - Kids Songs & Cartoons | early_learning | 0:11 | en | 3-5? |
| 4 | XPFSLhUHSX4 | Learn Math for Kids / Adding with Monster Trucks by Brain Candy TV | Brain Candy TV | math | 5:14 | en | 6-8? |
| 5 | tUjOL_Nk6uo | The Lion, The Mouse and The Sleepy Bear / Bedtime Stories for Kids / A | Fairy Tales and Stories for Kids | stories | 8:07 | en | 3-5? |
| 6 | gJpcvTNlfOE | How to Teach Numbers to Preschoolers #shorts #earlychildhoodeducation  | Intellakids | early_learning | 0:23 | en | 3-5? |
| 7 | oTjySm7mgZE | Explore Nature / Nature for Kids / Learn Nature Vocabulary / Kindergar | Joyful Start | nature | 7:33 | en | 6-8? |
| 8 | e4-iAyyzIfA | 🎨 Learn Colors and ABCs with Fun Alphabet Phonics for Kids and Toddler | Kids Happy ABC | early_learning | 12:42 | en | 3-5? |
| 9 | o1DfLzBEty4 | Assessing Early Literacy Skills: Kindergarten 1 Milestones Uncovered | Mommy Tutors | early_learning | 2:20 | en | 3-5? |
| 10 | s0pJXkTsi3k | 🖥 What is Coding? / Computer Science for Kids Part 6 / Grades K-2 | Ms. Dorismond's Virtual Corner | coding | 5:20 | en | 9-12? |
| 11 | mjlsSYLLOSE | Basic Math Addition For Kids / Noodle Kidz Pre-K and Kindergarten Educ | Noodle Kidz | math | 7:01 | en | 6-8? |
| 12 | HaEmIakO7f4 | Natural Disasters compilation / The Dr. Binocs Show / Best Learning Vi | Peekaboo Kidz | nature | 21:54 | en | 6-8? |
| 13 | _yH3BntZCSI | Why Is Ocean Water Salty? / Earth's Ocean / Dr Binocs Show / Peekaboo  | Peekaboo Kidz | nature | 4:58 | en | 6-8? |
| 14 | 7yDDSornHow | Best Learning Numbers, Shapes & Counting 1 - 10! Preschool Toddler Lea | Quinn's Playhouse - Kids Learning Videos | math | 8:45 | en | 6-8? |
| 15 | 1Q_4HXewiS0 | 4 Amazing Science Experiments for a Day Inside / Compilation / SciShow | SciShow Kids | science | 17:09 | en | 6-8? |
| 16 | UqCQsKxq4mY | Making a Fountain of Soda! / Summer Experiments / SciShow Kids | SciShow Kids | science | 4:55 | en | 6-8? |
| 17 | KJXd73u1g2c | PROGRAMMING for Kids 👦 What is Programming? What About Algorithms? 💻 C | Smile and Learn - English | coding | 9:47 | en | 9-12? |
| 18 | _j4Lj-BT00g | PROGRAMMING for kids 👦 Basic concepts 💻 Part 1 | Smile and Learn - English | coding | 4:28 | en | 9-12? |
| 19 | hgUnttJs1Vk | Power of Habit - English Stories For Kids / Moral Stories In English / | Sonic Octaves Kids | stories | 4:01 | hi | 3-5? |
| 20 | CmY-GqKGmgQ | 3 Easy Colorful Science Experiments For Kids / Sema's Lab | Super Sema | science | 8:18 | en | 6-8? |
| 21 | FMjwq1E0Lg0 | ABC Song for Kids / Learn A to Z Alphabet / Phonics Song / ABC Learnin | Tiny Hero Tales | early_learning | 2:01 | hi | 3-5? |
| 22 | i4CPSH6eQWE | The Very Hungry Caterpillar / Bedtime stories for kids / Fairy tales f | Twinkle Tales Time | stories | 4:57 | en | 3-5? |
| 23 | UZnork__OnU | What Does MORAL Mean? / Word Explainer for Kids | Wordsmyth | academic_explainers | 3:29 | en | 9-12? |

## D. Quarantined at 4-12 (50)

Not listed individually. 47 are marked not made for kids by YouTube and 4 carry a keyword flag.

Caution on the heuristic: it only looks at the discovery topic. For example the Cocomelon colours video was discovered under `academic_explainers` (which maps to 9-12) but is a toddler channel and almost certainly 3-5. Treat the column as a prompt, not an answer.
