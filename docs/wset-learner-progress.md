# Learner progress

Home → **Your WSET progress** separates required teaching, current fact mastery and recorded practice. All five study tracks are selectable: WSET Levels 1, 2, 3, Level 4 Diploma and CMS Certified. The progress view covers the four WSET levels; official exam results are separate learner declarations.

`WsetProgressRepository` derives progress from the installed knowledge items, cumulative study mappings, served question formats, shared review states, append-only review log and saved practice snapshots. It creates no curriculum facts and requires no schema migration. Counts come from the installed curriculum rather than a fixed release total.

The candidate **app 0.3.0+16 / dataset 0.23.0** bundles 119 registered curriculum includes, 3,781 factual items and 38 map layers. Its reviewed Level 1–3 study selections are:

| Level | Required topic rows | Distinct required facts |
|---|---:|---:|
| 1 | 49 | 132 |
| 2 | 442 | 752 |
| 3 | 888 | 1,625 |

These are cumulative app requirement groups, not official syllabus or examination counts. The [final outcome audit](research/wset-levels-1-3-final-outcome-audit.md) found no remaining mandatory instructional or exact-reference gap in this snapshot. Level 1–3 coverage completion metadata and final release acceptance are pending until the final delivery, regression and browser gates pass.

## Required and optional material

The app-owned `assets/progress/wset_scope.json` catalog links each Level 1–3 requirement to exact current lesson IDs, the teaching dimension and acceptable practice formats. Grapes, environment, production, style, labels and quality/price are separate from geographic location. Mastering a map pin therefore cannot substitute for a region's explanatory lessons. Required item IDs count once per level even when several requirements use the same lesson.

Required-material bars show available, studied and currently mastered facts. A required fact must be current, mapped at that level and served in a format accepted by each requirement that uses it. Missing, retired or unserved required lessons remain visible as unavailable gaps and block the study milestone; their review history is retained. Optional mapped material has a separate denominator and does not block a Level 1–3 milestone. A level without an explicit requirement catalog shows its available mapped material instead. Empty material has no percentage and cannot complete a milestone.

An unfinished requirement can start focused practice with its exact lesson IDs through the ordinary study planner. Study also searches assertion text, names and aliases without requiring accents, offers a topic filter, and retains each lesson's sources and memory state. Cumulative mappings let the same lesson and review state support each appropriate level without granting lower levels advanced-only content.

Shared-subject principle recall uses original point-specific questions with finite accepted responsive phrases. All 520 required shared points have cues; the 522-cue bank also includes two additional optional points. A sibling point or an unresponsive canonical lesson title cannot receive credit for the selected fact. This is finite phrase recall, not automated grading of an explanation. Written explanation pools separately use only current served points from the selected track and retain explicit self-assessment, including a valid one-point exercise.

## Current mastery and app milestones

A fact is studied after its first review. For current mastery it must be in the FSRS Review state, have stability of at least seven days and package-calculated retrievability of at least 0.90. It must also have Good/Easy reviews on at least three distinct UTC calendar dates spanning seven days, all after its most recent Again. Repeated taps or changes of question format cannot satisfy the date requirement. A failed reverse question or later memory decay can reduce mastery.

An **app study milestone** requires a nonempty scope explicitly marked complete, no unavailable required facts, every required fact currently mastered, every required topic internally reviewed, and all configured practice requirements satisfied. Mastering an incomplete available pack is a separate material milestone. These are study milestones, not WSET qualifications or predictions of an official examination result.

Level 1–3 scope and delivery are checked against the public specifications: Level 1 June 2022 Issue 1.2, Level 2 2026 Issue 2.1 and Level 3 May 2022 Issue 2. Completion metadata is published only after the outcome audit and delivery, regression and release gates close. The [completion plan](research/wset-1-3-completion-plan.md) and [delivery validation](research/wset-1-3-delivery-validation.md) record those checks. Internal scope review does not change a factual lesson's expert-review status; new facts remain unverified pending qualified review. Diploma's broader scope remains incomplete.

The screen refreshes after database changes and once a minute while visible. Its stable stream retains the previous result during refresh, serializes calculations and coalesces overlapping requests. The timer starts after the first successful result; Home uses a static initial loading message so optional progress calculations do not keep the interface animating.

## Recorded practice

Practice evidence measures participation and explicit self-review separately from shared FSRS memory. It does not infer correctness of written prose or an unknown physical wine, and does not write fact reviews or examination passes.

| Level | Practice required by the app study milestone |
|---|---|
| 1 | One completed original rehearsal with every multiple-choice question answered; three distinct completed calibration cases with observations and evidence |
| 2 | One completed original rehearsal with every multiple-choice question answered; three distinct completed calibration cases with observations and evidence |
| 3 | One completed original rehearsal with every multiple-choice question answered; four saved written responses with explicit self-review; three distinct completed calibration cases with observations and evidence; one completed timed two-wine practice |

Rehearsals use 220 original MCQs and twelve original Level 3 extended prompts, level-specific topic blueprints and the public assessment durations. Eligible MCQ pools are 65/190/220 questions for Levels 1/2/3. Presets sample 30 MCQs in 45 minutes at Level 1, 50 in 60 minutes at Level 2, and 50 MCQs plus four written prompts in 120 minutes at Level 3. Answers, prompt versions, explanations and written criteria are saved as snapshots. Feedback appears after the attempt ends. Written criteria support learner self-review, including an honest review with no criteria selected; they do not produce an official mark. Deadlines persist across restarts, and late or duplicate submissions cannot extend an attempt.

Three appended teaching grids and nine fictional calibration cases preserve the two historical grids and saved vocabulary. Required observations and evidence must be recorded before completing a calibration. Physical wine descriptions use the learner's observations, with no invented objective answer. Physical single-wine practice is optional for Levels 1–2. Level 3's timed two-wine practice saves both wines' observations, evidence and conclusions. Editing a completed physical tasting invalidates its guided completion evidence until the revised record is completed again.

The evidence reader checks current mapped lesson membership, completion timestamps, saved observations and calibration vocabulary. Valid retired practice remains readable but does not count toward current requirements. Malformed saved rows are handled individually, preserve their raw bytes for recovery and earn no completion credit; the progress view reports unreadable records while retaining valid history. Database failures still propagate. Backup and restore retain these records; erasing learner data removes them.

## Diploma and exam declarations

Diploma D1–D6 topic groups assign each mapped fact to at most one group. Explicit `itemIds` take precedence over selected regional facts, which take precedence over broad domains. Regional vineyard, winery and commercial lessons stay with D3 ahead of broad domain matching. Specialist production or business points can support D4/D5 without being treated as locations. Rutherglen's regional selector supplies location context because the region makes other wine styles; Douro is not automatically classified as Port. Dedicated fortified-production lessons are assigned explicitly to D5. Unassigned material is displayed separately.

Diploma's broader scope remains incomplete. Its groups measure supporting facts, not official unit completion. The original 704 D3 selectors remain intact. China's eight optional atlas references remain available, while its 44 analytical lessons remain Diploma-only. Wine history and other beverages are a separate sommelier strand and cannot inflate Award in Wines completion. Independently assessed tasting, written work and the Diploma research assignment remain outside fact-mastery counts.

Exam pass declarations are optional and labelled **self-reported**. `exam_pass_wset_l1` through `exam_pass_wset_l4` use the existing `user_settings` table. They can be checked or unchecked independently; a higher-level declaration does not set lower levels. Backup exports and imports these setting keys. Resetting study reviews retains settings; erasing all learner data removes declarations. No pass is inferred from app scores, practice participation or fact mastery.

## Validation and historical counts

The scope parser rejects contradictory completion/gap declarations, invalid or duplicate unit IDs, malformed or repeated unit item IDs, and invalid requirement dimensions or formats. Runtime checks reject unknown region/item selectors. Tests cover required versus optional counts, exact focused practice, cumulative memory, spaced dates, reverse failures, decay, unavailable facts, expiry, unit grouping, app milestones and independent exam declarations. Saved-practice checks cover restart and deadline handling, snapshot preservation, backup/erase, corrupt-history recovery, stale edits and the absence of FSRS or pass writes. Responsive navigation and controlled slow calculations check that Home loading settles, refresh retains visible data and unmounting cancels future calculations. Final release evidence belongs in the [delivery validation](research/wset-1-3-delivery-validation.md).

**Historical 0.20.7 snapshot, 27 September 2026:** that isolated audit had no Level 1 mappings, 103 cumulative Level 2 facts, 2,381 Level 3 facts and 2,885 Level 4 facts. All four completion flags were false in that snapshot. Its Diploma grouping included 704 D3 regional selectors, 58 D4 sparkling points and 57 D5 fortified points. Those are historical available-material counts, not current inventory or full syllabus denominators. The [0.20.5 business continuation](research/diploma-business-channels-continuation.md) records its 32 Diploma-only additions; the [0.20.7 numeric continuation](research/numeric-practice-continuation.md) adds objective presentations to 21 existing facts without changing fact denominators.

The public [Level 1](https://www.wsetglobal.com/qualifications/wset-level-1-award-in-wines), [Level 2](https://www.wsetglobal.com/qualifications/wset-level-2-award-in-wines), [Level 3](https://www.wsetglobal.com/qualifications/wset-level-3-award-in-wines) and [Diploma specification, August 2025 Issue 1.4](https://www.wsetglobal.com/media/17609/wset_l4wines_specification_en_august-2025.pdf) establish qualification scope. They do not endorse this app's authored lessons, mappings, practice or mastery threshold.
