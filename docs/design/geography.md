# Geography and Maps

| | |
|---|---|
| **Status** | Design for backlog group G ([backlog.md](../backlog.md)). Decisions are registered in [architecture-audit.md](../architecture-audit.md) §15; licensing questions in [legal-review.md](../legal-review.md) L-15 to L-23 and L-25. |
| **Content plan** | [content/subregion-atlas.md](../content/subregion-atlas.md): the sub-regions of the famous regions, their drills and registers (GEO-15 to GEO-18, tasks G10–G13) |
| **Builds on** | The knowledge graph (domain model §3.2), FS-2 (one memory state per item), V-2 (validity by date), the question system ([question-system.md](question-system.md)) |

Geography is a first-class study domain, not an illustration. A candidate must know:

- where places are, and how they nest from country to appellation;
- what lies beside them;
- which rivers, bodies of water and mountains shape their climate;
- how slope, aspect and elevation matter;
- which grapes and soils belong where.

Examiners test this spatially, so the app does too.

---

## 1. Principles

1. **One knowledge model** (GEO-1). A map question is a *format* of a canonical `KnowledgeItem`. Tapping Chablis on a map of Burgundy, naming the highlighted Chablis, and answering "In which region is Chablis?" in text all practise the same item, `ki_chablis_location`, and update its single FSRS state (FS-2). There are no map cards and no separate geography database.
2. **Geometry belongs to nodes** (GEO-2). Shapes attach to existing `KnowledgeNode` rows through a geometry reference, with curriculum provenance like any other fact.
3. **Offline and self-contained** (GEO-3). Vector geometry ships in the app bundle. Studying never needs a network, a tile server, Google Maps or any paid service.
4. **Depth follows relevance** (GEO-4). A place is mapped at a finer level only when a track maps items about it. Vineyard-level shapes exist where a track or pack needs them (e.g. Einzellagen in the Spätburgunder pack), not everywhere.
5. **Licensed sources only** (GEO-5). Every layer cites an open-licensed dataset, and the app shows the required attribution (§6, §8).

---

## 2. Geographic knowledge model

### Node types

The existing types are `country`, `region`, `subregion`, `appellation`, `soil` and `climate`. New types:

| Type | Examples | Notes |
|---|---|---|
| `continent` | Europe | The top of the containment chain, so a country has a location item too |
| `site` | Assmannshäuser Höllenberg, a Burgundy *climat* | A cru or Einzellage, mapped only where a track needs it |
| `river` | Rhône, Mosel, Ahr, Gironde (estuary) | Line geometry |
| `body_of_water` | Atlantic Ocean, Lake Geneva, Bay of Biscay | Area geometry |
| `mountain_range` | Vosges, Haardt, Andes, Coast Ranges | Area geometry, or line geometry along the crest |
| `landform` | Kaiserstuhl, Côte d'Or escarpment, Montagne de Reims | Hills, escarpments, plateaus, valleys |
| `climate_influence` | Mistral, Humboldt Current, Foehn | Winds and currents |
| `aspect` | south-facing, south-east-facing | Eight compass categories |
| `statistic` | Spätburgunder in Baden | A reified statistic for ranked facts, e.g. planted area in a survey year (question-system §6) |
| `informal_area` | Left Bank, Côte des Blancs, Gibbston | A traditional area with no legal definition (GEO-15). It is drawn from a cited commune list or as a labelled point, and never offered as an appellation. |

### Relation types

| Relation | Signature | Meaning, with an example | Used by |
|---|---|---|---|
| `LOCATED_IN` (extended) | any mapped node → its parent area | Chablis in Burgundy; Vosges in France | locate, identify, drills |
| `BORDERS` (symmetric) | area ↔ area of the same level | Pauillac borders Saint-Julien | neighbour drills |
| `LIES_ALONG` | area or site → river or body of water | Côte-Rôtie lies along the Rhône | rivers |
| `FLOWS_THROUGH` | river → area | the Ahr flows through the Ahr region | rivers (the river's location item) |
| `SHELTERED_BY` | area → mountain range or landform | Alsace sheltered by the Vosges (rain shadow) | barriers, climate reasoning |
| `MODERATED_BY` | area → body of water or climate influence | Médoc moderated by the Gironde estuary | climate influences |
| `EXPOSED_TO` | area → climate influence | Rhône Valley exposed to the Mistral | climate influences |
| `FACES` | site or area → aspect | Côte d'Or vineyards face east to south-east | slope and aspect |
| `HAS_ELEVATION` | site or area → quantity range | a site from 200 to 350 m | topography (numeric, ordering) |
| `HAS_SLOPE` | site → quantity range | a steep terrace, 50–70 % | topography |
| `ON_LANDFORM` | site or area → landform | Ihringer Winklerberg on the Kaiserstuhl | topography |
| `KNOWN_FOR_GRAPE` | area → grape | Ahr known for Spätburgunder | grape ↔ region drills (cited editorial fact, with a completeness assertion per area) |
| `HAS_SOIL`, `HAS_CLIMATE`, `PERMITS_PRINCIPAL_GRAPE` | as today | | soils and grapes on maps |

`BORDERS` is stored once, subject ID < object ID, and read in both directions. That needs `relation_types.is_symmetric` (schema v2, F2).

### The location item rule (GEO-6)

Every node that can appear as the answer of a map question has one **location item**. For an area, site, landform, mountain range or body of water, that is its `LOCATED_IN` item towards its direct parent; for a river, its principal `FLOWS_THROUGH` item. All locate and identify questions about the node update that item. The validator rejects map-enabled nodes without one.

**Units with two parents (GEO-16).** Some registers overlap: Los Carneros lies in both Napa and Sonoma, and Walla Walla Valley in Washington and Oregon. Such a unit has one location item per parent, and a map question grades the item whose parent frames the map.

---

## 3. Geometry model (schema v2)

```sql
-- Authored curriculum, read-only at runtime like every curriculum table.
CREATE TABLE map_layers (
  id                  TEXT PRIMARY KEY,   -- 'ml_fr_appellations'
  display_name        TEXT NOT NULL,
  geometry_kind       TEXT NOT NULL CHECK (geometry_kind IN ('area', 'line', 'point')),
  asset_path          TEXT NOT NULL,      -- assets/geography/fr_appellations.topo.json
  asset_sha256        TEXT NOT NULL,      -- verified at ingestion
  min_zoom            REAL NOT NULL,      -- display range, Web Mercator zoom
  max_zoom            REAL NOT NULL,
  parent_layer_id     TEXT REFERENCES map_layers (id),
  source_citation_id  TEXT NOT NULL REFERENCES source_citations (id)  -- licence and attribution
);

CREATE TABLE node_geometries (
  knowledge_node_id  TEXT NOT NULL REFERENCES knowledge_nodes (id),
  map_layer_id       TEXT NOT NULL REFERENCES map_layers (id),
  feature_key        TEXT NOT NULL,       -- the feature's ID inside the layer asset
  min_lon REAL NOT NULL, min_lat REAL NOT NULL, max_lon REAL NOT NULL, max_lat REAL NOT NULL,
  label_lon          REAL NOT NULL,       -- a point inside the area, for labels and markers
  label_lat          REAL NOT NULL,
  PRIMARY KEY (knowledge_node_id, map_layer_id),
  UNIQUE (map_layer_id, feature_key)
);
```

- **Coordinates stay in the assets.** The database holds only what SQL needs: which node has which feature, bounding boxes, and label points for frames and for north-to-south orderings. The renderer reads the asset. This keeps one database and one ingestion path (V-7) without storing megabytes of coordinates in SQLite (GEO-7).
- **Provenance.** `source_citations` already has `kind = 'dataset'`, `license` and `attribution_text` columns, so geometry provenance fits the existing model (§8). A layer can draw on several sources: a French layer draws INAO's commune lists on IGN's shapes. So the manifest lists them in `source_citation_ids`, and F2 stores that list instead of the single column above (GEO-21).
- **Ingestion.** The dataset manifest lists the layers. Ingestion checks each asset's SHA-256, loads `node_geometries`, and rejects any feature key missing from its asset, so the build fails before a map can be broken.
- **No derived facts in the database.** Adjacency, containment and orientation are computed by the build pipeline (§7). They are proposed as authored relations in its report, never inserted silently. The validator compares authored `BORDERS` with the computed adjacency and warns on any difference.

---

## 4. Map formats

Each row is a format or mode in the question system's registry. Depth follows question-system §2.

| Learner-facing mode | Format | Question → answer | Item graded | Depth |
|---|---|---|---|---|
| Tap the correct country, region, subregion or appellation | `map_locate` | "Tap Chablis" on its parent's map → tap | the node's location item | 1 with labels, 2 without |
| Identify a highlighted region | `map_identify` | a highlighted shape → MCQ, or typed at higher depth | the node's location item | 1 (MCQ), 3 (typed) |
| Hierarchy drill, country → region → subregion → appellation | `map_drill` | successive taps down the chain | each level's location item | 3 |
| Grape → the regions where it matters | `map_multi_locate` | "Tap every German region known for Spätburgunder" → taps | each `KNOWN_FOR_GRAPE` item in the complete set | 2 |
| Rank regions for a grape | `ordering` on a map | "Order by Spätburgunder area" → order | the `statistic` items | 3 |
| Region → its important grapes | map-prompted `multiple_response` | a highlighted region → select grapes | the region's grape items | 2 |
| Neighbours | `map_locate` with a `BORDERS` template | "Tap an appellation bordering Pauillac" → any correct tap | the `BORDERS` item of the neighbour tapped | 3 |
| Rivers and bodies of water | `map_locate`, `map_identify` | "Tap the river Côte-Rôtie lies along" | the `LIES_ALONG` item | 2 |
| Mountain ranges and barriers | `map_locate` | "Tap the range that shelters Alsace from Atlantic rain" | the `SHELTERED_BY` item | 2 |
| Slope, aspect and elevation | map-prompted `mcq` or `numeric` | a site with relief shading → its aspect, or its elevation band | the `FACES` or `HAS_ELEVATION` item | 3 |
| Climate influences | map-prompted `mcq`, or `reasoning` | "What moderates the Médoc?", with the estuary visible | `MODERATED_BY` and `EXPOSED_TO` items | 2–4 |
| Soils and geology | `map_locate` with a `HAS_SOIL` template | "Tap an appellation on Kimmeridgian marl" → any correct tap | the `HAS_SOIL` item of the node tapped | 2 |
| Map deduction | `reasoning` with a map prompt | location, relief, rivers and climate shown → most plausible grape or style | chain items (question-system §4) | 4–5 |
| North to south, upstream to downstream | `ordering` | order places by latitude or along a river | each element's location item | 3 |

### Difficulty modes

Map questions have four presentation modes. The ladder (question-system §5) raises the mode as the item's stability grows, within the depths the track serves (GEO-8).

1. **Labelled.** Every candidate is outlined and named, which makes this recognition.
2. **Outline.** Candidates are outlined but unnamed; the parent, rivers and coastline are named.
3. **Minimal.** Only the coastline, national borders and major rivers are drawn; candidates are revealed after the answer.
4. **Blank, zoomed out.** Minimal mode starting one level up; the learner zooms to find the answer.

### Grading details

- A tap is **inside** a candidate if it hits the polygon. It is **near** it if it falls within 12 logical pixels of its outline, or of the marker of a feature drawn as a point.
- If the tap is inside or near several candidates, the one hit exactly wins; failing that, the one whose outline is nearest.
- A question accepting several answers counts any correct node as right (question-system §6).
- `answer_payload` stores the tapped coordinate, the frame and the node hit, so the next miss can show "you tapped Côte de Beaune".

---

## 5. Frames, zoom and depth

- **Frames.** A question's frame is the bounding box of the answer's parent, plus a margin. The candidates are the same-type siblings inside the frame. A `map_locate` question needs at least four candidates, or it falls back to the next level up. This mirrors the three-distractor rule of QG-6.
- **Semantic zoom.** Each layer has a zoom range. When the learner zooms past a layer's minimum zoom, finer layers appear, but only features relevant to the active track (items in its effective mappings) are drawn fully. Other features appear dimmed, as context. Nothing is askable unless the track maps it (GEO-4).
- **Small features.** A feature smaller than 24 logical pixels at the current zoom is drawn as a marker at its label point, so every target stays tappable.
- **Atlas.** The Study tab gets a browse mode (task S1). It zooms from the world to countries, regions and appellations. Tapping a feature opens its items, their memory state and a *practise this area* action.

---

## 6. Data sources and licences

Layers are built only from sources that allow commercial redistribution. Findings from 2026-09-24, to be confirmed by counsel (legal review L-15):

| Source | Layers | Licence | Attribution |
|---|---|---|---|
| [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) 1:10m and 1:50m | continents, countries, coastlines, large lakes, major rivers, marine areas, physical regions | Public domain | Not required; "Made with Natural Earth" is shown as a courtesy |
| [IGN ADMIN EXPRESS COG CARTO](https://www.data.gouv.fr/datasets/communes-cantons-et-epci-2025-admin-express-cog-plus-ign) | French communes, the building blocks of appellation areas | Licence Ouverte / Etalab 2.0 (commercial use allowed) | "IGN – ADMIN EXPRESS, [date]" |
| [INAO aires géographiques des AOC/AOP](https://www.data.gouv.fr/datasets/aires-geographiques-des-aoc-aop) | Which communes form each AOC's geographical area (CSV) | Licence Ouverte 2.0 | "INAO, [date]" |
| [INAO délimitation parcellaire des AOC viticoles](https://www.data.gouv.fr/datasets/delimitation-parcellaire-des-aoc-viticoles-de-linao) | Parcel-level areas, only for crus a track needs (incomplete by INAO's own statement) | Licence Ouverte 2.0 | "INAO, [date]" |
| [BKG VG250](https://gdk.gdi-de.org/geonetwork/srv/api/records/93a98c5c-cf03-4a95-bf0a-54001fbf3949) | German municipalities and states, the blocks of Anbaugebiete and Bereiche | Datenlizenz Deutschland – Namensnennung 2.0 | "© BKG ([year]) dl-de/by-2-0" |
| [Landwirtschaftskammer RLP, Einzellagen lt. Weinbergsrolle](https://www.lwk-rlp.de/weinbau/rebflaechen/weinlagen) | Einzellagen in Ahr, Mosel, Mittelrhein, Nahe, Pfalz and Rheinhessen | Datenlizenz Deutschland – Namensnennung 2.0 | "© Landwirtschaftskammer RLP ([year]), dl-de/by-2-0, weinlagen.lwk-rlp.de [data edited]" |
| [ISTAT confini delle unità amministrative](https://www.istat.it/notizia/basi-territoriali-localita-e-confini-amministrativi-per-fini-statistici/) | Italian communes, the blocks of DOC and DOCG areas named in disciplinari | CC BY (version to confirm at download) | "ISTAT, [year]" |
| [UC Davis AVA Digitizing Project](https://ucdavislibrary.github.io/ava/) | American Viticultural Areas | CC0 | Courtesy only |
| SRTM 1 arc-second (NASA) | Elevation, slope and aspect facts; relief shading | Public domain | Courtesy only |

**Excluded (GEO-5, L-16):**

- **Eurostat GISCO / EuroGeographics boundaries:** non-commercial use only.
- **OpenStreetMap:** ODbL share-alike would reach a bundled derived database.
- **Map artwork from trade bodies and publishers** (e.g. regional wine councils, wine atlases): copyright.
- **Online tile services such as Google Maps or Mapbox:** online, paid, and not needed.

The Copernicus DEM is an alternative to SRTM, with a mandatory "all rights reserved" notice, so SRTM is preferred (L-23).

**Countries not yet covered.** Spain, Portugal, Austria, Switzerland, Australia, New Zealand, South Africa, Chile and Argentina are researched in their atlas tasks (G11–G13), and so are the German states outside Rhineland-Palatinate (G12) (L-25). Each needs an open-licensed boundary source, or it falls back as below.

**Fallback (GEO-9).** Where no open shape exists, the node is drawn as a *point* at a label point taken from an open municipal boundary or a public-domain gazetteer. It still supports locate questions at a coarser frame. Nobody draws boundaries by hand from copyrighted maps.

**Approximation disclosure.** An appellation area built from its communes is the legal *geographical area*, which is larger than the delimited vineyard parcels. The map legend says so (GEO-10).

---

## 7. Build pipeline

`tool/geography/` holds a Node project pinned by `package-lock.json`, like `tool/web_smoke/`:

1. `sources.yaml` lists every source: URL, version or date, SHA-256 of the download, licence, attribution text and notes. `fetch` downloads and verifies them into a cache outside the repository.
2. `layers.yaml` defines each layer:
   - the source features it takes;
   - the mapping from source IDs to knowledge node IDs (INSEE and ISTAT codes, INAO appellation IDs, Natural Earth `ne_id`);
   - the dissolve rules (communes → appellation area);
   - the clip box, the simplification tolerance and the quantization.
3. `build` runs [mapshaper](https://github.com/mbloch/mapshaper) (MPL-2.0; a build tool, not shipped) to dissolve, simplify with topology preserved, and quantize. It writes:
   - `assets/geography/<layer>.topo.json` (TopoJSON: shared borders stored once, integer coordinates);
   - `assets/geography/manifest.yaml`: the `map_layers` and `node_geometries` rows the dataset includes;
   - a report: sizes, feature counts, proposed `BORDERS` pairs, containment checks, and elevation, slope and aspect summaries from the DEM.
4. `check` verifies the committed assets against the sources and the manifest, so CI fails on drift, like `tool/web_assets.sh check`. Outputs are byte-identical for identical inputs.

**Budgets (GEO-11):**

- geography assets at most 8 MB in V0.1, and at most 1.5 MB per layer;
- a layer parses in at most 100 ms on a mid-range phone;
- a frame renders in at most 8 ms after warm-up.

**As built (G1).** `tool/geography/` builds ten layers, 1.4 MB in all (`report.md` lists them):

- **World context** comes from Natural Earth 5.1.1 at 1:50m: continents, countries, coastlines, seas and oceans, lakes, major rivers, and physical regions (ranges, plateaus, plains, valleys and basins). France comes from Natural Earth's map units, so metropolitan France is the node `n_geo_france` and each overseas department is a context feature of its own.
- **France** has three layers: wine regions, subregions and appellations. Each feature is the union of the communes of INAO geographical areas (INAO's list of 9 October 2025). The commune shapes come from IGN ADMIN EXPRESS COG CARTO 2026, reprojected from Lambert-93.
  - Regions and subregions have no legal area of their own, so `layers.yaml` composes each from named appellation areas. For example, Burgundy is the regional AOC Bourgogne without its communes in the Rhône department, which belong to Beaujolais. These compositions are provisional until G10 checks them (GEO-19).
  - INAO still names a few merged communes by their old INSEE codes. See GEO-20 for how the build draws them.
  - INAO lists whole communes. Where a specification includes only part of a commune, the map draws the whole commune. This is part of the approximation that GEO-10 discloses.
  - The areas follow INAO's commune lists, not INAO's SIQO area polygons. The research handoff treats the lists as authoritative wherever the two differ.
- **`fetch`** downloads each source into `~/.cache/sommelier-geography`, or into `$SOMMELIER_GEO_CACHE`.
  - It resumes interrupted downloads.
  - It refuses any file whose SHA-256 differs from `sources.yaml`.
  - The pinned `7zip-bin` unpacks ADMIN EXPRESS, a 64 MB archive.
- **`build`** runs mapshaper 0.7.67 through its JavaScript API. It reads the GeoPackage with Node's built-in `node:sqlite`, so it needs Node 22.13 or later.
  - It refuses to run unless every cached source is the edition `sources.yaml` records. For an archive, that is the edition its files were unpacked from. Otherwise, layers built from an older edition would cite the new one.
  - A node's feature carries the node ID as its TopoJSON `id`. A context feature carries only its `name`.
  - Each asset holds one object, named after the asset.
  - Quantization can shrink a thin context feature to nothing, and such a feature is dropped. A node's feature is never dropped: the build fails instead.
- **Containment** is checked on commune sets, not on shapes: a node lies inside its parent when all its communes belong to the parent. There are no failures.
- **Proposed `BORDERS` pairs.** The report proposes three: France–Italy, Burgundy–Champagne and Cornas–Crozes-Hermitage.
- **Several sources per layer.** Each manifest layer lists its sources in `source_citation_ids`, because a French layer draws INAO's lists on IGN's shapes. §3 sketched a single `source_citation_id` (GEO-21).
- **`check`** validates:
  - both YAML files;
  - each source's URL, retrieval date, SHA-256, licence and attribution, which is the licence and attribution gate the research asks for. The licence must be one of those GEO-5 allows, spelled out in full, so that CC BY-NC or dl-de's non-commercial variant cannot pass;
  - each asset's hash, size and budget;
  - each layer's manifest entry, including the attribution the app shows, against `layers.yaml` and `sources.yaml`;
  - the manifest rows against the curriculum.

  When every source is cached, `check` also rebuilds the layers in a temporary directory and compares them with the committed files. It fails when a cached source is another edition. CI runs it offline, in the web job, after `npm test`, which runs the pipeline's own unit tests.
- **The tool test** (`test/tool/geography_manifest_test.dart`) loads every asset with the G3 decoder. It checks that each node's label point lies inside the node's shape.
- **The research's provisional budgets** are looser than GEO-11: at most 30 MB for the certification core, at most 2 MB per frequently loaded layer, and three levels of detail for dense layers. GEO-11 stays. At 1.4 MB, no layer needs its own levels of detail yet: G3 already simplifies each shared arc per zoom level. The atlas tasks revisit this when dense layers arrive.

---

## 8. Rendering architecture

**Choice (GEO-12):** a custom renderer. It is built on `CustomPainter` inside an `InteractiveViewer`, with the geometry logic in pure Dart.

| Part | Where | Does |
|---|---|---|
| Geometry core | `lib/core/geography/` (pure Dart, no Flutter imports, per DL-1) | TopoJSON decoding; Web Mercator projection; bounding boxes; point-in-polygon with holes and multipolygons; distance to outline; frame fitting; level-of-detail choice; hit-testing |
| Map widget | `lib/features/map/` | Pan and zoom with limits; cached `Picture` per layer and zoom bucket; highlight and label modes; markers for small features; taps → hit test → callback; attribution button |
| Map formats | `lib/core/questions/formats/map_*` and `lib/features/practice/formats/` | Generation, presentation, grading and views (question-system §9) |

**Why not flutter_map.** [flutter_map](https://pub.dev/packages/flutter_map) 8.3.2 (BSD-3-Clause) does support vector polygons with hit detection and runs without tiles. It is the fallback if the atlas outgrows the custom renderer. Quiz maps need exact control of what is drawn and named (blank modes, candidate reveal, deterministic hit tests), and they need none of its tile, network and projection dependencies (`http`, `path_provider`, `proj4dart`). A small renderer is simpler to test and identical on web.

**Accessibility (GEO-13):**

- Every map question has a non-visual answer mode: a list of candidate names, graded the same way.
- Colours are chosen for colour-vision deficiency.
- Right and wrong are marked by icon as well as colour, as the Phase 3 MCQ view already does.

**Attribution (GEO-14):**

- A map shows an information button that lists the attributions of its visible layers.
- *Settings → About → Data sources* lists every dataset citation, with its licence and attribution text.

**As built (G3).** The renderer takes a decoded layer per asset and a question's settings:

- `Topology.parse` reads an asset. A feature's `id` is its `feature_key`, and a `name` property labels context features such as rivers. Open rings, missing arcs, unknown types and empty multi-geometries are refused with a `FormatException`.
- `GeoLayer.fromTopology` gives the layer its `map_layers` zoom range (minimum inclusive, maximum exclusive), its attribution and the manifest's label points. Two features with one key are refused. An area without a label point uses its centroid when that falls inside it, and otherwise its pole of inaccessibility.
- `MapCanvas` takes the layers (`MapLayer.base` for coastlines, borders and major rivers), the mode, the candidates' keys, the parent's key, highlights, the reveal flag, names, the frame and the frame one level up. A tap returns a `MapTap`: the coordinate, the view and every hit ranked, best first.
- Simplification ranks each shared arc once, so neighbours stay joined at every zoom. Hit tests use the full geometry.
- These cases were not specified above, so the renderer settles them:
  - When a tap is inside several candidates, where registers overlap (GEO-16) or a marker lies over a neighbour, the smallest wins.
  - A line has no inside, so a tap on a river counts as near it.
  - A tap hits only candidates whose layer is within its zoom range, so a layer the zoom hides can be neither seen nor tapped.
  - In the minimal and blank modes, markers stay hidden with the candidates until the answer is revealed. Taps are then graded against the shapes themselves.
  - Revealing shows the map as labelled mode does.

---

## 9. Worked examples

- **Chablis, three ways, one memory.**
  - "In which region is Chablis?" (MCQ).
  - "Tap Chablis" on the Burgundy map (`map_locate`, outline mode).
  - "Which appellation is highlighted?" (`map_identify`).

  All three grade `ki_chablis_location`. After a correct blank-map answer its stability grows, and its next text question is scheduled later, as FS-2 requires.
- **Rain shadow.** Alsace `SHELTERED_BY` Vosges. The questions are "Tap the range that shelters Alsace" (map) and "Why is Colmar one of France's driest towns?" (reasoning: `SHELTERED_BY` → rain shadow → dry, sunny autumns → late harvests). A right answer credits both items; a wrong one blames the reasoning item.
- **Map deduction (depth 5).** The prompt shows a steep south-facing slate valley on a northern river at about 50° N, with the relief shaded. The question: "Which grape and style is most plausible?" The answer is a high-acid, light-bodied Riesling. The distractors violate a stated principle: a full-bodied Grenache needs a warm climate. The chain covers `FACES`, `HAS_SOIL`, `HAS_CLIMATE`, and a climate → style principle.

---

## 10. Test strategy

| Level | Tests |
|---|---|
| Geometry core (unit) | Projection round trips; point-in-polygon with holes, multipolygons and antimeridian-free frames; TopoJSON decoding against a known fixture; frame fitting; the small-feature marker rule |
| Pipeline | Byte-identical rebuild; every feature mapped to an existing node; containment (every appellation inside its region's shape, within a tolerance); size budgets |
| Dataset validation | Every layer cites a dataset with a licence and attribution; every map-enabled node has a location item (GEO-6); authored `BORDERS` match the computed adjacency (warning); symmetric relations stored once |
| Generation | A `map_locate` question exists only with at least 4 candidates in its frame; answers accepting several nodes include every correct node; no map question for a node without geometry |
| FSRS | A map answer and a text answer about the same node update the same `review_states` row (the GEO-1 acceptance test) |
| Widget | A tap inside, near and outside a candidate grades correctly; minimal mode shows no candidate names; markers appear for small features; the accessible list mode answers correctly |
| Web | The web smoke test renders a layer and hit-tests a tap in Chromium |
| Performance | A synthetic stress layer of 2,000 polygons parses and paints within the budgets (task R2) |
