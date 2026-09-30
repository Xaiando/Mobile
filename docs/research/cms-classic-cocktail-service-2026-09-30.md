# CMS cocktail practice addition — 30 September 2026

This isolated next batch addresses a concrete companion gap: the previous bundled assertions had no named Martini, Manhattan, Negroni, Daiquiri, Margarita or Old Fashioned recipe lessons. The broad service-domain scope selector was not evidence that classic-cocktail recommendations had been authored.

The [CMS Europe 2026/2027 syllabus](https://courtofmastersommeliers.org/wp-content/uploads/2026/02/Syllabus-202627-1.pdf), PDF page 32 (zero-based page 31), places effective classic-cocktail and aperitif recommendation in the Certified practical-service column. Comprehensive cocktail preparation appears under Advanced/MS. This document establishes track scope only: it is not a bundled factual citation, recipe answer key or official examination question. The eight recipes below are an editorial starting set, not an official exhaustive CMS cocktail list.

## Authored batch

The new area supplies eight original recipe-identity principles and two guest-recommendation cases with four roles each: **16 new CMS-only service facts**. Principles are CMS_CERTIFIED core at depth 2; case roles are core at depth 3. No CMS_INTRODUCTORY or WSET Wines mapping is added. All facts remain expert-unverified with generic MCQ disabled.

| IBA reference and primary link | Fact and citation IDs | Bounded factual distinction |
| --- | --- | --- |
| [Dry Martini](https://iba-world.com/iba-cocktail/dry-martini/) | ki_cms_cocktail_dry_martini; src_iba_cms_dry_martini | 60 ml gin, 10 ml dry vermouth; stir; lemon oil or requested olive |
| [Manhattan](https://iba-world.com/iba-cocktail/manhattan/) | ki_cms_cocktail_manhattan; src_iba_cms_manhattan | 50 ml rye, 20 ml sweet red vermouth, one Angostura dash; stir |
| [Negroni](https://iba-world.com/iba-cocktail/negroni/) | ki_cms_cocktail_negroni; src_iba_cms_negroni | 30 ml each gin, Campari and sweet red vermouth; gently stir over ice |
| [Daiquiri](https://iba-world.com/iba-cocktail/daiquiri/) | ki_cms_cocktail_daiquiri; src_iba_cms_daiquiri | 60 ml white Cuban rum, 20 ml lime, two bar spoons superfine sugar; dissolve then shake |
| [Margarita](https://iba-world.com/iba-cocktail/margarita/) | ki_cms_cocktail_margarita; src_iba_cms_margarita | 50 ml 100% agave tequila, 20 ml triple sec, 15 ml lime; shake; optional half salt rim |
| [Old Fashioned](https://iba-world.com/iba-cocktail/old-fashioned/) | ki_cms_cocktail_old_fashioned; src_iba_cms_old_fashioned | 45 ml bourbon or rye, sugar cube, Angostura and water; dissolve then build and stir |
| [Whiskey Sour](https://iba-world.com/iba-cocktail/whiskey-sour/) | ki_cms_cocktail_whiskey_sour; src_iba_cms_whiskey_sour | 45 ml bourbon, 25 ml lemon, 20 ml syrup; optional egg white; shake |
| [Americano](https://iba-world.com/iba-cocktail/americano/) | ki_cms_cocktail_americano; src_iba_cms_americano | 30 ml Campari, 30 ml sweet red vermouth, splash soda; gently stir over ice, no added gin |

Each IBA page was directly checked on 30 September 2026. These are named references, not universal venue recipes. No fixed ml value is inferred for a soda splash, bar spoon, dash or egg-white drop. The original cases explicitly check actual stock, recipe, guest preference and any ingredient request; absence of added gin does not make an Americano alcohol-free.

The complete case subjects are n_cms_cocktail_case_aperitif and n_cms_cocktail_case_rum_citrus. Their eight item IDs are ki_cms_cocktail_aperitif_action/reason/tradeoff/limit and ki_cms_cocktail_rum_citrus_action/reason/tradeoff/limit. One compares Americano and Negroni for a stated no-gin request; the other compares Daiquiri and Margarita for a stated rum, lime and no-orange-liqueur request. Recommendations are conditional inferences from cited ingredient distinctions, not claims of universal flavour preference.

## Practice and integration

The template file supplies eight recognition choices, eight point-specific typed cues, two guest-action choices, two complete objective role-matching cases and two written self-review cases. The ten four-option authored choices have four distinct plausible alternatives with key positions **3/3/2/2**. Key length ranks are **2/3/3/2** across all four ranks, avoiding a cohort-wide short, long or middle-length key pattern. Peer review found no factual or scenario miskey in the eight directly checked IBA references.

The case_criteria format retains a full original premise, four sourced criteria and two explained false claims per case. It becomes available in CMS Study after its companion roles have been studied. It grades the four roles independently; the separate written response remains learner self-review. Neither format assesses physical bartending performance or awards a CMS credential.

Root integration must register areas/cms_classic_cocktail_service.yaml and templates/cms_classic_cocktail_service.yaml, add an explicit scoped cocktail objective if appropriate, update dataset version and measured coverage fixtures, and run lint/analyzer/focused tests. The focused cms_classic_cocktail_service_test.dart checks track isolation, exact 16 facts and eight IBA citations, recipe limits, balanced choices, accepted and rejected typed answers, cold/studied scenario eligibility, correct and false role grades, written rubric delivery and useful-practice coverage. **No SDK, test, analyzer or Git run was performed by this content author; integrated validation remains pending.**

## Numeric companion follow-up

The existing NumericFormat requires one unique current quantity target plus its quantity_values record; it does not calculate a result from prose. The registered PRINCIPLE_EXPLANATION signature targets a learning_point, and existing STATISTIC_VALUE represents survey evidence, so neither should be repurposed for business exercise answers. Root owns a new CALCULATED_VALUE signature with worked_example -> quantity for fixed original business premises.

A bottle/event case can state guests, pours, pour volume, bottle volume and waste assumption explicitly, then author the rounded-up integer bottle result. A selling-price case can state hypothetical cost, target gross margin, currency unit and tax assumption explicitly, then author the calculated price. NumericFormat can grade these with zero exact and outer tolerances without runtime changes. Its current units do not automatically convert ml/litres or US/Imperial fluid ounces: use exact authored units and identify any ounce convention. A percent-margin exercise must distinguish sales-based margin from cost-based markup. No changes to runtime, relation definitions or global policies are made in this cocktail batch.