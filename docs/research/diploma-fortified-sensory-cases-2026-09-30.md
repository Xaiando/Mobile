# D5 fortified sensory packets — 30 September 2026

Status: original draft, unverified. These packets practise reasoning about supplied fictional observations. They do not assess a learner's palate, authenticate a wine, award an official quality grade or establish WSET completion. Physical tasting and qualified feedback remain separate requirements.

The bounded addition is three four-role cases, twelve `tasting` facts, mapped only to `WSET_L4`, core, minimum depth 3. Every sample observation and identity assumption is app-authored. No WSET SAT grid, source tasting example or grading table is reproduced.

| Subject | Decision grounded by the packet | Explicit limit |
| --- | --- | --- |
| `n_d5sensory_case_madeira_compare` | Select the sweeter/richer supplied Boal sample for the guest's intermediate-sweet brief; retain the Verdelho alternative for a less-sweet preference. | Neither observation nor a supplied name authenticates grape, origin, exact composition or elevation; no quality hierarchy between grapes. |
| `n_d5sensory_case_rutherglen_muscat` | Choose the fresher fruit-led supplied Rutherglen Muscat for this brief while recording the Grand sample's longer developed finish and integrated warmth. | Category average ages are not component minima or a way to diagnose blend age or an authenticity mark. |
| `n_d5sensory_case_age_quality` | Support the supplied ordinary Oloroso's stronger current integration/finish evidence in the fictional comparison. | The packet neither verifies nor disproves the supplied V.O.S. identity, cannot calculate constituent ages and cannot promise ten more years of improvement. |

All item IDs follow `ki_d5sensory_case_{madeira_compare,rutherglen_muscat,age_quality}_{action,reason,tradeoff,limitation}`. Each subject has `CASE_ACTION`, `CASE_REASON`, `CASE_TRADEOFF` and `CASE_LIMITATION`. A complete criteria exercise carries four cited points plus two explained distractors. Three written prompts use the existing written self-review contract; new introductions retain the current two-point budget, with all four points available after their individual facts are studied. Three separate authored action choices contain sufficient supplied observations and explicit identity assumptions. Correct option indexes are 0/1/2; correct-option length ranks are 0/1/3, so neither position nor always choosing the longest answer works across the set.

## Primary source checks

Checked on 30 September 2026; reuse existing citation IDs and URLs rather than duplicate source records.

- `src_d5madeira_verdelho`: [IVBAM Verdelho](https://vinhomadeira.com/o-vinho-madeira/castas/verdelho), descriptive intermediate style context. The citation is introduced in the Madeira site/style batch, which must be integrated first.
- `src_d5madeira_boal`: [IVBAM Boal](https://vinhomadeira.com/o-vinho-madeira/castas/boal), style and balance context; same integration dependency. Neither source supplies the fictional samples' identity or composition.
- `src_wset_sf_muscat_aged`: [Winemakers of Rutherglen — Muscat](https://winemakers.com.au/muscat-of-rutherglen/), classification and producer variation. The main-page open timed out; its official-domain indexed page supplied the relevant text. No tasting descriptors are copied as a source example.
- `src_d5_sherry_age`: [Consejo Regulador — Special Categories](https://www.sherry.wine/sherry-wine/special-categories), individual saca certification. Authentic V.O.S. evaluates quality and average age over twenty years. This matters: the case must not imply the designation is purely age, treat an invented bottle comparison as a finding about a certified lot, or convert average age into every constituent's exact age.
- `src_wset_taste_awri`: [AWRI Advanced Wine Assessment course notes](https://www.awri.com.au/wp-content/uploads/2023/02/01-AWAC-Course-Notes-28092022-1.pdf), printed pp. 20 and 26–27 for whole-palate assessment and limits on intensity/preference shortcuts. The course's scoring and medal scheme is not reproduced.
- `src_wset_taste_ageing`: [WSET — Why do we age wine?](https://www.wsetglobal.com/knowledge-centre/blog/2023/march/21/why-do-we-age-wine), suitability and storage context. It supplies no fixed improvement window for these invented bottles.

## Integration and validation boundary

Owned files are `assets/curriculum/areas/diploma_fortified_sensory_cases.yaml`, its matching templates file, `test/core/curriculum/diploma_fortified_sensory_cases_test.dart`, and this note. The root agent owns manifest registration, D5/unit and `fortified.tasting` selectors, baseline/global fixtures and shared coverage policy. The base policy currently excludes `authored_choice` for `CASE_ACTION`; that scoped capability needs an explicit integration decision for the three optional action cues. Existing D4/D5 tasting fixture expectations must continue to include the earlier cases while accommodating these additions.

The focused regression file checks the exact twelve facts and mappings, reused source URLs, explicit fictional assumptions, complete rubrics, average-age/certification limits, balanced authored choices, track isolation, D5/tasting routing, runtime presentation, correct/incorrect grading and useful-practice coverage. SDK formatting, curriculum validation and test execution are intentionally left to root's sequential checks after integration. No test pass, device validation, expert verification or full-curriculum completion is claimed by this batch.

## Root integration checkpoint

Root integrated the Madeira source dependency, all manifest/template includes and the exact five-subject/twenty-fact fortified-tasting selection. The coverage policy preserves generic CASE_ACTION format support and explains that authored choices use separately scoped banks. Focused sensory-case and objective regressions passed; [combined validation](combined-companion-validation-2026-09-30.md) records the final gates without claiming expert or sensory assessment.
