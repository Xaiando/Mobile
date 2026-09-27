# Read-only Level 3 additional grape role audit

27 September 2026. Scope reference: [WSET Level 3 Issue 2](https://www.wsetglobal.com/media/11731/wset_l3wines_specification_en_highres_may2022_issue2.pdf), Unit 1 LO2 Range 2 (printed pages 13–14 / PDF pages 14–15). Original audit of registered/cumulative Level 3 facts, with raw `subject_id`, `object_id`, relation type and assertion inspected. No SDK/Git/source edits. `build/wset-l3-additional-grape-candidates.json` captures candidate assertions for follow-up; initial text matches include some permission rows, which were manually rejected as explanatory evidence.

## Definite missing regional/style roles

- **Dornfelder / Germany**: no canonical grape node or currently L3-mapped lesson found.
- **Welschriesling / Austria**: no node or mapped lesson found. Sweet white regional context exists but does not name this variety.
- **Saint Laurent (Sankt/St Laurent) / Austria**: no node or mapped lesson under those spellings found.
- **Arinto / Portugal**: no node or mapped lesson found.
- **Alfrocheiro / Portugal**: no node or mapped lesson found.
- **Jaen / Portugal**: no Dão association or style lesson found. Existing `n_grape_pirule_jaen` is explicitly `Pirulé (Jaén, Ribera del Duero)`, linked only by `ki_es_map_ribera_del_duero_pirule_jaen`. Do not rename or reuse that distinct regional reference as a Portuguese teaching fact. Establish the intended Portuguese identity/synonym using an authoritative source before adding it.
- **Trincadeira / Portugal**: no node or mapped lesson found.
- **Bonarda / Argentina**: no node or mapped lesson found (also checked likely Douce Noir/Charbono naming separately before final closure).

## Existing identity/permission is insufficient explanation

- **Petit Verdot / Bordeaux**: only `ki_fr_atlas_pauillac_permits_grape_petit_verdot` (`france_atlas.yaml:4991`), relation `PERMITS_GRAPE`, `subject_id:n_geo_pauillac`, `object_id:n_grape_petit_verdot`. No taught ripening/colour/tannin/blending role. Add an original conditional Bordeaux contribution lesson; retain legal fact separately.
- **Graciano / Rioja**: `ki_es_map_rioja_graciano` (`iberian_grape_maps.yaml:838`) is `PERMITS_GRAPE` from `n_geo_rioja` to `n_grape_graciano`; `ki_es_berry_graciano` teaches black berry colour only. No structural/aromatic blend contribution lesson found.
- **Mazuelo/Carignan / Spain**: Rioja/ Priorat permissions (`ki_es_map_rioja_carignan`, `_priorat_carignan`) and berry colour exist; `ki_reg_sa_maule_carignan` teaches old-vine rainfed heritage in Chile. None teaches a Spanish structural/blending role. Add source-backed contribution/context, without confusing legal permission with style or assuming old vines automatically improve quality.
- **Sárga Muskotály / sweet Tokaj**: correct existing node `n_grape_muscat_blanc_a_petits_grains` and `ki_hu_tokaj_muscat_blanc_a_petits_grains` (`hungary.yaml:115`) explicitly name the synonym but only `PERMITS_GRAPE`. Generic Muscat profile exists; no explicit aromatic contribution to a sweet Tokaj blend. Add a concise original sweet-Tokaj role rather than clone/create a second synonym node or require dry Tokaj.

## Present teaching — do not call these absent

- Muscadelle: `ki_wset_eu_bordeaux_sweet_white` teaches Sauternes/Barsac white blend + noble rot/retained sugar/acidity context.
- Ugni Blanc: `ki_wset_eu_gascogne_dry_white` names its Gascogne white blend association; refreshing style described.
- Petit Manseng: `ki_reg_fs_jurancon_cycle` (`regional_france_rivers_southwest_comparisons.yaml:794`) uses **“Petit and Gros Manseng”**, which a naive contiguous-name search misses. Jurançon harvest/environment and `ki_wset_eu_gascogne_manseng` / `ki_reg_fs_pacherenc_grapes` provide sweet/dry distinctions. Preserve those facts.
- Alsace Muscat and Pinot Blanc: `ki_reg_fe_alsace_muscat_dry`, `ki_reg_fe_alsace_pinot_blanc`; aromatic dryness distinction and lighter measured-acidity comparison.
- Grolleau: `ki_wset_eu_rose_anjou_style`; fruity off-dry Rosé d’Anjou association.
- Cinsault: `ki_reg_fm_bandol_structure`; Bandol rosé/red grape and structural context. Chilean Itata association also exists. More explicit Rhône blending context may improve coverage but is not total absence.
- Marsanne/Roussanne: `ki_reg_fs_marsanne_palate`, `_roussanne_sensitivity`; palate/vineyard/blending context.
- Silvaner/Müller-Thurgau: `ki_reg_de_franken_silvaner_palate`, `_muller_fresh`, Rheinhessen Silvaner; aroma/acidity/ripening/steel distinctions.
- Blaufränkisch: Mittelburgenland soils plus Leithaberg colour/grape association and Mittelburgenland DAC identity exist. Sensory role is weaker than those site/identity lessons; add concise style context if closing a required grape-style dimension.
- Zweigelt: `ki_reg_ah_neusiedler_zweigelt` (`regional_austria_hungary_comparisons.yaml:685`) associates red wine/steel vs wood at Neusiedlersee. No complete absence; a short fruit/structural role can strengthen it.
- Hárslevelű: `ki_reg_ah_tokaj_hars`; softer/aromatic contribution contrasted with Furmint. Dry-specific optional lessons must not inflate compulsory sweet-Tokaj scope.
- Grechetto/Trebbiano/Malvasia: Orvieto blend and Frascati white-family lessons; Trebbiano di Soave freshness separately taught. Clarify Procanico naming if relying on Orvieto's lesson to teach the exact Trebbiano role; do not collapse distinct Trebbiano varieties.
- Fiano/Greco: `ki_reg_isi_fiano_style`, `_greco_style` plus Irpinia terrain/cellar comparisons.
- Viura: `ki_reg_ib_rioja_white_oak`; fruit/aroma/texture and oak choices.
- Mencía: `ki_wset_eu_bierzo_mencia`, `_bierzo_cellar`; origin and varying fruit/structure/oak.
- Airén: `ki_reg_ib_mancha_adaptation`, `_mancha_ferment`, Valdepeñas identity.
- Loureiro: `ki_reg_ib_verde_atlantic`; fresh aromatic Vinho Verde white context.
- Baga: `ki_reg_ib_baga_structure` (`regional_iberia_comparisons.yaml:789`) and Bairrada ripening/cost cases.
- Alicante Bouschet: `ki_reg_ib_alentejo_heat`; ripe/full Alentejo red association.
- Vidal: `ki_wset_nw_ontario_icewine_selection`, `_icewine_style`; naturally frozen concentrated sweet route with acidity.
- NZ Pinot Gris/Riesling/Syrah: `ki_wset_nw_marlborough_aromatics`, `_hawkes_syrah_pinot_gris`, `_otago_aromatics`, `_gisborne_wine_styles`, `_canterbury_style_range`, old Canterbury Riesling; range and country associations present.

Root should author/map the truly missing contribution lessons and append exact IDs to the required matrix. Primary-source factual review and installed serving-mode availability remain necessary; this report does not upgrade verification_status or assign official outcome completion.
