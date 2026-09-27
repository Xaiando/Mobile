# French atlas source notes

The curriculum in `assets/curriculum/areas/france_atlas.yaml` adds 290 French
geographical subjects. Its track mappings are editorial and its knowledge items
remain `unverified`; they do not claim complete WSET or CMS examination coverage.

`france_atlas_areas.yaml` records INAO geographical-area identifiers for integration
into the map-layer recipes. These identifiers describe production communes, not
the planted vineyard boundary. Traditional areas combine the explicitly named
appellations; they do not gain a new legal boundary. Site recipes are recorded
separately because a commune outline cannot distinguish neighbouring climats.

## Parcel-derived markers

`france_atlas_points.geojson` contains 59 representative points derived from the
INAO national parcel delimitation published on 21 September 2026. These include
all seven named Chablis Grand Cru climats, four Chablis Premier Cru climats,
32 Côte d'Or Grand Cru appellations, ten Alsace Grand Cru appellations, and six
Jura/Marcillac fallbacks whose old production communes cannot safely be replaced
by the larger outlines of their modern successor communes.

- Dataset: [INAO parcel delimitation](https://www.data.gouv.fr/datasets/delimitation-parcellaire-des-aoc-viticoles-de-linao/).
- Original archive: [2026-09-21 shapefile snapshot](https://static.data.gouv.fr/resources/delimitation-parcellaire-des-aoc-viticoles-de-linao/20260921-213954/2026-09-21-delim-parcellaire-aoc-shp.zip).
- Original archive size: 267,322,044 bytes.
- Original archive SHA-256: `6f84e0622c2a27d35fc1ad7b39629856bc5038aa38b9d629758c2fb873801d81`.
- Licence: Licence Ouverte / Open Licence 2.0.
- Attribution: Institut national de l'origine et de la qualité (INAO).
- Retrieved: 26 September 2026.

The shapefile's `denom` name was matched to each curriculum subject; the matched
`id_denom` appears in the point's properties. It differs from the `IDA` field in
the separate commune CSV. Parcel records were dissolved by `id_denom`, a
mapshaper interior label point was calculated in the native Lambert-93 projection,
and that point was reprojected to WGS84. For Chambertin-Clos de Bèze and
Mazoyères-Chambertin the interior-point algorithm returned no point; their
area-weighted parcel centroids were used and identified explicitly in metadata.

The Jura region marker represents a sourced Côtes du Jura parcel point. The
Southwest France region marker represents a sourced Marcillac parcel point.
Neither representative region marker is a boundary of the larger region.
The source geometry is informational; the approved specification and municipal
delimitation plans remain authoritative for legal production eligibility.

Six Premier Cru names are absent from this digital parcel snapshot: Montée de
Tonnerre, Vaulorent, Vaillons, Montmains, Côte de Léchet and Beauroy. Their
fine-scale markers are provided separately in
`france_chablis_cadastre_points.geojson`, derived from the official June 2026
Cadastre Etalab lieux-dits polygons for Chablis (89068). The accompanying
`france_chablis_cadastre_sources.md` records the cadastral-to-climat name links
from the INAO specification and the source archive hashes.

## Champagne traditional areas

`france_champagne_points.geojson` contains four traditional-area markers.
Montagne de Reims and Côte des Blancs use Wikidata coordinates (CC0). Vallée de
la Marne and Côte des Bar use labelled representative commune points derived
from IGN ADMIN EXPRESS COG CARTO, edition 1 January 2026 (Open Licence 2.0).
Each feature names its source and explains its marker basis. These are not
polygon boundaries of the traditional Champagne areas.

## Grape geography questions

Sixteen forward `PERMITS_GRAPE` completeness assertions cover lists explicitly
curated from the cited legal specification or regulator register. The neutral
relations contain every variety in each asserted list. Principal and accessory
relations already present in the curriculum are retained separately.

The current [Champagne EU specification, 11 June 2026](https://eur-lex.europa.eu/legal-content/FR/TXT/PDF/?uri=OJ%3AC_202603119)
lists nine varieties, including Chardonnay rose and the conditional adaptation
variety Voltis. The Voltis knowledge item states its regulated experimentation
status and also cites an INAO/CIVC source explaining that status. An older list
of seven is insufficient for current absence-based grading.

Partial positive permissions for Châteauneuf-du-Pape, Château-Chalon and Madiran
have no completeness assertion. Missing relations for those subjects must not
be treated as proof that a grape is prohibited.
