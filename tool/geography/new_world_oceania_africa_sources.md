# Australian and South African additive register audit

Authoring edition: 26 September 2026. Facts and track importance remain editorial and `unverified`; this is not an expert-reviewed or complete Diploma curriculum. This addition preserves previous rows and adds 170 places, 170 cited `LOCATED_IN` items and 340 WSET Level 3 / CMS Certified mappings at depth 2. WSET Diploma inherits these mappings. It adds 58 Australian and 112 South African places, including 63 of the 64 wards missing at the start of this audit.

`new_world_oceania_africa_inventory.json` records every primary-register name, its curriculum ID and whether this addition authored it. It also lists all remaining South African wards. Rebuild that report with `node tool/geography/new_world_oceania_africa_inventory.mjs` from the repository root.

## Exact coverage and remaining gaps

The current [Wine Australia national register](https://www.wineaustralia.com/labelling/register-of-protected-gis-and-other-terms/geographical-indications) has 37 distinct State/Zone-column names, 63 Region-column names and 14 Subregion-column names. All 114 names are represented: Australia itself plus 113 noncountry nodes. The State/Zone column includes the country, states, territories, zones and Adelaide super zone; it must not be reported as 37 ordinary wine zones. The downloaded GIS has 14 subregion, 64 region and 28 zone records. Tasmania appears in both GIS region and zone layers but maps to one existing node and is in the primary table's State/Zone column. Queensland likewise has one state/zone node. Murray Darling and Swan Hill cross NSW and Victoria, so their new nodes use Australia as the valid containing parent. These counts establish geographic name coverage, not complete grape, climate, production or style knowledge for every GI.

The [SAWIS February 2026 production-area register](https://www.sawis.co.za/cert/download/Production_areas_-_Eng_%26_Afr_-_Feb26.pdf) has 150 distinct noncountry entries after bilingual aliases and `None` placeholders are excluded: 7 geographical units, 1 overarching geographical unit, 6 regions, 1 overarching region, 1 subregion, 32 districts and 102 wards. The combined curriculum represents 149 entries: all 48 entries above ward level and 101 wards. **Paardeberg South is the sole missing registered map target.** Its classification and parent are known, but no defensible distinct licensed marker was resolved. The source typo `Simonsberg-Stellenbosh` maps to canonical Simonsberg-Stellenbosch. The register places Lutzville Valley in Coastal Region / Cape West Coast; Nieuwoudtville is within the Western Cape Wine of Origin unit even though the named town is politically in Northern Cape. Statements expressly refer to the Wine of Origin hierarchy, and existing broader containment rows are preserved.

[Board Notice 65 of 2018](https://www.gov.za/sites/default/files/gcis_document/201805/41632bn65.pdf) places Paardeberg South north-west of Voor-Paardeberg and west of Paardeberg. The candidate GeoNames farm Staart van Paardeberg (3361096) lies east/south-east of the mountain; Slent farm is identified by its owner as Voor-Paardeberg. Both are rejected. Reusing another ward's mountain marker would provide an overlapping broad reference rather than a distinct target. No coordinates were shifted or taken from an unlicensed vineyard map to conceal this gap.

## Coordinate sources and licences

### Official Australian GIS: 55 derived interior markers, CC BY 4.0

Wine Australia links its official open data hub from its register. The ArcGIS item is owned by `WineAustralia` and expressly licenses the data **CC BY (Attribution) 4.0, Geographical Indications of Australia, © Wine Australia**. The script requires that exact licence classification and rejects BY-SA, ShareAlike, noncommercial or internal-use alternatives.

- Item metadata: https://www.arcgis.com/sharing/rest/content/items/2dd4c385f0ed4d109c2e18ae99e819e2?f=pjson
- Service: https://services6.arcgis.com/s8j6JbJJCqmhNgh7/arcgis/rest/services/Wine_Geographical_Indications_Australia/FeatureServer
- Official hub: https://wineaustralia-opendata-wineaustralia.hub.arcgis.com/

The GIS metadata describes the spatial data as an interpretation of the legal textual definitions and explicitly says the textual definitions prevail. Its snippet records a November 2024 update; retrieval on 26 September 2026 does not claim the GIS was revised on that date. The point algorithm selects the midpoint of the widest verified interior horizontal interval among 63 evenly spaced scanlines for each polygon, excluding holes. All 55 points were checked against their source polygon. These are derived interior reference markers, **not official centroids or legal boundaries**. No polygon boundary is copied into this addition's snapshots.

Each feature records its service layer, GI number, feature ID, source query, raw geometry hash, metadata hash, derivation and attribution. GIS fields preserve upstream names; curriculum labels qualify zones to distinguish their legal role. Tasmania and Queensland share state/zone roles rather than receiving duplicate geographic nodes.

### Wikidata: 35 exact P625 markers, CC0

`new_world_oceania_africa_reference_points.geojson` contains 3 Australian and 32 South African markers from exact nondeprecated Earth-globe Wikidata P625 claims. Preferred claims are selected first. Every feature preserves its QID, claim ID, precision, exact longitude/latitude, selected entity JSON hash and source URL. The selected entity hash covers the `wbgetentities` labels, descriptions, claims and sitelinks response, rather than an entire subsequent `Special:EntityData` download. [Wikidata structured data is CC0](https://www.wikidata.org/wiki/Wikidata:Licensing).

Adelaide city represents orientation for the much larger Adelaide super zone. Other South African points explicitly qualify named towns, administrative areas, passes or mountains. For example, Karoo Hoogland Local Municipality is a reference entity for the wine region; its extent is not asserted to equal the wine region. Nearby references cannot prove precise legal extent and are not offered as appellation centroids.

### GeoNames: 80 exact gazetteer markers, CC BY 4.0

The [GeoNames ZA national export](https://download.geonames.org/export/dump/ZA.zip) supplies exact gazetteer records where a qualified named locality or terrain reference is useful or a coarse Wikidata coordinate falls outside the simplified display coast. [GeoNames permits commercial use with attribution under CC BY](https://www.geonames.org/about.html). Each feature records its individual GeoNames URL/ID, original ZA.txt hash, coordinate export URL, feature class/code, administrative code and record modification date. No copyrighted producer-map coordinates or traced boundaries are used.

| Wine place | Qualified gazetteer reference | GeoNames ID |
| --- | --- | --- |
| Cape West Coast | Precise Lamberts Bay town reference | 3364847 |
| Citrusdal Mountain | Piekenierskloof pass | 3362893 |
| Nuveld-Karoo | Nuweveldberge mountain range | 968879 |
| Piekenierskloof | Named nearby farm | 3362894 |
| Slanghoek | Named populated place | 3361469 |
| Goudini | Goudini Spa locality | 3367548 |
| Simonsberg-Paarl | Simonsberg mountain terrain | 3361622 |
| Agter-Paarl | Windmeul locality | 3359354 |
| Voor-Paardeberg | Perdeberg mountain terrain | 3362943 |
| Paardeberg | Staart van Paardeberg hill | 3361095 |
| Porseleinberg | Named mountain terrain | 3362715 |
| Riebeekberg | Kasteelberg terrain near Riebeek valley | 3366070 |
| Riebeeksrivier | Named farm | 3362483 |
| Groenekloof | Mamreweg station by Darling Cellars; nearby orientation | 3364342 |
| Spruitdrift | Named Spruitdrif farm | 3361104 |
| Sunday's Glen | Sondagskloof river reference | 3361365 |
| Tradouw Highlands | Op de Tradouw farm reference | 967674 |

Additional first-party locality context includes [Windmeul's Agter-Paarl address](https://windmeul.com/contact-us/), [Vondeling's Voor-Paardeberg slopes description](https://vondelingwines.co.za/about/), [Darling Cellars' Groenekloof wine identification](https://www.darlingcellars.co.za/wine_PDF.aspx?WINEID=24822) and [Joubert-Tradauw's Tradouw Valley address](https://www.joubert-tradauw.com/contact/). The coordinates come solely from licensed gazetteer records, not those producer pages.

The table above documents the initial 17 gazetteer references. The additional 63 ward records are in [`new_world_oceania_africa_ward_references.json`](new_world_oceania_africa_ward_references.json), with their exact GeoNames IDs, Wine of Origin parents, explicit reference qualifications and supporting primary context URLs. The GeoJSON retains each qualification. GeoNames feature codes are preserved: a railway siding is not relabelled as a river or a vineyard, and a named mountain is not an appellation centroid.

Examples of carefully qualified references include Herold for Upper Langkloof, with the producer identifying its vineyards near that town; Schoemanshoek for Cango Valley, identified in Karusa's address; Prince Albert town for Kweekvallei, whose historical farm connection is described by Statistics South Africa; and Bergwater as historical orientation for Prince Albert Valley, without a claim of current winery operation. Kranskop Winery's licensed GeoNames vineyard record provides the Klaasvoogds reference; the Wine Industry Directory names Klaasvoogds as its region. Goedemoed uses the separate nearby Klaas Voogdsrivier railway locality with Bon Courage's primary farm context, not an invented coordinate for Bon Courage.

Blouvlei uses the named Hawequas farm/foothill reference explicitly associated with the area's eastern edge in a CSIR assessment. Bovlei uses the Bo-Vlei/Bovenvallei named farm as nearby valley orientation, without conflating it with Nabygelegen. Mid-Berg River uses Zeekoegat farm as a named boundary-farm vicinity from the final 2017 official description; it does not assert that the gazetteer point identifies an exact cadastral parcel or legal vertex. Coarse Hout Bay and St Helena Bay town coordinates lie outside the simplified display coast, so their markers use exact licensed inland Bokkemanskloof ravine and Laingville settlement references, respectively, with primary city/provincial context. These qualification decisions retain usable orientation while keeping legal geometry claims explicit.

## Pinned snapshots and reproduction

Run `node tool/geography/new_world_oceania_africa.mjs` from the repository root, with the geography package dependencies installed. Missing raw GIS and GeoNames caches are downloaded into ignored `.dart_tool` paths. Raw geometry/gazetteer editions are hash-pinned; an upstream edition change stops regeneration for review. Fresh metadata and Wikidata entity responses may change provenance hashes; compare generated snapshot hashes with this report before accepting a refreshed edition. A live daily GeoNames export may no longer supply the original edition; the committed feature snapshots retain the complete selected coordinates and provenance and can be used by the offline build without rerunning authoring. The inventory script downloads the legal PDF if absent and requires the February edition hash.

| Authored snapshot | Features | SHA-256 |
| --- | ---: | --- |
| `new_world_oceania_africa_au_gis_points.geojson` | 55 | `81568c51780095ab4f8223b24cb8da272750631f24c0d1564761c1e652eefd0a` |
| `new_world_oceania_africa_reference_points.geojson` | 35 | `070888983f87d9b6b734e1343512487a37a9e3e705e0533fedf79c33eb3778e0` |
| `new_world_oceania_africa_gazetteer_points.geojson` | 80 | `735baeda1a42a93633477c2ca61a4a6309ee799fa2f32756786880d3b12bb2ca` |

| Retrieved source | SHA-256 |
| --- | --- |
| Australian subregion layer 0 raw GeoJSON | `67f9179d90cf09e26ccf5f1af0aff2e592fec828f131da0a5c852a079b8c9adb` |
| Australian region layer 1 raw GeoJSON | `16ef048525b09b0127f79bf7e3bdbe351677f7e9be8e5016d9766fe45190f719` |
| Australian zone layer 2 raw GeoJSON | `84601bcde0f164d5a3ab2a51bbe289d17434ed4cbe1873df07c2044cdee7a9f4` |
| Australian ArcGIS item metadata | `d57b220dd6c7425298ca95d39b48e636c2568f02ed022d84e4661d1f0bbf0682` |
| Australian primary register HTML | `bdbd2bd4dad47080fd0c38d41bdfc2ba0ff861815289cfaf6bc46e47529e62de` |
| GeoNames ZA.txt | `65ab612c4c2ef21c25e6dc33ce0c9714d38fe9e777e36412c478166f1e543be8` |
| GeoNames ZA.zip | `b36fb219f4baf95c7c1a44c7a9380bf513be3f9e8bd6dbbb5f616009ef447005` |
| SAWIS February 2026 PDF | `0a0beac0faf48ba2dd079295b69dca46437da5341e37674d060d767bb591c871` |

Validation performed with Node: all 170 distinct IDs and one licensed marker per authored place; all 170 containing parents exist; no normalized-name collision within each country; 170 primary-cited location items; both track mappings at depth 2; finite WGS84 coordinates; all exact and six-decimal map points inside their displayed country polygon; all 55 Australian derived points inside their source polygon; no identical sibling map targets; all 80 GeoNames points match their pinned export records exactly; all 35 Wikidata points match the cited nondeprecated Earth-globe P625 claims and entity hashes; inventory totals and name mappings asserted against the primary register. All seven owned Node tests pass. Authoring rerun preserved the final snapshot hashes. Shared source registration, offline map build and application tests belong to the integrating parent task.
