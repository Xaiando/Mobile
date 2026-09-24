# Implementation Backlog

| | |
|---|---|
| **Date** | 2026-09-24 |
| **Baseline** | Phases 0–3 complete on `claude/charming-ramanujan-8w1v2r` ([Xaiando/Mobile#1](https://github.com/Xaiando/Mobile/pull/1)): 241 tests, CI green on Android, iOS and web |
| **Design** | [Question system and coverage](design/question-system.md) · [Geography and maps](design/geography.md) · [Study packs](design/study-packs.md) |
| **Decisions** | [architecture-audit.md](architecture-audit.md) §12–§16 (DL, QF, COV, GEO and PK rows) |

The product specification's backlog (§P) has ten large tasks, seven of which are done. This backlog decomposes the rest of the product into **40 tasks**, each sized for one Claude Code cloud session and one pull request. It widens the study experience in three ways:

- geography becomes a first-class, map-based study domain;
- the question system grows from three formats to the sixteen study modes requested, plus short written answers (spec §T) and episodic recall;
- a coverage checker makes sure that no important knowledge can only ever be practised as a flashcard.

---

## 1. How to run a task

1. **Merge [Xaiando/Mobile#1](https://github.com/Xaiando/Mobile/pull/1) into `main` first.** Every task branches from `main` (`claude/<task-id>-<slug>`), so parallel sessions start from the same code.
2. Read `CLAUDE.md` and the design section the task names. A task implements the design; it does not redesign it. If a task needs a design change, it records a decision in the audit and says so in its PR.
3. Respect the **hot spots** in §4: a file listed there is edited only by the task that owns it in that wave.
4. **Done** means:
   - the acceptance criteria are met;
   - the required automated tests exist and pass;
   - `dart format`, `flutter analyze`, `flutter test` and `tool/web_assets.sh check` are clean;
   - the coverage ratchet (F1) passes;
   - CI is green;
   - this backlog's status column is updated in the same PR.

---

## 2. Already done

| Spec task | What exists | Where |
|---|---|---|
| TASK-001 Schema | Canonical schema (31 tables), constraints, triggers, v1 snapshot | Phase 0, `ad0f369` |
| TASK-002 Seed hydration | Dataset 0.1.0 (65 nodes, 87 relations, 46 cited items), parser, validator, ingestion | Phase 1, `db25d15` |
| TASK-003 FSRS | `ReviewService`: one transaction per review, lapses, replayable log | Phase 3, `044d520` |
| TASK-004 Distractors | Question generator, scoped distractor search, seeded presentation | Phase 2, `429dea7` |
| TASK-005 Adaptive queue | Priority score, effective mappings, 15-item sessions | Phase 3, `044d520` |
| TASK-006 Dashboard | Home: track picker, due and new counts, retention, start button | Phase 3, `044d520` |
| TASK-007 Study UI | Practice: MCQ and flashcards; Study list | Phase 3, `044d520`, `b90fb51` |
| TASK-010 Build-time checks | Dangling edges, prerequisite cycles, distractor viability (§S) | Phases 1–2 |
| Repository layer | Only `lib/core` queries the database; a layering test enforces it (DL-1) | `2e56fba` |

TASK-008 (tasting grids) and TASK-009 (journal integration) remain; they are T1–T2 and J1–J3 below.

---

## 3. Task index

**Status:** ☐ open · ◐ in progress · ☑ done. **Wave:** the planned wave (§4). A task may start earlier only when its dependencies are merged and it touches no hot spot owned in the running wave.

| ID | Task | Depends on | Wave | Status |
|---|---|---|---|---|
| **F** | **Foundations** | | | |
| F1 | Question-coverage checker: report and ratchet | — | 1 | ☐ |
| F2 | Schema v2: question system, geography, packs | C1 | 2 | ☐ |
| F3 | Format registry and exercise runtime | F2 | 3 | ☐ |
| F4 | Presentation difficulty ladder | F3 | 4 | ☐ |
| **C** | **Curriculum content and tooling** | | | |
| C1 | Dataset modularization, authoring and verification tools | — | 1 | ☐ |
| C2 | Content: France | C1, F2 | 3 | ☐ |
| C3 | Content: Italy, Spain, Portugal and fortified wines | C1, F2 | 3 | ☐ |
| C4 | Content: the New World | C1, F2 | 3 | ☐ |
| C5 | Content: principles | C1 | 2 | ☐ |
| **G** | **Geography and maps** | | | |
| G1 | Geodata pipeline, sources and licences | — | 1 | ☐ |
| G2 | Geometry ingestion and validation | F2, G1 | 3 | ☐ |
| G3 | Offline map renderer | — | 1 | ☐ |
| G4 | Map locate and identify, with difficulty modes | F3, G2, G3 | 4 | ☐ |
| G5 | Hierarchy drills and map orderings | G4, Q3 | 5 | ☐ |
| G6 | Physical geography and climate influences | G4 | 5 | ☐ |
| G7 | Topography and geology | G4 | 5 | ☐ |
| G8 | Neighbours and grape–region drills | G4, Q2, Q3 | 5 | ☐ |
| G9 | Map-based deduction | Q6, G6, G7 | 6 | ☐ |
| **Q** | **Question formats** | | | |
| Q1 | Typed recall and short written answers | F3 | 4 | ☐ |
| Q2 | Multiple response and completeness assertions | F3 | 4 | ☐ |
| Q3 | Matching and ordering | F3 | 4 | ☐ |
| Q4 | Numeric and range answers | F3 | 4 | ☐ |
| Q5 | Label interpretation and wine-list error spotting | F3 | 4 | ☐ |
| Q6 | Reasoning engine: climate, viticulture, production | F3 | 4 | ☐ |
| Q7 | Service and food-pairing scenarios | Q6, C5 | 5 | ☐ |
| Q8 | Tasting deduction | Q6, T1 | 5 | ☐ |
| Q9 | Cross-domain reasoning | Q6, G6 | 6 | ☐ |
| **T** | **Tasting (spec Phase 4)** | | | |
| T1 | Tasting grids and lexicon | C1 | 2 | ☐ |
| T2 | Tasting session UI and persistence | T1 | 3 | ☐ |
| **J** | **Wine journal (spec Phase 5)** | | | |
| J1 | Journal entries: create, edit, list | — | 1 | ☐ |
| J2 | Journal-to-graph matching and the journal priority factor | J1 | 2 | ☐ |
| J3 | Episodic questions from the journal | J2, F3 | 4 | ☐ |
| **P** | **Study packs** | | | |
| P1 | Study packs as tracks | F2 | 3 | ☐ |
| P2 | Germany core and Spätburgunder pack I | P1, G2 | 5 | ☐ |
| P3 | Spätburgunder pack II and competition drills | P2, Q6, Q8, S1 | 6 | ☐ |
| **S** | **Study experience and analytics (spec Phase 6)** | | | |
| S1 | Study browser v2: atlas, search, focused and timed sessions | F3, G3 | 5 | ☐ |
| S2 | Learner analytics | F1, F3 | 4 | ☐ |
| **R** | **Quality and release** | | | |
| R1 | Onboarding, settings, attributions, accessibility | — | 3 | ☐ |
| R2 | Performance and scale | F3, G3 | 6 | ☐ |
| R3 | Release readiness and gates | all V0.1 tasks | 7 | ☐ |

---

## 4. Parallel plan

### Waves

Tasks in the same wave can run in separate cloud sessions at the same time, because they own disjoint hot spots. A task that slips moves to a later wave, once its dependencies are merged.

| Wave | Can run in parallel | Why they do not collide |
|---|---|---|
| **1** | F1, C1, G1, G3, J1 | F1 adds `lib/core/coverage/`, C1 the dataset loader and tools, G1 `tool/geography/`, G3 `lib/core/geography/` and `lib/features/map/`, J1 journal screens. |
| **2** | F2, C5, T1, J2 | F2 exclusively owns the schema and the dataset section list. C5 and T1 add new dataset files only. J2 edits the priority score before F3 touches the planner. |
| **3** | F3, G2, P1, C2, C3, C4, T2, R1 | F3 exclusively owns the question engine and the practice screen core. G2 owns geometry ingestion. P1 owns the track model. Content tasks write their own files. R1 adds settings screens. |
| **4** | F4, Q1–Q6, G4, J3, S2 | Each format lives in its own folder under `formats/` and adds one registry line. F4 owns the format chooser. |
| **5** | Q7, Q8, G5, G6, G7, G8, S1, P2 | Each adds formats, content files or layers of its own. S1 owns the Study tab and the router. |
| **6** | Q9, G9, P3, R2 | These build on waves 4–5. |
| **7** | R3 | The release gate. |

With five to eight sessions per wave, the backlog runs in seven waves rather than forty sequential sessions.

### Hot spots

| Hot spot | Owner | Rule for everyone else |
|---|---|---|
| `lib/core/database/schema.drift`, `drift_schemas/`, migrations | F2 only (DL-3) | Changes are batched into F2. A later schema change needs its own scheduled task and a migration test (DL-2). |
| Dataset loader and its section list (`curriculum_dataset.dart`) | C1, then F2, then G2, in that order | Content tasks do not touch the loader. |
| Dataset files | one file per area, pack or task after C1 | Adding an include line or bumping `dataset_version` is a one-line change; resolve by rebasing. |
| `lib/core/questions/` and `lib/features/practice/` cores | F3 (wave 3) | Afterwards a format task adds a `formats/<id>/` folder and one registry line. |
| `lib/core/study/` planner, session and priority | J2 (wave 2), F3 (wave 3), F4 (wave 4), S1 (wave 5) | No two of them run at the same time. |
| `review_service.dart` | F3 | Formats grade through the runtime and never write reviews themselves. |
| `coverage_policy.yaml`, `coverage_baseline.json` | append and raise only | After rebasing, re-run the checker and regenerate the baseline. |
| `tool/geography/layers.yaml`, `assets/geography/manifest.yaml` | one entry per layer | Rebuild only your own layer's asset. |
| Router and app shell | R1 (wave 3), S1 (wave 5) | Other tasks add screens only under their feature folder. |
| Question templates | one file per format, `assets/curriculum/templates/<format>.yaml` | A format task writes only its own template file. |
| `pubspec.yaml` | C1 declares the curriculum asset folders; G2 declares `assets/geography/` | Folders are declared once, so new files need no edit. A new dependency needs a compatibility note in the architecture validation first. |

---

## 5. Tasks

### Group F: Foundations

#### F1 · Question-coverage checker: report and ratchet

- **Objective.** Build the coverage checker of [question-system §8](design/question-system.md#8-coverage-checker) for today's formats. It answers, for each track and domain, which items are testable, which formats can and do test them, and which core areas lack useful practice. Every later task must then keep or raise coverage.
- **Depends on.** Nothing; it runs on the current schema.
- **Modules.** New:
  - `lib/core/coverage/`: the model, the checker, and policy loading;
  - `tool/coverage_report.dart`;
  - `assets/curriculum/coverage_policy.yaml` and `coverage_baseline.json` (not bundled in the app);
  - `test/core/coverage/`.
- **Acceptance criteria.**
  - For WSET_L3 and CMS_CERTIFIED, the report lists per domain and area:
    - items, core items, testable items and flashcard-only items;
    - items with useful practice (at least one objective format and two families);
    - items per family;
    - a list of gaps.
  - The policy declares format capabilities for every relation type in the dataset. The checker fails if a relation type is missing from the policy.
  - `dart run tool/coverage_report.dart --track WSET_L3 --format md|json` runs offline.
  - `coverage_baseline.json` is committed. The build fails if a metric drops below it, or if a *new* core item is flashcard-only.
  - Known gaps are allowed only when listed in the baseline, each with a reason and the task that will close it. The five `mcq_disabled` items that are flashcard-only today are the first entries; Q1 closes them.
  - The PR attaches the report for the current dataset.
- **Required automated tests.**
  - Fixture datasets for each metric and each gap rule.
  - Policy errors: an unknown relation type and a malformed threshold.
  - Ratchet behaviour: a drop fails, a rise passes, a new flashcard-only core item fails.
  - A test that runs the checker on the bundled dataset for both selectable tracks.
- **Parallel.** Yes. It adds new files only; it runs with C1, G1, G3 and J1.

#### F2 · Schema v2: question system, geography, packs

- **Objective.** Land every schema change this backlog needs in one reviewed migration (DL-3), so no feature task edits the schema.
- **Depends on.** C1. The loader is modularized first, then gains the new sections.
- **Modules.**
  - `lib/core/database/schema.drift`;
  - `app_database.dart`: `schemaVersion` 2 and `onUpgrade` from the generated step helpers;
  - `drift_schemas/` and the generated `test/drift/`;
  - `curriculum_dataset.dart` and `curriculum_validator.dart`;
  - `docs/domain-model.md` and the audit.
- **Changes, exactly:**
  1. `question_templates`:
     - `mode` is checked as an identifier only, and the format registry validates membership (QF-2);
     - add `variant` (default `''`) to its unique key;
     - add a `parameters` column (JSON).
  2. New generated tables `exercise_pools` and `exercise_pool_items`, read-only and rebuilt on ingestion.
  3. `review_events`: add `exercise_id` (a UUID, nullable) and `answer_payload` (JSON, nullable).
  4. `review_event_options.position`: CHECK `position >= 1` (it was 1–4).
  5. `relation_types.is_symmetric`.
  6. New authored table `relation_set_assertions`, with a citation.
  7. `certifications`:
     - add `kind` (`certification` or `pack`) and a `description`;
     - `organization` is null for packs, and a CHECK couples the two.
  8. New authored tables `map_layers` and `node_geometries` ([geography §3](design/geography.md#3-geometry-model-schema-v2)).
- **Acceptance criteria.**
  - A fresh install creates v2.
  - A v1 database holding reviews, options, a profile and a curriculum upgrades with every user row intact, and the append-only triggers still reject changes.
  - The v2 snapshot is committed, and CI's stale-code check passes.
  - The dataset format (domain model §7) documents the new sections.
  - The validator checks the new rules:
    - a symmetric relation is stored once, with subject ID < object ID;
    - completeness assertions cite a source;
    - map layers cite a `dataset` source with a licence and attribution;
    - geometry rows reference existing layers and nodes.
  - The 241 existing tests still pass, and existing formats behave the same.
- **Required automated tests.**
  - The generated v1 → v2 migration test, proving data is preserved.
  - CRUD and constraint tests for every new table and column, in the style of `crud_test` and `domain_model_test`.
  - One negative validator test per new rule.
  - The append-only triggers after migration.
  - The web smoke test.
- **Parallel.** No for the schema, the section list and migrations, which F2 owns exclusively. Tasks touching none of them (C5, T1, J2) may run alongside.

#### F3 · Format registry and exercise runtime

- **Objective.** Split generation, presentation, grading and practice views into per-format plug-ins, and add the composite-exercise runtime ([question-system §9](design/question-system.md#9-generation-and-runtime-architecture)). After this, each new format is an isolated task.
- **Depends on.** F2.
- **Modules.**
  - `lib/core/questions/`: the registry, with `formats/flashcard/` and `formats/mcq/` moved in;
  - `review_service.dart`: exercises covering several items;
  - `study_planner.dart` and `study_session.dart`: the format-choice hook and co-items;
  - `lib/features/practice/`: the view registry;
  - F1's format catalogue, moved into the registry;
  - `CLAUDE.md` ("Question engine": how to add a format).
- **Acceptance criteria.**
  - Flashcard and MCQ behave exactly as before.
  - A composite exercise writes one review event per item, with a shared `exercise_id` and an `answer_payload`, in one transaction; a failure writes nothing (QF-3).
  - A format is added with one file per layer and one registry line per layer.
  - A test-only two-item format proves the runtime end to end.
  - Co-items count as bonus reviews and use no session slot.
- **Required automated tests.**
  - The registry rejects a duplicate format ID, and the validator rejects an unknown template mode.
  - Composite review transactions, including rollback.
  - Sessions with co-items.
  - A practice widget test with the test-only format.
  - All Phase 2 and 3 tests still pass.
- **Parallel.** No inside the question engine and practice core, which it owns exclusively in wave 3. It runs alongside G2, P1, C2–C4, T2 and R1.

#### F4 · Presentation difficulty ladder

- **Objective.** Choose each presentation's format by the item's stability, with variety rules ([question-system §5](design/question-system.md#5-presentation-difficulty-ladder), QF-7). This replaces FS-15's random draw and drives the map difficulty modes.
- **Depends on.** F3.
- **Modules.**
  - `lib/core/study/format_ladder.dart` (new);
  - the session's format-choice hook;
  - an audit update marking FS-15 as superseded.
- **Acceptance criteria.**
  - The chosen family follows the stability bands.
  - The last format is not repeated when another is served.
  - One presentation in five is a seeded random draw.
  - Only formats allowed by `minimum_depth` are chosen.
  - Map modes (labelled → blank) follow the same bands.
- **Required automated tests.**
  - Unit tests for each band.
  - A distribution test over many seeds.
  - A simulated-weeks integration test in which an item's presentations harden as it is recalled.
- **Parallel.** Yes with Q1–Q6, G4, J3 and S2. It owns only the chooser.

### Group C: Curriculum content and tooling

#### C1 · Dataset modularization, authoring and verification tools

- **Objective.** Split the curriculum into per-area files under one release, and give authors lint, report and expert-verification tools, so that content tasks run in parallel without merge conflicts (DL-4).
- **Depends on.** Nothing.
- **Modules.**
  - `assets/curriculum/`: `curriculum.yaml` becomes a manifest with `includes:`, plus `areas/*.yaml` and `reviews/` (the review ledger);
  - `curriculum_dataset.dart` and `curriculum_providers.dart`: loading several files with one checksum;
  - `pubspec.yaml`;
  - new `tool/curriculum/` with `lint`, `report` and `verify`;
  - `docs/domain-model.md` §7 and `CLAUDE.md`.
- **Acceptance criteria.**
  - Release 0.1.0's content is split across files. Ingestion produces identical rows and questions (release 0.1.1, same content).
  - A duplicate key across files is reported with both file names and lines.
  - `lint` prints validator issues with file and line.
  - `report` prints the generation report and, once F1 exists, the coverage summary.
  - `verify` records an expert's review in the ledger (reviewer, date, outcome, notes). It sets `verification_status` and `last_verified_at` through a normal content change, so verification is auditable (D3).
- **Required automated tests.**
  - The loader: includes, missing includes, duplicates across files, and one checksum over all files that changes whenever any file does.
  - Ingestion equivalence between the split and single-file datasets.
  - Smoke tests for each tool command.
  - Ledger parsing and verification-status updates.
- **Parallel.** Yes in wave 1. It must merge before F2 and every content task.

#### C2 · Content: France

- **Objective.** Author the WSET Level 3 and CMS Certified core for France, geography-ready for maps:
  - Bordeaux, Burgundy, Beaujolais, Champagne, Loire, Rhône, Alsace, Provence, Languedoc-Roussillon, South West, Jura and Savoie;
  - their rivers (Gironde, Garonne, Dordogne, Loire, Rhône, Saône, Marne, Serein), barriers (Vosges, Massif Central) and influences (Atlantic, Mistral);
  - key neighbour sets (Médoc communes, Côte de Nuits villages);
  - completeness assertions for the principal-grape sets.
- **Depends on.** C1 and F2. Geometry layers arrive through G1 and G2, and items can land before the layers do.
- **Modules.** `assets/curriculum/areas/france_*.yaml`, `tool/geography/layers.yaml` (the French layers), `coverage_policy.yaml`.
- **Acceptance criteria.**
  - At least 60 new cited items. Wine-law relations cite the cahier des charges; physical and climate facts cite public sources.
  - Every node that can be asked on a map has a location item (GEO-6).
  - No new core item is flashcard-only, and French areas meet the thresholds for every format built at merge time.
  - Every item is `unverified` (D3).
- **Required automated tests.**
  - The validator and the §S.3 gate pass.
  - The generation report is reviewed in the PR.
  - The ingestion counts are updated.
  - The coverage baseline is raised.
- **Parallel.** Yes with the other content tasks, since each writes its own files.

#### C3 · Content: Italy, Spain, Portugal and fortified wines

- **Objective.** Author the WSET Level 3 and CMS Certified core for:
  - **Italy:** Piedmont, Tuscany, Veneto, the South and the islands;
  - **Spain:** Rioja, Ribera del Duero, Priorat, Rías Baixas and Sherry;
  - **Portugal:** Douro and Port, Vinho Verde, Madeira;
  - **fortified production:** as principles for production reasoning.
- **Depends on.** C1 and F2.
- **Modules.** `assets/curriculum/areas/italy_*.yaml`, `spain_*.yaml`, `portugal_*.yaml`; the geography layers (ISTAT; Spanish and Portuguese boundary sources); `docs/legal-review.md`.
- **Acceptance criteria.** As C2, with at least 50 new items. It also:
  - researches and records open-licensed boundary sources for Spain and Portugal in `tool/geography/sources.yaml`, or documents the point fallback (GEO-9);
  - cites the MASAF disciplinari, Spain's *pliegos de condiciones* and Portugal's IVV and IVDP rules.
- **Required automated tests.** As C2.
- **Parallel.** Yes.

#### C4 · Content: the New World

- **Objective.** Author the core for the USA (AVAs), Canada, Chile, Argentina, Australia, New Zealand and South Africa.
- **Depends on.** C1 and F2.
- **Modules.** `assets/curriculum/areas/<country>.yaml`, the geography layers (the UC Davis AVA dataset, CC0; other sources as researched), `docs/legal-review.md`.
- **Acceptance criteria.** As C2, with at least 50 new items. It cites 27 CFR part 9 and each country's GI register. Every geometry source is recorded with its licence, or the point fallback is used.
- **Required automated tests.** As C2.
- **Parallel.** Yes.

#### C5 · Content: principles

- **Objective.** Author the general knowledge that reasoning and scenario formats need ([question-system §7](design/question-system.md#7-principles-the-knowledge-behind-reasoning-formats)):
  - climate → style;
  - viticultural hazards and practices;
  - winemaking methods and their effects, including sparkling and fortified;
  - wine faults (cork taint, oxidation, *Brettanomyces*, volatile acidity);
  - service: temperatures, glassware, decanting, storage;
  - food-pairing principles;
  - the **business** domain (wine lists, pricing, cellar management), which is empty today;
  - spirits, beer and sake basics for the CMS tracks.
- **Depends on.** C1. It needs no schema change, since node types and relation types are data.
- **Modules.** `assets/curriculum/areas/principles_*.yaml`, `coverage_policy.yaml`.
- **Acceptance criteria.**
  - At least 60 principle items, with cited public sources, and no WSET or CMS text (D10, L-17).
  - Every relation type added is listed in the coverage policy.
  - The domains `viticulture`, `winemaking`, `service` and `business` each have core items for both tracks.
- **Required automated tests.** Validator, generation report, and the coverage baseline raised.
- **Parallel.** Yes from wave 2. It writes only its own files.

### Group G: Geography and maps

#### G1 · Geodata pipeline, sources and licences

- **Objective.** Build the reproducible pipeline of [geography §7](design/geography.md#7-build-pipeline), with the first layers:
  - **Natural Earth context:** continents, countries, coastlines, major rivers, lakes, seas and physical regions;
  - **France:** régions, plus the AOC areas of the current dataset, from INAO's commune lists and IGN ADMIN EXPRESS.
- **Depends on.** Nothing. It reads node IDs from the dataset.
- **Modules.**
  - new `tool/geography/`: `sources.yaml`, `layers.yaml`, the `fetch`, `build` and `check` scripts, and a pinned `package-lock.json`;
  - `assets/geography/`: the TopoJSON layers and the manifest;
  - `docs/legal-review.md` L-15;
  - CI: a `check` step.
- **Acceptance criteria.**
  - After one online `fetch`, `build` and `check` run offline, and outputs are byte-identical across runs.
  - Every layer fits the budgets of GEO-11.
  - Every feature maps to an existing node ID.
  - The report lists proposed `BORDERS` pairs and any containment failures (none for the bundled nodes).
  - `sources.yaml` records each source's URL, date, SHA-256, licence and attribution; excluded sources are listed with the reason.
  - CI fails when the assets drift from the manifest.
- **Required automated tests.**
  - `check` runs in CI.
  - A tool test that validates the manifest schema and that every manifest node ID exists in the dataset.
- **Parallel.** Yes in wave 1. It is tool-only.

#### G2 · Geometry ingestion and validation

- **Objective.** Ingest map layers and node geometries from the manifest into the schema v2 tables, and give the map formats their queries.
- **Depends on.** F2 and G1.
- **Modules.**
  - `lib/core/curriculum/`: the manifest sections, and asset SHA-256 checks at ingestion;
  - `curriculum_validator.dart`: the location item rule (GEO-6), attributions, feature keys, bounding box sanity;
  - new `lib/core/geography/geometry_repository.dart`: a node's geometry and frame, the candidates in a frame, siblings;
  - `pubspec.yaml` assets.
- **Acceptance criteria.**
  - Startup ingests the layers offline.
  - An asset whose hash does not match is refused, and nothing is written.
  - A map-enabled node without a location item is a validator error.
  - The web smoke test loads a layer.
- **Required automated tests.**
  - Ingestion: a hash mismatch, a missing feature key, an unknown node.
  - Repository queries: frames, candidates, siblings.
  - One negative validator test per rule.
  - The web smoke test.
- **Parallel.** Yes in wave 3, alongside F3, P1 and the content tasks.

#### G3 · Offline map renderer

- **Objective.** Build the pure-Dart geometry core and the `MapCanvas` widget of [geography §8](design/geography.md#8-rendering-architecture), working on fixture geometry.
- **Depends on.** Nothing.
- **Modules.** New `lib/core/geography/` (TopoJSON decoding, projection, hit-testing, frames, level of detail), new `lib/features/map/map_canvas.dart`, test fixtures.
- **Acceptance criteria.**
  - Pan and zoom stay within limits.
  - Highlighting works, with the four label modes, and markers replace features too small to tap.
  - A tap returns the node under it, using the inside and near rules of geography §4.
  - It behaves the same on Android, iOS and web.
  - A stress fixture parses and paints within the GEO-11 budgets.
  - It adds no new runtime dependency, unless an audit update records a switch to `flutter_map`.
- **Required automated tests.**
  - Unit: projection round trips; point-in-polygon with holes and multipolygons; distance to an outline; TopoJSON decoding; level of detail.
  - Widget: taps inside, near and outside; the marker rule; what each mode shows.
  - The layering test: `lib/core` has no widgets.
  - A benchmark test with generous thresholds.
- **Parallel.** Yes in wave 1. It adds new files only.

#### G4 · Map locate and identify, with difficulty modes

- **Objective.** Deliver the first spatial formats, `map_locate` and `map_identify`, for location items. They come with the four difficulty modes and an accessible list mode ([geography §4–5](design/geography.md#4-map-formats)).
- **Depends on.** F3, G2 and G3. F4 drives the modes once it exists; until then, the depth sets them.
- **Modules.**
  - `lib/core/questions/formats/map_locate/` and `map_identify/`;
  - `lib/features/practice/formats/map_*_view.dart`;
  - templates in the dataset;
  - the coverage policy.
- **Acceptance criteria.**
  - **Acceptance test for GEO-1:** locating Chablis on the map, identifying it when highlighted, and answering "In which region is Chablis?" in text all update the same `review_states` row.
  - Frames and candidates follow geography §5: at least four candidates, or the frame moves up a level. Every correct node is accepted.
  - `answer_payload` logs the tap.
  - Every core geography item with geometry has a spatial format, and the coverage baseline is raised.
- **Required automated tests.**
  - Generator eligibility.
  - Grading taps inside, near and outside a candidate, and questions with several correct answers.
  - The GEO-1 same-item test.
  - Widget tests for each mode and for the accessible list mode.
  - A web smoke test that taps a feature.
- **Parallel.** Yes in wave 4.

#### G5 · Hierarchy drills and map orderings

- **Objective.** Add two map exercises:
  - `map_drill`: country → region → subregion → appellation, one tap per level, graded per level and stopping at the first wrong one;
  - map-prompted orderings: north to south, and along a river from upstream to downstream.
- **Depends on.** G4 and Q3.
- **Modules.** `formats/map_drill/`, an ordering variant with a map prompt, views and templates.
- **Acceptance criteria.**
  - A drill reviews each level's location item once, with a shared `exercise_id`.
  - Ordering keys come from label points, and a question is generated only when neighbouring elements differ by a clear margin.
- **Required automated tests.** Drill grading, including the early stop; the ordering key and margin rules; widget tests.
- **Parallel.** Yes in wave 5.

#### G6 · Physical geography and climate influences

- **Objective.** Model rivers, bodies of water, mountain ranges, landforms, winds and currents as mapped nodes, with `LIES_ALONG`, `FLOWS_THROUGH`, `SHELTERED_BY`, `MODERATED_BY` and `EXPOSED_TO` items. Add map feature questions and map-prompted climate-influence questions.
- **Depends on.** G4. Natural Earth layers come from G1.
- **Modules.** Its own dataset file `areas/physical_geography.yaml` (the new node and relation types, referring to nodes in other files), `layers.yaml` (physical layers), `templates/` files, the coverage policy.
- **Acceptance criteria.**
  - Every river, range and body of water that a core item of the bundled dataset names is mapped, with its location item.
  - Rain shadow, maritime moderation and wind exposure each have at least one map question and one text question.
  - The coverage baseline is raised.
- **Required automated tests.** Validator signatures for the new relation types; generation of feature questions; line hit-testing for rivers; FSRS same-item tests.
- **Parallel.** Yes in wave 5.

#### G7 · Topography and geology

- **Objective.** Cover slope, aspect and elevation, derived from SRTM by the pipeline and authored as cited `FACES`, `HAS_ELEVATION` and `HAS_SLOPE` relations, plus optional relief shading. Add soil and geology questions on maps.
- **Depends on.** G4 and G1.
- **Modules.** A DEM step in `tool/geography/`, its own dataset file `areas/topography.yaml`, `templates/` files, the renderer's relief-shading overlay.
- **Acceptance criteria.**
  - The pipeline reports the elevation range, mean slope and dominant aspect of every mapped site and area.
  - Relations carry an SRTM citation.
  - Aspect and elevation questions work in MCQ, numeric and map-prompted forms.
  - Soil questions on a map accept every correct node.
  - Relief shading stays within the asset budget.
- **Required automated tests.** DEM summaries on a synthetic elevation fixture; generation and grading; the budget check.
- **Parallel.** Yes in wave 5.

#### G8 · Neighbours and grape–region drills

- **Objective.** Add:
  - `BORDERS` items with "tap a neighbour";
  - `KNOWN_FOR_GRAPE` with completeness assertions;
  - grape → regions (`map_multi_locate`);
  - region → grapes (map-prompted multiple response);
  - statistic nodes for planted areas, with orderings.
- **Depends on.** G4, Q2 and Q3.
- **Modules.** `formats/map_multi_locate/`, `templates/` files, its own dataset files `areas/neighbours.yaml` and `areas/plantings.yaml` (relations and statistic nodes).
- **Acceptance criteria.**
  - Authored `BORDERS` match the pipeline's adjacency; any difference is reviewed in the PR.
  - A multi-answer question is generated only for an asserted complete set (QF-8).
  - Ranking questions cite a survey and its date.
- **Required automated tests.** Adjacency comparison; closed-world refusal; multi-locate grading per item; ranking generation.
- **Parallel.** Yes in wave 5.

#### G9 · Map-based deduction

- **Objective.** Add reasoning templates with map prompts: location, relief, water and climate lead to the most plausible grape or style ([geography §9](design/geography.md#9-worked-examples)).
- **Depends on.** Q6, G6 and G7.
- **Modules.** Reasoning templates with map prompts, a map-prompt view, the coverage policy.
- **Acceptance criteria.**
  - Chain grading follows QF-5.
  - Each distractor violates a stated principle.
  - Map deduction is served at depth 4 or 5 only.
- **Required automated tests.** Chain enumeration on fixtures; distractor validity; grading attribution.
- **Parallel.** Yes in wave 6.

### Group Q: Question formats

#### Q1 · Typed recall and short written answers

- **Objective.** Two recall formats:
  - **typed recall:** answers graded using `normalizeName` and alternative names, forward and reverse (QF-4); this turns self-graded recall into an objective format;
  - **short written answers:** for WSET-style short-answer practice (spec §T), the learner writes an answer and then ticks the key points it covered, each point being an item.
- **Depends on.** F3.
- **Modules.** `formats/typed/` and `formats/short_answer/`, their views, a grader over `node_alternative_names`, short-answer templates (key-point paths).
- **Acceptance criteria.**
  - Typed recall:
    - synonyms are accepted (e.g. Shiraz for Syrah), and accents and case are ignored;
    - one edit away is graded Hard;
    - the five flashcard-only items of today gain an objective format, and F1's known gaps shrink.
  - Short answers:
    - each key point is graded per item (question-system §4);
    - the written text is kept in `answer_payload` and never machine-graded.
- **Required automated tests.**
  - The typed grader: exact, synonym, accents, near misses, wrong answers.
  - Short-answer grading per key point.
  - Widget tests.
  - The coverage change.
- **Parallel.** Yes in wave 4.

#### Q2 · Multiple response and completeness assertions

- **Objective.** Add "select all that apply" for asserted complete sets, and author the assertions the bundled dataset supports, such as the varieties the Champagne cahier des charges lists.
- **Depends on.** F3.
- **Modules.** `formats/multiple_response/`, its view, its own dataset file `areas/completeness.yaml` (the assertions).
- **Acceptance criteria.**
  - Questions are generated only for asserted sets (QF-8).
  - Grading is per item (QF-4).
  - Distractors follow QG-4.
- **Required automated tests.** Refusal for a set without an assertion; per-item grading with false positives and misses.
- **Parallel.** Yes in wave 4.

#### Q3 · Matching and ordering

- **Objective.** Add two composite formats:
  - **matching:** three to five pairs from a pool of items sharing a relation type within a scope;
  - **ordering:** three to six elements ordered by a tier chain, process chain, quantity or latitude.

  Both have drag-and-drop views with an accessible move-up and move-down alternative.
- **Depends on.** F3.
- **Modules.** `formats/matching/` and `formats/ordering/`, their views, pool generators, `templates/` files, and its own dataset file `areas/orders.yaml` (relation types and chains for tier and process order: `RANKS_ABOVE`, `PRECEDES`).
- **Acceptance criteria.**
  - Grading is per pair and per element; ordering uses the longest correctly ordered subsequence (QF-4).
  - Pools prefer due items.
  - An ordering by quantity is generated only when neighbouring values differ.
- **Required automated tests.** Pool generation; grading, including the ordered-subsequence rule; the accessible reorder controls; the composite review transaction.
- **Parallel.** Yes in wave 4.

#### Q4 · Numeric and range answers

- **Objective.** Accept numeric and range answers for quantity items: minimum ageing, service temperatures and elevations. Tolerance bands come from template parameters, and units are displayed as the learner prefers (°C or °F).
- **Depends on.** F3.
- **Modules.** `formats/numeric/`, its view, unit conversion.
- **Acceptance criteria.**
  - Legal minima are exact.
  - Ranges are graded by inclusion.
  - Converting to and from °F keeps the grade the same.
- **Required automated tests.** Grading bands, unit conversions, range answers.
- **Parallel.** Yes in wave 4.

#### Q5 · Label interpretation and wine-list error spotting

- **Objective.** Two exercises:
  - Synthetic labels, rendered from layout assets per labelling regime (French AOC, German, Italian DOCG, Spanish, New World) with invented producers. Questions ask about the fields.
  - Error spotting in a generated wine list, where one entry contradicts the graph (e.g. a wrong region for an appellation).
- **Depends on.** F3.
- **Modules.** `formats/label/`, layout assets under `assets/labels/`, its own dataset file `areas/label_terms.yaml` (label-term nodes and `DENOTES` relations).
- **Acceptance criteria.**
  - Only invented producers are used (L-20).
  - Each label field practises a canonical item.
  - Every generated list error is detectable from graph facts alone.
- **Required automated tests.** Label generation from a fixture; each error is detectable; grading; a widget test.
- **Parallel.** Yes in wave 4.

#### Q6 · Reasoning engine: climate, viticulture, production

- **Objective.** Build the reasoning engine: path-pattern templates, chain enumeration, primary and supporting items, distractors that violate a principle, and chain grading ([question-system §7](design/question-system.md#7-principles-the-knowledge-behind-reasoning-formats), QF-5). Add climate, viticulture and production reasoning templates.
- **Depends on.** F3. C5 supplies real principles, and fixtures suffice until then.
- **Modules.** `formats/reasoning/`, path queries in `lib/core/curriculum/`, `templates/` files.
- **Acceptance criteria.**
  - A right answer credits the whole chain; a wrong answer blames only the target (QF-5).
  - Every distractor violates a stated principle.
  - Reasoning is served at depth 4 and above.
  - Reasoning coverage for core viticulture and winemaking items rises in the report.
- **Required automated tests.** Path enumeration; distractor validity; grading attribution; a widget test.
- **Parallel.** Yes in wave 4.

#### Q7 · Service and food-pairing scenarios

- **Objective.** Scenario templates on the reasoning engine:
  - **service:** temperature, glassware, decanting for sediment versus aeration, order of service, storage, faults;
  - **food pairing:** from principles.
- **Depends on.** Q6 and C5.
- **Modules.** `formats/scenario/`, `templates/` files, the coverage policy.
- **Acceptance criteria.**
  - Scenarios draw only on cited public sources and never reproduce the CMS service standards (L-17).
  - Pairing is framed as principles (L-18).
  - Temperatures reuse the numeric format.
- **Required automated tests.** Scenario generation; distractor validity; grading.
- **Parallel.** Yes in wave 5.

#### Q8 · Tasting deduction

- **Objective.** Generate structured tasting notes from style-profile relations, in the active framework's lexicon (T1). Ask for the most plausible grape, region, climate or age. Distractor profiles differ on key markers.
- **Depends on.** Q6 and T1.
- **Modules.** `formats/tasting_deduction/`, its own dataset file `areas/style_profiles.yaml` (style-profile relations).
- **Acceptance criteria.**
  - Notes use only the active framework's vocabulary.
  - Grading follows QF-5, with the primary items being the markers that separate the answer from the distractor chosen.
  - Deduction is served at depth 5.
- **Required automated tests.** Note generation per framework; marker-difference distractors; grading.
- **Parallel.** Yes in wave 5.

#### Q9 · Cross-domain reasoning

- **Objective.** Reasoning chains across at least two domains, e.g. geography → climate → grape → style → pairing, at depth 5.
- **Depends on.** Q6 and G6.
- **Modules.** Cross-domain templates on the reasoning engine.
- **Acceptance criteria.**
  - Each chain spans at least two domains.
  - The coverage report shows cross-domain coverage for every core area.
- **Required automated tests.** Chain generation across domains; grading.
- **Parallel.** Yes in wave 6.

### Group T: Tasting (spec Phase 4)

#### T1 · Tasting grids and lexicon

- **Objective.** Author the app's own two tasting frameworks, in its own wording:
  - a **systematic grid** for the WSET track;
  - a **deductive grid** for the CMS track.

  Each value can link to a `style_trait` node, so tasting deduction (Q8) can use it.
- **Depends on.** C1.
- **Modules.** `assets/curriculum/areas/tasting_*.yaml` (the tasting grid sections), `docs/legal-review.md` (D10 lexicon review).
- **Acceptance criteria.**
  - The framework names, attribute layout and wording are the app's own. No proprietary grid text or artwork is used, and a review checklist is attached to the PR.
  - The validator checks single and multiple selection rules.
  - The certification defaults point at the right grid.
- **Required automated tests.** Validator rules for grids; ingestion; the existing tasting triggers still enforce each framework's vocabulary.
- **Parallel.** Yes in wave 2.

#### T2 · Tasting session UI and persistence

- **Objective.** A Stepper form per framework, with strict vocabulary, save and resume, a list of past sessions, and an optional link to a journal entry.
- **Depends on.** T1. It links to journal entries once J1 exists.
- **Modules.** `lib/features/tasting/`, a tasting repository in `lib/core/`.
- **Acceptance criteria.** Spec Phase 4: *"User can complete a full tasting grid and save it to the local database."* Only the active framework's terms can be chosen.
- **Required automated tests.**
  - A widget test of a full grid and saving it.
  - Repository tests.
  - Rejection of another framework's value.
- **Parallel.** Yes in wave 3.

### Group J: Wine journal (spec Phase 5)

#### J1 · Journal entries: create, edit, list

- **Objective.** A journal repository in `lib/core/` and the Cellar screens: list, detail, create, edit and delete. The fields are producer, cuvée, vintage, appellation, grapes, alcohol, a 1–5 rating (P-3) and notes. There is no photo interface (D6).
- **Depends on.** Nothing; the tables exist since v1.
- **Modules.** `lib/core/journal/`, `lib/features/cellar/`.
- **Acceptance criteria.** Entries persist and validate (UTC timestamps, vintage range). The layering test passes.
- **Required automated tests.** Repository CRUD; widget tests for list, create and edit.
- **Parallel.** Yes in wave 1.

#### J2 · Journal-to-graph matching and the journal priority factor

- **Objective.** Match an entry's text to knowledge nodes (`name_norm`, alternative names, fuzzy matching), with confirmation by the learner, and write `wine_journal_entry_nodes` rows. Add the journal factor J (A-5) to the priority score, with provisional η and τ (audit).
- **Depends on.** J1.
- **Modules.** `lib/core/journal/matching.dart`, `lib/core/study/priority.dart`, `study_planner.dart`.
- **Acceptance criteria.** Spec Phase 5: *"Saving a wine entry successfully influences the FSRS priority queue for related nodes."* The acceptance test: after logging a Barolo, Barolo items rise in the queue.
- **Required automated tests.** Matching (synonyms, accents, former names, ambiguous names); the J factor; the acceptance test.
- **Parallel.** Yes in wave 2. It owns the priority score until F3 starts.

#### J3 · Episodic questions from the journal

- **Objective.** The `episodic` format (spec §J). "Which grape was the primary component of the [producer] Barolo you tasted in May?" It practises the canonical item (Barolo's grape), never a separate card.
- **Depends on.** J2 and F3.
- **Modules.** `formats/episodic/`, its view.
- **Acceptance criteria.**
  - An episodic question updates the same item as its text counterpart.
  - Episodic questions are generated at runtime from the learner's entries, never at ingestion.
- **Required automated tests.** Generation from entries; the same-item update.
- **Parallel.** Yes in wave 4.

### Group P: Study packs

#### P1 · Study packs as tracks

- **Objective.** Treat packs as tracks ([study-packs §1](design/study-packs.md#1-model)). They appear, grouped, in the track picker with descriptions, and the coverage policy has a section per pack.
- **Depends on.** F2.
- **Modules.** `learner_profile.dart`, `track_picker.dart`, the coverage checker, a fixture pack for tests.
- **Acceptance criteria.**
  - A fixture pack is selectable and planned through the unchanged planner.
  - Switching between a certification and a pack keeps memory state (FS-12).
  - A test proves that no pack ID appears in `lib/` (PK-1).
- **Required automated tests.** Profile and picker tests with a pack; coverage per pack; the no-special-case test.
- **Parallel.** Yes in wave 3.

#### P2 · Germany core and Spätburgunder pack I

- **Objective.** Author the German core for WSET Level 3 and CMS Certified. Then build the first half of the pack:
  - the regions and their hierarchy, down to flagship Einzellagen;
  - rivers, ranges and landforms;
  - climate and soils;
  - label law.

  This includes the German geography layers: BKG VG250, and the Einzellagen register of the Landwirtschaftskammer RLP, both dl-de/by-2-0.
- **Depends on.** P1 and G2. Full spatial coverage needs G4 and G6–G8.
- **Modules.** `assets/curriculum/areas/germany_*.yaml` and `packs/spaetburgunder.yaml`, the German entries in `tool/geography/layers.yaml`, `docs/legal-review.md` (L-19, L-21).
- **Acceptance criteria.**
  - Every fact is cited to German wine law, a state vineyard register, Destatis or another public source, and stays `unverified`.
  - VDP terms are described as a private classification, never as law (L-19).
  - The pack's coverage policy passes for the formats built at merge time.
- **Required automated tests.** Validator; the generation report; coverage for the pack; the map GEO-1 test on a German site.
- **Parallel.** Yes in wave 5.

#### P3 · Spätburgunder pack II and competition drills

- **Objective.** Complete the pack:
  - viticulture, winemaking and tasting profiles;
  - comparisons with the world's other Pinot Noir regions;
  - blind deduction series;
  - timed map and label drills, through S1's generic modes.
- **Depends on.** P2, Q6, Q8 and S1. Label drills need Q5.
- **Modules.** Pack content files, the pack's coverage policy section.
- **Acceptance criteria.** [study-packs §3](design/study-packs.md#3-acceptance-for-the-pack-as-a-whole) in full, including that no line of code names the pack.
- **Required automated tests.** Pack coverage at full policy; a timed drill and a deduction series running on pack content.
- **Parallel.** Yes in wave 6.

### Group S: Study experience and analytics (spec Phase 6)

#### S1 · Study browser v2: atlas, search, focused and timed sessions

- **Objective.** Rework the Study tab:
  - a region tree and search;
  - an **atlas** that zooms from the world to countries, regions and appellations, showing the track's features with their memory state;
  - item details, and a glossary of label and tasting terms;
  - "practise this area or domain" (sessions limited to a subtree, audit §1);
  - session modes: focused, timed drill, and exam-style with feedback at the end.
- **Depends on.** F3 and G3. The atlas is richer after G4.
- **Modules.** `lib/features/study/`, `lib/core/study/` (focus filters on the planner), the router.
- **Acceptance criteria.**
  - A session limited to Burgundy plans only Burgundy items.
  - A timed drill records response times and ends on time.
  - Exam-style mode shows feedback only at the end.
  - The atlas is usable with a screen reader through its list view.
- **Required automated tests.** Planner focus filters; widget tests of the atlas, search and modes; the timed session ending on time (fake clock).
- **Parallel.** Yes in wave 5. It owns the router in that wave.

#### S2 · Learner analytics

- **Objective.** The analytics of spec Phase 6 and §N:
  - retention over time;
  - weakness by domain and area (lapses, low R);
  - the learner's coverage (studied against available, per area, using F1's grouping);
  - a forecast of reviews due.
- **Depends on.** F1 and F3.
- **Modules.** `lib/core/analytics/`, `lib/features/home/` or a new analytics screen, and a decision on the chart implementation (custom painter or a package, verified per the validation practice).
- **Acceptance criteria.**
  - Every metric is computed from the review log and states.
  - Charts are readable in light and dark themes and have text alternatives.
- **Required automated tests.** Metric computations on fixture logs; widget tests of the charts' text alternatives.
- **Parallel.** Yes in wave 4.

### Group R: Quality and release

#### R1 · Onboarding, settings, attributions, accessibility

- **Objective.**
  - **Onboarding:** an age confirmation (L-24), the track choice, and how spaced repetition works.
  - **Settings:** session size, new items per session, °C or °F, and a daily reminder (a local-notification plugin, verified first, or deferred with an audit note).
  - **Data:** export and import of user data as JSON, and a progress reset.
  - **Feedback:** *flag this question*, stored locally and included in the export, so content problems reach curators without telemetry.
  - **About:** the disclaimers, and every dataset's licence and attribution (GEO-14).
  - **Accessibility:** semantics, text scaling, contrast and tablet layouts.
  - **Localization readiness:** strings extracted; English only.
- **Depends on.** Nothing to start. Attributions become complete as G1, G2 and the content tasks land.
- **Modules.** `lib/features/settings/` (new), `lib/features/onboarding/` (new), the router, `lib/core/` export and import.
- **Acceptance criteria.**
  - Export followed by import round-trips every user table.
  - Every attribution in `source_citations` appears on the About screen.
  - Accessibility checks pass: `meetsGuideline` tests for tap-target size, contrast and labels.
- **Required automated tests.** Export and import round trip; widget tests with accessibility guidelines; onboarding shown once.
- **Parallel.** Yes in wave 3. It owns the router in that wave.

#### R2 · Performance and scale

- **Objective.** Build a synthetic curriculum of 5,000 items and 2,000-feature layers. Set budgets for first-launch ingestion, planner latency, practice frame times, map parsing and painting, and startup, and profile on Android and iOS.
- **Depends on.** F3 and G3.
- **Modules.** `test/perf/` or `integration_test/`, and fixes wherever the profile points.
- **Acceptance criteria.**
  - Spec Phase 6: *"Application runs smoothly on Android and iOS simulators without jank."*
  - With 5,000 items, the planner runs in under 100 ms and ingestion fits a budget recorded in the audit.
  - Large graph queries are profiled on an Android 16 KB page-size image, as spec §T asks, and the results are recorded in the architecture validation.
- **Required automated tests.** Benchmarks with recorded budgets in CI (with generous thresholds), and an integration test on the synthetic curriculum.
- **Parallel.** Yes in wave 6.

#### R3 · Release readiness and gates

- **Objective.** The V0.1 release gate:
  - **store readiness:** icons, splash screen, bundle IDs (L-10), signing configuration, versioning, privacy labels (no data collected), the age rating (L-24), and store listing text with disclaimers;
  - **release builds in CI** (AAB and unsigned IPA), with the 16 KB alignment check;
  - **coverage stage 3:** the policy thresholds enforced (COV-3);
  - **content:** at least 150 verified items (P-6);
  - **legal:** the legal review items cleared.
- **Depends on.** Every task in V0.1 scope. The product owner decides the V0.1 scope before R3 starts.
- **Modules.** `android/`, `ios/`, CI workflows, `coverage_policy.yaml`, `docs/`.
- **Acceptance criteria.**
  - CI produces release builds.
  - The coverage policy passes at stage 3.
  - The verified-item gate passes.
  - The legal review register has no open blocking item.
- **Required automated tests.** The coverage gate at full thresholds; a test counting verified items; the release build job.
- **Parallel.** No. It runs last.

---

## 6. Coverage of the requested study modes

Every mode requested for this backlog maps to tasks:

| Requested | Tasks |
|---|---|
| Simple recall; reverse recall; multiple choice | built (Phases 2–3); Q1 adds typed recall in both directions and short written answers |
| Multiple response; matching; ordering; numeric and range | Q2; Q3; Q3; Q4 |
| Label interpretation | Q5 |
| Map and geography | G1–G9 |
| Climate, viticulture and production reasoning | Q6, with principles from C5 |
| Service and food-pairing scenarios | Q7, with principles from C5 |
| Tasting deduction | Q8, with the lexicon from T1 |
| Cross-domain reasoning | Q9 |
| Tap the country, region, subregion or appellation; identify a highlighted region | G4 |
| Hierarchy drills | G5 |
| Grape → regions; region → grapes; neighbours | G8 |
| Rivers and bodies of water; mountain ranges and barriers; climate influences | G6 |
| Slope, aspect, elevation; soils and geology | G7 |
| Map-based deduction | G9 |
| Blank-map and minimal-label progression; zooming by relevance | G4 modes, F4 ladder, G3 semantic zoom, S1 atlas |
| One memory for map and text | GEO-1, tested in G4, G6 and P2 |
| Coverage matrix and checker, enforceable | F1 (report and ratchet); every Q and G task (capabilities); R3 (release gate) |
| Spätburgunder mastery and competition pack | P1–P3, built only from generic features |

---

## 7. Product-area review

The backlog was reviewed against the specification (§A–§T), the decision register and a sommelier's study needs. The review found these gaps, now covered:

| Area | Found | Now in |
|---|---|---|
| Business domain (wine lists, pricing, cellar management) | The domain exists but has no items | C5 |
| Wine faults | Absent, but essential for service and tasting | C5, Q7 |
| Spirits, beer and sake basics | Needed for the CMS tracks' breadth | C5 |
| Age gate and age rating | Alcohol-related apps need a store age rating | R1, R3, L-24 |
| Units (°C and °F) | Service temperatures for US candidates | Q4, R1 |
| Accessible alternatives for maps and drag-and-drop | Map taps and reordering exclude screen-reader users | G3, G4, Q3, R1 |
| Attribution of open data | Licence Ouverte, dl-de/by and CC BY require it | G1, R1 (GEO-14) |
| Verification workflow | P-6 needs 150 verified items, but no process existed | C1, R3 |
| Parallel content authoring | One YAML file would serialize every content task | C1 (DL-4) |
| Subtree study ("practise Burgundy") | The audit decided it; nothing built it | S1 |
| Exam and competition practice | Timed and exam-style modes | S1, P3 |
| Short written answers | WSET Level 3 includes them; spec §T plans self-evaluation against a rubric | Q1 |
| SQL performance on 16 KB page devices | Spec §T asks for profiling before V1.0 | R2 |
| Content feedback | Learners had no way to report a wrong question offline | R1 |
| Glossary | Label and tasting terms had no reference view | S1 |

**Deliberately deferred** (recorded so they are not forgotten):

| Area | Reason |
|---|---|
| Over-the-air curriculum updates | V-8 |
| Cloud sync and accounts | §N |
| Label scanning (OCR) | §K, D6 |
| AI tutors and graded essays | §N; no paid APIs in V0.1 |
| Desktop apps | D5 |
| Offline web app shell (service worker) | validation F-2 |
| Pronunciation audio | Useful for service; needs recorded audio or offline speech |
| Producer and vintage knowledge | Volatile, and raises trademark questions |
| Several learner profiles | V0.1 is a single-learner app; `user_profiles` has one row by design (CM-9) |
| Studying several tracks at once | PK-3 |
| More selectable tracks (WSET Levels 2 and 4; CMS Introductory and Advanced) | Mapping and content work after V0.1 (CM-1) |
| Streaks, goals and other motivation features | Product decision |
| Automated ingestion of legal-text updates | Spec §T; curators update releases by hand (V-7, V-8) |
| Images of grapes and leaves | No licensed images |

**Open product question.** The business model (free, paid or subscription) is not in the specification. It affects R3 (store listing, in-app purchases) and should be decided before release.
