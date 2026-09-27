# Diploma principles continuation — release 0.12.0

This local continuation begins the production, business and service gaps identified in the [executive-summary comparison](executive-summary-comparison.md). It adds original, cited explanation and decision practice to the existing atlas. **It does not complete the Diploma curriculum or establish certification parity.** Existing authored rows, geographic assets and learner review history are preserved.

This document retains the 0.12.0 snapshot. The subsequent [0.13.0 products/faults continuation](diploma-products-faults-continuation.md) adds 173 further points and 15 cases and records that release's integrated counts and validation. The latest [0.14.0 regional comparisons continuation](diploma-regional-comparisons-continuation.md) adds 132 points and 12 cases.

## Authored content

| Domain | New principle points | New case points | Total new items | Cases |
|---|---:|---:|---:|---:|
| Viticulture | 40 | 20 | 60 | 5 |
| Winemaking | 42 | 24 | 66 | 6 |
| Business | 26 | 12 | 38 | 3 |
| Service | 14 | 4 | 18 | 1 |
| **Total** | **122** | **60** | **182** | **15** |

The 122 principle points span 102 subjects. The addition contains 299 nodes, 374 explicit track mappings, 273 answer aliases and 51 primary institutional, technical or producer sources. Every new item has source provenance and remains `unverified`. Publication, access and authoring timestamps do not represent expert verification.

Vineyard practice covers vine physiology, water and canopy management, frost, disease, roots, crop balance and harvest assessment. Winery practice covers extraction, fermentation, nutrition, malolactic conversion, oxygen, maturation, stabilisation and production risks. Business practice separates margin from markup, contribution from gross profit, profit from cash, and exchange-rate exposure from nonpayment. Service practice makes storage and assessment conditions explicit and distinguishes sediment removal from deliberate aeration.

The detailed source notes retain editions, page/section locators, mapping choices, limitations and original case assumptions:

- [Vineyard principles and sources](diploma-viticulture-sources.md)
- [Winemaking principles and sources](diploma-winemaking-sources.md)
- [Business and wine-service principles and sources](diploma-business-service-sources.md)

No new geographic node or map layer is introduced. The installed curriculum now contains **1,926 items**: geography 1,645; viticulture 139; winemaking 86; business 38; service 18; tasting 0. Tasting records and journal functionality already exist, but those features do not create authored tasting-domain knowledge items or complete Diploma analytical tasting preparation.

## Practice and integration behaviour

Generation currently reports **9,947 single-item question rows and 66 exercise pools**. The pools comprise the 31 existing regional profiles, 20 vineyard explanation subjects and 15 new cases. These are generated practice presentations and pools, not thousands of independently authored examination questions.

Principle subjects provide standalone question stems. Their brief answer terms, phrases and authored aliases support typed recall; the cited assertion supplies the fuller explanation. Typed grading does not evaluate an essay, judge a vineyard plan or machine-grade the invented business arithmetic. New MCQs are disabled where multiple decisions or explanations could be defensible.

Typed recall still rejects exact known wrong node names across domains. For partial answers, ambiguity is checked against node types permitted by the relation's signatures. This prevents an explanatory sentence mentioning frost from making the existing incomplete hazard answer "frost" fail, while other soil/place/climate names still block ambiguous fragments. Authored aliases remain the route for accepting additional correct terminology.

Each original case has four canonical facts: a defensible action, its mechanism, a trade-off and a condition or limitation. The existing short-answer format selects **two to four points** according to its serving rules and the learner's studied material. The learner checks which selected points the written response covers, and each point updates its own FSRS state. This is selected-point practice feedback, not an official mark, exhaustive answer key or automated professional assessment. The current UI explicitly identifies original practice and selected self-check points.

Case templates use `scope_node_ids` to bind their prompt to the intended case subject. Runtime filtering and template validation must reject malformed or inappropriate scope rather than showing another case's facts beneath that prompt. Shared data definitions use general principle, learning-point and decision-case labels while retaining stable internal type identifiers. No database schema migration is introduced.

Level mappings preserve foundation depth and cumulative inheritance. Selected elementary material supports Level 2, production/service foundations support Level 3 and CMS Certified, and deeper commercial or conditional production items map explicitly to Level 4. Mapping an item to a track does not demonstrate complete syllabus representation. **Every WSET level scope remains explicitly incomplete**, and study percentages describe available installed material only. Self-reported examination passes remain separate from app mastery.

## Validation status

The final curriculum report identifies release **0.12.0**, published at `2026-09-26T22:47:16.000Z`, with checksum `sha256:d3edea3402d86de5147314d66f97c3292b1b80488e5ea8bebccbde2128b0c2a3`. This is local validation of the working tree, not evidence of a pushed commit, installed device update or store release.

| Gate | Status |
|---|---|
| Curriculum lint and release ingestion | Pass: 44 files, zero errors; warnings retain 1,835 uncurated dates, 111 structural edges and 1,926 unverified items |
| Generation report and all selectable coverage baselines | Pass: 9,947 question rows, 66 pools; all three track baselines updated, zero blocking or flashcard-only gaps |
| Principle aliases, case scope filtering and composite grading tests | Pass through affected reruns; conditions, all four case points, source references and Diploma progress exercised |
| Analysis and Flutter validation | Clean analysis; 749 unique cases exercised across full and focused runs, with failures resolved as described below |
| Fresh web build and bundled-asset verification | Pass: `build/diploma-web`, app version 0.2.1+3; all 76 curriculum/geography/progress files match source bytes, SQLite wasm/worker match pins |
| Qualified expert review | Open; all items await review |

The broad Flutter run finished with **747 passed and two failed out of 749**. It started before the final missing-scope safeguard was compiled; that new regression and the real typed-partial ambiguity regression were resolved and passed in the fresh affected run. That run covered **29 tests**: 28 passed, with one older validator test receiving an additional diagnostic from the stronger safeguard. Removing the redundant diagnostic and fixing the analyzer's null-aware-list style yielded **four final targeted validator/scope tests passing** and clean static analysis. The complete 749-case suite was not repeated after these narrow fixes. Source/alias practice, full case grading, progress, typed UI, short-answer UI and accessibility passed in the affected run.

The existing provisional reasoning/useful-practice thresholds are not completed by this module. The new explanations and cases use the recall family; the Q6 objective reasoning format remains open. Passing the coverage ratchet does not establish full assessment depth or a public certification-parity release gate.

No native installer, device installation, browser offline-reopening test or store publication is established by the web compilation. Native/offline architecture and the unchanged map assets retain their existing validation; browser app-shell offline reopening remains a separate release task.

## Remaining work

`DIP-1` still needs a coherent production course with wider site, vineyard-establishment, cellar, packaging and quality-control coverage, more comparisons, and expert-reviewed analytical depth. `DIP-2` still needs producer structures, intermediaries, supply and demand evidence, market systems, marketing comparisons and broader commercial analysis. Its business domain now has authored practice; that closes the empty-domain problem without completing the unit.

`Q6` remains a wider reasoning-format task. These cases use the existing learner-checked short-answer format; they do not implement objective reasoning grading or establish that all defensible choices are recognised. Regional integration, sparkling and fortified depth, analytical tasting, research practice, non-wine CMS beverage coverage, remaining atlas detail and public release gates also remain open in the [Diploma audit](wset-level-4-gap-audit.md) and [backlog](../backlog.md).

No WSET/CMS examination question, syllabus prose, proprietary rubric or tasting-grid artwork is reproduced. Technical validation and primary citations cannot replace qualified review or justify an official-affiliation, accreditation or completed-level claim.
