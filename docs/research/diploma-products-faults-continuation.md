# Diploma products and faults continuation — release 0.13.0

This local continuation adds sparkling and fortified production study, wine-fault mechanisms and diagnostic limits to the [0.12.0 principles module](diploma-principles-continuation.md). The user-confirmed target remains WSET Level 4 Diploma, with CMS Europe Certified support. Full curriculum coverage and qualified review remain unfinished.

This document retains the 0.13.0 snapshot. The subsequent [0.14.0 regional comparisons continuation](diploma-regional-comparisons-continuation.md) records the latest integrated counts and validation.

## Authored practice

| Module | Principle points | Case points | New items | Cases |
|---|---:|---:|---:|---:|
| Sparkling | 38 | 20 | 58 | 5 |
| Fortified | 37 | 20 | 57 | 5 |
| Faults and quality control | 38 | 20 | 58 | 5 |
| **Total** | **113** | **60** | **173** | **15** |

Sparkling study distinguishes traditional, tank, transfer, ancestral and carbonation processes. It covers base wine, blending, optional malolactic conversion, lees ageing, riddling, disgorgement, dosage, pressure handling and selected cost decisions. Fortified study explains fermentation arrest, fruit-led and oxidative Port styles, flor and oxidative Sherry maturation, fractional blending, Madeira heating and cask ageing, VDN and Rutherglen maturation/blending. Fault study separates sensory evidence from a confirmed diagnosis, unwanted oxidation from intended oxidative styles, cell removal from removal of existing metabolites, and package damage from sensory deterioration.

The new facts include 141 winemaking, three business, 12 service and 17 tasting items. Tasting points concern observations, sensitivity and diagnostic limitations. They do not establish comprehensive analytical tasting, blind identity assessment or practical competence.

The addition contains 301 nodes, 173 relations, 313 explicit track mappings, 212 answer aliases, 48 new source records and 179 item citations. Three existing canonical sources are reused. The complete bundle contains 2,258 nodes, 2,210 relations, 4,181 mappings, 543 source records and 2,371 item citations.

Each original case has one subject and four cited facts: a defensible action, a supporting mechanism, a tradeoff and a limitation. The existing short-answer format presents two to four selected points; learners check their own response and each point updates its canonical FSRS history. Typed practice recalls key terms and authored synonyms. Conditional alternatives disable MCQ. These exercises are original practice, not copied examination questions or official marking rubrics.

Source registers, case assumptions, mapping choices and exclusions are retained in:

- [Sparkling sources](diploma-sparkling-sources.md)
- [Fortified sources](diploma-fortified-sources.md)
- [Faults and quality-control sources](diploma-faults-sources.md)

All new facts remain `unverified`. Primary citations, author checks and independent source review do not substitute for qualified expert verification. No new geographic node, map layer, boundary or legal permission list is added.

## Progress and scope

Explicit editorial `itemIds` selectors route all 58 sparkling points to D4 and all 57 fortified points to D5. This takes precedence over geography and broad domain grouping, so specialist production/cost points do not inflate D1 or D2. Each mapped fact contributes to at most one Diploma topic group. Fault-control winemaking supports D1; diagnostic tasting foundations support D3; service points remain supporting material outside the six groups. The broader scope report may count relevant support for several objectives, which is distinct from exclusive learner-progress grouping.

Scope validation rejects malformed, duplicate and unknown explicit item references. Referenced retired facts may remain in the editorial list but leave current progress counts; their reviews are preserved. All six unit gap notes and all four incomplete-level flags remain. Studied/mastered percentages describe installed available material, and self-reported exam passes remain independent.

The integrated release contains **2,099 knowledge items**. Cumulative mappings supply 103 Level 2 items, 1,954 Level 3 items and 2,099 Diploma items; Level 1 still needs its dedicated foundation pack. Source scope selectors now identify sparkling production/commerce, fortified production and quality-control support. Represented objectives indicate authored presence, not sufficient depth or completed units. D4/D5 structured tasting and D6 research remain planned work.

Generation supplies **10,293 single-item question rows and 81 exercise pools**. The pools comprise 31 existing region profiles, 20 vineyard explanation groups and 30 original cases across the two production releases. These are generated presentations/pools, not thousands of independently authored examination questions. The existing recall-family cases do not implement the Q6 reasoning format or increase useful-practice counts automatically.

## Validation

Release **0.13.0** is published in the local manifest at `2026-09-26T23:43:39.000Z`, with checksum `sha256:6d1210833db8e25df25d510a68f2fd5e5043d6eb47a614cc285648d78f02ae1b`. No commit, push, device installation or publication is implied by local validation.

| Gate | Local result |
|---|---|
| Curriculum lint and ingestion | Pass: 50 files, zero errors. Warnings retain 1,835 uncurated dates, 111 structural edges and 2,099 unverified facts. |
| Generation and coverage | Pass: 10,293 question rows, 81 pools; all three selectable-track baselines updated with zero blocking or flashcard-only gaps. |
| Focused content/scope/progress tests | Pass: 29 tests. Every new typed alias, all 15 four-point case rubrics, canonical per-point review storage, exact level counts and exclusive D4/D5 assignment are exercised. |
| Preservation against preceding build | Pass: all 42 earlier curriculum includes and all 32 geography files match 0.12.0 build bytes. |
| Full Flutter suite | Pass: all 755 tests in one fresh run after content/code freeze (24 minutes 25 seconds). |
| Static analysis | Pass: no issues. Changed Dart files are formatted; whitespace check passes and `pubspec.lock` is unchanged. |
| Fresh web build and packaged assets | Pass: `build/products-faults-web`, app 0.2.2+4, including a successful Wasm dry run. All 82 curriculum/geography/progress files match source bytes; SQLite wasm/worker match the 3.6.0 / Drift 2.35.0 pins. |
| Qualified review and whole-Diploma release gate | Open. |

Detailed local artifacts use the `build/products-faults-*` prefix, with inventory/preservation evidence in `build/products-faults-inventory.json`. Author/source cross-review corrected ambiguous flor-question wording, citation locators, duplicate URLs and normalized aliases before release validation. A source with an explicit AI-use restriction was replaced with independently sourced closure facts. No source PDFs or figures are bundled.

The fresh build compiles the web app; it does not establish native-package installation, device testing, browser offline reopening, remote CI or store publication. The preceding snapshots retain their historical test results; this release's full 755-test run passes after all content and code changes were frozen.

## Remaining work

The [Diploma audit](wset-level-4-gap-audit.md) and [backlog](../backlog.md) retain regional style and quality comparisons, detailed product/label distinctions, wider commercial analysis, sustained written explanations, analytical tasting, research support, CMS non-wine beverages, finer atlas gaps and qualified review. The objective reasoning format and public release gates remain separate tasks. This continuation advances D1, D3, D4 and D5 without claiming the total study companion is finished.
