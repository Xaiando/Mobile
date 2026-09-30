# British sparkling category comparison — 30 September 2026

This original D4 batch adds 14 assertions: six category principles and two four-role buying cases. All map only to WSET_L4 as core at depth 3, remain unverified and disable automatic MCQs. It adds six item-specific authored choices, six bounded typed-recall cues, two written self-check pools and two interactive criteria pools. It does not establish full D4 coverage, assessed tasting accuracy or qualification readiness.

Only the isolated companion-acceptance-next worktree is edited. The .61 validation checkout, frozen PR #44 and original dirty checkout are untouched. Shared manifest, scope selectors, baseline and existing fixture integration belong to root.

## Primary sources and category limits

The official [English PDO register](https://www.gov.uk/protected-food-drink-names/english) and [Welsh PDO register](https://www.gov.uk/protected-food-drink-names/welsh) currently link their December 2011 specifications. Their age is recorded; they are not relabelled as new 2026 editions. Each has separate still-wine and quality-sparkling parts.

| Citation ID | Opened primary source | Locators used |
|---|---|---|
| src_d4brit_english_pdo | [Registered English PDO specification](https://assets.publishing.service.gov.uk/media/5fd361f48fa8f54d6545da82/pfn-english-wine-pdo.pdf) | Part 2, PDF pages 6–7: sparkling cultivars; page 8: additional traditional-method conditions; pages 9–10: analytical and no-fault assessment |
| src_d4brit_welsh_pdo | [Registered Welsh PDO specification](https://assets.publishing.service.gov.uk/media/5fd36910e90e076637bb5a45/pfn-welsh-wine-pdo.pdf) | Same separately checked Part 2 sections and PDF-page positions |
| src_d4brit_fsa_sparkling | [FSA sparkling scheme guidance](https://www.gov.uk/government/publications/uk-quality-wine-schemes-guidance-sparkling-wines/uk-quality-wine-schemes-guidance-sparkling-wines) | Published 2 September 2025; sections 1–3 and the wine-category label example |
| src_d4nw_awri_sensory — reused | [AWRI sensory considerations](https://www.awri.com.au/industry_support/winemaking_resources/sensory_assessment/considerations/) | Controlled commercial sensory comparison, differences and preference; scenario cost/stock/demand reasoning is an explicitly original application |

The six sparkling cultivars are checked against both complete Part 2 lists. They are not substituted for the broader Part 1 still-wine lists, a UK-wide cultivar union or the incompletely enumerated PGI list. No PERMITS_GRAPE relations or permission-map distractor sets are introduced.

The FSA guide describes category-specific grape origin, hybrid flexibility, protected wording and testing. It also says that full scheme specifications prevail. The teaching does not use its variable PGI cultivar count as an exact statutory inventory. It avoids extending an English example's remaining-origin details into an unverified Welsh rule.

The 2025 WineGB consultation material is not treated as an approved replacement for the registered specifications. The technical teaching is bounded to the currently linked registered files and the opened FSA guidance. The source-check date and relation valid_from record this authored batch; they do not invent a legal commencement date.

## Item and exercise inventory

Six principles:

- ki_d4brit_pdo_origin
- ki_d4brit_pdo_grapes
- ki_d4brit_pdo_method
- ki_d4brit_pgi_hybrid
- ki_d4brit_unprotected_origin
- ki_d4brit_pdo_assessment

Two complete cases:

- ki_d4brit_case_hybrid_offer_action
- ki_d4brit_case_hybrid_offer_reason
- ki_d4brit_case_hybrid_offer_tradeoff
- ki_d4brit_case_hybrid_offer_limitation
- ki_d4brit_case_category_quality_action
- ki_d4brit_case_category_quality_reason
- ki_d4brit_case_category_quality_tradeoff
- ki_d4brit_case_category_quality_limitation

The first case supplies English-grown Seyval Blanc, a proposed PDO label, missing approval/test records and an invented print deadline. Cultivar eligibility and scheme approval are distinct: a PGI investigation is possible, but permission to use the hybrid cannot certify the final wine.

The second supplies approved Welsh PDO and PGI offers, a higher PDO purchase quote at equal quantity, and missing samples/landed costs/demand. It asks for sensory and commercial evidence. Analytical/no-fault checks do not constitute a head-to-head quality score. Neither the quotes nor the scenario constitute current Welsh market data.

The six authored choices distribute correct indices as 2/2/1/1 and correct-answer length ranks as 2/1/1/2. Alternatives target actual confusions: UK origin versus the named demarcation; still versus sparkling cultivars; bottle storage versus bottle second fermentation; hybrid permission versus approval; product-origin wording versus protected-name certification; and no-fault testing versus comparative quality. Each answer references a citation already linked to its item.

## Integration and validation

New files:

- assets/curriculum/areas/diploma_british_sparkling_categories.yaml
- assets/curriculum/templates/diploma_british_sparkling_categories.yaml
- test/core/curriculum/diploma_british_sparkling_categories_test.dart
- docs/research/diploma-british-sparkling-categories-2026-09-30.md

Root must register the two YAML files, select all 14 facts explicitly in D4, add all six principle subjects and both case subjects to the British D4 objective, and add both cases to D4 commerce. New subject prefixes are n_d4brit_principle_ and n_d4brit_case_. No new relation types, node types, schema changes or geometry are required.

The focused test checks exact item/mapping isolation, primary citation identity and reuse, balanced authored choices, complete original rubrics, honest D4 routing, and real planner/presenter delivery and grading. It respects the introductory two-point written budget, then records individual study before checking complete four-role written and criteria delivery. It rejects wrong category recall and incorrect criteria while preserving correct roles.

The author has not run Flutter, Dart, pub, SDK tests or Git. Root will format and validate this continuation sequentially after the frozen .61 full suite. Source review is internal editorial evidence; qualified expert verification remains pending.
