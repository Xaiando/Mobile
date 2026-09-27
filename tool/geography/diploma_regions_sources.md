# Diploma macro-region geography — 26 September 2026

This bounded addition contains **10 region nodes, 10 cited location items and 20 editorial secondary mappings at depth 2** for WSET Level 3 and CMS Certified. WSET Level 4 inherits lower-level items. All items await qualified expert review. This addition does not claim complete Diploma geography or legal-rule coverage.

Country increments: Spain 5, Portugal 1, South Africa 1, New Zealand 2, Australia 1. Every node has its sovereign country as parent. Existing appellation nodes and location facts are retained, without asserting that a wine GI lies wholly in a similarly named administrative community.

## Primary factual evidence

- [INE autonomous-community register](https://www.ine.es/daco/daco42/codmun/cod_ccaa.htm): codes 08 Castilla-La Mancha, 10 Comunitat Valenciana, 14 Región de Murcia, 15 Comunidad Foral de Navarra, 17 La Rioja. All five nodes describe administrative communities. Valencia city/province, Valencia DO, Navarra DO and Rioja DOCa are distinct concepts.
- [ViniPortugal Lisboa region](https://www.winesofportugal.com/en/discover/wine-regions/lisboa/): Lisboa is a Portuguese wine-growing region stretching north of Lisbon, with Torres Vedras among its central denominations. The node is the wine region, not Lisbon city; the coordinate is a qualified Torres Vedras municipality reference.
- SAWIS / Wine Certification Authority, [Wine of Origin production areas, February 2026](https://www.sawis.co.za/cert/download/Production_areas_-_Eng_%26_Afr_-_Feb26.pdf), is the reused `src_atlas_za_wo_2026` citation. Its Western Cape list identifies Olifants River as a region and Vredendal as a ward. The cached primary publication was checked during authoring. [Wines of South Africa](https://www.wosa.co.za/The-Industry/Winegrowing-Areas/Winelands-of-South-Africa/) also describes the Olifants River wine region and its Vredendal/Spruitdrift wards. The reference point names Vredendal town, not a river feature or a wine-region centroid.
- [LINZ / New Zealand Geographic Board](https://www.linz.govt.nz/our-work/new-zealand-geographic-board/place-name-stories/te-ika-maui-north-island-and-te-waipounamu-south-island) identifies North Island / Te Ika-a-Māui and South Island / Te Waipounamu as the two main islands of New Zealand. These nodes model geographic islands, not wine GIs. They do not reparent existing regional GI nodes.
- [Wine Australia GI register](https://www.wineaustralia.com/labelling/register-of-protected-gis-and-other-terms/geographical-indications), reused `src_atlas_au_gis`, lists the registered South Eastern Australia zone. Footnote 1 includes the whole of NSW, Victoria and Tasmania and parts of Queensland/South Australia. Melbourne, a city in Victoria, is therefore a qualified reference location within the GI; it is not the GI centroid. No administrative or other wine region is reparented here.

Four new primary source-citation rows are authored; two existing regulator citations are reused. No map artwork is traced, downloaded for geometry or bundled. No grape permissions or complete legal sets are asserted.

## CC0 point provenance

All 10 marker coordinates are **exact Earth-globe Wikidata P625 values**, retrieved on 26 September 2026, under [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing). Features retain the exact claim ID, QID, source/coordinate URLs, source entity hash, date, precision, licence and explicit reference qualification.

`source_entity_sha256` is calculated over UTF-8 `JSON.stringify(entity)` from the `wbgetentities` response, not a differently serialized live EntityData download. The committed GeoJSON snapshot hash fixes the bundled coordinate edition.

| Node | Coordinate entity | Marker qualification |
| --- | --- | --- |
| `n_geo_valencian_community` | Q5720 | Valencian autonomous community |
| `n_geo_region_murcia` | Q5772 | Murcia autonomous community |
| `n_geo_castilla_la_mancha` | Q5748 | Castilla-La Mancha autonomous community |
| `n_geo_la_rioja_region` | Q5727 | La Rioja autonomous community |
| `n_geo_navarra_region` | Q4018 | Navarre autonomous community |
| `n_geo_lisboa_wine` | Q917319 | Qualified Torres Vedras municipality reference |
| `n_geo_olifants_river_wine` | Q1341350 | Qualified Vredendal town reference |
| `n_geo_north_island` | Q118863 | Geographic North Island |
| `n_geo_south_island` | Q120755 | Geographic South Island |
| `n_geo_south_eastern_australia` | Q3141 | Qualified Melbourne city reference |

Snapshot SHA-256: `d8fb7b10664e06059a9c69d07c1e01c28fb9de367fbce127c56baab01e1ffce2`.

Suggested source/layer IDs: `src_diploma_regions_markers` / `ml_diploma_regions_markers`.

Attribution: **Wikidata (CC0), reference coordinates retrieved 26 September 2026. Administrative communities and geographic islands use entity reference coordinates; Lisboa, Olifants River and South Eastern Australia use explicitly qualified locality references. Points are not wine-area boundaries or official centroids.**

Run `node tool/geography/diploma_regions.mjs` from the repository root to reproduce the YAML and points from the research entity cache. `--refresh` queries Wikidata again; changed coordinates/provenance require a new snapshot hash and release registration.
