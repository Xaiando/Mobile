# D4 New World commercial comparisons — 30 September 2026

This bounded pack adds three original fictional purchasing cases, with four separately
cited roles each: action, reason, tradeoff and limitation. The twelve facts are
`business`, core WSET_L4 only, minimum depth 3. All remain `unverified`;
source retrieval and automated delivery do not constitute expert review, an
assessed qualification, practical tasting competence or verified supplier data.

The cases extend existing New World sparkling contexts with commercial decisions.
They do not reproduce WSET examination questions, prescribe national taste norms,
add GI permissions, or claim new legal maturation minima.

## Case premises and keys

| Subject | Supplied evidence and decision |
| --- | --- |
| `n_d4commercial_case_us_offer` | Oregon A has fictional bottle-fermentation/24-month records, EUR 18 before freight, payment now and six-week delivery. California B has the same bottle quote, stock and payment 14 days after delivery, but no method/lees records. Obtain B's records, taste both for an eight-week launch and compare complete delivered costs and cash dates. Regional origin is not lot-specific method evidence. |
| `n_d4commercial_case_andes_offer` | Chile A has fictional tank records/two-week delivery; Argentina B has fictional bottle records/eight-week delivery. A six-week opening allows a conditional small A trial, while B is a later option. The supplier's claim that dated INV 2023 aggregate dispatches prove this lot's future local sales is unsupported. |
| `n_d4commercial_case_oceania_africa_offer` | NZ A is EUR 15 plus EUR 1 freight; Cap Classique B is EUR 12 plus EUR 5 freight. At stipulated EUR 34 net revenue, with those charges explicitly treated as all COGS solely for this calculation, A is EUR 16 cost/EUR 18 gross profit and B EUR 17/EUR 17. The lower bottle quote reverses after supplied freight; longer fictional lees time needs a sensory comparison and does not prove better quality or net profit. |

All quoted prices, currencies, payment/delivery terms, lees periods, availability,
venue briefs and cost inclusions are invented inputs. No source is presented as
publishing these offers. The cost premise is deliberately simplified and is not a
real import, tax or landed-cost schedule. Actual customer demand, sales receipts,
supply reliability, sensory balance and full operating costs remain limitations.

Each subject owns:
`ki_d4commercial_case_<case>_action`,
`ki_d4commercial_case_<case>_reason`,
`ki_d4commercial_case_<case>_tradeoff` and
`ki_d4commercial_case_<case>_limitation`, where `<case>` is
`us_offer`, `andes_offer` or `oceania_africa_offer`.

## Primary sources retrieved and bounded use

All URLs already exist in the base dataset, so the pack reuses citation IDs and
adds no duplicate source rows. Sources were checked again on 30 September 2026.

| Existing source ID | Source and bounded use |
| --- | --- |
| `src_d4nw_us_california` | [Wine Institute California sparkling overview](https://wineinstitute.org/our-industry/statistics/wine-fact-sheets/sparkling-wine-champagne): diverse producers, varieties and styles. No fermentation method is inferred for a label-only fictional lot. |
| `src_d4nw_us_oregon` | [Oregon Wine Board Corollary profile](https://www.oregonwine.org/wineries/corollary-wines/): one Willamette Valley producer's traditional method. Neither invented offer is identified as this producer and no Oregon-wide recipe is asserted. |
| `src_d4nw_chile_spark` | [Wines of Chile sparkling methods](https://www.winesofchile.org/pt/lets-make-a-toast-to-summer-with-the-freshness-of-chilean-sparkling-wines/): separate tank and bottle routes. The article's Pét-Nat account, sugar thresholds and marketing sensory claims are not used. |
| `src_d4nw_argentina_report` | [INV Informe Vino Espumoso 2023](https://www.argentina.gob.ar/sites/default/files/2018/12/vino_espumoso_2023_una_-_rev-1.pdf), published October 2024, printed pages 2–4: dated aggregate 2023 commercial/domestic dispatches. No numerical market fact or current sales forecast is newly added. |
| `src_wset_sf_nz_spark` | [New Zealand Winegrowers sparkling reference](https://www.nzwine.com/en/winestyles/sparkling/?page=1): varied styles and a prominent traditional-method route. Country-level marketing descriptors and serving temperatures are unused. |
| `src_d4nw_za_cap` | [Cap Classique Producers Association](https://www.capclassique.co.za/about.html): bottle fermentation and style-dependent maturation. Association membership, a full grape list, category certification and legal minima are not inferred. |
| `src_spark_maturation` | [Comité Champagne maturation reference](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/maturation): physical yeast-autolysis/maturation mechanism only. Champagne legal maturation periods and cellar settings are not transferred to these offers. |
| `src_d4nw_awri_sensory` | [AWRI practical sensory considerations](https://www.awri.com.au/industry_support/winemaking_resources/sensory_assessment/considerations/): controlled, independent commercial comparison and establishing difference before preference. Laboratory temperatures, sample volumes and universal panel-size rules are unused. |
| `src_biz_victoria_pricing` | [Business Victoria gross profit, margin and markup](https://business.vic.gov.au/business-information/finance/pricing-for-profit/calculate-your-breakeven-point-margin-and-markup): gross profit equals net sales less COGS. Inclusion of freight and all EUR inputs are expressly supplied assumptions, not jurisdictional accounting or tax rules. |
| `src_biz_sec_statements` | [SEC financial statements guide](https://www.sec.gov/about/reports-publications/investorpubsbegfinstmtguide): cash flows differ from profit; operating expenses still follow gross profit before net profit. No investor recommendation or actual financial projection is supplied. |
| `src_biz_au_cashflow` | [Australian Government cashflow guide](https://business.gov.au/guide/guide-to-managing-cash-flow): payment terms, inventory and supplier planning. Invented delivery dates and venue opportunity costs are original case applications. |

## Practice and integration

`qt_d4commercial_case_criteria_3` supplies one six-statement pool per case:
four sourced role summaries and two case-specific false claims with explanations.
The learner assigns the four roles; each fact receives its own grade. Supported
statements assigned to the wrong role and both false alternatives must fail that
role. Previously studied co-items control availability.

`qt_d4commercial_case_written_3` uses the same complete scenario and four
key points for the learner's own written analysis and self-review. It does not
machine-grade prose or mark official WSET assessed work. General role flashcards
continue to introduce all twelve facts.

The focused regression checks complete premises, exact role delivery, twelve
L4-only mappings, cited evidence, cold/studied availability, six unique
statements per pool, correct and incorrect role assignment, written-point
omissions, lower-track exclusion and useful practice coverage. It intentionally
uses the bundle publication clock rather than a fixed date predating the facts.

Owned files:

- `assets/curriculum/areas/diploma_new_world_commercial_cases.yaml`
- `assets/curriculum/templates/diploma_new_world_commercial_cases.yaml`
- `test/core/curriculum/diploma_new_world_commercial_cases_test.dart`
- `docs/research/diploma-new-world-commercial-cases-2026-09-30.md`

Root owns manifest includes, Diploma unit/scope selectors, progress requirements,
coverage baseline and shared fixture adjustments. No SDK, pub, test, CI or Git
commands were run by this author. Static authorship is ready for review; passing
runtime validation has not been claimed.

## Root integration checkpoint

Root integrated all manifest/template includes and all four roles for each subject into the commerce objective, which measures 63 authored facts. The focused case-delivery regression passed in the integrated run. The [combined validation record](combined-companion-validation-2026-09-30.md) records exact group outcomes and remaining release gates.
