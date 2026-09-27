# Diploma French regional depth — release 0.16.0

This local continuation expands selected French D3 analysis for the user-confirmed WSET Level 4 Diploma target. It follows the [Italy/Iberia continuation](diploma-italy-iberia-continuation.md). Full Diploma coverage and qualified review remain unfinished.

This document retains the 0.16.0 snapshot. The subsequent [European depth continuation](diploma-european-depth-continuation.md) records the latest integrated counts and checks.

## New study material

| Module | New points | Paired explanation groups | Original cases |
|---|---:|---:|---:|
| Alsace, Beaujolais and Jura | 44 | 14 | 4 |
| Languedoc, Roussillon and Provence | 44 | 14 | 4 |
| Loire, Rhône and South West | 44 | 14 | 4 |
| **Total** | **132** | **42** | **12** |

The lessons connect grapes, vineyard setting and production choices to regional style, quality and cost explanations. Eastern study adds Alsace, Beaujolais and Jura comparisons. Mediterranean study covers selected still-wine and rosé contrasts. Loire/Rhône lessons deepen the earlier broad regional comparisons, while South West lessons add distinctive local grape and style contexts. The modules use selected examples and do not complete every French appellation, producer, product or legal distinction.

Each explanation group has two independently cited points. Twelve original hypothetical cases supply a decision, reason, tradeoff and limitation. Case names retain the complete prompt premises, so individual recall and grouped exercises share the same conditions. The existing presenter combines studied points and limits unfamiliar points during introduction. Learners self-check explanations against cited statements; typed practice accepts authored terms and aliases. Neither format automatically evaluates the accuracy of an essay or provides official marking.

- [Eastern French sources and qualifications](regional-france-east-sources.md)
- [French Mediterranean sources and qualifications](regional-france-mediterranean-sources.md)
- [Loire, Rhône and South West sources and qualifications](regional-france-rivers-southwest-sources.md)

These registers separate primary observations from original comparison applications and hypothetical assumptions. All new facts remain unverified, with automatic multiple choice disabled where alternative answers may be defensible. A place, method or geological description cannot guarantee an individual wine's quality, price or blind-tasting origin. Existing authored rows, atlas assets and legal permission lists are preserved; the release adds no geographic nodes or geometry.

The addition contains 186 nodes, 132 relations, 300 mappings, 132 aliases, 60 new source records and 177 item citations. The integrated bundle has 2,816 nodes, 2,606 relations, 2,495 items, 5,077 mappings, 1,126 aliases, 704 sources and 2,906 item citations. Domains contain 232 viticulture, 296 winemaking, 89 business, 30 service, 17 tasting, 1,831 geography points.

## Progress and official scope

All 132 new facts map directly to Diploma at core depth 3 and join the earlier 264 regional facts explicitly in D3. This preserves the unit assignment of regional vineyard, cellar and business explanations ahead of broad domain matching. D4/D5 specialist assignments remain intact and the units remain an exclusive partition of mapped material.

The 84 foundations also support Level 3 and CMS Europe Certified at depth 2; the 48 case points are Diploma-only. Jura foundations are secondary enrichment on the lower tracks. Their new analytical selectors are explicitly optional; the lower tracks' existing additional-place selectors remain optional and limited to location facts. Jura remains a required regional objective for Diploma. These are editorial study mappings, not new required examination-body outcomes.

The regional comparison objective now selects 396 points across 126 paired groups and 36 cases. Cumulative authored material supplies 103 Level 2, 2,204 Level 3 and 2,495 Diploma facts; Level 1 still needs its foundation pack. All four scopes remain incomplete. Mastery of available material and self-reported exam passes remain separate.

Generation supplies 11,085 single-item presentations and 243 pools: 31 regional profiles, 146 paired explanations and 66 original cases across the integrated companion. These are generated presentations of canonical facts, not independently authored examination questions. Recall-family pools do not implement Q6 reasoning or establish completed D3 tasting and written assessment.

## Validation

Local release 0.16.0 is recorded at `2026-09-27T06:28:50.000Z`, checksum `sha256:8de6ac1ad646c1271f9f59d12b04341789cb6ea72e9692bf964f30bdacb81ecd`, app version 0.2.5+7.

| Gate | Local result |
|---|---|
| Curriculum lint and ingestion | Pass: 68 files, zero errors. Existing uncurated-date/structural warnings and all 2,495 unverified facts remain visible. |
| Generation, coverage report and baseline | Pass; no blocking or flashcard-only gaps for authored material on selectable tracks. Unfinished syllabus tasks remain open. |
| Affected tests | Pass: 31 content/scope/progress tests plus the invalid-scope report regression. Checks cover all 126 regional pairs, 36 regional cases, aliases, exact counts, D3 routing and optional lower-track Jura support. |
| Preservation | Pass: all 60 prior curriculum includes and 32 geography files match the fresh 0.15.0 build bytes. |
| Static analysis and formatting | Pass: no issues; changed Dart formatted, whitespace checks clean and dependency lock unchanged. |
| Fresh web build and packaging | Pass: `build/france-depth-web`, with Wasm dry run. All 100 curriculum/geography/progress files match source bytes and SQLite wasm/worker match the existing pins. |
| Broad test suite | The prior 0.14.0 broad run passed 756 of 757; its corrected invalid-scope fixture then passed. This content continuation runs affected tests and does not claim a new full-suite result. |
| Qualified review and full Diploma release | Open. |

Author primary-source checks and an independent content review are source QA, not qualified verification. Review narrowed the Alsace late-harvest example to CIVA's illustrated sweet style, qualified the rosé case's possible flavour tradeoff, and refreshed pricing passage locators. Specific source-access qualifications are recorded in each source register. The Jura PDFs remain limited to indexed primary text after live retrieval failures; independent review recovered the Loire guide and Rhône water report through live HTTP and read the relevant pages. Local logs use `build/france-depth-*`; the inventory records counts and preservation. No commit, push, native/device installation or publication is implied. Web compilation does not prove browser offline reopening or remote CI.

## Remaining work

The [Diploma gap audit](wset-level-4-gap-audit.md) and [backlog](../backlog.md) retain broader regional and product coverage, current law and labels, commercial evidence, sustained written analysis, analytical tasting, research support, finer atlas gaps, lower-level foundations, CMS non-wine beverages and qualified review. Authored presence does not establish a sufficient course or a completed qualification.
