# Level 3 winemaking decision-case practice audit (2026-09-29)

## Boundary and measured result

The `WSET_L3` coverage report for release 0.24.40 found 77 core
`winemaking` `CASE_*` assertions, of which 68 lacked useful objective
practice. This batch adds `case_criteria` to the 16 complete four-role pools
whose action, reason, tradeoff and limitation are all in the winemaking
domain. That closes 64 gaps. The remaining four winemaking gaps belong to
three mixed geography/winemaking cases (Valpolicella buyer: two; Rioja site:
one; Dão/Vinho Verde comparison: one) and are reserved for the geography case
batch. The nine core winemaking case roles already served by the business case
rubric are unchanged.

The 16 new case pools have 64 cited response criteria and 32 tailored false
options. Each criterion grades independently. The existing short-answer and
typed questions remain in the release so a learner can still practise a
written response. Twelve subjects previously had only a short title as their
node name, so the rubric displays their full existing short-answer premise via
validated per-subject prompt overrides. The other four regional subjects
already carry the complete scenario in their node names. The new rubric does
not claim to replace WSET assessment or
award a qualification. All underlying assertions remain `unverified` pending
qualified subject-matter review. The WSET Level 3 `core` and depth-2 mapping is
an editorial study-plan decision, not copied examining-body wording.

The measured Level 3 winemaking core useful count rises from 242/451 to
306/451. The structured count rises from 19 to 83 because these 64 roles now
have the whole-case objective rubric. Level 4 inherits the same 64 core
gains. CMS Certified, Level 1 and Level 2 core metrics do not change.

## Scenario and source boundaries

The 16 rubrics reuse the curriculum's item-level source citations; the
`case_criteria` presenter attaches those sources to each response criterion.
No new factual assertions, legal limits, or source-citation mappings were
introduced. The two false responses per case test misapplication of its given
premise rather than making a rival process universally wrong.

| Case subjects | Primary source anchors | Distinction assessed |
| --- | --- | --- |
| Fresh white skin contact, hot red ferment, low-YAN juice, difficult MLF, protein haze, sweet bottling | [AWRI skin contact](https://www.awri.com.au/industry_support/winemaking_resources/winemaking-practices/winemaking-treatment-skin-contact/), [AWRI temperature](https://www.awri.com.au/industry_support/winemaking_resources/winemaking-practices/fermentation-temperature/), [AWRI YAN](https://www.awri.com.au/industry_support/winemaking_resources/wine_fermentation/yan/), [AWRI MLF](https://www.awri.com.au/files/attachment/mlf-in-white-and-sparkling-wine/), [AWRI fining](https://www.awri.com.au/industry_support/winemaking_resources/frequently_asked_questions/fining_agents/), [Wine Australia filtration](https://www.wineaustralia.com/news/articles/top-tips-for-filtration) | Batch-specific extraction; must temperature and cooling; measured early nutrition; several MLF inhibitors; heat-tested bentonite trials; final membrane integrity and downstream hygiene. |
| Fresh tank sparkling, transfer finishing, dosage trial | [Australian Wine production guide](https://www.australianwine.com/experience/articles/how-sparkling-wine-is-made), [Comité Champagne dosage](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/dosage), [Comité Champagne maturation](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/maturation) | Tank freshness versus extended bottle lees time; transfer after bottle fermentation versus individual disgorgement; dosage versus tirage or past maturation. |
| Fruit-led Port, weak Sherry flor, foundation Rutherglen Muscat | [IVDP Port introduction](https://www.ivdp.pt/en/wines/port-wines/introduction/), [IVDP special categories](https://www.ivdp.pt/en/wines/port-wines/special-categories/), [Sherry Council ageing](https://www.sherry.wine/sherry-wine/production/ageing), [Sherry Council flor](https://www.sherry.wine/news/biological-ageing-sherry-veil-flor-part-1), [Pfeiffer Rutherglen Muscat](https://pfeifferwinesrutherglen.com.au/product/pfeiffer-rutherglen-muscat/), [Chambers Muscat](https://www.chambersrosewood.com.au/grapevine/muscat) | Youthful fruit versus oxidative maturity; oxygen access and flor health; blended sensory balance rather than age-only classification. |
| Bordeaux blend, Fiano cellar trial, Provence rosé selection, Madiran extraction | [Bordeaux Cabernet](https://www.bordeaux.com/en/grape-varieties/cabernet-sauvignon/), [Bordeaux Merlot](https://www.bordeaux.com/en/grape-varieties/merlot/), [Irpinia Fiano](https://consorziovinidirpinia.it/vini/fiano-di-avellino-docg-vino/), [Iowa State oak](https://www.extension.iastate.edu/wine/oak-wood-composition), [Provence rosé methods](https://www.vinsdeprovence.com/en/le-rose/l-elaboration-du-rose), [Madiran wines](https://madiran-pacherenc.com/les-vins/les-vins-de-madiran/) | Trial actual lots for a stated style; distinguish oak expression from quality; direct press colour from universal quality; avoid inferring ageability from colour and tannin alone. |

The source pages support the underlying production mechanisms and style
contrasts. They do not establish the best commercial decision for every
producer; each rubric uses the case's specified sensory result, capacity and
customer brief as its decision boundary. AWRI's YAN guidance, for example,
supports measured nitrogen additions and warns that excessive DAP can change
fermentation or leave residual nutrients. Comité Champagne distinguishes
dosage after disgorgement from earlier lees maturation. These are the specific
premises used to reject the tempting false responses.

## Verification

`wset_l3_winemaking_case_criteria_test.dart` checks 16 complete source-linked
four-role pools, all 64 Level 3 core/depth-2 mappings, equality of the 12
full-premise overrides with their written cases, preservation of written
practice, independent per-role grading, a false-nutrition option,
certification scope and the new winemaking coverage count. Curriculum lint and the bundled
coverage ratchet validate generation and release metrics. The report on this
branch should still show four unserved winemaking `CASE_*` roles until the
separate mixed geography-case batch is integrated.
