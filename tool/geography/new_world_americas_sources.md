# Additive Americas geography, researched 26 September 2026

This addition authors **191 nodes, 191 primary-cited `LOCATED_IN` items and 382 depth-2 mappings** (WSET L3 and CMS Europe Certified; Diploma inherits L3). Every new item remains `unverified`: the expert-review ledger and the analytical Diploma curriculum are separate work. It preserves earlier nodes rather than duplicating them.

| Country | New places | Scope of this addition |
|---|---:|---|
| Canada | 32 | Ontario 14; British Columbia 18 |
| Argentina | 41 | Ten administrative province frames and 31 registered wine IGs |
| Chile | 30 | Atacama, northern/central zones and selected areas, Austral and its current subregions, Rapa Nui |
| United States | 88 | California 83; Oregon-only 1; Washington-only 2; two multistate AVAs associated with these states |

There are **96 new primary citations**. Argentine IG items reuse the existing `src_atlas_ar_gis`, and US AVAs also reuse the existing TTB register citation. The 88 US primary references are 87 distinct eCFR AVA sections plus the current Columbia Hills final rule. No examining-body syllabus is used as a fact source.

## Closed geographical inventories

“Closed” below concerns the named geography in the pinned official register; it does not mean complete wine production, grapes, climate, business, tasting or exam preparation. These are editorial regression inventories, not `relation_set_assertions` for offering unresearched absent relationships as answers.

**Ontario:** [OWAA overview](https://vqaontario.ca/ontario-appellations/) lists three main appellations and eleven sub-appellations. Its [current West Niagara page](https://vqaontario.ca/ontario-appellations/niagara-peninsula/west-niagara/) identifies three regional appellations; the [2025 official map booklet](https://office.vqaontario.ca/vqaservices/public/OWAA-MAPS_BOOKLET-APPELLATIONSET-2025.pdf) dates West Niagara recognition to 2024. The existing three main appellations plus these fourteen additions cover the following seventeen names:

- Main: Niagara Peninsula, Lake Erie North Shore, Prince Edward County.
- Regional: Niagara Escarpment, Niagara-on-the-Lake, West Niagara.
- Niagara sub-appellations: Beamsville Bench, Twenty Mile Bench, Short Hills Bench, St. David’s Bench, Lincoln Lakeshore, Niagara Lakeshore, Niagara River, Four Mile Creek, Creek Shores, Vinemount Ridge.
- Lake Erie North Shore sub-appellation: South Islands.

The regional appellations overlap. The ten Niagara sub-appellations use their fully containing Niagara Peninsula parent, so the single-parent study tree does not invent exclusive membership in one regional group. South Islands uses Lake Erie North Shore. Existing generic Ontario is a province frame, not a fourth main wine appellation.

**British Columbia:** [BC Reg. 168/2018, section 56](https://www.bclaws.gov.bc.ca/civix/document/id/complete/statreg/168_2018/) is current to 22 September 2026 and last amended 14 July 2025. Excluding the generic British Columbia indication, it has nine main wine GIs and twelve sub-GIs. Existing Okanagan Valley, Similkameen Valley and Golden Mile Bench plus eighteen additions cover all twenty-one names:

- Main: Fraser Valley, Gulf Islands, Kootenays, Lillooet, Okanagan Valley, Shuswap, Similkameen Valley, Thompson Valley, Vancouver Island.
- Okanagan subdivisions: East Kelowna Slopes, Golden Mile Bench, Golden Mile Slopes, Lake Country, Naramata Bench, Okanagan Falls, Skaha Bench, South Kelowna Slopes, Summerland Bench, Summerland Lakefront, Summerland Valleys.
- Vancouver Island subdivision: Cowichan Valley.

Every BC subdivision uses the containing subdivision explicitly stated in the legislation. The closed lists do not cover every emerging Canadian growing area, Quebec or Nova Scotia.

**California, Oregon and Washington:** [TTB established AVAs](https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/established-avas), page updated **18 August 2026**, provides names, CFR sections, states/counties and full-versus-partial nesting. The committed `new_world_americas_us_inventory.json` records every name/CFR identity: **196 unique AVAs**, consisting of CA154, OR19 and WA18 single-state AVAs plus five multistate AVAs associated with OR/WA. State-associated totals are **California154, Oregon23, Washington22**; the latter two counts overlap and must not be summed as unique AVAs.

The five multistate names are Columbia Gorge (OR/WA), Columbia Valley (OR/WA), Lewis–Clark Valley (ID/WA), Snake River Valley (ID/OR), Walla Walla Valley (OR/WA). Lewis–Clark and Snake River are new and use the United States parent. Existing multistate nodes remain intact. The TTB `*` marker means partial overlap and is excluded from full-containment parent selection. Some broader parents, including California or North Coast, are therefore intentional.

[Columbia Hills, T.D. TTB-206](https://www.govinfo.gov/content/pkg/FR-2026-08-17/pdf/2026-16701.pdf), effective **16 September 2026**, is entirely within Columbia Valley. It is newer than the pinned community polygon collection and uses an exact published park reference, with no guessed boundary. Beverly, Washington was missed by code-only state matching; the source uses the full state name. Snake River Valley was missed by whitespace in `ID| OR`. The author normalises both cases. The California San Antonio Valley AVA has its own qualified ID, `n_geo_san_antonio_valley_california`, distinct from the existing Chilean valley.

## Argentine and Chilean additions

**Argentina** uses the [official province list](https://www.argentina.gob.ar/pais/provincias) and the [current INV IG/DOC register](https://www.argentina.gob.ar/sites/default/files/i.g._y_d.o.c._de_la_republica_argentina_1.pdf), linked from [INV protection of origin](https://www.argentina.gob.ar/inv/proteccion-del-origen). Names and full containment come from the register’s department/province column, not marketing regions. The ten new province frames are Catamarca, La Rioja, Tucumán, Jujuy, Chubut, La Pampa, Buenos Aires, Córdoba, San Luis and Entre Ríos. These administrative frames do not independently assert new wine IG status.

The 31 additions include the registered wine Cuyo, Valles del Famatina, Valle de Chañarmuyo, Tinogasta, Santa María, Belén, Tafí, Quebrada de Humahuaca, Valle del Tulum, Valle de Zonda, Valle de Calingasta, Barreal, Cachi, Molinos, San Carlos in Salta, Alto Valle de Río Negro, Añelo, Trevelin, Chapadmalal, Villa Ventana, Colonia Caroya, Victoria in Entre Ríos, La Consulta, Barrancas, Lunlunta, Distrito Medrano, Lavalle, San Martín, Rivadavia, Junín and General Alvear in Mendoza. Distrito Medrano spans Junín/Rivadavia and therefore uses Mendoza. Registered wine Cuyo includes Mendoza, San Juan and La Rioja; it is not asserted to be coextensive with the informal physical Cuyo region. The whole Argentine IG register is **not** claimed closed by this selection.

**Chile** uses [Decree464 consolidated 14 July 2026](https://www.bcn.cl/leychile/Navegar/imprimir?idNorma=13601&idVersion=2026-07-14), the detailed [2018 Decree56 geography amendment](https://www.bcn.cl/leychile/navegar?i=1118954), and [Decree27 published 14 May 2025](https://www.diariooficial.interior.gob.cl/publicaciones/2025/05/14/44148/01/2643653.pdf). The latest 2026 amendment was checked for continuing geographical hierarchy. Added geography includes Atacama/Copiapó/Huasco, Teno/Lontué, Claro/Loncomilla/Tutuvén, selected legally named Maipo/Cachapoal/Colchagua/San Antonio/Curicó areas, Austral/Cautín/Osorno/Chiloé and Rapa Nui–Isla de Pascua. Legal Cautín includes Perquenco/Galvarino; legal Osorno includes specified communes in Los Lagos and Los Ríos. Rapa Nui’s legal definition concerns the commune’s insular territory, so an Easter Island reference does not claim boundary equivalence.

These thirty additions close missing major northern/far-southern frames, **not** every named Chilean communal wine area or every Costa/Entre Cordilleras/Andes usage. Peumo legally includes several communes; San Vicente is not invented as a separate legal area. Selected areas may use a fully containing valley where a finer legal zone could be authored later.

## Marker licences and immutable snapshots

Markers are study references, not authored legal polygons. A gazetteer city, municipality, island, park or terrain point may differ from a wine boundary. This is stated in each feature’s `point_role` and `label_note` and in the fact’s prose.

| Snapshot | Points | Licence | SHA-256 |
|---|---:|---|---|
| `new_world_americas_points.geojson` | 144 | CC0 1.0: UC Davis AVA interiors and Wikidata published coordinates | `4ff905658bc90c7bde1f732f4d3dc35ddd33794b85fc7d0eb1a2b3303383b284` |
| `new_world_americas_gazetteer_points.geojson` | 47 | CC BY4.0: GeoNames published rows | `da030bbaf1557eafef7b360e879c0a85949d02c750d37f8eeea15b82808b839c` |
| `americas_country_islands.geojson` | 2 complete polygon parts | Natural Earth public domain | `fa2e4dac547eb06e8d4971285301d9ee091ef4bf3c7ab97f2531b97a243b8c93` |

The CC0 snapshot contains **87 AVA polygon-interior references and 57 Wikidata references**. UC Davis commit `7af5b29d45aee5e6c6ce3889e9b1de19085d7107` has aggregate SHA-256 `c90068f7154764519f0a7c6fb2788e597b7c56bf7581e8c0faa979554d984926`. Source interiors are the widest verified horizontal scanline interval midpoint across 63 scanlines per original polygon; holes are excluded, and the result is checked inside the actual source geometry. This does not publish or invent the source’s legal status or an official centroid. Wikidata features retain entity/coordinate statement IDs, precision and the exact published point.

Valid unique registry provenance URL for the combined CC0 snapshot: [pinned UC Davis aggregate blob](https://github.com/UCDavisLibrary/ava/blob/7af5b29d45aee5e6c6ce3889e9b1de19085d7107/avas_aggregated_files/avas.geojson). Feature metadata separately identifies the Wikidata portion. Primary wine facts do not cite this community dataset as their legal authority.

GeoNames licence and attribution: [GeoNames data](https://www.geonames.org/export/), [CC BY4.0](https://creativecommons.org/licenses/by/4.0/). Each feature retains exact row ID, original name, feature class/code, last-modified date, country dump URL and complete extracted-country-file SHA. Country dump hashes:

| Dump | Extracted UTF-8 country text SHA-256 | Downloaded ZIP SHA-256 when newly retrieved here |
|---|---|---|
| [CA.zip](https://download.geonames.org/export/dump/CA.zip) | `3715e892de87dacb72ddfa4089542fd7200e97f86fb458a8ab0a0687172c9639` | `7ec802a6562c7fba661aed51e229b63fadb7ae43a4908fdb6ebc1af3f8e4a1a5` |
| [AR.zip](https://download.geonames.org/export/dump/AR.zip) | `4b33f774103c9390525ad774e59371d5244ebeffcd709fde5559751cf49ac688` | Reused earlier local pinned country text |
| [CL.zip](https://download.geonames.org/export/dump/CL.zip) | `8073778743e096619f023343c3e372102986122e72aee812973507a5669ceb5b` | `8c438f284db18a1156f3f9e20098a3da91af085e081bb597661d203e900e3109` |

The forty-seven GeoNames references are Canada32, Argentina11 and Chile4. No manual coordinate offsets were applied. Specific rejected homonyms/errors: Barreal’s English Wikipedia title resolved to Puerto Rico; use exact San Juan GeoNames3864688. A Wikidata point labelled Junín,Mendoza was actually near Junín,Buenos Aires; use Mendoza GeoNames3853355. Zonda’s northern namesake is rejected in favour of qualified Villa Basilio Nievas. The wrong Apalta farm near Rengo is rejected; the CC0 Apalta village reference is explicitly identified. Chapadmalal uses nearby Colonia Chapadmalal as a named orientation locality because the coarse coastline excluded the beach reference. Vinemount Ridge uses Fonthill, matching the regulator’s named Fonthill Kame terrain reference. Penticton for Skaha Bench and Temuco for Austral are qualified regional orientation references, not asserted vineyard or legal centroids.

## Sourced island geometry repair

The 50m bundled country outlines omitted the real markers on Salt Spring Island and Rapa Nui. Moving them to mainland references would misrepresent the named geography. `americas_country_islands.mjs` instead selects exactly one original polygon part from the corresponding `ADM0_A3` country in [Natural Earth 10m countries5.1.1](https://www.naturalearthdata.com/downloads/10m-cultural-vectors/10m-admin-0-countries/). Its [terms](https://www.naturalearthdata.com/about/terms-of-use/) permit commercial redistribution in the public domain.

Archive: `https://naciscdn.org/naturalearth/10m/cultural/ne_10m_admin_0_countries.zip`, SHA-256 `ce1ac7036499a0edd641fbc093cd209a98f96a49d2eca8480aaacad35138a7f6`. Selected original source parts: Canada index129 of412, 44vertices; Chile index4 of163, 37vertices. Selection is by exact point containment in the source country feature. Every exterior/hole vertex is retained. There is no clipping, buffering, tracing or coordinate invention.

`src_ne_americas_island_parts` is an additive country source. The `natural_earth.supplement` recipe merges those parts by country key, preserving the existing France map-unit replacement. The country-layer preview is352750bytes, below the1.5MB layer limit. All191 original and six-decimal manifest-rounded Americas points fall inside rebuilt country polygons. The Chile frame now includes its Pacific island; a focused island inset can improve later study-map framing without changing the point’s location.

## Reproduction and checks

Normal builds read the three checked-in snapshots offline. Research authoring is explicit; it does not run in normal builds:

```powershell
& 'C:\Program Files\nodejs\node.exe' tool/geography/new_world_americas.mjs --author
& 'C:\Program Files\nodejs\node.exe' tool/geography/americas_country_islands.mjs --author
& 'C:\Program Files\nodejs\node.exe' --test tool/geography/new_world_americas.test.mjs tool/geography/americas_country_islands.test.mjs
```

The author expects the pinned AVA aggregate and TTB HTML (`.dart_tool/new_world_ava_aggregate.geojson`, `.dart_tool/new_world_ttb.html`), current-retrieval country gazetteer texts at the explicit paths in the script, and the Wikidata research cache `.dart_tool/new_world_americas_entities.json`. Missing Wikidata entities are fetched from the named sitelinks via the official API, with published Earth coordinates only. Reproducing an old research edition requires retaining these pinned inputs: live gazetteer/entity/register editions can change and must be reviewed as new snapshots. The TTB HTML SHA-256 is `3567f820daeea4fb48aec940a125e6a631bc15e8516aec995f6a2921be78d2d8`; the committed name/CFR inventory records that edition. The island author additionally expects the pinned 10m ZIP and extracted shapefile under `.dart_tool/americas_ne_10m_admin_0_countries`.

Six focused Node tests passed: Ontario17 and BC21 official names/parents; the196 TTB name/CFR identities with state-associated counts; all new facts/citations/tracks/point IDs and two homonym regressions; all exact/rounded country containment plus France map-unit preservation; immutable complete source island parts. The author checks published references, parents, finite coordinates, unique identities, noncoincident same-type new markers, the aggregate hash, and no authored node/item deletions. Full Dart curriculum lint, generated map eligibility and release coverage are integrated by the root task.

## Remaining meaningful gaps

The broader New World work must still be audited country by country. Within this contribution, Canadian areas outside the closed Ontario/BC lists; additional Chilean communal areas, Secano Interior and lateral geographic designations; remaining Argentine registered districts/localities; other US states/AVAs; and the all-country analytical content remain separate tasks. Legal appellation boundaries, study-neighbour relationships, regional grape/style/climate/production/business depth, original analytical questions and expert verification are not established merely by a clickable point or a closed name inventory. No full WSET Diploma or whole-sommelier-geography completeness claim follows from these counts.
