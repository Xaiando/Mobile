# British atlas source notes — 26 September 2026

This bounded addition authors **23 nodes**, including one UK country frame, and **22 cited location items**. Every noncountry node has one CC0 reference point and two editorial track mappings (`WSET_L3` and `CMS_CERTIFIED`, secondary, minimum depth 2). Diploma inherits the WSET lower-level facts. No item is expert verified, and the addition does not establish full Diploma coverage.

## Primary geography evidence

- [Office for National Statistics administrative geographies](https://www.ons.gov.uk/methodology/geography/ukgeographies/administrativegeography) identifies England and Wales as constituent countries within the UK. The existing data model represents both with `region` nodes under the sovereign-country UK frame; the assertions retain their correct constituent-country status.
- [WineGB wine regions](https://winegb.co.uk/wines/regions/) identifies Kent, Sussex, Essex, Hampshire and Surrey as its five leading county study areas, describes regional county groupings, and names Monmouthshire, Carmarthenshire, Pembrokeshire and Ceredigion in Welsh viticulture.
- [WineGB regional associations](https://winegb.co.uk/about/regional-associations/) lists the English counties represented by its East, South East, Wessex and West associations. Wessex contains Dorset, Hampshire, Isle of Wight and Wiltshire. Association membership is a geographic grouping; it is not a legal wine appellation.

Sussex is an `informal_area` representing the historical county and WineGB wine-growing study area. It is **not** an assertion about the legal Sussex PDO. Wessex is an `informal_area` explicitly named `Wessex (WineGB region)`; it is **not** the historic kingdom. Ordinary county nodes use `region`. English county names refer to geographic/ceremonial study areas rather than asserting the boundaries of a particular local-government authority. Welsh county markers identify the current principal areas.

No legal grape permissions, grape-set completeness assertions, Sussex PDO geography or English/Welsh PDO completeness claims are added. In particular, a quality-sparkling-only grape list must not be treated as a complete list for a designation that also includes still wine.

## Reusable coordinates and licence

`british_atlas_points.geojson` contains **22 exact Earth-globe P625 coordinates** selected from Wikidata entities on 26 September 2026. Wikidata structured data are [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing), usable in a proprietary offline app. These are sourced reference locations, **not** wine-area boundaries or official centroids. WineGB maps are not traced, bundled or used to derive geometry.

Each feature records the Wikidata QID, exact coordinate claim ID, entity URL, source-coordinate URL, coordinate precision, retrieval date and CC0 licence. `source_entity_sha256` hashes the UTF-8 `JSON.stringify(entity)` value returned in the `wbgetentities` response, not a differently serialized live EntityData download. The committed GeoJSON snapshot hash below fixes the shipped coordinates and provenance even if the public source changes later.

Two markers use inland localities to remain inside the simplified country frame. [Somerset Council](https://lcn.somerset.gov.uk/local-community-networks/local-community-network-areas/taunton/) confirms Taunton as Somerset's county town; [Dorset Council](https://www.dorsetcouncil.gov.uk/visit-us) places its county hall in Dorchester, Dorset. Somerset uses exact Taunton P625 `q845619$2EAE736E-086B-4A3D-8B1F-AE5C4EA71CA0`, `[-3.1, 51.019166666667]`. Wessex uses exact Dorchester P625 `q503331$73001DF7-FBF8-4330-B849-DC4506C35432`, `[-2.4397222222222, 50.710833333333]`. Both points were checked inside the bundled decoded UK MultiPolygon, at exact coordinates and after rounding to six decimals. These are qualified town references, not centroids. This correction replaces only the former Somerset entity reference and coastal Weymouth marker; all twenty other features and all curriculum facts/mappings remain unchanged.

| Study area | Coordinate entity | Qualification |
| --- | --- | --- |
| England | Q21 | Constituent-country reference |
| Wales | Q25 | Constituent-country reference |
| Kent | Q23298 | County reference |
| Essex | Q23240 | Ceremonial county reference |
| Hampshire | Q23204 | Ceremonial county reference |
| Surrey | Q23276 | County reference |
| Dorset | Q23159 | Ceremonial county reference |
| Wiltshire | Q23183 | Ceremonial county reference |
| Isle of Wight | Q9679 | Island/county reference |
| Cornwall | Q23148 | Geographic county reference |
| Devon | Q23156 | Ceremonial county reference |
| Somerset | Q845619 | Taunton, county town of Somerset; qualified inland reference, not a county centroid |
| Herefordshire | Q23129 | County reference |
| Gloucestershire | Q23165 | Ceremonial county reference |
| Norfolk | Q23109 | County reference |
| Suffolk | Q23111 | County reference |
| Sussex | Q23346 | Historic county reference; not the PDO |
| Wessex (WineGB region) | Q503331 | Dorchester, a town in member county Dorset; qualified inland reference, not a region centroid |
| Monmouthshire | Q207176 | Current Welsh principal area |
| Carmarthenshire | Q217840 | Current Welsh principal area |
| Pembrokeshire | Q213361 | Current Welsh principal area |
| Ceredigion | Q217829 | Current Welsh principal area |

Snapshot SHA-256: `4391727a11732f523c7a19a3bb7489947bf59f9b2e0088ac957d9d41571ac41c`.

Suggested source ID: `src_british_atlas_markers`; suggested layer ID: `ml_british_atlas_markers`. Country `n_geo_united_kingdom` needs Natural Earth GBR registration in the world-country layer. No country point is bundled here.

Attribution: **Wikidata (CC0), reference coordinates retrieved 26 September 2026. County and constituent-country markers show reference locations; Somerset uses qualified Taunton and Wessex uses qualified Dorchester in Dorset. Markers are not wine-area boundaries or official centroids.**

Run `node tool/geography/british_atlas.mjs` from the repository root to reproduce the authored YAML and point snapshot from the research entity cache. Missing entities are fetched individually without refreshing existing marker entities. `--points-only` preserves the curriculum file. `--refresh` re-queries Wikidata and can change the snapshot; a changed snapshot requires a new source hash and release registration.

## Remaining scope

This is a useful bounded geography addition, not a complete list of every UK county, registered GI, subregion, site, production rule or Diploma learning outcome. It does not add Scottish or Northern Irish wine geography, remaining WineGB associations, English/Welsh PDO/PGI legal rule sets, Sussex PDO or Darnibole. Expert content review remains outstanding.
