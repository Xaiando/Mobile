# PR 45: native CI diagnostic basis

Prepared 30 September 2026, approximately 11:45 UTC. This is a diagnostic record, not a CI pass or a claim that current progress is known beyond the cited observation. It was written only in the future CMS worktree. The current workflow and PR head remain unchanged.

## Run identity and observed progress

- Pull request: [PR 45](https://github.com/Xaiando/Mobile/pull/45).
- Workflow: [run 36708753882](https://github.com/Xaiando/Mobile/actions/runs/36708753882).
- Recorded head: `42bcb6f997c7df69a9ed5cba1c0af7130729fb46` (local read-only object resolution confirmed the full hash).
- The owner observed the native `flutter test` step begin at **11:31:09 UTC** on 30 September.
- The owner's browser-log capture at **11:41 UTC** exposed **97 named passing events**, most recently `test/tool/coverage_report_test.dart: refuses a policy that leaves out a relation type`. The exposed count is not established as the complete reporter total; per-test timestamps were not shown. Neither a percentage nor an ETA can be calculated from this visible subset.
- The initial job metadata records the Analyze-and-test execution start at **11:28:30 UTC**. Android and iOS have passed; Windows and web have failed, according to the owner's completed-job log captures. Native analysis/test completion remains pending in this record. Completed logs are retrievable through the job-log REST endpoint even while the overall workflow is unresolved; a withheld `gh run --log` is not proof that every job log is unavailable.
- The timestamp above is an observation time, not the execution time of the last displayed test. No later browser progress was inspected for this note. Later progress, the current active test and its exact start time therefore remain **unknown** until another bounded capture supplies them.

Named test events are actual progress evidence. A status value such as `in_progress` alone is not. Future captures must record the observed UTC time, last visible full name, visible count and whether the view is complete or virtualized; record unavailable per-test timestamps explicitly. If the latest name/count is unchanged, retain the record silently rather than narrating another unchanged status.

## Preserved local passing evidence

The exact local NEXT candidate `aa4aae33218b8a56e639a4b99744b73a5ad772f8` completed its full native suite at **11:24:38 UTC**, with **1,395 passing tests, zero failures**, and **68m56s wall time** as recorded by the owner. This local result does not establish a hosted CI outcome at the PR head.

The preserved log is `C:/Users/Kaged/.codex/worktrees/companion-acceptance-next/Sommelier study companion/build/full-suite-d3-scanner.log`. Its SHA-256 at this inspection was `D52E740DA9EA8509A4ED3945447EE652460C4ABF89D02F051C2A3D2859D51F91`. The final reporter line is `68:51 +1395: All tests passed!`; the reporter clock and wall-clock wrapper differ by about five seconds. Do not replace the recorded wall duration with the reporter timestamp.

### Corresponding coverage evidence and its limits

The exact latest CI name has a local matching displayed label at `64:06 +1385`: `test/tool/coverage_report_test.dart: refuses a policy that leaves out a relation type`. The preceding event is `62:32 +1384`, a 94-second gap; the following event is `64:47 +1386`, a 41-second gap. Neither boundary is a measured exclusive start/end for that named test. The local concurrent reporter also names bundled coverage setup at `01:05 +64` through `01:15 +82`, retaining `(setUpAll)` while counts increase. Do not turn these interleaved labels into per-test timings.

The related `test/tool/coverage_report_test.dart` family does have the following reporter intervals. Each row is an interval between observed global events, not an exclusive stopwatch duration or a proof of which test was executing throughout it.

| Previous reporter event | Next reporter event | Gap | Next displayed label |
| --- | --- | --- | --- |
| `61:19 +1383` | `62:32 +1384` | 73 seconds | `--update-baseline keeps the known gaps still open` |
| `62:32 +1384` | `64:06 +1385` | 94 seconds | `refuses a policy that leaves out a relation type` |
| `64:06 +1385` | `64:47 +1386` | 41 seconds | `refuses what it cannot do` |
| `64:47 +1386` | `65:29 +1387` | 42 seconds | `scope objectives (SCOPE-1) are reported for each track, as Markdown and JSON` |
| `65:29 +1387` | `67:41 +1388` | 132 seconds | `scope objectives (SCOPE-1) lint checks the manifest against the release and the backlog` |

The suite runs concurrently; the inspected coverage-report test calls `coverageReport` in the same process against a copied manifest. The log interleaves other feature/tool tests with these labels. The 132-second interval is the largest observed gap ending at a coverage-family event; calling that test the uniquely slowest test would overstate the evidence. The log demonstrates that this family can involve lengthy report/lint work and that the full local run eventually passed. It does not explain a silent hosted job indefinitely or predict its remaining duration.

## Runtime budget verified from official documentation

At the recorded PR head, `.github/workflows/ci.yml` defines `checks` / “Analyze and test” with `runs-on: ubuntu-latest`, a `flutter test` step and **no `timeout-minutes` override**. It was read from the supplied local Git object; no workflow file was changed.

GitHub documents a default job timeout of **360 minutes** when `jobs.<job_id>.timeout-minutes` is omitted. A step-level timeout, when configured, is separate; this workflow does not configure one. [GitHub workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idtimeout-minutes).

GitHub also documents a **six-hour execution limit for hosted jobs**, after which the job is terminated. This is a job limit, not a promise of six further hours for a later test step. [GitHub Actions limits](https://docs.github.com/en/actions/reference/limits#existing-system-limits).

The initial diagnostic record used the estimated `J = 11:28:30 UTC` (superseded by the exact API start correction below), so the documented six-hour job deadline is **17:28:30 UTC**, conditional on that original execution and the unchanged workflow. Remaining job budget at any observation `O` is `17:28:30 − O`, never six additional hours from the native test step. Earlier checkout, SDK, generation and analysis work already consumed **2m39s** before the 11:31:09 test start. Queue time or a different job's start must not replace this execution start.

At the scheduled two-hour test-step checkpoint, **13:31:09 UTC**, the default job budget would be **3h57m21s remaining** if the job is still executing. This is a limit-based budget, not an ETA or proof of progress. Revalidate job identity/metadata at the checkpoint; do not reset this deadline in response to elapsed time.

## Scheduled checkpoint and bounded next action

The two-hour **test-step** diagnostic checkpoint is **13:31:09 UTC on 30 September 2026**. It is not an automatic cancellation deadline.

Use five-minute observations. From the supplied 11:41 capture, the next scheduled observation is 11:46 UTC, then every five minutes while the step remains unresolved. A single checkpoint action should inspect the existing native browser log, record any newly exposed test name/count and available timestamps, and confirm the recorded job execution identity and budget if a diagnostic checkpoint requires it. Do not repeatedly query unchanged status between checkpoints. Report only a result, a concrete diagnostic finding, or the scheduled checkpoint.

At 13:31:09, assess these three dimensions together:

1. **Progress:** compare the latest bounded capture with the prior name/count. New events are observed progress; unchanged or inaccessible logs leave active test progress unknown. If only `in_progress` is available, write “progress unknown” explicitly.
2. **Correspondence:** identify the exact latest CI test before comparing with the local log. Use the intervals above as family context, with their concurrency caveat. If its local event is absent or ambiguous, retain that limit rather than claiming an exclusive duration.
3. **Budget:** use the actual job start and the documented limit. For this original execution, the recorded default deadline is 17:28:30 UTC; if its job identity/start cannot be revalidated, mark that uncertainty explicitly. Do not continue extending a justification solely because more time has elapsed.

If progress cannot be observed, the bounded next action is **one further existing-log/job-metadata inspection after five minutes** (13:36:09 for the two-hour checkpoint), keeping the head/workflow intact. Persist the unknown status and capture limit; an unchanged observation is not new evidence. New diagnostic action requires a concrete failing event, error, budget constraint or final log, not elapsed time alone.

When the job concludes, inspect and preserve the final native log, its conclusion, failing names/stacks if any, final pass count and source/run identity. Keep the passing local log and previously passing checks. Do not skip tests, weaken assertions, push speculative changes, cancel for the two-hour threshold or restart the whole workflow to obtain a faster result. This document neither changes those instructions nor grants an approval/pass claim.

## Windows onboarding handoff diagnosis and future test repair

The preserved completed-job log `C:/Users/Kaged/.codex/worktrees/companion-acceptance-next/Sommelier study companion/build/ci-pr45-windows-job.log` records startup ready after 97.885 seconds, then at **11:33:21 UTC** the integration test fails because `find.text('Practice')` finds zero widgets at `integration_test/app_test.dart:120`. Startup had passed its existing 180-second bound; this is a subsequent navigation observation failure, not evidence that startup needs a larger timeout.

Source evidence: `OnboardingScreen._finish` awaits `completeOnboarding` before calling the router; `settingsProvider` independently observes saved settings through a native Drift stream, and the router's redirect reads that emitted state. Track selection similarly enables “Start studying” only after the profile watch emits. `pumpAndSettle` observes an idle frame queue; it does not establish that either native write/watch handoff has completed. The log proves the missing destination at the tap, while source identifies the unguarded asynchronous seam. It does not prove permanently broken production navigation.

The future CMS worktree's integration test now waits, with the existing bounded `pumpUntil`, for the enabled `FilledButton` before tapping “Start studying”, then for a hit-testable “Practice” label inside the real `NavigationBar` or `NavigationRail`. It additionally asserts one destination before tapping. The startup 180-second limit, 90-second diagnostic checkpoint, helper's default bounds, original study choice/flashcard checks and actual tasting/save assertions are unchanged. No production route, settings, database or workflow code was changed. PR45 head remains unchanged; the failing log is preserved.

At this initial record, the repair was **not yet runtime-validated**. That historical status is superseded by the measured local future-candidate Windows result below. The test uses its isolated `integration` database; the actual outcome is recorded separately from the original hosted CI failure.

## Measured continuation: 12:42:32.462 UTC

The owner's bounded native browser-log observation at **12:42:32.462 UTC on 30 September 2026** exposed **`core/curriculum/curriculum_dataset_test.dart: rejects an unknown section`**, with a displayed test-log timestamp of **12:35:49 UTC**. The view showed **50 events in a virtualized visible subset**; the cumulative reporter total and complete count remain **unknown**. This subset must not be compared with the earlier 97-event view as though the total regressed. Observation time and displayed test time are separate.

The newly exposed named event is actual progress evidence. The preserved preceding checkpoint at 12:35:33.746 UTC had exposed `core/curriculum/cms_loire_geography_test.dart: named municipality markers keep their qualified source coordinates`, timestamped 12:35:20 UTC. The new completion is later than that checkpoint; neither visible subset is a cumulative count. The currently executing test, its start time and progress after 12:35:49 remain unknown from this view. Receiving `in_progress` alone would add no test-progress evidence. The next scheduled observation is **12:47:32.462 UTC**, retaining five-minute polling and quiet treatment of unchanged status. This entry records supplied evidence and issued no additional CI query.

The two-hour test-step checkpoint remains **13:31:09 UTC**, the original job deadline remains **17:28:30 UTC**, and its documented budget at that checkpoint remains **3h57m21s** if this same job is still executing. Earlier observations and scheduled actions above are historical records. The checkpoint is diagnostic, not an automatic cancellation deadline. PR 45 head `42bcb6f997c7df69a9ed5cba1c0af7130729fb46` and run `36708753882` remain unchanged.

## Canonical unchanged-build browser diagnostic

A separate **diagnostic-only** browser run from **12:26:50.449 to 12:35:39.764 UTC** passed all **12 original stages**, with zero page errors and zero console errors. Stage 11 took **246,406 ms** across its original D4/D5/D3 actions and reloads. The hosted D4 Back freeze was **not reproduced**. This comparison is not a hosted CI pass or final acceptance result.

The preserved artifact was `C:/Users/Kaged/.codex/worktrees/companion-acceptance-next/Sommelier study companion/build/d3-web-offline`; `main.dart.js` SHA-256 remained identical before and after: `69F47DBFEFB92DE1901DC980A532D7A9BE9E334C848914027912D27460411918`. Generator restoration verified the original **12 stages, 65 assertion sites, 12,000-ms action bound and 300,000-ms startup bound**. `createRequire` stayed anchored to the original `tool/web_smoke/app_ui.mjs`. Message forwarding retained the native receiver, original arguments and transfer lists through `Reflect.apply`; passive listeners did not start/close application ports or alter application logic. Only ignored build artifacts were written.

Worker initialization selected **`opfsLocks`**. At the first D4 pre-reload checkpoint, **12:30:35.995 UTC**, there were zero pending observed requests and **529 matched nested-control commit requests / successful replies**. Last three `user_settings` upserts before that checkpoint:

| Port/request | Request UTC | Successful query reply UTC | Matched nested-control commit success |
| --- | --- | --- | --- |
| `port4 / 4364` | `12:30:35.386` | `12:30:35.390` | request `4365`, `12:30:35.393` |
| `port4 / 4371` | `12:30:35.404` | `12:30:35.408` | request `4372`, `12:30:35.411` |
| `port4 / 4378` | `12:30:35.423` | `12:30:35.426` | request `4379`, `12:30:35.429` |

These specifically match Drift request payload `5`, control `1`, and successful responses. A received query response alone was not counted as a commit. Protocol commit acknowledgement is not independent durable-storage/`fsync` proof. Omitted argument contents prevent attribution to particular questions or setting keys.

The passive DOM observer captured **no labeled Back event**. Exact Back UTC and Flutter `endOfFrame`/pop phases are **unknown**. A checkpoint rAF callback at **12:30:05.190 UTC** was not Back-specific and does not prove Flutter frame completion. Original WSET-progress and Home assertions passed before the first D4 reload checkpoint. The startup ring evicted early records, preventing absence inferences about those records. No assertion failed, so post-failure retention was not exercised.

No freeze, lock failure or transaction deadlock is evidenced. This non-reproduction warrants neither an application transaction change nor longer assertions. On a later unchanged-runner failure, the bounded next diagnostic is intent/return checkpoints around its existing Back action and at most one minute of passive message/visibility/frame observation, with original deadlines and no second click or reload. Do not restart CI or change the PR head for this evidence.

Artifacts remain under ignored NEXT `build/d4-back-diagnostic/`: `output/summary.json` records bounded findings; `output/diagnostic.json`, `output/result.json`, `run.log`, `creation.json`, generator, runner and screenshots preserve the raw evidence. SHA-256 values are:

- Observer JSON: `499EBA490C768AFD2DECDB465F8AA8A73596B5824F7820BD70B54ABE9B9CED41`.
- Diagnostic-only original results: `78AF6551EEDB86FFA7ED26031E4AF8281138706CB70FDA620BCD942E4D137A8F`.
- Run log: `95FC9001ED3F14DC0C3C99B0B7EF5611800709E3A68FFE5E4578475CE1F391B6`.
- Generator: `0C35A1CB16275582E4DCFEDEA133EA30D293C71911BFF7E39D6AA081762C3836`.

Original local full-suite passing evidence, Android/iOS job results, hosted Windows/web failures and pending native CI conclusion remain separately preserved.

## Two-hour test-step checkpoint: exact job-start correction

The scheduled checkpoint was **13:31:09 UTC on 30 September 2026**. The preserved API response `NEXT build/ci-pr45-native-job-two-hour.json` identifies job **109865215598**, run **36708753882**, attempt **1**, head **`42bcb6f997c7df69a9ed5cba1c0af7130729fb46`**, and exact job `started_at` **11:28:29 UTC**. The earlier 11:28:30 value was an estimate corresponding to the setup-step timestamp; it is superseded for runtime budgeting, not a new execution or extended deadline.

The corrected six-hour deadline is **17:28:29 UTC**, with **3h57m20s remaining at the scheduled 13:31:09 checkpoint**. The test step still began at 11:31:09, after 2m40s of job execution. The response retained `in_progress`/no conclusion for the job and test step; these statuses alone establish no test progress.

At **13:32:26.562 UTC**, one browser reload followed by expanding details/timestamps exposed an **older** chunk: `features/study_flow_test.dart: a session from Home: answers grade items and advance the queue (TASK-006, TASK-007)`, timestamped **11:55:04 UTC**, with **50 visible events**. The previously exposed latest completion remains `core/curriculum/typed_cue_reference_test.dart: retired supporting relations remain valid references for preserved history`, timestamped **12:40:33 UTC** at the 13:27:47.937 observation. An older virtualized chunk is not later progress or a regression in the cumulative count.

**Current active progress and cumulative passed count remain unknown.** The checkpoint record was saved at 13:33:53.6158586 UTC in `NEXT build/ci-pr45-checkpoints.jsonl`; capture time, displayed completion time and record-save time are distinct. The bounded next action is one existing-log observation at **13:37:26.562 UTC**, five minutes after the browser refresh, then inspect the final native log when available. No cancellation, workflow restart, speculative push or head change follows from crossing two hours.

### Local comparison at this checkpoint

The exact exposed retired-reference name and all `typed_cue_reference_test.dart` labels are absent from the preserved concurrent local reporter text. Its exact local counterpart time, count and exclusive duration are **unavailable**. Source `test/core/curriculum/typed_cue_reference_test.dart:172` does contain the exact test; it synchronously validates a small authored fixture, with no database, awaited I/O, timer or full bundled ingestion. This source inspection does not measure hosted runtime or identify the currently executing test. Absence from the interleaved reporter is not evidence of a skipped test.

Supplementary displayed typed-family intervals are:

| Global reporter interval | Gap | Ending displayed label |
| --- | --- | --- |
| `28:57 +959` → `29:05 +960` | 8 seconds | `typed_format_test.dart: a synonym or another correct answer counts (QF-8)` |
| `32:00 +1001` → `32:06 +1002` | 6 seconds | `typed_format_test.dart: part of the answer is Hard, unless it names something else` |
| `56:05 +1349` → `56:17 +1350` | 12 seconds | `typed_practice_test.dart: a wrong answer shows the right one` |

These are separate tests, not exact retired-reference counterparts. The 12-second gap is the largest ending at a displayed typed-family label, not an exclusive duration. Other families appear immediately around them. The longest global reporter intervals remain **132 seconds** (`65:29 +1387` → `67:41 +1388`, coverage scope lint), **94 seconds** (`62:32 +1384` → `64:06 +1385`, coverage-policy refusal), and **73 seconds** (`61:19 +1383` → `62:32 +1384`, coverage baseline). They are interleaved global gaps and cannot establish uniquely slowest tests or explain the hosted silence.

The log remains byte-unchanged at SHA-256 `D52E740DA9EA8509A4ED3945447EE652460C4ABF89D02F051C2A3D2859D51F91`, ending `68:51 +1395: All tests passed!`. Preserve that local passing evidence while hosted completion remains pending.

## Future candidate: measured local Windows integration acceptance

The future CMS/D2 candidate's real Windows integration test now passed **1/1**, using its isolated `integration` database. The preserved log is `build/cms-d2-windows-junction-integration.log`, SHA-256 **`EC13A89AB667BEB086D89AF5751544214C29206ECF84E0A7EC06D002E6FD17F4`**. It records `STARTUP_READY after 0:00:53.331726` and final **`00:59 +1: All tests passed!`**. The wrapper metadata records execution from **13:06:35.7757883 to 13:08:30.6070612 UTC**, exit code 0; wrapper/build time and reporter time are different clocks.

The first local invocation failed before loading the test because Windows symlink creation privileges were unavailable. Its log remains `build/cms-d2-windows-integration.log`, SHA-256 **`AA88D53ABF2F416C920567DA0D19D00CB68D6CC332302A740650BAB5AAE0A89F`**. It is preserved rather than overwritten. The subsequent local preparation created only **five junctions for already-present pinned pub-cache plugins in ignored ephemeral build paths**; Flutter's `Link.exists` recognized them. No operating-system setting, installation, workflow, assertion or test deadline was changed.

The pass exercised the real app startup, curriculum installation, guarded saved-onboarding transition to actual main Practice navigation, the original choice/flashcard study branch and actual tasting/save checks. Earlier startup180s/diagnostic90s/default90s bounds remain unchanged. This local future-candidate result supersedes the earlier “not yet runtime-validated” status of that guard. It does not change the original hosted Windows failure, establish the precise cause of that failure, or claim a hosted CI pass. PR 45 head/run and all original logs remain preserved.

## Final native CI result: 14:12:11 UTC

The completed-job REST log subsequently resolved the native result: **1,395 tests passed, zero failures**, with the exact final reporter summary at **14:12:08.8292791 UTC on 30 September 2026**. Analyze-and-test job **109865215598** completed with **`success` at 14:12:11 UTC**, in unchanged run **36708753882**, attempt **1**. The job began at 11:28:29; the test step began at 11:31:09 and reached its final summary after approximately 2h40m59s. This is an observed final result, not a timeout-based inference.

The checked-out source in the complete log is synthetic PR merge **`39bc6159d6f51b59332c0a8fc1fa9f2d1eea5bea`**, merging unchanged PR 45 head **`42bcb6f997c7df69a9ed5cba1c0af7130729fb46`** into **`a77df27bfb27f5a3cc39337a1a37b996cd68b945`**. Checkout lines record both the fetched merge ref and `git log -1 --format=%H`. PR 44, PR 45, the workflow and this execution were not changed, restarted or cancelled by the monitoring work.

The final log is preserved at `C:/Users/Kaged/.codex/worktrees/companion-acceptance-next/Sommelier study companion/build/ci-pr45-native-job-final.log`, **279,784 bytes**, SHA-256 **`441513B6898242FBA6F87A18882C9492F7FA2A65ACD4743A88658AC42BB8A8AC`**. Reading the entire log found **1,395 named passing events**, including six events represented in grouped headings, matching its final count. The last named test is `core/backup/user_data_backup_test.dart: failed picker discard leaves erase marker for retry`, completed at **14:12:08.7870271 UTC**. Analysis reports **no issues found** at 11:31:09.7118015, and the final web-assets lock check confirms **sqlite3 3.6.0 / drift 2.35.0** at 14:12:08.9598496. No failing test marker, test timeout or failing-test stack was found.

Four **debug Drift duplicate-database warnings with warning stacks** remain in the log, associated with numeric backup, foreign-transaction tasting-pair, guided-transaction and missing-profile tests. Their named tests passed. The cleanup also records a **nonfatal dependency-cache reservation warning** at 14:12:10.6837305; its action concludes successfully. These warnings are preserved and distinguished from test failures. The initial completed-job API response retained stale step statuses (`flutter test` in progress / web-assets pending) despite the successful job conclusion; the complete final log supplies the actual completed test and asset-check evidence.

At the handoff checkpoint, the browser tab could not be bound: the available-surface inventory had no browsers. Test progress was therefore unknown from that live view; the scheduled read-only API checkpoint exposed completion, after which the final REST log was retrieved. Final metadata, all five job conclusions and inspected evidence are preserved in NEXT ignored `build/ci-pr45-native-job-final.json`, `build/ci-pr45-run-final.json`, `build/ci-pr45-jobs-final.json` and `build/ci-pr45-native-final-evidence.json`. The final checkpoint entry was saved at **14:21:05.1852334 UTC** in `build/ci-pr45-checkpoints.jsonl`; observation time differs from execution completion time.

The historical two-hour checkpoint remains accurately **unknown at the time of observation**. The final log establishes that the previously exposed retired-reference test completed at **12:40:30.2432926 UTC**, while the virtualized browser had displayed 12:40:33. This later evidence does not establish what was active at any silent checkpoint, convert an `in_progress` status into observed progress, or supply an exclusive local counterpart runtime. All historical captures, uncertainty statements and passing local evidence above remain intact.

The **overall workflow conclusion remains `failure`** because the existing **Windows build and installer** and **Web build and smoke test** jobs failed. **Native analyze/test, Android build and iOS build succeeded**. The final native pass does not supersede those other job failures or accept the later CMS/D2 candidate. Monitoring of this unchanged run is complete; no further polling, speculative changes or workflow restart is required for this result.
