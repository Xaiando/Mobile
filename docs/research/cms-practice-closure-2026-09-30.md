# CMS practice closure — 30 September 2026

This continuation is release 0.24.60, based on local release 0.24.59 and the frozen PR #44 head a77df27bfb27f5a3cc39337a1a37b996cd68b945. PR #44 and its workflow were kept unchanged; the frozen run has now completed successfully. The original checkout's uncommitted Antigravity/handoff files are preserved. This document retains the measured 0.24.60 snapshot; candidate 0.24.61 supersedes it for final validation, as described in the [current outcome audit](wset-levels-1-3-final-outcome-audit.md).

## Result and scope

The 68 measured CMS Certified core useful-practice gaps are closed without deleting or demoting facts, lowering the general format depths, or marking expert review complete:

- Seven complete service cases add objective matching for 28 existing action/reason/tradeoff/limitation items. They cover live cask condition, beer with a spiced curry, Belgian beer profiles, dressed oysters, chocolate with salted caramel, published Irish whiskey categories, and herbal versus orange liqueurs. Each case has four cited criteria and two scoped false claims. Actual bottle, guest and dietary checks remain explicit; suggested pairings are trials rather than guaranteed matches.
- 33 existing beer, cider, spirits, liqueur and food-pairing principles gain independent authored choices. The mash cue cites the AHA reference that explicitly supports starch conversion by malt enzymes. HMRC's cider reference is bounded to a UK duty definition; maker descriptions and BJCP style guidance are not universal legal definitions.
- Distillation retains its CMS Introductory core mapping at depth 1. An explicit Certified core override at depth 2 enables ordinary recall alongside its existing recognition question. Tests keep the general forward flashcard, typed and short-answer depth at 2.
- Six existing Loire product facts gain choices. The Cheverny white assertion is corrected using the specification approved on 5 December 2025: Sauvignon Blanc/Gris with permitted complementary Chardonnay, Chenin or Orbois, rather than mandatory Chardonnay. Approved Cheverny and Saint-Pourçain citations are registered. Broad red profiles do not impose red blend requirements on every rosé. An opposition proposal is not treated as adopted law.
- The diagnosed Itata question failure is repaired with distinct quantitative, suitability and legal-recipe distractors. Correct index 3, correct-answer length rank 2, citations and the strict absolute-wording test are preserved.

All 4,380 assertions remain expert-unverified. The published Irish technical-file distinctions are supported, but independent confirmation of any current EU amendment adoption remains open. Editorial track mappings are study decisions, not official examination approval.

## Measured delivered coverage

The baseline was generated from delivered practice at the release publication instant, 2026-09-29T23:41:02.013Z. Local Oslo calendar date is 30 September.

| Track | Mapped items | Core useful / core |
| --- | ---: | ---: |
| WSET Level 1 | 132 | 132 / 132 |
| WSET Level 2 | 829 | 748 / 748 |
| WSET Level 3 | 3,439 | 2,232 / 2,232 |
| WSET Level 4 | 4,127 | 2,853 / 2,853 |
| CMS Certified | 2,902 | 1,247 / 1,247 |

CMS service is 181/181 core useful and geography is 776/776. CMS structured availability rises from 44 to 72; recognition rises by 39 and recall by one. These are authored-item denominators, not a measurement of the entire official syllabus. Existing core mappings and all spatial practice remain intact. Diploma completion and all six unit acceptance gaps stay explicitly incomplete.

## Validation evidence

- Curriculum lint: zero errors, three existing warning classes across 236 included files (2,199 uncurated effective dates; 150 structural relations; 4,380 expert-unverified assertions).
- Five-track delivered coverage baseline: zero known blocking gaps, unchanged WSET core totals and complete authored CMS core useful practice.
- Six affected regression files: 23/23 passed in 2:09, including exact 1,717 selected authored questions from 83 templates, source-linked delivery, Introductory/Certified depth, cold-case ineligibility, legitimate role reviews before full-case practice, and independent correct/incorrect grades.
- Earlier release 0.24.59 release browser smoke: all ten stages passed; no page/console/request errors. It checks paired deadlines and separate wine observations, rehearsal persistence, five-track navigation, narrow layout, and cellar manual/photo label proposals. It does not establish physical mobile camera/OCR performance.
- Local 0.24.59 and 0.24.60 full suites were interrupted by the PC restart; neither has a final full-suite success. The 0.24.59 log exposed the single Itata distractor failure repaired in 0.24.60. Completed focused checks and the final no-issues static analysis remain valid for their tested snapshots.
- Frozen PR #44 completed all five hosted jobs successfully. Its final test log reports 1,293 passing tests at 2026-09-29T23:56:38.0496084Z; this validates head a77df27, not later local content.
- Candidate 0.24.61 is the resumed integration. Its quality-focused regression passed 12/12; remaining candidate validation is pending and recorded separately by root.

The initial CMS test run exposed two fixture errors: cases were presented before their required co-items were studied, and the aggregate choice fixture classified new CMS IDs as old Level 3 IDs. Repairs preserve eligibility checks and every grade assertion. An attempted concurrent Dart linter launch encountered a Windows native sqlite DLL lock; the sequential retry succeeded. No OS settings or test assertions were weakened to avoid that lock.

## Frozen CI diagnostic checkpoint

PR #44's test step began 2026-09-29T21:29:52Z. At two hours, progress was initially unknown because the browser required login; API `in_progress` alone was not treated as progress. After user login, actual passing test lines became available. At 23:38 UTC, the latest visible timestamped pass was `reasoning_integration_test.dart: a studied support outside the track removes target reasoning availability`, timestamp 23:37:09 UTC, log line 1128. This line number is not a test count.

At the subsequent scheduled checkpoint, live DOM and screenshot showed coverage/baseline/architecture/backup passes through log line 1390, including `user_data_backup_test.dart: a corrupt photo refuses import before replacing any rows`. The latest visible timestamped baseline pass was 23:49:31 UTC. The native accessibility tree was stale; its old line numbers were not used to infer a stall. At that observation, the exact completed count remained unknown; the final log below resolves it.

An earlier local 0.24.58 concurrent expanded log reported coverage-report tests between 43:00 and 51:56 (~8m56 of reporter time); it does not establish individual hosted durations. Several study tests also ingest the full bundle in per-test setup, a concrete potential runtime cost as content grows. No hosted-current-test position or hang is inferred from local elapsed labels.

At the checkpoint, the workflow had no custom timeout. [GitHub's hosted job maximum is six hours](https://docs.github.com/en/actions/reference/limits); the 21:27:28 UTC job start left approximately 3h49m at 23:38. That was a budget, not an ETA. Five-minute checks preserved the head and workflow without unchanged-status narration, skips or weaker assertions.

The final log was inspected after completion: the test step ran from 21:29:52 to 23:56:38 UTC and finished with 1,293 passing tests at `2026-09-29T23:56:38.0496084Z`. The retained local record is `D:/Apps/Sommelier study companion/build/resume-ci/pr44-final-test.log`. All five jobs in [run 36633382422](https://github.com/Xaiando/Mobile/actions/runs/36633382422) succeeded for the same frozen head. No further polling of this completed run is needed. The earlier progress observations and two-hour diagnostic checkpoint remain historical evidence, rather than indications that the job is still running.

## Remaining acceptance work

The resumed named WSET Levels 1–3 crosswalk identified the label, sensory-condition, quality-conclusion and required-geography corrections recorded in the 0.24.61 outcome audit; its current delivery validation remains pending. Authored coverage does not settle expert sufficiency, physical tasting performance, Diploma commercial/production depth or current-law review. Fine atlas boundaries still require defensible licensed geometry, and the mobile cellar camera/OCR path still needs physical Android/iOS evidence. Official qualification and self-reported exam outcomes must remain separate from app study progress.
