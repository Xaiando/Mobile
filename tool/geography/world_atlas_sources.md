# World atlas source notes

The curriculum file `assets/curriculum/areas/world_atlas.yaml` adds 214 nodes: 11 countries and 203 geography nodes. Each new noncountry node has a cited `LOCATED_IN` item and a matching point in `world_atlas_points.geojson`. Both offered certification tracks receive editorial study mappings. Facts remain unverified until expert review. This atlas adds no grape-permission or winemaking-rule claims.

The point file is a checked-in coordinate snapshot, retrieved on **26 September 2026**. Every feature records its Wikidata entity ID, entity URL, JSON download URL, exact `P625` claim ID, source name, source description, coordinate precision and CC0 licence. Coordinates were copied from the cited Earth coordinate claim; coordinates and borders were not estimated or drawn.

| Country | New geography points | Curriculum authority |
| --- | ---: | --- |
| Italy | 29 | MASAF DOP list, updated 18 March 2026 |
| Spain | 30 | MAPA PDO list; Rioja regulatory council; Xunta de Galicia |
| Portugal | 30 | IVV regional pages; Diário da República Vinho Verde legislation |
| United States | 28 | TTB established AVA register, updated 18 August 2026 |
| Canada | 8 | Ontario Wine Appellation Authority; British Columbia Wine Authority |
| Chile | 20 | Decree 464, consolidated government legislative database |
| Argentina | 12 | INV GI/DOC list and Paraje Altamira resolution |
| Australia | 20 | Wine Australia protected GI register |
| New Zealand | 10 | IPONZ GI register and examination/application records |
| South Africa | 10 | Wine Certification Authority / SAWIS production-area list, February 2026 |
| Georgia | 3 | National Wine Agency wine-region descriptions |
| Lebanon | 3 | Investment Development Authority of Lebanon wine-region map |

All source URLs and individual fact locators are in the curriculum citation tables. The INV list explicitly places the Uco Valley in Mendoza and includes the departments of Tupungato, Tunuyán and San Carlos. TTB marks Columbia Valley and Walla Walla Valley as multistate AVAs; Columbia Valley consequently has the United States as its parent rather than a false exclusive Washington parent. Los Carneros is assigned California rather than an exclusive Napa parent. Rioja and Cava similarly use Spain because their boundaries span administrative regions.

## How the points must be presented

A point is a **reference point**, never a legal boundary or a complete representation of a wine-growing area. A matching wine-region gazetteer entry is used where one supplies a coordinate. Otherwise, a named municipality, locality or administrative area provides the reference point. Each feature's `point_place_name`, `point_role`, `point_description` and `label_note` make the distinction explicit.

Municipal reference points deliberately retain the municipality's exact coordinates. They are neither moved into a guessed vineyard nor described as a GI centroid. For example, Paraje Altamira uses La Consulta, Cima Corgo uses Pinhão, Willamette Valley uses McMinnville, and Cape South Coast and Walker Bay use Hermanus. Hemel-en-Aarde Valley uses the distinct wine-region gazetteer entry Q31919666, rather than a nearby municipal reference. Map legends and detail views should preserve the reference-point explanation. Reused coordinates at different hierarchy levels are intentional; they must not imply identical territorial boundaries.

The country outlines and all generated map layers are owned by the geography pipeline. This point snapshot does not replace or amend legal GI polygons. Future freely licensed authoritative boundary data can supersede a point after its licence, containment and identifiers have been checked.

## Retrieval and review

Exact Wikipedia sitelink titles were resolved through Wikidata's `wbgetentities` API in paced batches. Disambiguation pages and missing coordinates were rejected. Pinhão and Barcelos were resolved to `Q1019773` and `Q213242`; La Consulta was resolved through its Spanish-language sitelink to `Q1246763`. All selected `P625` values were taken from nondeprecated Earth coordinate statements and their claim IDs were retained. Local API responses were cached during authoring; the checked-in GeoJSON is the reproducible snapshot used by the build.

For updates, retrieve the per-feature `source_coordinate_url`, verify that `wikidata_id` still identifies `point_place_name`, inspect the recorded coordinate statement, then review the point against the official regional source. If a source coordinate changes, update the snapshot, retrieval date and pinned SHA-256 together. Never silently infer a border from these points.

Wikidata's structured data are released under [CC0](https://www.wikidata.org/wiki/Wikidata:Licensing). Curriculum assertions paraphrase public facts from the cited primary authorities; they do not copy syllabus text or extensive source passages.
