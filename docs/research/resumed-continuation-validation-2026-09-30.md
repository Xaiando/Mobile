# Resumed continuation validation — 30 September 2026

Release 0.24.61 continues the local 0.24.59 Diploma tasting and 0.24.60 CMS practice commits from frozen PR #44. Its scope corrections come from a named comparison with the pinned public Level 1–3 specifications, not from a mapped-item count alone. The [outcome audit](wset-levels-1-3-final-outcome-audit.md) records sources and omissions; [learner progress](../wset-learner-progress.md) defines participation and mastery.

## Concrete changes

- Level 2 reuses the six statutory Prädikat definitions and six original quality principles at core depth 2. Three new cited, unverified principles distinguish Kabinett must weight from sweetness and explain closure/heat sensory effects. Higher-track depths remain unchanged.
- Level 3 requires 27 existing named locations, including parent regions, sparkling/fortified origins and Champagne districts. Eleven existing secondary mappings become core at depth 2. No geometry is invented or changed.
- Original guided Level 2 cases and physical tastings now request written description and quality evidence. The 17 observation attributes and grid identity stay unchanged. Saved older flights retain their own contracts and backups; missing current evidence cannot supply a new quality milestone.
- Practice scope schema 1 adds optional guidedEvidenceIds, empty for older scopes. Required evidence is checked when reading participation; IDs without a guided activity are rejected. Reads never rewrite history or generate memory reviews.
- Cellar-label parsing now withholds malformed, signed and out-of-range whole percentage tokens instead of extracting a misleading numeric tail; valid decimal clues remain supported. Six existing Amarna history assertions are restored to the chronological CMS/Diploma timeline without including unrelated sake/cigar enrichment.

## Measured authored coverage

Measured on 2026-09-30 with the actual ingester, planner and serving gates; baseline regenerated with no known blocking gaps.

| Track | Mapped facts | Core useful / core | Required facts |
|---|---:|---:|---:|
| Level 1 | 132 | 132 / 132 | 132 |
| Level 2 | 844 | 763 / 763 | 767 |
| Level 3 | 3,442 | 2,246 / 2,246 | 1,655 |
| Diploma | 4,130 | 2,867 / 2,867 | Not a completed Diploma syllabus |
| CMS Certified | 2,902 | 1,247 / 1,247 | Editorial CMS core |

Required selections and core mappings are different denominators. Level 3 geography is 1,071 / 1,071 core useful. All 4,383 authored assertions remain unverified; no qualified-review ledger entry is inferred from source research or passing tests.

## Current validation

- Curriculum lint: 0 errors, 3 warning classes across 238 included files. Existing warnings retain 2,199 uncurated dates, 150 structural relations and expert-unverified facts.
- Quality/history/backup/UI regressions: 12 / 12 passed in 10 seconds before the additional configuration guard.
- Seven scope/regional/case/choice regression files: 33 / 33 passed in 1 minute 54 seconds. Exact selected authored questions: 1,720 from 84 templates. Checks preserve current-item prerequisites, correct/incorrect grading, citations, and track boundaries.
- Final static analysis passed with no issues after the unused test import was removed. Formatting checked all 391 non-generated Dart files with zero changes; git diff whitespace check passed.
- Parser/current-progress/legacy-participation regressions: 22 / 22 passed in 1 second, including the additional configuration guard.
- History timeline regression passed in 42 seconds on both CMS and Diploma tracks: all six bridge assertions, 117 history facts, chronological grouping, source details, unverified status and memory display. It scrolls the phone detail sheet with a fixed bound; the initial failure and all assertions remain documented.
- Web asset hashes/versions match sqlite3 3.6.0 and Drift 2.35.0 in the pinned lockfile. Release web build passed with bundled resources and a successful Wasm dry run. The original ten browser stages passed. The final full suite ended at 02:20:54 UTC after 65 minutes 48 seconds: 1,318 tests passed and six failed. The six diagnosed count/date/mapping failures were repaired in .62, whose corresponding focused checks passed. This .61 result remains a failed full suite; current .63 gates are recorded in the [combined validation](combined-companion-validation-2026-09-30.md).

Logs are local ignored build artifacts in the level2-tasting-quality managed worktree. Dart commands that execute SQLite native hooks are sequential because concurrent hooks encountered a Windows DLL lock in the prior continuation. Dependencies resolved with the pinned lockfile; --no-pub avoids a redundant Windows Developer Mode/symlink check without changing OS settings.

## Preserved evidence

Frozen [PR #44](https://github.com/Xaiando/Mobile/pull/44), head a77df27bfb27f5a3cc39337a1a37b996cd68b945, remains unchanged. Its [run 36633382422](https://github.com/Xaiando/Mobile/actions/runs/36633382422) passed all five jobs. The inspected hosted log ends at 2026-09-29T23:56:38.0496084Z with 1,293 tests passed. This validates its own head.

The PC restart interrupted the newer .59 and .60 local full suites. Their focused and browser evidence remains preserved and limited to completed checks; neither interrupted run supplies a full-suite pass. The inspected .61 full-suite result is 1,318 passed and six failed; it supplies a completed result for its own frozen head, not a passing replacement.

## Remaining acceptance work

D1–D6 remain incomplete as Diploma workstreams. Current explicit editorial selectors include D3 720 facts, D4 133, D5 102 and D6 17; D1/D2 use domain selectors. These groups do not add up to official syllabus counts. D4/D5 now include original fictional sensory cases and physical flights, and D6 has a persisted research workspace; historical 'not started' wording must not hide implemented support.

Continue named regional/product analytical comparisons, defensible licensed fine-map references, physical Android/iOS scanner validation and qualified factual/curriculum/tasting review. App mastery, recorded participation and self-reported examination outcomes remain separate.
