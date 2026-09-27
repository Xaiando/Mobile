# Chablis and Alsace named-location completion

The new `assets/curriculum/areas/france_atlas_completion.yaml` adds 71 named
geographical subjects, 71 cited location items and 142 editorial track mappings:
30 Chablis Premier Cru climats and 41 Alsace Grand Cru appellations. Existing
authored rows remain untouched. Items remain `unverified` and are tertiary atlas
study on both tracks; this does not establish examination-scope completeness.

Together with `france_atlas.yaml`, this represents all 40 Premier Cru **label
climat names**, all 17 Chablis umbrella names, and all 51 Alsace Grand Cru
appellations. The 40 names are not the larger set of individual cadastral
lieux-dits or all underlying classified plots. A constituent climat is retained
as its own place; its assertion states its umbrella grouping without turning
the umbrella reference point into a boundary containing other points.

## Primary name registers

- [Chablis specification, homologated 11 December 2023](https://www.chablis.fr/gallery_files/site/25717/25779/25781.pdf),
  reproduced by BIVB: Chapter I, II.2–4 lists 40 names and explains the umbrella
  grouping; Chapter I, X confirms the 40/17 counts. Page 1 was visually inspected.
- [INAO Chablis Premier Cru register](https://www.inao.gouv.fr/produit/chablis-premier-cru-fourchaume-23059):
  current regulator product entry, with the classified-climat cadastral table
  used only for identifying lieu-dit names. Its historical name associations do
  not make a current cadastral outline a legal vineyard boundary.
- [Chablis standard amendment, 5 February 2026](https://eur-lex.europa.eu/legal-content/FR/TXT/?uri=CELEX:52026XC00744):
  the geographical-area change updates the administrative reference without
  changing the production perimeter. It does not replace the named-climat list.
- [Alsace Grand Cru specification, homologated 4 July 2025](https://info.agriculture.gouv.fr/boagri/document_administratif-9f9cedf1-9289-4ab8-aaf0-29c6aa255616/telechargement),
  Ministry of Agriculture publication of 17 July 2025. The current
  [INAO Vorbourg register](https://www.inao.gouv.fr/produit/alsace-grand-cru-vorbourg-muscat-21577)
  identifies this homologation. Download attempts timed out during this
  continuation; the official indexed text and the INAO denomination registers
  corroborate the names. Every Alsace item additionally cites the existing
  INAO commune-area register, which identifies its named denomination.

## Separate coordinate snapshots

Each snapshot has one licence. Source metadata remains in every feature.
The main completion snapshot does **not** include the cadastral/locality points.

| Snapshot | Points | Licence | SHA-256 |
| --- | ---: | --- | --- |
| `france_atlas_completion_points.geojson` | 47 | Licence Ouverte / Open Licence 2.0 | `1cb8d2bff646ad71bff6f829bf355a0cc09084672c6e3b8bfa579fe30aa9b0be` |
| `france_atlas_completion_cadastre_points.geojson` | 23 | Licence Ouverte / Open Licence 1.0 | `53ea8cb1fcd2dc05c0b2c531953451d73cf1fad9a19e2af1bef5883e92266d70` |
| `france_atlas_completion_reference_points.geojson` | 1 | CC0 1.0 | `99749e76f6610838d8833c11d864ed0d19db62cf35421065c53697398bcbea94` |

### INAO parcels

The 47 points comprise all 41 missing Alsace Grand Cru locations and six Chablis
climats: Vaupulent, Vaugiraut, Les Fourneaux, Chaume de Talvat, Côte de Jouan and
Les Beauregards. Exact denominations and their `id_denom` values are retained.

- [INAO parcel-delimitation dataset](https://www.data.gouv.fr/datasets/delimitation-parcellaire-des-aoc-viticoles-de-linao/).
- [Pinned 21 September 2026 archive](https://static.data.gouv.fr/resources/delimitation-parcellaire-des-aoc-viticoles-de-linao/20260921-213954/2026-09-21-delim-parcellaire-aoc-shp.zip).
- Raw archive SHA-256:
  `6f84e0622c2a27d35fc1ad7b39629856bc5038aa38b9d629758c2fb873801d81`.
- Attribution: Institut national de l'origine et de la qualité (INAO).
- Retrieved 26 September 2026; Licence Ouverte 2.0.

Select records by exact denomination, dissolve by `id_denom` in Lambert-93,
compute an interior label point with mapshaper 0.7.67 `-points inner`, then
reproject to WGS84. Every resulting point has a finite coordinate; no centroid
fallback was needed. These are vineyard location references, not bundled parcel
boundaries or legal production-eligibility determinations.

### Cadastre Etalab

The 23 points derive from the official June 2026 communal lieux-dits snapshots,
using the INAO climat-to-lieu-dit table above. Repeated polygons bearing the same
name in the same commune are dissolved before computing an interior point. The
original commune source was fetched and its exact cadastral label verified for
each point. DGFiP supplies the PCI data, redistributed by DINUM/Etalab under
Licence Ouverte 1.0; see the [official dataset metadata](https://www.data.gouv.fr/api/1/datasets/cadastre/).

| Commune | Snapshot URL | SHA-256 of decompressed GeoJSON |
| --- | --- | --- |
| 89068 Chablis | [June 2026 lieux-dits](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89068/cadastre-89068-lieux_dits.json.gz) | `0d53f1927a93188b64c882aa852f8262f028a3323211d4db9f0a9bae9bbb0a45` |
| 89034 Beine | [June 2026 lieux-dits](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89034/cadastre-89034-lieux_dits.json.gz) | `af65271051788aac1f44085dfd02367e1dedfddd5ef5bf363eced662ad2c2a56` |
| 89123 Courgis | [June 2026 lieux-dits](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89123/cadastre-89123-lieux_dits.json.gz) | `26d901092fcace2c2df3002369856a67de27e766cb4509ccdeca70ba823ad537` |
| 89168 Fleys | [June 2026 lieux-dits](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89168/cadastre-89168-lieux_dits.json.gz) | `79e720f783e857dc86382876ff583bc07e4ecdce9fec29059000f93aaf14c568` |
| 89242 Maligny | [June 2026 lieux-dits](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89242/cadastre-89242-lieux_dits.json.gz) | `55373ff78d1e9b7a168b31efc497c985aef1a2b07712b16fe5b53e3408a4cd1d` |

| Climat | Exact cadastral label | Commune |
| --- | --- | --- |
| Chapelot | LES CHAPELOTS | 89068 |
| Pied d'Aloup | PIED D'ALOUE | 89068 |
| Côte de Bréchain | COTE DE BRECHAIN | 89068 |
| L'Homme Mort | L'HOMME MORT | 89242 |
| Chatains | LES CHATAINS | 89068 |
| Sécher | SECHER | 89068 |
| Beugnons | LES BEUGNONS | 89068 |
| Les Lys | LES LYS | 89068 |
| Mélinots | LES MINOS | 89068 |
| Roncières | LES RONCIERES | 89068 |
| Les Épinottes | LES EPINOTTES | 89068 |
| Forêts | LES FORETS | 89068 |
| Butteaux | LE MILIEU DES BUTTAUX | 89068 |
| Troesmes | COTE DE TROUEMES | 89034 |
| Côte de Savant | COTE  DE SAVANT | 89034 |
| Vau Ligneau | VAU LIGNEAU | 89034 |
| Vau de Vey | VAU DE VEY | 89034 |
| Vaux Ragons | VIGNES DES VAUX RAGONS | 89034 |
| Morein | MOREIN | 89168 |
| Côte des Prés-Girots | COTE DES PRES GIROT | 89168 |
| Côte de Vaubarousse | COTE DE VAUBAROUSSE | 89068 |
| Berdiot | BERDIOT | 89068 |
| Côte de Cuisy | COTE DE CUISSY | 89123 |

The historic INAO table uses Aloup, Butteaux and Troesmes; the current cadastral
labels use Aloue, Buttaux and Trouemes. These are explicitly recorded spelling
associations within the named commune. Mélinots uses the table's Les Minos
association. Vau Ligneau retains the current exact cadastral name rather than
the historical Vau Vigneau spelling. Côte de Cuisy also receives the commonly
used Côte de Cuissy alternative name. A selected constituent lieu-dit point
does not identify the entire legal climat footprint.

### Côte de Fontenay limitation

No distinct Côte de Fontenay parcel record occurs in the pinned INAO archive;
the current cadastre no longer contains the historical exact Côte de Fontenay
label. A similarly named `LA COTE` was deliberately not asserted to be the
climat without a documented name association. The actual
[Wikidata Fontenay-près-Chablis coordinate](https://www.wikidata.org/wiki/Special:EntityData/Q1139642.json)
is retained as a **representative locality reference**, CC0 1.0, retrieved
26 September 2026. The INAO table independently locates the climat in that
commune. Its marker metadata explicitly says it is not a vineyard marker or
climat boundary. The independent fine-scale location remains an open refinement;
do not claim 40 precise Chablis Premier Cru vineyard markers.

Local validation confirms all 71 point IDs and coordinates are distinct, every
new item has citations and both track mappings, and all 70 parcel/cadastral
points lie inside their actual source polygons (including exclusion of holes).
The combined lists contain exactly 40 named Chablis Premier Cru subjects and
51 Alsace Grand Cru subjects. Bundle lint and generation validation follow the
parent task's manifest/layer integration.

No OSM-derived geometry,
copyrighted map tracing or manually invented coordinate is used.
