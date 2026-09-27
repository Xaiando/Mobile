# Diploma Italy and Iberia continuation — release 0.15.0

This local continuation develops selected D3 regional analysis for the user-confirmed WSET Level 4 Diploma target. It builds on the [0.14.0 regional comparisons](diploma-regional-comparisons-continuation.md). The whole Diploma companion and qualified curriculum review remain unfinished.

This document retains the 0.15.0 snapshot. The subsequent [French depth continuation](diploma-france-depth-continuation.md) records the latest integrated counts and local checks.

## Authored practice

| Module | New items | Paired comparison groups | Original cases |
|---|---:|---:|---:|
| Northern and central Italy | 44 | 14 | 4 |
| Southern Italy, islands and Abruzzo | 44 | 14 | 4 |
| Spain and Portugal | 44 | 14 | 4 |
| **Total** | **132** | **42** | **12** |

Northern and central Italian study connects Piedmont, Veneto, Alto Adige, Friuli, Tuscany, Marche and Umbria to grape, site, maturation and style comparisons. The southern/island module covers Campania, Basilicata, Puglia, Sicily and Sardinia, plus an Abruzzo comparison classified with central Italy. Iberian study contrasts selected Spanish and Portuguese still-wine regions, including Atlantic/inland differences, grape and production choices, terrain and commercial constraints. These selected topics do not complete every region or product category.

Each comparison has two independently cited points. Twelve hypothetical cases ask for a defensible action, reason, tradeoff and limitation. Case premises stay visible in individual cards and typed practice as well as the grouped exercise. Studied points can be presented together; introductory selection retains the existing limit on unfamiliar points. Learners self-check their explanations against cited points, and typed recall accepts authored terms and aliases. The app does not automatically evaluate an essay or every defensible answer.

- [Northern and central Italy sources](regional-italy-north-centre-sources.md)
- [Southern Italy, islands and Abruzzo sources](regional-italy-south-islands-sources.md)
- [Iberian sources](regional-iberia-sources.md)

Source notes distinguish primary-body descriptions from editorial comparison applications and hypothetical case assumptions. Region, altitude, soil or grape does not guarantee an individual wine's style, quality, price or blind-tasting origin. All new items remain unverified, with multiple choice disabled where alternative decisions may be defensible. This release preserves the existing atlas and legal permission lists; it adds no new geographic nodes or map geometry.

The integrated bundle has 2,630 nodes, 2,474 relations, 2,363 items, 4,777 mappings, 994 aliases, 644 sources and 2,729 item citations. Domain counts are 199 viticulture, 264 winemaking, 71 business, 30 service, 17 tasting, 1,782 geography.

## Progress and scope

All 132 new facts have explicit depth-3 Diploma mappings and join the earlier 132 regional facts in D3. The 84 new foundation points also support Level 3 and CMS Europe Certified at depth 2; 48 case points remain Diploma-only. Explicit item selectors keep regional vineyard, cellar and business points in D3 ahead of broad domain grouping. Existing D4/D5 specialist assignments and review history remain intact.

The regional comparison scope selects 264 authored points across 84 paired groups and 24 cases. Northern, central and southern Italy, Spain and Portugal selectors include the new subjects alongside their existing geographic roots. This demonstrates authored presence, not sufficient official depth or completed units. Cumulative available material is 103 Level 2, 2,120 Level 3 and 2,363 Diploma facts; Level 1 still needs its own foundation pack. All four scopes remain incomplete, and self-reported exam passes remain independent of fact mastery.

Generation supplies 10,821 single-item presentations and 189 pools. Across the integrated companion these pools comprise 31 regional profiles, 104 paired explanations and 54 cases. Generated presentations are not independently authored examination questions. Recall-family explanations and cases do not implement the separate Q6 reasoning format or provide official marking.

## Local validation

Release 0.15.0 is recorded at `2026-09-27T05:59:15.000Z`, checksum `sha256:94c3f6efdc349f6f688d7387d9fbd0ca82d2917c8fa8f2680e7d0fbd2bae40f3`, app version 0.2.4+6.

| Gate | Result |
|---|---|
| Curriculum lint and ingestion | Pass: 62 files, zero errors; existing uncurated-date/structural warnings and all 2,363 unverified facts remain visible. |
| Generation, coverage and baseline | Pass; all selectable tracks have no blocking or flashcard-only gaps for their authored material. Scope tasks remain open. |
| Affected content/scope/progress tests | Pass: 31 tests, exercising all 84 regional pairs, 24 regional cases, aliases, exact counts and exclusive D3 routing. The parsed invalid-scope tool regression also passes separately. |
| Preservation | Pass: all 54 previous curriculum includes and 32 geography files match the fresh 0.14.0 build bytes. |
| Static analysis and formatting | Pass: no issues; changed Dart formatted, whitespace check clean and dependency lock unchanged. |
| Fresh web build and packaging | Pass: `build/italy-iberia-web`, with Wasm dry run; all 94 curriculum/geography/progress files match source bytes and SQLite wasm/worker match the existing pins. |
| Full Flutter suite | Prior 0.14.0 broad run: 756 of 757 passed, then the corrected invalid-scope fixture passed its recheck. This content-only continuation runs affected tests and does not claim a new full-suite result. |
| Qualified review and complete Diploma release | Open. |

Primary-source author checks and a separate content review support integration; these are source QA, not qualified expert verification. Review narrowed the Rueda Verdejo point to fruit/herbal character and acidity supported by its cited page. Validation corrected one module's mapping-section name before the passing gates. A peer independently retrieved the three Valpolicella pages through direct HTTP after author/browser timeouts and confirmed the selected production descriptions. Friuli and the older Marche page returned 403 during the peer pass, so those specific passages retain the author's source check without an independent live recheck. Local logs use the `build/italy-iberia-*` prefix, with counts and preservation evidence in `build/italy-iberia-inventory.json`. Web compilation does not establish native installation, browser offline reopening, remote CI or publication. No commit or push is implied.

## Remaining work

The [gap audit](wset-level-4-gap-audit.md) and [backlog](../backlog.md) retain further French, central/eastern European and other regional/product comparisons; current legal/label distinctions; broader commercial evidence; sustained written analysis; structured tasting; D6 research support; finer atlas gaps; CMS non-wine beverages; and qualified review. Neither large fact counts nor mastered available material demonstrate a completed WSET qualification.
