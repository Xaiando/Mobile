# Diploma French dimensional crosswalk — 30 September 2026

## Scope and evidence boundary

This is a bounded editorial audit of Bordeaux, Burgundy, the Loire and the Rhône against the public Diploma specification. It records the current application content at the aa4aae3 baseline, not a claim that Diploma or any qualification is complete. The audited curriculum remains expert-unverified. Map locations are recorded separately from analytical practice: more location facts cannot establish explanation, comparison or evaluation.

The [current official qualification page](https://www.wsetglobal.com/qualifications/wset-level-4-diploma-in-wines) linked the [August 2025 Issue 1.4 specification](https://www.wsetglobal.com/media/17609/wset_l4wines_specification_en_august-2025.pdf) when reviewed. Printed pages 12–13 (PDF pages 16–17) contain D3 criteria 3.1.1–3.1.7 and associated ranges. Those criteria require description, explanation, comparison and evaluation across style, quality, price, growing environment, production, law and business, including routes to sale. The region range includes all four areas audited here. The published document does not prescribe a complete commune-by-commune list, so the gaps below concern supplied analytical applications, not invented official item mandates.

No fresh curriculum ingestion, SDK test, coverage command or observed learner session was performed for this audit. “Practice anchor” means that the included area, mapping and template contracts provide the exercise; it does not mean every exercise appears immediately in every fresh session.

## Delivery contracts

- `assets/curriculum/curriculum.yaml` at dataset `0.24.63` includes the area and template files cited here.
- `assets/curriculum/track_scope.yaml` explicitly identifies `wset_l4.world.bordeaux`, `wset_l4.world.burgundy`, `wset_l4.world.loire` and `wset_l4.world.rhone`.
- `lib/core/study/study_planner.dart`: `effectiveMappings` resolves nearest track overrides and inherited mappings; `servedFormats` respects minimum depth. Most earlier regional classification/style principles are inherited at depth 2. The later regional comparisons and case roles have explicit Level 4 core mappings at depth 3.
- `_readyCaseCriteriaTemplates` requires all four mapped case roles and prior study of the other three roles. Objective case criteria therefore have a meaningful readiness gate, rather than being universally available on first exposure.
- Written short-answer cases use original supplied scenarios and self-review. They do not automatically grade prose or certify practical performance.

## Current regional evidence

IDs below are exact current local anchors. A case prefix followed by `{action,reason,tradeoff,limitation}` identifies four separate knowledge items.

### Bordeaux

| Dimension | Current anchors and limits |
| --- | --- |
| Location | `ki_fr_atlas_bordeaux_location` and left/right bank and appellation descendants in `areas/france_atlas.yaml`. These support location practice, not reasoning sufficiency. |
| Variety and environment | `ki_reg_fr_cabernet_late`, `ki_reg_fr_merlot_early`, `ki_reg_fr_cabernet_gravel`, `ki_reg_fr_merlot_clay`, `ki_reg_fr_vintage_disease`, `ki_reg_fr_vintage_window` in `areas/regional_france_comparisons.yaml`. |
| Production and style | `ki_reg_fr_cabernet_structure`, `ki_reg_fr_merlot_roundness`; complete case `ki_reg_fr_case_bordeaux_blend_{action,reason,tradeoff,limitation}` with subject `n_reg_fr_case_bordeaux_blend`. The case uses supplied ripe Merlot and firm Cabernet observations and a blending trial, not a fixed bank recipe or an assertion of appellation compliance. |
| Law and classification | `ki_wset_eu_bordeaux_superieur_identity`, `ki_wset_eu_bordeaux_superieur_evaluation`, `ki_wset_eu_bordeaux_classifications_scope`, `ki_wset_eu_saint_emilion_grand_cru_classe`, `ki_wset_eu_bordeaux_classification_quality` in `areas/wset_regional_europe.yaml`. Classification and reputation are distinguished from a guarantee about the tasted cuvée. |
| White and sweet production | `ki_wset_eu_bordeaux_dry_white`, `ki_wset_eu_bordeaux_sweet_white`, `ki_wset_eu_bordeaux_white_mlf`; `ki_wset_apply_bordeaux_maritime`, `ki_wset_apply_sauternes_environment`, `ki_wset_apply_bordeaux_white_cost`, `ki_wset_apply_sauternes_selection_cost` in `areas/wset_regional_applications.yaml`. |
| Price and commerce | Existing classification, white production and selective sweet-harvest costs support price reasoning. No current complete Bordeaux route-to-market evaluation case was found in the included regional case banks. |

Actual practice anchors include `qt_reg_fr_case_bordeaux_blend` in `templates/regional_france_cases.yaml` and the scoped `qt_wset_l3_winemaking_case_criteria_16` in `templates/wset_l3_winemaking_case_criteria.yaml`. `qt_wset_l4_viticulture_principle_closure_51`, `qt_wset_europe_application_67`, `qt_wset_l3_geography_gap_scenarios` and `qt_wset_principle_point_typed` provide additional mapped mechanisms/recall families. These are real analytical or principle exercises; the audit does not classify Bordeaux as map-only.

### Burgundy and Chablis

| Dimension | Current anchors and limits |
| --- | --- |
| Location | `ki_burgundy_location`, `ki_chablis_location` and Burgundy atlas descendants. |
| Variety | `ki_chablis_grape`, `ki_volnay_grape`, `ki_reg_fr_nuits_pinot`, `ki_reg_fr_beaune_mix`. |
| Environment | `ki_chablis_frost`, `ki_reg_fr_chablis_cool`, `ki_reg_fr_macon_warm`, `ki_reg_fr_climat_site`, `ki_reg_fr_hautes_plateaus`, `ki_reg_fr_cote_aspect`. |
| Production and quality | `ki_reg_fr_chablis_vessels`, `ki_reg_fr_chablis_new_oak`, `ki_reg_fr_chablis_mlf_acid`, `ki_reg_fr_chablis_quality`, `ki_reg_fr_climat_separate`. |
| Law, origin and price | `ki_wset_eu_burgundy_regional_village`, `ki_wset_eu_burgundy_premier_cru`, `ki_wset_eu_burgundy_grand_cru`, `ki_wset_eu_burgundy_origin_price`, `ki_wset_eu_bourgogne_cote_or_level`, `ki_wset_eu_burgundy_hautes_level`, `ki_wset_eu_montagny_chardonnay`. Restricted origin, supply and demand are taught without equating appellation rank with an automatic quality result. |
| Sustained application and commerce | `ki_reg_fr_case_chardonnay_buy_{action,reason,tradeoff,limitation}`, subject `n_reg_fr_case_chardonnay_buy`, compares supplied Chablis/Meursault/Mâconnais samples and an explicit affordable budget. Current sustained regional case work is Chardonnay-focused; no complete Pinot site/production/price or Burgundy route-to-market packet was found. |

The written practice is `qt_reg_fr_case_chardonnay_buy`; objective four-role review is included in `qt_wset_l3_business_case_criteria_19` in `templates/wset_l3_business_case_criteria.yaml`. Regional principles also have typed and scoped choice practice. Pinot and climat facts already exist, so a future Pinot case should reuse them rather than duplicate introductory knowledge.

### Loire

| Dimension | Current anchors and limits |
| --- | --- |
| Location | `ki_loire_valley_location`, `ki_vouvray_location`, `ki_pouilly_fume_location`, `ki_muscadet_sevre_et_maine_location`. |
| Variety | `ki_pouilly_fume_grape`, `ki_vouvray_grape`, `ki_muscadet_sevre_et_maine_grape`, `ki_reg_fs_chinon_grapes`. |
| Environment | `ki_reg_fr_centre_slow`, `ki_reg_fr_centre_microclimates`, `ki_reg_fs_saumur_season`, `ki_reg_fs_saumur_thermal`, `ki_reg_fs_saumur_water`, `ki_reg_fs_chinon_sites`, `ki_wset_apply_muscadet_rainfall`. |
| Production and style | `ki_reg_fs_muscadet_melon`, `ki_reg_fs_muscadet_lees`, `ki_reg_fs_savennieres_dry`, `ki_reg_fr_centre_sauvignon`, `ki_reg_fr_vouvray_range`. |
| Label/style distinctions | `ki_wset_eu_rose_anjou_style`, `ki_wset_eu_cabernet_anjou_style`, `ki_wset_eu_rose_loire_style` distinguish origin/style/sweetness. They are not by themselves a complete law/business impact case. |
| Price and commerce applications | Complete `ki_reg_fr_case_loire_list_{action,reason,tradeoff,limitation}` and `ki_reg_fs_case_loire_muscadet_inventory_{action,reason,tradeoff,limitation}`. These address a white-wine list and Muscadet inventory; no supplied Cabernet Franc/Chenin site-and-production decision packet or regional route-to-market evaluation was found. |

Written anchors are `qt_reg_fr_case_loire_list` and `qt_reg_fs_case_loire_muscadet_inventory` in `templates/regional_france_cases.yaml` and `templates/regional_france_rivers_southwest_cases.yaml`. Both are included in `qt_wset_l3_business_case_criteria_19`. Mechanism principles in `areas/regional_france_comparisons.yaml` and `areas/regional_france_rivers_southwest_comparisons.yaml` provide existing explanatory content.

### Northern and southern Rhône

| Dimension | Current anchors and limits |
| --- | --- |
| Location | `ki_rhone_valley_location`, `ki_northern_rhone_location`, `ki_southern_rhone_location` and appellation map facts. |
| Variety and specific rules | `ki_cornas_grape`, `ki_condrieu_grape`, `ki_crozes_hermitage_grape`, `ki_crozes_hermitage_accessory_marsanne`, `ki_reg_fr_rhone_north_syrah`, `ki_reg_fr_rhone_south_blends`. Specific legal/variety distinctions are already present. |
| Environment | `ki_reg_fr_rhone_terraces`, `ki_reg_fr_rhone_south_varied`, `ki_reg_fs_syrah_timing`, `ki_reg_fs_grenache_water`, `ki_reg_fs_chateauneuf_variation`, `ki_reg_fs_lirac_variation`, `ki_reg_fs_gigondas_exposure`, `ki_reg_fs_gigondas_soils`. |
| White and other style | `ki_reg_fs_marsanne_palate`, `ki_reg_fs_roussanne_sensitivity`, `ki_wset_eu_cote_rotie_style`, `ki_wset_eu_cote_rotie_work`, `ki_wset_eu_tavel_identity`, `ki_wset_eu_tavel_style`. |
| Production, price and commerce cases | `ki_reg_fr_case_rhone_cost_{action,reason,tradeoff,limitation}` and `ki_reg_fs_case_rhone_harvest_water_{action,reason,tradeoff,limitation}`. Current red harvest/water and cost decisions are real; a complete Rhône white production/quality/price packet and regional route-to-market case remain absent from the audited banks. |

Written anchors are `qt_reg_fr_case_rhone_cost` and `qt_reg_fs_case_rhone_harvest_water`. Cost cases use `qt_wset_l3_business_case_criteria_19`; the harvest case has the scoped `qt_wset_l3_viticulture_case_action_choice`, `...reason_choice`, `...tradeoff_choice`, `...limitation_choice` in `templates/wset_l3_viticulture_case_choice.yaml`. Those original choices test supplied assumptions and role-specific reasoning, not a universal regional recipe.

## Measured application gaps and bounded next work

1. **Regional routes to sale:** no complete supplied route-to-market evaluation for these four regions was found in the included regional banks. Generic D2 business models/channels already exist in `areas/business_producer_models.yaml` and `areas/business_routes_to_market.yaml`. A search for `en primeur`, `Place de Bordeaux`, `courtier`, `négociant` and `domaine` did not identify a French regional commercial case. This supports an application gap against the broad 3.1.7 requirement; it does not establish that any one of those terms is individually mandated by the public specification.
2. **Burgundy:** provide a supplied Pinot/climat production-quality-price packet using the existing Pinot/site principles. The existing Chardonnay purchasing packet must remain.
3. **Loire:** provide a supplied Cabernet Franc or Chenin site/production packet. Preserve the existing white-list and Muscadet inventory cases.
4. **Rhône:** provide a supplied white production/quality/price packet using existing Marsanne/Roussanne mechanisms. Preserve red harvest/water and cost work.
5. **Timed sustained France practice:** `assets/study/diploma_written_practice.json` version `1.2.0` currently supplies D3 prompts `d3_bairrada_rain`, `d3_ribeira_offer`, `d3_otago_frost`. There is no French-region timed D3 prompt. The independent short written French cases above remain meaningful analytical practice; an absent timed preset is not absence of analysis.

A bounded first authoring batch would add one Bordeaux/Burgundy channel-and-label decision and one Loire or Rhône production decision, with supplied evidence, explicit assumptions, four reasoning roles, plausible scoped choices, original written self-review and primary citations. Reuse existing principles and source IDs. Later sufficiency review should assess the dimension/region matrix and delivered practice, not count maps as reasoning.

## Verification still required

This document is an evidence inventory and a targeted editorial diagnosis. The broad official ranges are not fully exhausted by these examples. It does not establish independent expert approval, complete Diploma coverage, sensory competence, official examination readiness or qualification completion. Any future authoring needs curriculum lint/ingestion, mapped format coverage and focused case tests before it is reported as delivered.
