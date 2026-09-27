# Independent Level 2–3 catalog review

27 September 2026. Reviewer: curriculum critic agent, separately inspecting the integrated requirement catalog, actual assertion text, certification mappings and original rehearsal pool. This is an app curriculum review, not WSET accreditation or an award of a qualification. No SDK or Git commands were run by this reviewer. The reviewer authored Europe, general-production, sparkling/fortified, regional-role and several later closure packs; rereading those assertions is a defensive editorial review, not independent authorship approval. The foundation, New World and grape-structure packs, root-owned catalog integration and other author's rehearsal selection are separately authored inputs to this review. The research agent independently reviewed general production, regional roles and root's European applications.

## Review state

**Final semantic verdict: no remaining substantive Level 2–3 scope or instructional-evidence blocker was identified in the reviewed integrated catalog.** This verdict follows the repaired grape/origin associations, complete structural-profile selection, general and regional explanations, service/fault closures and required rehearsal boundary checks below. It is not inferred from an empty-dimension count. The catalog appropriately keeps `curriculumComplete` and requirement review flags false until the parent's separate delivery and release gates pass.

The final snapshot contains 49 Level 1 requirements with 132 distinct facts, 442 Level 2 requirements with 752 facts, and 888 Level 3 requirements with 1,624 facts. These are cumulative app requirement groups, not official examination-topic counts. All 149 Level 2 grape/origin combinations, 30 grape profiles and 22 Level 3 sparkling/fortified families retain exact selected evidence. `pendingDimensions` is empty; no selected fact is missing, and no explicitly optional enrichment ID appears in the required fact sets.

Reviewed sources of scope:

- [Level 2, April 2026 Issue 2.1](https://www.wsetglobal.com/media/19132/wset_l2wines_specification_en_april2026_issue21.pdf), general outcomes, learning outcomes 3–5 and named grape/origin lists, and storage/service/food advice.
- [Level 3, May 2022 Issue 2](https://www.wsetglobal.com/media/11731/wset_l3wines_specification_en_highres_may2022_issue2.pdf), Unit 1 learning outcomes 1–5 and Unit 2 analytical tasting; the live linked document is Issue 2 despite legacy cover wording.

Reviewed app inputs: `assets/progress/wset_scope.json`, `docs/research/wset-required-study-evidence.json`, all manifest-included knowledge items and mappings, and `assets/study/wset_rehearsal.json` version `2026.09.27-original.4`. The review distinguishes facts that identify a permitted variety, facts that locate a place, and facts that teach a local wine's style and causes. The final integrated Level 2 rows select the exact origin repairs listed below; the one omitted supplementary Châteauneuf variation point is not needed because two actual Grenache/style lessons already support the pair.

## Level 2 named grape/origin combinations

The catalog has 149 combinations across the 30 required grape families. The counts and named origins match the public Level 2 list, including broad GIs and the specified suborigins. Generic grape profiles, geographic pins and named regional context are separately identified. The new context ledger is useful, but its presence alone initially overstated several combinations.

The critic identified these substantive mismatches and supplied exact replacements in `docs/research/wset-grape-origin-contexts-evidence.json`:

| Required combination | Initial evidence problem | Correct evidence |
|---|---|---|
| Syrah and Grenache / Minervois | Pays d’Oc context neither named Minervois nor explained the local Grenache blend | Existing `ki_wset_eu_languedoc_red_blends` and colour distinctions, promoted to Level 2 |
| Viognier / Condrieu | Northern Rhône red and Côte-Rôtie cofermentation context stood in for a white Condrieu lesson | `ki_wset_origin_condrieu_viognier` |
| Sauvignon Blanc / Touraine | Vouvray Chenin was the entire local style context | `ki_wset_origin_touraine_sauvignon` |
| Grenache / Côtes de Provence | Rosé methods taught extraction but did not associate the grape with the wine | `ki_wset_origin_provence_grenache` plus retained rosé production facts |
| Grenache / Rioja and Priorat | Rioja context named Tempranillo; Priorat borrowed broad Catalunya style | `ki_wset_origin_rioja_garnacha`, `ki_wset_origin_priorat_grenache` |
| Tempranillo / Ribera del Duero | Climate alone did not identify its wine grape and red structure | `ki_wset_origin_ribera_tempranillo` plus retained climate facts |
| Merlot / Stellenbosch | Cabernet vineyard facts did not establish local Merlot style | `ki_wset_origin_stellenbosch_merlot`, explicitly limited to a documented producer example |
| Chardonnay / Western Cape | Chenin and Pinotage lessons were the local style evidence | `ki_wset_origin_western_cape_chardonnay` plus the documented Robertson steel/lees example |
| Merlot / California | Broad state context did not name Merlot | Already taught Napa Merlot and Sonoma Merlot-site facts, joined to the California context |
| Pinot Noir / Los Carneros | Regional Chardonnay and warming/cooling facts did not name still Pinot Noir | `ki_wset_origin_carneros_pinot`, retaining marine climate evidence |
| Six named Burgundy villages | Broad Côte de Nuits/Beaune text lacked the actual village/grape/style identity in several rows | New Gevrey, Nuits, Beaune, Pommard, Meursault and Puligny points; red/white exceptions preserved |
| Chardonnay / Mâcon and Pouilly-Fuissé | Warmer Mâconnais climate alone did not identify the wine's Chardonnay association | Existing `ki_wset_eu_maconnais_white_names`, promoted to Level 2 |
| Nebbiolo / Barolo and Barbaresco; Sangiovese / Brunello and Chianti Classico | Useful profile/site/maturation facts did not establish the exact appellation/grape identity in the pair row | Reuse the existing canonical wine/grape identity facts beside the explanations |
| Barbera / Barbera d’Asti | Piedmont timing and a generic Barbera profile did not identify this named wine | `ki_wset_origin_barbera_asti` |
| Chardonnay / Chablis | Climate and cellar lessons did not explicitly identify the named grape/style pair | Selected cumulative `ki_wset_found_familiar_chablis` |
| Cabernet Sauvignon / California | State variation and Zinfandel context did not establish a Cabernet example | Selected `ki_wset_nw_napa_cabernet`, retaining broad California variation rather than fixing a state-wide style |
| Corvina / Recioto della Valpolicella | Sweet dried-grape production did not explicitly distinguish this Corvina-associated family from white Recioto | `ki_wset_ofinal_recioto_corvina`; the current blend allows Corvina and/or Corvinone, so neither purity nor Corvina in every bottle is asserted |

The same evidence file records suitable cumulative Level 1 Chianti, Côtes du Rhône and Châteauneuf-du-Pape style lessons. These should be used rather than authored a second time. A parent region's climate is useful support; it cannot establish that another grape makes the named wine. Conversely, this review does not require a unique terroir history or fixed tasting signature for every village.

**Structural-profile finding closed:** the initial 30 grape rows selected only profile and variation lessons and omitted several expected characteristics. The final catalog selects each new grape-specific structure point with the aroma/profile context; principal-eight rows separately select environment, harvest, cellar and ageing explanations. A shared descriptor-context lesson remains a separate required row, so it need not be repeated in every grape's evidence. Suitable existing introductory fermentation and ripening explanations correctly replace deeper generic mechanisms in beginner evidence. Conditional comparisons are appropriate; a universal alcohol, tannin or acidity value for every bottle is not required.

The registered grape-structure pack contains 30 structural explanations, eight vineyard/harvest explanations and five missing named ageing examples. I read all 43 assertions and the principal-eight exact evidence matrix, then checked the final selected rows. Two genuine acid-reference gaps in Montepulciano and Zinfandel were corrected with bounded primary examples, and a sentence confusing potential and actual alcohol was corrected. Independent primary checks support Barbera's relatively low grape tannin, Corvina's limited pigment/moderate skin tannin/fresh acidity, and the Soave source's qualified Garganega acidity. Existing exact Riesling, Pinot Noir and Hunter Shiraz lessons teach developed aromas and texture. The required axes are represented by actual explanations, rather than berry-colour classification alone.

## Level 3 regional and sparkling/fortified dimensions

The five regional dimensions now explicitly separate grapes/style, environment, production, label identity and quality/price. Named conditional applications are substantially stronger evidence than the initial generic cost-plus lesson, permission rows or geographic selectors. For example, Bordeaux reputation/classification belongs in quality/price evidence; a Merlot/Cabernet blend tradeoff alone does not.

The 22 sparkling/fortified families match the specified Level 3 scope. The content distinguishes Asti's classic single-fermentation sweet route from conventional Prosecco's second tank fermentation, covers the three specified Crémants and Loire sparkling examples, includes Deutscher Sekt and Cap Classique, and distinguishes Port, Sherry and fresh versus cask-aged Muscat examples. Wine identity and geography remain separate where Port and the city of Porto would otherwise be confused.

Two Level 2 delivery gaps were found within that otherwise broader pack: Cava had generic traditional-method and sweetness evidence without a named Cava style point, and Cap Classique's useful grape/style lesson was mapped only at Level 3. The context closure provides `ki_wset_origin_cava_basic_style` and promotes `ki_wset_sf_cap_style`; it does not require advanced Cava legal categories at Level 2.

The final scope reread found two additional boundaries and both are repaired. Transfer, ancestral and force-carbonation processes are explicit Level 3 scope; the three corresponding Level 2-only required rows were removed. I checked every remaining required Level 2 fact: no indirect advanced-method instruction remains. The preservation lesson's use of the word carbonation and Cap Classique's contrast with injected gas are suitable introductory context. Level 2 also needs country sparkling examples from Australia, New Zealand and the USA. `extended_sparkling_country_examples_l2` now selects `ki_wset_sf_tasmania_spark`, `ki_wset_sf_marlborough_spark` and `ki_wset_sf_carneros_spark`, each with a real Level 2 core/depth-2 mapping, beside `ki_spark_traditional`. These bounded examples teach the relevant grapes, fresh bases and bottle-fermentation route without adding those particular regions as new compulsory Level 2 geographic families.

Current legal statements retain meaningful qualifications: modern Asti includes routes beyond the classic sweet example; the 2026 Sherry specifications do not make spirit addition universal for every protected dry wine; Cava Reserva uses the current 18-month minimum. The compulsory Award in Wines denominator excludes Madeira. China and optional atlas references must remain outside this Level 1–3 required denominator.

The new Level 3 role pack supplies actual contributions for Dornfelder, Welschriesling, Saint Laurent, Arinto, Alfrocheiro, Portuguese Jaen, Trincadeira, Argentine Bonarda, Petit Verdot, Graciano, Mazuelo and Sárga Muskotály, alongside stronger Austrian red roles. Jaen uses the verified Mencía synonym rather than the distinct Pirulé/Jaén entry. The three origin families Saumur-Champigny, Friuli Colli Orientali and Castilla y León IGP now have explicit required regional-role rows and geography, with named original explanatory facts rather than geography standing in for style or production.

## Rehearsal scope

The reviewed bank contains 220 original MCQs and 12 written cases. Madeira prompts were already removed from required selection in version `.2`; this preserves the optional-versus-required distinction.

The three remaining scope findings are repaired in version `.3`: Vienna/Gemischter Satz is replaced by a required Welschriesling role; Vin Doux Naturel mutage is available only at Level 3; and the named amber/orange question is replaced by a Level 3 white skin-contact mechanism linked to the actual `ki_win_skin_flavour` lesson. The two Madeira prompts remain excluded. These are appropriate repairs; mapping importance alone would not have made the optional origin or named style compulsory.

Version `.4` makes the ancestral and force-carbonation questions Level 3 only, matching the last scope correction. The final required pools contain 65 Level 1, 190 Level 2 and 220 Level 3 eligible MCQs. Every eligible MCQ link and all 52 criteria across the 12 Level 3 written cases belong to the exact required fact set for their level. Distractor mentions of another process do not make it a required correct-answer topic. No other concrete optional-region or advanced-method answer was found in the reviewed required pools.

The exact bank-link audit distinguished sound missing evidence links from true optional scope. Gentle pressing, unhealthy-fruit sorting, appropriate white fermentation, sparkling-base acidity/alcohol, second-fermentation alcohol and flor air space are compulsory production mechanisms. Their existing explanations appropriately join the relevant catalog rows. The Amontillado/Oloroso questions and written criteria now link directly to the selected original style lessons. Chablis quality limitations, Tokaj selection and the full Portuguese white comparison argument legitimately support required regional reasoning, without adding another region to the denominator.

## General production, advice and analytical tasting

A full reread of the selected Level 3 production assertions supports all public LO1 ranges: vine identity and needs, seasonal cycle and ripening, climate/site/soil effects, vineyard management and hazards, production approaches, sugar concentration, intake and wine routes, oxygen and sulfur dioxide, adjustments, MLC/lees/oak, blending, finishing/stability, packaging/closures and causal cost/quality distinctions. The lessons preserve conditional reasoning rather than asserting universal low-yield superiority, sensory quality from cost, one suitable frost intervention or one cellar recipe for every wine.

The separate LO5 review identified and closed eight missing contexts: three fault explanations, three advice/pairing considerations, and two service-sequence explanations. Existing selected cork taint, oxidation and volatile-acidity lessons are joined by reduction, exact H2S/Brett sensory lessons, excessive sulfur dioxide and out-of-condition distinctions. The app separates sulfur dioxide from hydrogen sulfide and sound maturity from deteriorated condition. Advice now considers bitterness in the dish itself, wine complexity versus fruitiness/intensity, occasion and individual tolerance. Service sequence combines identity confirmation, equipment/temperature preparation, safe opening, condition checks and full service; multi-wine order considers actual intensity and texture with flexible colour/venue conventions.

Food and wine suggestions remain conditional on the person and actual dish. Responsible-service explanations do not advertise wine as a health treatment or invent a personally safe dose. Analytical tasting lessons explain observations, primary/secondary/tertiary origins, structural dimensions, calibration, quality reasoning and readiness/ageing limits; digital logs record practice rather than awarding a professional tasting qualification. The final serving/practice validation remains the parent's gate.

## Delivery and release boundary

The final semantic refresh and exact selection checks are complete. The parent owns served practice, geographic frame/tap checks, integrated tests and release validation. A successful content review does not substitute for those delivery checks. Original facts remain at their actual unverified/expert-review status; this internal review does not upgrade them to expert verification. Recorded app study participation does not award an official WSET qualification, and Level 4 completeness remains outside this Levels 1–3 acceptance.

Snapshot fingerprints before delivery metadata is enabled:

- `assets/progress/wset_scope.json`: `22fcc1db9848b35a39efc4e527ed53885411b3d703319f7fcea8a95ddbe02487`.
- `docs/research/wset-required-study-evidence.json`: `008ad931236429a0d40f2f09ba006a98964125d4c70e1d8f8a1caccfab92f7b6`.
- `assets/study/wset_rehearsal.json`: `997c85b9fecb5cc46016160fee6f0d53bd782e4f531074b54ca09238a0b4540f`.


## Final release-intent refresh after point-specific recall

27 September 2026. This appended read-only acceptance audit preserves the earlier review snapshots and fingerprints above. The current integrated catalog contains **49/442/888 requirements and 132/752/1,625 distinct required facts** for Levels 1/2/3. The increase from the earlier 1,624-fact Level 3 snapshot is the existing, source-cited `ki_spark_counterpressure` explanation, now expressly selected for tank production and Prosecco. It explains retaining fermentation-derived carbon dioxide during processing, is mapped at Level 3 depth 2, and does not introduce a new compulsory Level 2 method or geographic origin. There is no unexplained change to the requirement denominators.

The current evidence ledger still has 149 exact Level 2 grape/origin context entries, 30 grape-structure evidence entries and zero pending dimensions. Required IDs are present in the actual curriculum. The unchanged original rehearsal bank `2026.09.27-original.4` contains **220 distinct MCQs, 12 written cases and 52 criteria**, with eligible MCQ pools of 65/190/220. The point-specific typed bank contains **522 cues**: 520 required shared-subject points plus two additional optional points. Five mapped optional Level 2 examples add only two IDs beyond the required Level 1–3 union because three are required at Level 3. They do not alter the Level 2 required denominator. All cues were independently read beside their linked assertions; five precision repairs and the finite-only grading contract are recorded in `wset-typed-point-cue-independent-review.md`.

The root reports 13 focused checks passing, including presentation of the real bundled 522 cues, grading of every authored finite answer, exact served required cues per level, legacy typed-template suppression and no automatic FSRS writes. Analysis is clean and source lint reports zero errors. These are parent-reported execution results; this reviewer did not execute the SDK. Measured coverage, the final complete regression suite and release/browser gates were still running or pending at this audit. Completion must not be published before those gates actually pass.

**Release-intent verdict:** no remaining substantive scope, semantic evidence or claim-boundary blocker was identified that would prevent publishing the Level 1–3 **app study coverage** flags after the outstanding delivery gates pass. A static count or this conditional review alone is insufficient. The current metadata remains honest: all three `curriculumComplete` flags and requirement `reviewed` flags are false while release validation is pending. At publication, the parent should update those internal scope-review flags, clear genuinely closed gaps and refresh pending metadata/document wording together; internal review must not change fact expert-verification statuses. Diploma remains incomplete.

Two release wording refreshes were sent to the parent: the Home progress card's fixed “Full level coverage is still being built” sentence needs a neutral or level-sensitive message once lower-level coverage is published; and old Level 2/3 gap strings naming already-authored outcome/sparkling/regional additions need clearing at the final metadata change. Historical dated audit documents may retain their earlier snapshots when clearly identified as historical. The delivery ledger must report the final tests and browser outcomes actually observed, rather than convert planned checks into passed claims.

The progress code and learner documentation preserve the distinction between complete app coverage, a learner's app study milestone, expert fact review and an official qualification. The study milestone requires nonempty current required material, no unserved facts, required memory mastery, reviewed topics and saved practice participation. Rehearsals/calibration/physical observations do not award an official score or objectively validate unknown wines; written work remains explicit self-review. An exam pass is separately learner-declared and cannot be inferred from app progress. Official teaching, independently assessed tasting/written performance and passing the WSET examination remain external. New content retains its factual review status, and China/other-beverage/history enrichment does not inflate the Award in Wines denominator.

Current pre-publication fingerprints for this refresh:

- `assets/progress/wset_scope.json`: `fc8695102c71f5aa1c0f3b226235460a21ae4866a32e53860c8203a1856257fb`.
- `docs/research/wset-required-study-evidence.json`: `db4f6a106a17712b0b85357a87c4d73f981f612e43af2047a68e207bb64295a6`.
- `assets/study/wset_rehearsal.json`: `997c85b9fecb5cc46016160fee6f0d53bd782e4f531074b54ca09238a0b4540f`.
- `assets/study/wset_typed_point_cues.json`: `ff182ac7d0cdc3ae07641662e34aa266ce11efa04640d79bfea1b5a7fcdeb615`.
