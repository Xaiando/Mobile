# Diploma New York atlas sources

Checked on **26 September 2026**. `diploma_us_atlas.yaml` adds **12 places**, **12 cited location items** and **24 depth-two mappings** across WSET Level 3 and CMS Certified. Diploma inherits these mappings. The addition supplies New York state and all 11 current New York-associated American Viticultural Areas (AVAs); it does not supply a complete regional wine curriculum. Authored facts await expert review.

## Legal geography

The primary [TTB established AVA register](https://www.ttb.gov/regulated-commodities/beverage-alcohol/wine/established-avas), updated **18 August 2026**, lists ten AVAs wholly within New York and the multistate Lake Erie AVA. The [US Census Bureau state-code register](https://www.census.gov/library/reference/code-lists/ansi/ansi-codes-for-states.html) identifies New York as a US state, FIPS 36 / USPS NY. Each AVA location item cites its current eCFR legal definition and the TTB register; state identity has its own Census citation.

| AVA | Fully containing parent used in the curriculum | Current legal section |
|---|---|---|
| Cayuga Lake | Finger Lakes | [27 CFR §9.127](https://www.ecfr.gov/current/title-27/section-9.127) |
| Champlain Valley of New York | New York | [27 CFR §9.258](https://www.ecfr.gov/current/title-27/section-9.258) |
| Finger Lakes | New York | [27 CFR §9.34](https://www.ecfr.gov/current/title-27/section-9.34) |
| Hudson River Region | New York | [27 CFR §9.47](https://www.ecfr.gov/current/title-27/section-9.47) |
| Long Island | New York | [27 CFR §9.170](https://www.ecfr.gov/current/title-27/section-9.170) |
| Niagara Escarpment | New York | [27 CFR §9.186](https://www.ecfr.gov/current/title-27/section-9.186) |
| North Fork of Long Island | Long Island | [27 CFR §9.113](https://www.ecfr.gov/current/title-27/section-9.113) |
| Seneca Lake | Finger Lakes | [27 CFR §9.128](https://www.ecfr.gov/current/title-27/section-9.128) |
| The Hamptons, Long Island | Long Island | [27 CFR §9.101](https://www.ecfr.gov/current/title-27/section-9.101) |
| Upper Hudson | New York | [27 CFR §9.264](https://www.ecfr.gov/current/title-27/section-9.264) |
| Lake Erie | United States | [27 CFR §9.83](https://www.ecfr.gov/current/title-27/section-9.83) |

Lake Erie spans **New York, Ohio and Pennsylvania**. Its fact does not assert exclusive New York containment. The script verifies exact AVA names, state lists and fully containing AVA parents. It rejects partial-overlap parents. The current TTB table incorrectly repeats the Hamptons §9.101 link for Long Island: the Long Island entry uses §9.170, verified against its current legal definition. That single known table-link mismatch is documented and explicitly allowed; other mismatches fail authoring.

## Licensed markers

The point snapshot contains **12 CC0 markers**. Eleven are derived from community digitized AVA polygons maintained by the [UC Davis Library and DataLab AVA Project](https://github.com/UCDavisLibrary/ava), with UCSB Library and Virginia Tech contributors. The [CC0 licence](https://raw.githubusercontent.com/UCDavisLibrary/ava/7af5b29d45aee5e6c6ce3889e9b1de19085d7107/LICENSE) and [aggregate geometry](https://raw.githubusercontent.com/UCDavisLibrary/ava/7af5b29d45aee5e6c6ce3889e9b1de19085d7107/avas_aggregated_files/avas.geojson) are pinned to commit `7af5b29d45aee5e6c6ce3889e9b1de19085d7107`. Aggregate SHA-256: `c90068f7154764519f0a7c6fb2788e597b7c56bf7581e8c0faa979554d984926`.

The script reuses the atlas scanline procedure: 63 evenly spaced horizontal scanlines per source polygon, ring intersections, exclusion of holes and the midpoint of the widest verified interior interval. Every generated AVA marker is checked against its original polygon. Each feature records its source revision, aggregate hash, AVA ID, CFR section and derivation. These markers are **source-derived interior references**, not official centroids or legal boundary geometry.

The New York state marker is the exact nondeprecated Earth-coordinate statement for [Wikidata Q1384](https://www.wikidata.org/wiki/Q1384). Its feature records the statement ID, precision, entity download URL and description. Wikidata structured data are [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing). The state marker is a gazetteer reference; it is not an asserted vineyard location or state boundary. No coordinate is invented or manually displaced.

Snapshot SHA-256: **`26f004387b0820815bf0fa6679abd1803eacf827ffe067c9756da173b9505852`**.

## Reproduction

From the repository root, run `node tool/geography/diploma_us_atlas_points.mjs --author` with the pinned authoring caches present: `.dart_tool/new_world_ava_aggregate.geojson`, `.dart_tool/new_world_ttb.html` and `.dart_tool/diploma_us_new_york_q1384.json`. The script rejects a changed aggregate hash, changed TTB edition, missing or duplicate AVAs, invalid parents and absent source references. It preserves existing authored IDs on regeneration. Without `--author` it writes only the point snapshot.

The ordinary map build consumes the checked-in GeoJSON offline and does not require these ignored authoring caches. The source note and scripted checks establish provenance and geographic consistency; expert review and app tests remain separate release checks. Regional grapes, production choices, styles, quality, business context and comparative tasting remain part of `DIP-3`.
