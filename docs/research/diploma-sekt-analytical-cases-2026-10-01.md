# German Sekt: original D4 analytical practice

## Authored content and boundary

Authored 2026-10-01T18:00:00.000Z in the isolated `codex/diploma-depth-continuation` branch based on `d5009c97ac77b78f46aaba8083c8c67e4a42ad7c` (Draft PR #48, dataset 0.24.67). This candidate continues the handover's sufficiency audit and sourced regional leads for WSET Level 4 / Diploma Unit D4 (Sparkling Wines).

The [August 2025 Issue 1.4 Diploma specification](https://www.wsetglobal.com/media/17609/wset_l4wines_specification_en_august-2025.pdf), Unit D4 (Sparkling Wines), includes German sparkling wines (Sekt, Deutscher Sekt, Sekt b.A., Winzersekt). These original scenarios, principles and criteria are app-authored for analytical study; they are not official exam questions or an exhaustive commercial syllabus.

The module contains exactly six principles and two complete four-role analytical cases: fourteen facts, twenty-two nodes, fourteen dated relations and fourteen `WSET_L4`/`core`/depth-3 mappings. All items remain `unverified` and carry `mcq_disabled: true`. All fourteen facts are assigned to the `winemaking` domain, spanning enological method, regulatory origin, base-wine selection, and production-commercial allocation. Explicit D4 item selection keeps these sparkling cases in Unit D4. Lower-track mappings, existing maps, saved writing banks, and duration models remain unchanged.

| Subject | Exact item IDs | Focus |
| --- | --- | --- |
| Sekt origin hierarchy | ki_d4sekt_origin_hierarchy | Sekt (EU base), Deutscher Sekt (100% German base), Sekt b.A. (single Anbaugebiet and mandatory A.P.-Nr.). |
| Winzersekt standards | ki_d4sekt_winzersekt_standards | 100% estate fruit, traditional bottle fermentation (Klassische Flaschengärung), 9 months lees minimum, vintage/variety. |
| VDP.SEKT classification | ki_d4sekt_vdp_classification | Private estate tiers: VDP.SEKT (15m lees) and single-vineyard VDP.SEKT.PRESTIGE (36m lees). |
| Base wine selection | ki_d4sekt_base_wine_selection | Early harvest, botrytis-free fruit, preserved brisk acidity, moderate alcohol (9.5–11.5% abv), gentle pressing. |
| Autolysis vs fruit | ki_d4sekt_autolysis_vs_fruit | Tank (autoclave) primary fruit retention and rapid turnaround vs bottle lees autolysis and mannoprotein mouthfeel. |
| Dosage and style | ki_d4sekt_dosage_style | Balancing high cool-climate acidity across statutory sweetness categories (Brut Nature to Trocken). |
| Winzersekt allocation case | ki_d4sekt_case_winzersekt_allocation_{action,reason,tradeoff,limitation} | Estate Winzersekt vs tank Sekt b.A., impending 24-day lease bill, prepaid merchant vs delayed wholesale distributor. |
| Extended lees positioning case | ki_d4sekt_case_extended_lees_positioning_{action,reason,tradeoff,limitation} | VDP.SEKT 15m vs Prestige 36m single-vineyard lees hold, 30-day lease bill, prepaid restaurant allocation vs export consignment. |

Each case retains a complete prerequisite set across all four roles: ten prerequisites per case point, eighty prerequisite edges in total, combining local principles with foundational business items (`ki_biz_routes_partner_fit`, `ki_biz_routes_reviewable_roles`, `ki_biz_routes_downstream_sales`, `ki_biz_payment_timing`, `ki_biz_inventory_cash`, `ki_biz_profit_cash`, `ki_biz_working_capital`).

## Source distinctions

- The [Deutsches Weininstitut (DWI) quality levels](https://www.deutscheweine.de/wissen/qualitaetsstufen/) outline statutory requirements for Sekt, Deutscher Sekt, and Deutscher Sekt b.A., including regional origin and Amtliche Prüfungsnummer (A.P.-Nr.) testing.
- The [DWI Winzersekt guide](https://www.deutscheweine.de/weinerzeugnis/259/winzersekt/) details estate fruit origin, traditional bottle fermentation, minimum 9 months on lees, and varietal/vintage labelling rules.
- The [VDP.SEKT Statut](https://www.vdp.de/en/vdp-sekt/) defines association tiers: traditional method, estate grapes, 15 months minimum on lees (24m for vintage), and 36 months for single-vineyard VDP.SEKT.PRESTIGE.
- [Commission Delegated Regulation (EU) 2019/934](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R0934) and OIV international code govern sparkling base wine oenological practices, pressing separation, and enrichment limits.
- [Commission Delegated Regulation (EU) 2019/33](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A32019R033) sets statutory residual sugar definitions (Brut Nature <3 g/L without added sugar, Extra Brut 0–6 g/L, Brut <12 g/L, Extra Trocken 12–17 g/L, Trocken 17–32 g/L).
- [The Australian Wine Research Institute (AWRI) fact sheets](https://www.awri.com.au/information_resources/fact_sheets/) ground physiological autolysis mechanisms (yeast cell breakdown releasing mannoproteins and amino acids) and sparkling sensory presentation.

## Fictional cases and templates

All parcels, ripeness logs, vessel/lees trials, panel observations, bottle counts, financial terms, and buyer proposals are fictional exercise inputs. They do not constitute actual producer financial forecasts or German statutory commercial terms.

Four question templates deliver the material:
1. `qt_d4sekt_principle_typed_6` (variant `d4sekt_principle_typed_6`): Bounded recall for key regulatory terms, minimum lees aging months, fungal risks, and sweetness categories.
2. `qt_d4sekt_case_criteria_2` (variant `d4sekt_case_criteria`): Multi-role analytical scenario prompt presenting four correct role summaries and two plausible distractors targeting common fallacies (treating order placement as cash/sell-through; misrepresenting tank wine as Winzersekt; truncating required Prestige lees aging; assuming volume equals profit).
3. `qt_d4sekt_case_written_2` (variant `d4sekt_case_written`): Short answer rubrics matching the four WSET Diploma analytical roles (Action, Reason, Tradeoff, Limitation).
4. `qt_d4sekt_principle_choice_6` (variant `d4sekt_principle_choice_6`): Authored four-option questions providing structured practice for the six underlying principles.

## Integration and validation

- Release: Dataset 0.24.68, published `2026-10-01T18:00:00.000Z`.
- Included areas: `assets/curriculum/areas/diploma_sekt_analytical_cases.yaml`.
- Included templates: `assets/curriculum/templates/diploma_sekt_analytical_cases.yaml`.
- Track scope: Nodes registered in `wset_l4.sparkling.germany`, `wset_l4.sparkling.production`, and `wset_l4.sparkling.commerce`.
- Progress tracking: All 14 items added to `assets/progress/wset_scope.json` under Unit D4.
- Verification: Validated via `tool/curriculum/lint.dart` (0 errors, 3 expected warnings), focused regression tests, and canonical LF hash invariant assertions.
