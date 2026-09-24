# Architecture Validation — Sommelier Study App (V0.1)

| | |
|---|---|
| **Date** | 2026-09-24 |
| **Inputs** | *Sommelier App Product Specification*; [Phase 0 engineering audit](../audit/phase-0-engineering-audit.md) |
| **Rule applied** | Keep the product design unless there is a concrete technical reason to change it. Every change below cites its reason and the evidence for it. |

## Method

Package compatibility was **tested, not inferred**. A throwaway spike project was built on the current stable toolchain:

- **Toolchain**: Flutter **3.47.5** / Dart **3.13.4** (stable, 2026-09-18), SHA-256 verified.
- **Dependencies**: the proposed set resolved together at the latest versions (§2).
- **Code generation**: Drift code was generated with `build_runner`.
- **Tests**: `flutter analyze` reported no issues and `flutter test` passed **21/21**. These tests cover the schema, FSRS, question generation, Riverpod wiring and navigation.
- **Negative controls**: two controls showed the tests fail when the configuration they depend on is removed (§3.2).
- **Web**: a release Web build ran in headless Chromium against the real Drift web database, with and without COOP/COEP headers (§3.2, W-1).

The spike is deliberately **not committed**, so it cannot collide with the Phase 0 scaffold. The configuration it proved is reproduced inline, and its tests are the starting point for Phase 0.

---

## 1. Verdicts

| # | Area | Verdict | Why |
|---|---|---|---|
| 1 | Flutter architecture | **Keep, pin versions** | Flutter, Material 3, the five-tab shell and offline-first all work. The spec's "3.29+" floor cannot run current Riverpod. The Web target needs extra runtime setup. |
| 2 | Drift / SQLite data layer | **Keep** | Every graph pattern the spec needs works on native and Web. Four configuration details are mandatory (D-1…D-4). |
| 3 | Riverpod state management | **Keep, configure** | Riverpod 3.4.3 works with Drift's reactive queries. Its default automatic retry must be turned off for local failures (R-2). |
| 4 | Canonical Node / Relation / Item model | **Keep, tighten** | The hybrid relational graph is sound. It needs integrity constraints and a relation registry, and the spec's names need unifying. |
| 5 | FSRS integration | **Keep the concept, change the version** | Tracking memory per knowledge item with the pure-Dart `fsrs` package stays. The package implements FSRS-6, and the spec's formulas are wrong (audit §4). |
| 6 | Adaptive study architecture | **Keep the concept, change the formula** | A composite priority score over urgency, relevance, lapses and prerequisites stays. The published formula cannot rank as intended (audit §5). |
| 7 | Deterministic question generation | **Keep** | Graph-derived distractors with seeded ordering were demonstrated end to end. |
| 8 | Certification profiles | **Keep, add inheritance** | Certifications as a lens over one canonical graph stays. Tracks must be cumulative. |
| 9 | Tasting session model | **Keep, data-driven grids** | Two separate engines (SAT and DTM) stay. Grid vocabularies become versioned data so the database enforces "SAT terms only". |
| 10 | Wine journal model | **Keep, add the missing link** | The journal stays. A junction table and a journal term in the priority score make the spec's "influences the queue" requirement implementable. |

Nothing in the product design is dropped. The changes fall into three groups:

- mathematical corrections (FSRS, the priority score)
- configuration that the platform requires
- constraints that turn the spec's validation rules into database guarantees

---

## 2. Compatibility matrix (resolved on Flutter 3.47.5 / Dart 3.13.4)

| Package | Resolved | Role | Notes |
|---|---|---|---|
| `flutter_riverpod` / `riverpod` | 3.4.3 | State and dependency injection | Needs Dart ≥ 3.12, so **Flutter ≥ 3.44**. This alone rules out the spec's "3.29+" floor. |
| `drift` / `drift_dev` | 2.35.0 | Relational data layer | Needs Dart ≥ 3.10. |
| `drift_flutter` | 0.3.1 | Opens the database on each platform | Replaces hand-written setup. |
| `sqlite3` | 3.6.0 | SQLite engine | Bundles **SQLite 3.53.4** through Dart build hooks, on native and on Web (WASM). |
| `sqlite3_flutter_libs` | — | **Do not add** | 0.6.0+eol is an empty package that `sqlite3` 3.x replaces. |
| `fsrs` | 2.0.1 | Scheduler | FSRS-6. MIT-licensed, a single file, last released 2025-06. |
| `build_runner` | 2.16.1 | Code generation | Now ignores `--delete-conflicting-outputs`. |
| `go_router` | 18.0.1 | Navigation | Needs Flutter ≥ 3.44. |
| `yaml` | 3.1.4 | Seed parsing (Phase 1) | |
| `clock` | 1.1.3 | Injectable time for tests | |
| `riverpod_generator` | 4.0.9 *(dry run)* | Optional code generation | Resolves alongside `drift_dev`, but pulls in a pre-release dependency, `riverpod_analyzer_utils 1.0.0-dev.12` (R-1). |
| `fl_chart` | 1.2.0 *(dry run)* | Analytics charts (Phase 6) | Resolves. |
| `image_picker` | 1.2.3 *(dry run)* | Journal photos (if D6 changes) | Resolves on all five platforms. |
| `fsrs-rs-dart` | — | **Not for V0.1** | Adds a Rust toolchain and FFI. Its advantage, the weight optimizer, is deferred by §F anyway. |
| `isar` | — | Rejected, as the spec says | Last published 2023 and constrains the SDK to `<3.0.0`. |

**Pin**: Flutter **3.47.5** in CI and in the cloud-session setup. Set `environment: sdk: ^3.13.0` in `pubspec.yaml`.

---

## 3. Area-by-area validation

### 3.1 Flutter architecture

**Kept**
- Flutter for all five targets
- Material 3
- five-tab bottom navigation: Home, Study, Practice, Tasting, Cellar
- offline-first

**Validated** in a widget test: `go_router`'s `StatefulShellRoute.indexedStack` with a Material 3 `NavigationBar` switches between all five modules. The `indexedStack` variant is designed to keep each tab's navigation stack alive; the test did not check that. The spec does not name a router; `go_router` is the Flutter team's package.

**Layering (proposed)**, with dependencies pointing downward only:

```
presentation   widgets, screens, Stepper forms              (flutter)
application    Riverpod providers / Notifiers                (flutter_riverpod)
domain         pure Dart: scheduler adapter, priority scorer,
               question generator, grid definitions          (no Flutter imports)
data           Drift tables, DAOs, repositories, seed ingestion
```

Code is organized by feature: `lib/features/{home,study,practice,tasting,cellar}`, plus `lib/core/{db,fsrs,…}`. Keeping the domain layer free of Flutter lets the FSRS, priority and question logic run under plain `dart test`.

| ID | Finding (evidence) | Change |
|---|---|---|
| F-1 | The spec's "Flutter 3.29+" cannot resolve current Riverpod or Drift (§2). | Pin 3.47.5; the floor is 3.44. |
| F-2 | **Web is not offline-first by default.** By default a Flutter web build fetches its CanvasKit renderer from `gstatic.com` at startup. The probe failed with *"Failed to fetch … canvaskit.js"* until it was rebuilt with `--no-web-resources-cdn`. | Build Web with `--no-web-resources-cdn`. Treat full offline support on Web (caching the app shell) as work for after V0.1. |

### 3.2 Drift / SQLite data layer

**Kept**
- Drift over SQLite
- immutable canonical tables kept separate from mutable user tables
- junction tables standing in for graph edges
- SQL JOINs and recursive queries for traversal

**Validated** (spike tests pass on native; the Web probe passes in Chromium):

| Capability the spec needs | Result |
|---|---|
| "Robust foreign key constraints" (TASK-001) | Enforced, **only** with `PRAGMA foreign_keys = ON` in `beforeOpen`. Negative control: with the pragma off, a dangling edge is accepted. |
| No dangling edges (§S.1) | Edge → node FKs reject unknown nodes. |
| An item must assert an existing edge (audit DM-4) | A composite FK from `(subject_id, relation, object_id)` onto `UNIQUE(...)` on `knowledge_edges` rejects an item whose triple is not an edge. |
| DAG integrity (§S.2) | A `CHECK` rejects self-prerequisites. A recursive CTE finds cycles of **any length**: the test found A→B→A. |
| Graph traversal (Phase 1) | A recursive CTE returns transitive `LOCATED_IN` ancestors, nearest first (Chablis → Burgundy → France). |
| Curriculum updates must not destroy history (audit DM-5) | Re-ingesting with an upsert (`ON CONFLICT DO UPDATE`) changes the item text and keeps the user's `review_state` row. |
| FSRS timestamps in UTC | Round-trip exactly **only** with `store_date_time_values_as_text: true`. Negative control: with Drift's default storage the value comes back non-UTC. |
| Web runtime | In Chromium the release build opens the database: SQLite 3.53.4 (WASM), `foreign_keys = 1`, reads and writes succeed. |
| SQL maths (`pow`) | Available on native **and** on Web with the official `sqlite3.wasm`, although Drift's typed helpers are documented as native-only. Not relied upon (A-6). |

**Required configuration**. None of this is optional; each item is backed by a failing control or a generator warning:

| ID | Requirement |
|---|---|
| D-1 | `beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON')` |
| D-2 | `build.yaml` → `drift_dev: options: store_date_time_values_as_text: true` |
| D-3 | `@ReferenceName(...)` on each column when a table has two FKs to the same table (edge subject/object → node; prerequisite item/prerequisite → item). Without it, drift_dev warns and **silently omits** the generated manager filters for those references. |
| D-4 | Write `CHECK` constraints as table-level `customConstraints`. Drift's documented self-referencing `integer().check(col…)` pattern triggers the current lint set's `recursive_getters`. |
| D-5 | Snapshot the schema from v1 (`drift_dev make-migrations`) so migrations are tested from the first release. |

| ID | Finding | Change |
|---|---|---|
| W-1 | Web needs `sqlite3.wasm` (from the `sqlite3` 3.6.0 release) and `drift_worker.js` (from the `drift` 2.35.0 release) in `web/`. The versions must match the resolved packages. | Fetch and checksum them in the Phase 0 scaffold. Add a CI check that their versions match `pubspec.lock`. |
| W-2 | Without COOP/COEP headers, Chromium offers only IndexedDB-backed storage (`sharedIndexedDb`, `unsafeIndexedDb`). With `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: require-corp`, OPFS (`opfsLocks`) also becomes available. | Serve Web with COOP/COEP where hosting allows. IndexedDB is an acceptable fallback. |

### 3.3 Riverpod state management

**Kept**: `flutter_riverpod` for dependency injection and reactive UI.

**Validated**: a `StreamProvider` built on a Drift `watch()` query emitted `[0, 1]` across an insert. Drift is the source of truth, and Riverpod exposes its streams. The database is injected by overriding a `databaseProvider` at startup (`openAppDatabase()`) and in tests (an in-memory `NativeDatabase`), using `ProviderContainer.test`.

| ID | Finding (evidence) | Change |
|---|---|---|
| R-1 | `riverpod_generator` co-resolves with `drift_dev`, so there is no version conflict. It does add a second code generator and a pre-release transitive dependency. | Use **hand-written providers** (`Provider`, `StreamProvider`, `Notifier`, `AsyncNotifier`) in V0.1. Revisit if the provider count grows. |
| R-2 | **Riverpod 3 retries failing providers automatically**: up to 10 attempts, with a delay growing from 0.2 s to 6.4 s. It retries every `Exception` and never an `Error`. `SqliteException` is an `Exception`, so a failed migration or seed ingestion would be retried silently for about 38 s (0.2 + 0.4 + 0.8 + 1.6 + 3.2 + 5 × 6.4). The test showed repeated builds by default and exactly one with `retry: (_, _) => null`. | `ProviderScope(retry: (_, _) => null)` at the root. Local failures are deterministic and should be shown, not retried. |
| R-3 | `StateProvider` and `StateNotifierProvider` now live in `legacy.dart`. Offline persistence and mutations are experimental. | Don't use the legacy or experimental APIs. Drift already persists everything. |

### 3.4 Canonical knowledge model (§C–§E)

**Kept**
- Nodes are concepts.
- Edges are typed relations between nodes.
- Items are atomic, testable assertions over one edge, with provenance.
- Certifications reference items; they do not duplicate them.

The spike schema implements this with the constraints above.

| ID | Change | Reason |
|---|---|---|
| K-1 | Use one name per concept. Tables: `knowledge_node`, `knowledge_edge`; the edge's type column is `relation`. The spec's `KnowledgeRelation` and `KnowledgeEdge` refer to the same table. | The spec uses both names for one entity (audit DM-1). |
| K-2 | Stable TEXT primary keys (`n_<type>_<slug>`, `ki_<slug>`). User tables reference them by string. The canonical data is never hard-deleted; `valid_until` retires rows. | Re-ingestion must not break user foreign keys (validated upsert). |
| K-3 | A composite FK from item to edge; `UNIQUE(subject, relation, object)` on edges. | Makes "item asserts an existing edge" a database guarantee (validated). |
| K-4 | A relation registry (subject and object types, cardinality, transitivity, inverse label) and node attributes (e.g. grape colour). | §H's distractors ("other **black** grapes") and 1:N relations cannot work without them (audit DM-6, QE-1). |
| K-5 | Prerequisites link **items**, never nodes. | §G's prose mixes the two up (audit ENG-5). |

### 3.5 FSRS integration (§F)

**Kept**
- memory state per knowledge item, not per card or question format
- a four-point grade
- an append-only review log
- the pure-Dart `fsrs` package

**Validated**
- `fsrs` 2.0.1 is FSRS-6: 21 weights, and states 1 to 3 only.
- A card saved to `review_state` columns and read back schedules **identically** to the in-memory card: same stability, difficulty and due date.
- Fuzzed scheduling is reproducible with `Scheduler.customRandom(Random(seed))`.
- `reviewCard` rejects non-UTC timestamps.
- A never-reviewed card reports R = 0.

| ID | Change | Reason |
|---|---|---|
| S-1 | Use FSRS-6 exactly as implemented by the package. The §F equations are illustrative only, and all FSRS maths goes through the package. | §F cannot be satisfied (it mixes FSRS 4.5, 6 and v3), and its recall formula overshoots by up to ~10⁷× (audit FSRS-1/2). |
| S-2 | `review_state` columns: `state` (1–3, CHECK), `step`, `stability`, `difficulty`, `due`, `last_review`, plus app-maintained `reps` and `lapses`. No row means New. Retrievability is computed, never stored. | Matches the package's `Card` model (validated round trip). The package tracks no lapses. |
| S-3 | `review_event` records the grade, `format`, `response_ms`, `elapsed_days`, the template and seed, and the before/after state. | Makes the review log replayable if the weights are later optimized. |
| S-4 | `Card.cardId` is an `int` that the scheduler never reads. Pass any value; identity lives in `item_id`. | Validated round trip. |
| S-5 | Inject time (`clock`) and randomness everywhere. Keep the package's defaults (learning steps of 1 and 10 minutes, fuzzing on) and re-queue learning-step items within the session. | Deterministic tests; §F does not cover sessions. |

### 3.6 Adaptive study architecture (§G)

**Kept**
- a composite priority built from urgency (U), certification relevance (C), lapse history (L) and prerequisite repair (P)
- recursive prerequisite traversal
- a top-N session, 15 items per TASK-005

| ID | Change | Reason |
|---|---|---|
| A-1 | `score = U^αU · C^αC · L^αL · P^αP · J^αJ` | With the spec's `(W·U)×(W·C)×…` product, **no weight can change the ranking** (audit ENG-1, demonstrated). |
| A-2 | Due reviews are ranked by score. New items come from a separate per-session budget, ordered core first, prerequisites first. | Otherwise new items (R = 0, so U = 1) outrank due reviews tenfold (audit ENG-2; R = 0 confirmed in the package). |
| A-3 | `L = 1 + λ·lapses`. `C`: core 1.0 / secondary 0.5 / tertiary 0.25. Items with no mapping to the active track are filtered out. | Any zero factor wipes out a product (audit ENG-4). |
| A-4 | `P_i = 1 + β·max over transitive dependents j of γ^depth·(1 − R_j)`. Boost only, no gating. | P is undefined in the spec (audit ENG-5). |
| A-5 | `J = 1 + η·e^(−days/τ)` for items touching journal-linked nodes. | The Phase 5 acceptance criterion needs this term (audit ENG-7). |
| A-6 | SQL selects the candidates (reviewed items due within a horizon, filtered by track). Dart computes R and the score. | Correction to the audit: SQL `pow()` **does** work on native and Web (§3.2), so this is not a platform limit. The reason is one source of truth: R must come from the same package that schedules, rather than being re-implemented in SQL. The scorer is pure Dart and unit-testable. |

### 3.7 Deterministic question generation (§H)

**Kept**
- natural-language templates over the graph
- Simple Recall, Reverse Recall and MCQ in V0.1
- distractors taken from the graph (no LLM)
- no proprietary question text

**Validated** on a 15-node test graph:

- The same seed gives the same question. 20 seeds gave more than one ordering.
- There are always 4 distinct options, including the answer.
- The candidate scope widens from Burgundy (1 candidate) to France when fewer than 3 distractors exist.
- For Bourgogne, which permits both Chardonnay and Pinot Noir, **Pinot Noir is never offered as a wrong answer** across 25 seeds.

| ID | Change | Reason |
|---|---|---|
| Q-1 | Distractor search: walk up from the subject's geographic scope and widen until 3 candidates exist (region → country → the whole type). Filter by the answer's node type and attributes. Exclude every object the subject holds for the tested relation, and duplicate display names. | The spec gives two different algorithms (§H vs TASK-004). This one works (validated) and handles grapes, which have no parent node. |
| Q-2 | Templates per relation type and direction. | A single generic template cannot phrase every relation (audit QE-3). |
| Q-3 | "Deterministic" means the same seed gives the same question, not the same answer position every time. Log the seed on `review_event`. | Reproducible tests without users memorizing positions. |

The closed-world risk remains: a missing edge does not make a statement false (audit SEED-3). That is a content-curation problem, not an architecture one.

### 3.8 Certification profiles (§B, §N)

**Kept**
- Certifications change what is studied and how deep, not the data itself.
- An item-to-certification junction carries `importance` and `minimum_depth`.
- V0.1 offers `WSET_L3` and `CMS_CERTIFIED`.

| ID | Change | Reason |
|---|---|---|
| C-1 | A self-referencing `certification.includes_id` (L3 → L2 → L1; Certified → Introductory). Relevance resolves through the chain. | The seed tags `ki_chablis_grape` for `WSET_L2`, so a WSET L3 candidate would never see it (audit ENG-8). |
| C-2 | The active profile lives in a one-row `user_profile` table, not in preferences. | It drives SQL filtering and must be transactional with study state. |
| C-3 | Exam-simulator configuration stays out of V0.1. | Deferred by §N. |

### 3.9 Tasting session model (§I)

**Kept**
- two separate engines, WSET SAT and CMS DTM, which never mix vocabularies
- a stepped form (the Material `Stepper`, as TASK-008 specifies)
- a tasting session with many descriptors

| ID | Change | Reason |
|---|---|---|
| T-1 | Grids become **versioned data**: `grid(framework, version)` → `grid_attribute(section, key, order)` → `grid_value(attribute, key, ordinal)`. Descriptors are stored as `(session_id, attribute_key, value_key)`, with a composite FK onto the session's grid values. | TASK-008's "only WSET terminology in SAT mode" becomes a **database guarantee**, using the same composite-FK pattern validated for item → edge. The UI is generated from the same data, so SAT and DTM share one form engine. Grid versions allow for the L3 vs L4 SAT differences. |
| T-2 | Fixed scales per attribute (e.g. sweetness uses dry … luscious). | §I's single "low … high" scale is inaccurate (audit TAST-1). |
| T-3 | V0.1 captures tastings but does not score them. | No answer key exists in scope. |

The grid vocabulary depends on the legal review in audit D10. The schema does not.

### 3.10 Wine journal model (§J)

**Kept**
- manual entry in V0.1
- producer, cuvée, vintage, appellation, grapes, ABV and notes
- linking to canonical nodes, and through them influencing study priority

| ID | Change | Reason |
|---|---|---|
| J-1 | A `journal_entry_node(entry_id, node_id, role)` junction (roles: appellation, region, grape…). The raw text entered is kept alongside. | One entry has several grapes. The spec gives single foreign keys. |
| J-2 | Linking uses typeahead pickers bound to nodes, backed by a normalized `node_alias` table (case, diacritics, AOC/DOCG suffixes). Fuzzy matching is deferred. | Deterministic matching (audit JRNL-2). |
| J-3 | The priority influence goes through the `J` term (A-5). | Phase 5's acceptance criterion needs it. |
| J-4 | A nullable `photo_path` column exists from v1, with no capture UI unless D6 changes. `image_picker` 1.2.3 resolves on all targets. | Avoids a schema migration later, as §K asks. |
| J-5 | Episodic flashcards are deferred. | They need review state for user-created items, and V0.1 scope does not include them. |

---

## 4. Changes to the specification, with reasons

| Spec element | Change | Concrete reason (evidence) |
|---|---|---|
| Flutter 3.29+ | Pin 3.47.5 (floor 3.44) | Current Riverpod and Drift will not resolve below it (§2). |
| FSRS 4.5/5.0 and §F formulas | FSRS-6 through `fsrs` 2.0.1; formulas non-normative | The formulas cannot be satisfied and overshoot by up to ~10⁷× (audit §4); the package is FSRS-6. |
| `fsrs_state` with `0: New`; stored R | `review_state` without New or stored R | The package has no New state; R depends on the current time (validated round trip). |
| `Score = Π(W·x)` | Weighted geometric score, new-item budget, `J` term | The weights cannot change the ranking (demonstrated); cold start; Phase 5 (audit §5). |
| Priority computed "in a SQL query" | Candidates in SQL, score in Dart | One source of truth for R (A-6). This is **not** a platform limit. |
| Two distractor algorithms | One: widening scope with exclusions | Validated. Grapes have no parent node. |
| Fixed certification tracks | Cumulative tracks | The seed's WSET_L2 items would be invisible to L3 candidates. |
| Hard-coded tasting vocabularies | Versioned grid data with FK enforcement | Makes TASK-008's rule a database guarantee. |
| Single journal FKs | A junction with roles, plus a `J` term | Several grapes per entry; Phase 5. |
| (implicit) `sqlite3_flutter_libs` | Removed | End of life. |

**Unchanged**:

- offline-first
- Drift over Isar
- Riverpod
- Material 3 and the five-tab shell
- the canonical graph of nodes, edges and items
- per-item FSRS memory state
- the adaptive priority concept
- deterministic, template-based questions with graph distractors and no proprietary text
- certification-as-lens
- separate SAT and DTM tasting engines
- the journal linked into study priority
- the V0.1 scope and deferrals in §N

---

## Appendix — Configuration proven by the spike

```yaml
# pubspec.yaml (excerpt)
environment:
  sdk: ^3.13.0
dependencies:
  flutter_riverpod: ^3.4.3
  drift: ^2.35.0
  drift_flutter: ^0.3.1
  fsrs: ^2.0.1
  yaml: ^3.1.4
  clock: ^1.1.3
  go_router: ^18.0.1
dev_dependencies:
  drift_dev: ^2.35.0
  build_runner: ^2.16.1
```

```yaml
# build.yaml
targets:
  $default:
    builders:
      drift_dev:
        options:
          store_date_time_values_as_text: true
```

```dart
// Mandatory connection and database setup
AppDatabase openAppDatabase() => AppDatabase(driftDatabase(
      name: 'sommelier',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    ));

@override
MigrationStrategy get migration => MigrationStrategy(
      beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
    );

// Item must assert an existing edge (composite FK onto UNIQUE(subject_id, relation, object_id))
@override
List<String> get customConstraints => [
      'FOREIGN KEY (subject_id, relation, object_id) '
          'REFERENCES knowledge_edges (subject_id, relation, object_id)',
    ];

// Root scope: show local failures instead of retrying them
runApp(ProviderScope(
  retry: (_, _) => null,
  overrides: [databaseProvider.overrideWithValue(openAppDatabase())],
  child: const SommelierApp(),
));
```

**Spike test inventory**: 21 tests, all passing. Negative controls are marked †.

| File | Tests |
|---|---|
| `schema_test` (9) | FK enforcement† · item → edge composite FK · CHECK constraints (self-prerequisite, depth) · cycle detection of any length · transitive ancestors · UTC millisecond round trip† · `state` in 1–3 · native `pow` · upsert re-ingestion keeps user state |
| `fsrs_test` (5) | FSRS-6 shape · R = 0 when never reviewed · UTC enforced · database round trip schedules identically · seeded fuzz is reproducible |
| `question_test` (3) | seeded determinism with 4 distinct options · scope widening · no correct answer offered as a distractor |
| `riverpod_test` (3) | Drift stream → `StreamProvider` · default retry of Exceptions · retry disabled |
| `widget_test` (1) | Material 3 five-tab `go_router` shell |
| Web probe | Chromium, with and without COOP/COEP: `DB_OK sqlite=3.53.4 fk=1 rows=1 pow=1024` |

† Also run with the relevant configuration removed: FKs off, and Drift's default DateTime storage. Both failed as expected.
