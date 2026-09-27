# Independent sparkling and fortified review

Reviewed 27 September 2026 by the Level 1/2 research agent, who did not author this sparkling/fortified pack. This is an editorial and scope review, not expert verification, official approval or a claim that the entire app is finished.

## Result

I read all 77 new assertions in `assets/curriculum/areas/wset_sparkling_fortified.yaml`, its source ledger, all 22 family rows and six method rows in `wset-sparkling-fortified-evidence.json`, and the selected existing production/environment assertions. I found no missing required wine family and no substantive false style distinction in those 77 new lessons. The named explanations are actual grape, environment, cellar, style and cost evidence; atlas locations are not counted as explanations.

One existing lesson selected as Level 3 evidence was accessible only at Level 4. Four legal-source jurisdiction fields and one scope note also need correction. These were sent to the parent integrator; no shared content or catalog was edited by this reviewer.

Semantic acceptance is therefore conditional on the precise integration corrections below. The lesson text remains unverified; reading every assertion is not the same as independently verifying every citation or teaching the learner every assessment skill.

## Scope documents and family check

Scope was checked against the live [Level 2 specification, 2026 issue 2.1](https://www.wsetglobal.com/media/19132/wset_l2wines_specification_en_april2026_issue21.pdf), learning outcome 5, printed page 14, and [Level 3 specification, May 2022 issue 2](https://www.wsetglobal.com/media/11731/wset_l3wines_specification_en_highres_may2022_issue2.pdf), Unit 1 outcomes 3–4, printed pages 16–18. The specification defines what learners need to study; its place names do not independently prove local climate, production law or wine style.

The family ledger represents Champagne and its five named districts; the three specified Crémant origins; sparkling Saumur/Vouvray; Asti; Prosecco and Conegliano Valdobbiadene; Cava; German Sekt/Deutscher Sekt; Cap Classique; the six named Australian, New Zealand and US sparkling regions; and Port, Sherry, Muscat de Beaumes-de-Venise and Rutherglen. I matched the required names to explanation evidence rather than treating each district as an additional independent wine family. The narrower Level 2 sparkling origin list is also covered through its named European families and four New World country examples.

Madeira is not a missing mandatory Level 3 family in this specification. Fortified Muscat is required Level 3 theory even though individual tasting suggestions are optional. Recommended sample lists are not a license to omit named theory topics, nor are they an additional mandatory tasting denominator. Level 3 Unit 2 assesses still wines; this review does not certify a learner’s tasting competence.

## Concrete integration findings

### Required pressure handling was mapped only to Level 4

`ki_spark_counterpressure` appears in `methods.tank` and the Prosecco production dimension. At review time, its only installed mapping was `WSET_L4`, core, depth 3. Its assertion explains gas retention during tank processing; the Level 3 process range requires pressure bottling. Add an explicit Level 3 core depth-2 mapping, or replace its evidence selection with another actual Level 3 explanation. Do not lower every advanced sparkling lesson.

`ki_wset_sf_prosecco_style` already explicitly teaches filtering and pressure bottling. `ki_spark_case_transfer_batch_action` also explicitly teaches bulk filtration followed by rebottling under controlled pressure. These are suitable contextual support, but their existence should not hide the level mismatch of the exact selected lesson. The parent acknowledged the mismatch and owns the mapping correction.

### Eight appropriate Level 2 production mechanisms currently use secondary importance

The required-topic catalog is independent of mapping importance, so secondary importance alone does not make a selected lesson inaccessible. Nevertheless, these eight existing facts are appropriate Level 2 core depth-2 production support:

- `ki_spark_traditional`
- `ki_spark_tirage`
- `ki_spark_white_press`
- `ki_spark_autolysis`
- `ki_spark_riddling`
- `ki_spark_disgorgement`
- `ki_spark_dosage`
- `ki_spark_tank`

The comparison of classic Asti with dry-base Prosecco is provided separately by the new Level 2 core facts `ki_wset_sf_asti_method`, `ki_wset_sf_asti_stop` and `ki_wset_sf_prosecco_style`. They explain the fermentation sequence, yeast removal, retained sugar and gas rather than describing tank equipment as a universal method.

Transfer, ancestral and injected-carbonation processes are required at Level 3, and should not become mandatory Level 2 merely because the older lessons also have optional Level 2 mappings. The parent reports removing these advanced method groups from the Level 2 required selection and correcting the relevant rehearsal scope. This reviewer did not rerun the catalog or bank after that report.

### Four legal-source jurisdiction values are semantically wrong

These source rows currently use `Regional wine education` as their jurisdiction. That is an educational category, not the law’s jurisdiction:

| Source ID | Correct jurisdiction |
| --- | --- |
| `src_wset_sf_prosecco_rules` | IT |
| `src_wset_sf_cava_spec` | ES |
| `src_wset_sf_manzanilla_spec` | ES |
| `src_wset_sf_asti_2026` | IT |

The actual referenced specification/ministerial documents can remain legislation sources. Their publishers, URLs and legal content should not be replaced with promotional pages merely to satisfy a citation validator. Reference-work sources may have educational descriptors, but legislation needs its actual legal context.

### The evidence scope note overstates the lower-level separation

The JSON note says specific New World sparkling regions and Reserve Tawny remain Level 3. The installed pack intentionally maps `ki_wset_sf_tasmania_spark`, `ki_wset_sf_marlborough_spark` and `ki_wset_sf_carneros_spark` at Level 2 as bounded country examples. `ki_wset_sf_port_tawny_labels` is also Level 2 and mentions Reserve Tawny.

Replace the note with the distinction actually implemented: Level 2 uses bounded regional examples to teach its country styles; those narrower geographic identities and Reserve Tawny are not separately required Level 2 topics. No false wine claim follows from teaching a little extra context in a shared assertion. Separate required groups, rather than deleting useful text or treating every mentioned name as a new requirement.

## Style and method review

The new lessons correctly distinguish grape skin from the finished wine’s colour: Champagne Blanc de Noirs is pale wine from black grapes. District grape associations are qualified rather than exclusive. Champagne cru is a commune classification, not a Burgundy vineyard category or a promise of bottle quality. Non-vintage/vintage, base blending, lees maturation and dosage have different meanings.

Traditional, transfer, tank, ancestral, Asti and injected-carbonation explanations remain distinct. The existing selected facts teach bottle fermentation, tirage, lees, riddling, disgorgement, filtration and gas retention. Generic dosage applies after sediment removal; regional examples identify their actual production route. Prosecco is not automatically sweet or artificially carbonated. Classic Asti uses fermentation arrest, not spirit addition. The current-law qualification prevents the familiar sweet white Asti example from defining every modern DOCG product.

The three Crémant origins, Saumur and Vouvray have named grape/style explanations. Still Vouvray is not equated with sparkling Vouvray. Cava is not confined to one contiguous Catalan vineyard area. German bottling alone is not proof of German base wine; Deutscher Sekt and traditional Winzersekt are separate origin/method claims. Cap Classique is a South African production category, not a grape or a geographic node. Named New World climate and method examples do not imply that an AVA/GI requires traditional-method sparkling production.

Port’s short fermentation/extraction, spirit arrest, fruit-retaining Ruby, oxidative wood-aged Tawny, late bulk-aged LBV and early-bottled Vintage routes remain distinct. Age-indicated Tawny is not a single harvest or a guarantee that every blended component has the printed age. Reserve does not mean Vintage. Filtered and unfiltered LBV are appropriately separated.

Sherry’s dry base fermentation and subsequent biological/oxidative ageing are not confused with Port fermentation arrest. Palomino bases, raisined Pedro Ximénez and aromatic Moscatel are distinguished. Fino/Manzanilla, Amontillado, Oloroso, Palo Cortado and sweetened blends each have real style explanations. Dry Oloroso is not called intrinsically sweet. Pale Cream is not simply a dark oxidative Cream with another name; Medium is not the dry Amontillado category. Flor, glycerol, acetaldehyde, refreshing soleras and cask oxidation are different mechanisms.

The fresh fortified Muscat example in Beaumes is distinguished from Rutherglen’s increasingly developed oxidative blends. Their grapes, environment, spirit arrest, maturation and cost opportunities are taught, and the Beaumes protected identity is separate from the dry red appellation. Rutherglen tiers are described as a progression of style/complexity rather than exact ages for every component.

The conditional quality/cost applications correctly discuss fruit suitability, site constraints, handling, equipment, stock and maturation. They do not claim that every bottle from a cool region is premium or that greater storage time always gives a better wine or a higher retail price. Shared traditional-method cost support is named separately from regional evidence, avoiding a generic cost formula as the sole proof of a regional practice.

## Independent primary-source spot checks

These are targeted checks of important distinctions, not a fresh verification of every factual clause in the 77 lessons:

| Primary source checked live | What this review established |
| --- | --- |
| [Cava PDO specification](https://www.cava.wine/documents/579/PLIEGO_DE_CONDICIONES_DOP_CAVA_mX07RG7.pdf), sections 2, 3 and 8 | The sweetness and ageing statements match the cited legal text. Reserva/Gran Reserva/Paraje use 18/30/36 months, measured from tirage to disgorgement. Organic requirements refer to the 2025 harvest onward; they do not retrospectively classify every older retail bottle. |
| [Champagne regulatory consumer guidance](https://www.economie.gouv.fr/dgccrf/les-fiches-pratiques/champagne-connaitre-le-langage-des-etiquettes) and [Comité Champagne FAQ](https://www.champagne.fr/fr/foire-aux-questions-champagne) | Commune cru and the white/black grape distinction are supported. The 15-month/three-year ageing explanation is a before-release/cellar duration, not an assertion that every month must be spent on lees. |
| [IVDP special Port categories](https://www.ivdp.pt/pt/vinhos/vinhos-do-porto/categorias-especiais/) | LBV’s filtered/unfiltered difference, Vintage bottle development, Reserve category distinction and age-indicated blending are supported. The lesson correctly acknowledges categories beyond the familiar 40-year label. |
| [Sherry Council Palo Cortado](https://www.sherry.wine/sherry-wine/dry-sherry-wines/palo-cortado) | Its published classic route starts with initial flor and is redirected to oxidative ageing. This supports the teaching example; it should not be presented as an independently proven universal modern legal requirement. |
| [Manzanilla consolidated specification, May 2026](https://www.sherry.wine/documents/596/21052026_Pliego_Manzanilla.pdf), sections B, C and G | It explicitly includes wine and liqueur-wine categories, confines fortification to the latter, and explains Sanlúcar’s humidity/temperature context. This supports qualifying the older blanket assertion that protected dry styles always receive spirit. |
| [MASAF Asti consolidated decree, March 2026](https://www.masaf.gov.it/flex/cm/pages/ServeBLOB.php/L/IT/IDPagina/24256), attachment articles 1, 5 and 6 | The current consolidated document includes tank and traditional bottle products and a pas-dosé-to-sweet range. Its embedded font makes text extraction misleading; the document still supports the broader-current-law caveat instead of assuming all Asti is the classic one-fermentation sweet example. |
| [Cap Classique Producers Association](https://www.capclassique.co.za/) | The primary association defines the South African category through second fermentation in bottle. It does not define one mandatory vineyard district. |
| [Winemakers of Rutherglen classification](https://winemakers.com.au/muscat-of-rutherglen/) | Its four tiers reflect richness, development and complexity; age is one factor. This supports the bounded tier explanation without universal parcel-age promises. |

The Jerez consolidated PDF intermittently failed retrieval in this independent pass. Its exact source and current-law interpretation remain in the author’s ledger; the separate current Manzanilla specification was fetched and read. Several association pages also timed out on direct opening but returned their relevant primary text through search. Those retrieval limitations are not silently counted as complete independent re-verification.

## Review boundary and acceptance checklist

After the exact pressure-handling mapping, legal-jurisdiction metadata and scope-note corrections, the 77 new lessons and the family ledger are acceptable as original study content for integration. The parent must still verify the final exact required-topic selections at both levels, served geography, study rendering, practice answerability, bundled parser/validator, and focused runtime checks. This reviewer ran no SDK or Git commands and changed no shared lesson, source or catalog during this review.

Expert verification, actual course participation, a learner’s practical tasting work and passing the official assessment remain separate from app study completion. This report does not mark the assertions verified or certify any qualification.
