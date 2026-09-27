# Diploma regional comparisons continuation — release 0.14.0

This continuation develops D3 regional analysis for the user-confirmed WSET Level 4 Diploma target. It builds on the [products and faults release](diploma-products-faults-continuation.md), while retaining CMS Europe Certified and Level 3 foundation support. The full Diploma companion and qualified curriculum review remain unfinished.

This document retains the 0.14.0 snapshot. The subsequent [Italy/Iberia continuation](diploma-italy-iberia-continuation.md) records the latest integrated counts and local checks.

## Authored practice

| Module | Paired explanation points | Case points | New items | Comparison groups | Cases |
|---|---:|---:|---:|---:|---:|
| France | 28 | 16 | 44 | 14 | 4 |
| Americas | 28 | 16 | 44 | 14 | 4 |
| Australia, New Zealand and South Africa | 28 | 16 | 44 | 14 | 4 |
| **Total** | **84** | **48** | **132** | **42** | **12** |

French study connects Chablis and other Burgundy contexts to Chardonnay, Pinot Noir, sites and cellar choices; Bordeaux to variety, soil, ripening and blending; and Loire/Rhône comparisons to grape and production differences. American study adds California, Oregon, Washington, Finger Lakes, Canadian, Chilean and Argentine regional explanations. Southern Hemisphere study adds Australian, New Zealand and South African contrasts. These are selected regional comparisons, not a complete course in every required country's wines.

Each comparison group has two independently cited points. The existing short-answer format brings selected points from the same subject together, so a learner can explain regional mechanisms and conditions. Twelve original scenarios ask for a defensible decision, supporting reason, tradeoff and limitation. When their points have been studied, the cases can present all four; the existing introductory selection still limits unfamiliar points. Learners self-check explanations against cited statements. Typed practice checks authored terms and aliases, not the accuracy of an essay or every possible defensible answer.

Regional-body observations support comparison hypotheses. A place, soil, altitude or method does not establish an individual wine's quality, selling price or blind-tasting origin. Case premises retain hypothetical targets and constraints; primary-source evidence is distinguished from editorial applications in the source registers:

- [French sources and case assumptions](regional-france-sources.md)
- [American sources and case assumptions](regional-americas-sources.md)
- [Southern Hemisphere sources and case assumptions](regional-southern-sources.md)

All new items remain `unverified`. Qualified and conditional answers disable automatic multiple-choice distractors. Existing geographic nodes, location questions and licensed map assets are preserved; this release adds analytical depth rather than new map boundaries or complete legal grape lists.

The addition contributes 186 nodes, 132 relations, 296 certification mappings, 132 aliases, 44 new primary-source records and 170 item citations. The integrated release has 2,444 nodes, 2,342 relations, 2,231 items, 4,477 mappings, 862 aliases, 587 sources and 2,541 item citations. Domains now contain 1,718 geography, 167 viticulture, 243 winemaking, 56 business, 30 service and 17 tasting items.

## Progress and scope

All 132 items are explicitly assigned to Diploma D3. This takes precedence over broad vineyard, winery or business domain grouping, and avoids adding false geographic containment edges for non-place subjects. The six Diploma topic groups remain an exclusive partition of current mapped material; supporting material outside them remains visible separately.

Every new fact has an explicit depth-3 Diploma mapping. Of the 84 explanation points, 82 also have editorial Level 3 and CMS Europe Certified mappings. Two dated Bordeaux 2024 illustrations and the 48 conditional case points are Diploma-only. Cumulative level counts describe available authored material, not the total official syllabus. All four level scopes remain incomplete, and self-reported exam passes remain independent of fact mastery.

The official-scope report now selects these authored regional subjects alongside existing geographic facts. The regional comparison objective gains substantive authored presence while retaining its unfinished tasks. This presence check cannot establish completed D3 study, official written assessment or practical tasting competence. D4/D5 tasting and D6 research support remain open.

Cumulative mappings supply 103 Level 2, 2,036 Level 3 and 2,231 Diploma items; Level 1 still needs its own foundation pack. CMS Europe Certified has 2,044 items. All selectable tracks have no flashcard-only or blocking format gaps for their authored material. Generation supplies 10,557 single-item presentations and 135 exercise pools: 31 region profiles, 62 paired explanation groups and 42 original cases across the three continuation releases. These presentations are generated from authored facts and templates, not independently authored examination questions. Recall-family cases do not automatically increase the coverage checker's useful-practice or Q6 reasoning counts.

## Validation

Release 0.14.0 is recorded in the local manifest at `2026-09-27T00:36:04.000Z`, with checksum `sha256:d0e026031f41a61e079dfc32de1af9e61ec22dfdb7035aef73422a62f202a08d`. Validation describes the local working tree and fresh build, not GitHub or an installed device package.

| Gate | Local result |
|---|---|
| Curriculum lint and ingestion | Pass: 56 files, zero errors. Warnings retain 1,835 uncurated dates, 111 structural edges and 2,231 unverified facts. |
| Generation and coverage baseline | Pass: 10,557 single-item rows, 135 pools; all three selectable-track baselines updated for 27 September 2026 with zero blocking or flashcard-only gaps. |
| Focused content/scope/progress tests | Pass: 31 tests. New aliases, all 42 paired pools, all 12 new case conditions/grades, exclusive D3 assignment and exact cumulative level counts are exercised. |
| Preservation against preceding build | Pass: all 48 earlier curriculum includes and all 32 geography files match the 0.13.0 build bytes. |
| Full Flutter suite and affected recheck | Fresh full run (25:16): 756 of 757 passed. The sole failure was an invalid-scope test whose literal YAML replacement no longer changed the expanded selector. It now mutates the parsed objective, retaining the unknown-node rejection assertions; the targeted recheck passes. All 757 tests have passing results across that full run and the affected recheck. |
| Static analysis | Pass: no issues; changed Dart files formatted, whitespace check clean and `pubspec.lock` unchanged. |
| Fresh web build and packaged assets | Pass: `build/regional-comparisons-web`, app 0.2.3+5, with a successful Wasm dry run. All 88 curriculum/geography/progress files match source bytes; SQLite wasm/worker match the 3.6.0 / Drift 2.35.0 pins. |
| Qualified review and whole-Diploma release gate | Open. |

Author checks and independent primary-source/content reviews found no blocking defects. Review aligned a Chablis MLF question with its cited points, retained complete scenarios in individual recall, excluded two dated Bordeaux examples from lower-level mappings, and strengthened commercial/sample-evaluation citations with existing canonical sources. Southern PDF claims were independently checked through indexed primary text; physical page locators were not independently confirmed. This is source QA, not expert verification.

Detailed local artifacts use the `build/regional-comparisons-*` prefix. The source inventory and preservation evidence are in `build/regional-comparisons-inventory.json`. No commit, push, native/device installation or product publication is implied by this local continuation. Web compilation does not establish native installation, browser offline reopening, remote CI or store publication.

## Remaining work

The [Diploma gap audit](wset-level-4-gap-audit.md) and [backlog](../backlog.md) retain further country and product comparisons, current legal/label distinctions, broader commercial evidence, sustained written analysis, analytical tasting, research support, finer atlas gaps, CMS non-wine beverages and expert review. The recall-family explanation/case pools do not implement the separate Q6 reasoning format or supply official marking.
