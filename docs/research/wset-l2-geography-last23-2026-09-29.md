# WSET Level 2 geography: last 23 mapped-core practice gaps — 29 September 2026

## What changed

The release audit at the previous local base had **253/276** WSET Level 2
geography core facts with useful practice. The 20 remaining `LOCATED_IN` facts
already had `map_locate`, `map_identify`, and `map_pair`, but those are all one
spatial family. An item-specific, source-linked `authored_choice` now asks for
the place from a different cue: outline, neighbour, coast, administrative
register, production-area description, or county-versus-AVA label reading.
The original three map formats still serve all 20 facts. Each choice has four
distinct options; answer positions are evenly distributed (5/5/5/5) and no
keyed option is the unique shortest or longest.

The other three gaps are Chablis→Chardonnay, Champagne→Chardonnay and
Champagne→Pinot Noir. They had Level 2 depth 1, which served recognition-only
`mcq` despite existing recall questions. Their Level 2 mappings now use depth
2, serving `typed` recall and `flashcard` alongside `mcq` and `map_grape`.
This is a **study-planning choice**, not a claim about WSET's exam format: the
[current WSET Level 2 specification](https://www.wsetglobal.com/media/19132/wset_l2wines_specification_en_april2026_issue21.pdf)
lists Chablis under Chardonnay (printed p. 11), and asks learners to identify
key sparkling grapes, listing Chardonnay and Pinot Noir and Champagne (printed
p. 14). Although the official Level 2 exam is multiple choice, active recall
is a reasonable way for the app to practise those expressly named associations.
The [INAO Chablis](https://www.inao.gouv.fr/produit/chablis-23041) and
[INAO Champagne](https://www.inao.gouv.fr/produit/champagne-21054) product
accounts remain the primary item-level grape citations.

The new Level 2 geography count is **276/276 core facts with useful practice**
on 2026-09-29. This means the *mapped geography core* has two served format
families under the app's coverage rule. It does not measure question quality
review, learner mastery, the whole WSET Level 2 curriculum, or award of a WSET
qualification. All 4,288 bundled items remain marked unverified pending a
qualified subject review.

## Source boundaries and editorial checks

| Items | Cue and source | Boundary |
| --- | --- | --- |
| 13 country→World facts | Neighbour, coastline and outline cues from [Natural Earth Admin 0 country geometries](https://www.naturalearthdata.com/downloads/50m-cultural-vectors/50m-admin-0-countries/) already cited by each item. | Cartographic orientation only; no claim about legal wine boundaries or official WSET assessment requirements. |
| Burgundy→France | Yonne, Côte-d'Or and Saône-et-Loire department cue from the [INAO Bourgogne account](https://www.inao.gouv.fr/produit/bourgogne-blanc-24525). | Does not imply all wine from these departments is Bourgogne AOC. |
| Catalunya DO and Navarra DO | Label and administrative-register cues from [Spain's official protected-wine list](https://servicio.mapa.gob.es/es/dam/jcr%3Af9643333-ef75-4a2f-8864-afd1ade63fd1/02_vinos.pdf); Navarra's north–south cue comes from its [DO wine body](https://navarrawine.com/en/d-o-navarra/). | Navarra asks for the autonomous-community heading rather than a supposedly separate wine region. |
| Delle Venezie DOC | Veneto, Friuli Venezia Giulia and Trento production-area cue from the [DOC consortium](https://dellevenezie.it/en/do-delle-venezie-official-page/). | Country-of-origin inference only. |
| Pays d'Oc IGP | French protected-indication cue from the [EU legal notice](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:52026XC01735). | Does not infer grape variety or wine style. |
| Sonoma and Santa Barbara counties | County-appellation label classification from the [TTB county list](https://www.ttb.gov/system/files?file=images%2Fpdfs%2Fus_by_county_state.pdf), [TTB appellation categories](https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/labeling-wine/wine-labeling-appellation-of-origin), and [California county listing](https://census.ca.gov/regions/). | A county appellation is not presented as a named AVA. The TTB county chart is dated 2004; the state listing independently verifies current county identity. |

The Navarra question asks the learner to join a producer-body orientation cue
(Pamplona to the Ebro) with the autonomous-community heading in the official
register. It avoids giving away the answer in the DO name and adds no grape,
style or legal-boundary claim.

## Verification

`wset_l2_geography_location_clues_test.dart` checks the exact 20 IDs,
item-specific citation links, answer balance, ingestion, and preserved map
formats. It checks that the three grape facts gain recall and that the
`CoverageChecker` measures 276/276 geography core useful practice. The full
release baseline is regenerated separately from the current dataset.
