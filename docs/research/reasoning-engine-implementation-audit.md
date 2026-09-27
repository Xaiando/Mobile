# Objective reasoning: implementation audit

Historical read-only assessment for release 0.19.0 on 27 September 2026, alongside the China regional continuation. The subsequent [0.20.0 continuation](diploma-reasoning-continuation.md) implements the runtime and four starter chains; the assessment below records the earlier unimplemented state. This note records a concrete next task; it does not count new reasoning practice or complete Diploma written analysis.

The [question-system design](../design/question-system.md#7-principles-the-knowledge-behind-reasoning-formats) and [Q6 backlog](../backlog.md#q6--reasoning-engine-climate-viticulture-production) specify objective premise-to-consequence questions through two or three cited relations. A correct answer credits the assessed chain; a wrong answer grades only its target. This differs from the existing short-answer self-check and from essay marking.

## What the current app supports

The current schema and pooled-format runtime already support ordered pool membership, one primary item, supporting items, seeded presentation, per-item grades and answer JSON. Review transactions and backups can retain completed answers without a new schema or dependency. Curriculum relations remain read-only at runtime.

Two data and scheduling gaps must be addressed explicitly:

- Current regional principles and cases are star-shaped `PRINCIPLE_EXPLANATION` and `CASE_*` groups. Their arbitrary point order does not establish a causal path. Author actual bounded mechanisms and validated contrasts rather than infer causality from prose or missing graph edges.
- Existing Diploma explanations use depth 3. Reasoning requires depth 4. Only intended targets should gain an appropriate depth-4 mapping; unrelated Diploma and lower-track depths must stay intact.

Both `StudyPlanner` and `CoverageChecker` currently expose a pooled format to every member. A reasoning chain must be schedulable only through its final target. Supporting membership still enables review credit. Counting support-only membership as an independently available reasoning assessment would overstate coverage.

## Smallest complete implementation

Add a pure-Dart path query under `lib/core/curriculum/` and a pooled `ReasoningFormat` under `lib/core/questions/formats/reasoning/`. Register it in the existing format registry, with reasoning family, objective grading and required depth 4. Add its view through the existing practice view registry.

Template parameters should specify bounded forward relation paths, optional starting-node scope, and explicitly authored contrasts with evidence. The template relation is the final path edge. Validate two or three composable edges, referenced types/nodes/items, unique current items, cycles, target role and sufficient defensible answer options. Extend curriculum validation where the present template interface cannot check references.

Enumerate only current, unsuperseded, cited KnowledgeItems. Structural edges alone are insufficient. Each concrete chain has an ordered pool, its starting node as scope and its last edge as target. Render the premise from the starting node rather than accidentally substituting the final edge's subject.

Every incorrect option needs an evidenced contradiction of the stated conditions. A missing edge, a regional tendency from another location or the generic MCQ distractor pool does not establish that contradiction. Skip ambiguous conclusions or insufficient valid options and report the reason. Do not credit evidence used only to explain a distractor.

Share target-eligibility logic between planner and coverage, and independently reject support-only requests in the presenter. Keep complete chains; do not truncate or sample their members like short-answer key points. Bound unfamiliar supporting items so reasoning cannot silently exceed the session's introduction limit.

Record the shown options, selected answer, seed, ordered assessed chain and starting premise in answer payloads. A correct answer grades each assessed item once; a wrong answer creates only the target's Again review. Feedback shows the cited chain and each authored contradiction, clearly distinguishing support that was not regraded. Source queries belong in core repositories, never screen SQL.

Add format support or explicit exclusions for every relation type in the coverage policy. Refresh release metadata, generation, coverage and baseline only after primary-only served reasoning coverage actually increases in viticulture and winemaking. A small initial pack cannot establish full written-analysis or qualification readiness.

## Persistence boundary

Completed review events, options and payloads already belong to the backup model. Add real success and wrong-target-only export/import tests. The session controller and unfinished short-answer drafts currently live in memory. Replanning from saved FSRS state after restart is supported; restoring an exact unfinished question or draft requires a separately scheduled durable-session change. Do not emulate it with fake review events or undocumented settings.

## Required verification

- Path fixtures: two/three edges, branches, cycles, retired/superseded items, uncited structural edges, ambiguous conclusions and invalid contrast evidence.
- Format fixtures: parameter validation, target-role guards, complete chains, seeded replay, assessed-versus-explanation-only membership and depth 3 versus 4.
- Review/session fixtures: credit the chain, blame the target, transaction rollback, introduction limits and queue bonuses.
- Coverage/planner parity: supporting-only membership never schedules or reports an independent reasoning assessment.
- UI fixtures: no answer leakage, accessible options, full cited feedback and continuation.
- Backup fixtures: options, payloads and review groups survive a real roundtrip, including primary-only wrong answers.
- Regression checks: curriculum validation, bundled coverage, format ladder and architecture layering, followed by static analysis and a fresh app build.

Relevant runtime files are `lib/core/study/study_planner.dart`, `lib/core/study/review_service.dart`, `lib/core/coverage/coverage_checker.dart`, `lib/core/questions/exercise_presenter.dart`, `lib/core/questions/format_registry.dart` and `lib/features/practice/format_views.dart`. The canonical model remains [domain-model.md](../domain-model.md); no schema alteration is proposed by this audit.
