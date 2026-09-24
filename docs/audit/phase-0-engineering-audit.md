# Phase 0 Engineering Audit — Sommelier Study App

| | |
|---|---|
| **Date** | 2026-09-24 |
| **Specification** | *Sommelier App Product Specification* (21 pages, PDF). Not committed: this repository is public. |
| **Repository** | `Xaiando/Mobile` at `728fc3f` ("Initialize repository") |
| **Status** | Audit only. No application code was written. |

> **Note (2026-09-24):** entity names and schema details in this document predate the [canonical domain model](../domain-model.md), which wins where they differ (for example `knowledge_edges` became `knowledge_relations`).

## How this audit was done

- All 21 pages were extracted, including tables. Every equation and inline math symbol in §F–§G is an image in the PDF, so a text extractor drops them. They were read and transcribed by hand (§4.1).
- Ecosystem claims were checked against pub.dev and the Flutter release feed on 2026-09-24. Where FSRS behaviour matters, it was checked against the published source of `fsrs` 2.0.1.
- Numerical results in §4 and §5 come from the package's default weights. The script is in Appendix A.
- Section references (§A–§T) use the specification's own lettering.

Severity levels:

- **Blocker**: produces wrong behaviour or makes an acceptance criterion unsatisfiable. Resolve it before the phase that depends on it.
- **High**: must be decided before its phase starts.
- **Medium / Low**: can be fixed while implementing.

---

## 1. Verdict

The architecture direction is sound:

- offline-first
- relational SQLite through Drift, not Isar
- immutable canonical curriculum kept separate from mutable user state
- memory state tracked per knowledge item
- questions generated from templates over a graph
- an explicit IP stance

The specification is **not implementation-ready as written**. Three problems would produce wrong software if implemented literally:

1. **The FSRS mathematics in §F is wrong and self-contradictory** (§4). The text says FSRS 4.5/5.0, but the retrievability formula uses FSRS-6's `w20`. The recall-stability formula matches no FSRS version.
   - With the recommended package's defaults, a medium-difficulty item rated *Good* at 3 days' stability gets a next interval of **~145,000 days**. Correct FSRS-6 gives **10.8 days**.
   - The formula also gives the same result for Hard, Good and Easy.
2. **The priority score in §G cannot express its intended balance** (§5).
   - The weights `W_U…W_P` multiply a pure product, so no weight value can ever change the ranking.
   - Never-reviewed items get maximum urgency and would crowd out due reviews.
   - The score has no term through which the wine journal could raise priority, so the Phase 5 acceptance criterion cannot be met.
3. **The seed dataset fails the specification's own acceptance tests** (§7).
   - It has 8 nodes and 5 edges; TASK-002 requires 50 and 50.
   - No knowledge item has the three distractors that §S.3 and Phase 2 require.
   - The JSON Schema in §E would reject it.
   - Curriculum *content* is on the critical path, but no backlog task covers authoring it.

None of these block the **Phase 0 scaffold** (project, Drift schema, CRUD tests). They do block Phases 1–5. §13 proposes a Phase 0 scope that avoids the unresolved areas. §14 lists the decisions needed, each with a recommended default.

---

## 2. Repository and environment

| ID | Finding | Impact |
|---|---|---|
| ENV-1 | The repository has one commit containing only `.gitkeep`. There is no Flutter project, README, LICENSE, `.gitignore`, CI, `CLAUDE.md`, or PR template. | Greenfield. Every convention is still open (§13). |
| ENV-2 | The repository is **public**. | Anything pushed is published, including curriculum content and this audit. The specification PDF was deliberately not committed. A LICENSE decision is needed before content lands (D8). |
| ENV-3 | The cloud session has **no Flutter or Dart SDK**. It has OpenJDK 21, gcc/clang, and Chromium, but no Android SDK and no Xcode (Linux host). | Phase 0's acceptance test (`flutter test`) cannot run until an SDK is installed. pub.dev and the Flutter release bucket are reachable, so a pinned SDK can be installed each session. A SessionStart hook or environment setup script is recommended. |
| ENV-4 | iOS, macOS and Windows builds are impossible in this environment. Android builds need the Android SDK installed. | Phase 6 acceptance ("runs on Android and iOS simulators") needs CI with a macOS runner, or local verification. |
| ENV-5 | `sqlite3` 3.x build hooks download prebuilt SQLite binaries from GitHub releases at build time. The hashes are pinned in the package. | Every build machine needs network access to GitHub release assets. Check this during Phase 0 in both the cloud session and CI. |

---

## 3. Specification versus the current ecosystem (checked 2026-09-24)

| ID | Spec says | Current reality | Action |
|---|---|---|---|
| ECO-1 | "Flutter v3.29+" (§M) | Current stable is **3.47.5 (Dart 3.13.4, 2026-09-18)**. Flutter 3.29 shipped Dart 3.7 (Feb 2025). Current `flutter_riverpod` 3.4.3 needs Dart ≥ 3.12, which first shipped with Flutter 3.44. `drift` 2.35.0 needs Dart ≥ 3.10 (Flutter 3.38). | Pin **Flutter 3.47.x**. The effective floor is 3.44. |
| ECO-2 | Drift (§M) | `drift` / `drift_dev` 2.35.0, `drift_flutter` 0.3.1, `build_runner` 2.16.1. | Adopt as specified. |
| ECO-3 | *(implicit: most Drift guides add `sqlite3_flutter_libs`)* | `sqlite3_flutter_libs` is **0.6.0+eol**, an empty package. `sqlite3` 3.x bundles SQLite through Dart build hooks. | Do **not** add `sqlite3_flutter_libs`. Open the database with `drift_flutter`. |
| ECO-4 | "`fsrs` pure Dart package or `fsrs-rs-dart` Rust FFI" (§F) | `fsrs` 2.0.1 (2025-06-20) implements **FSRS-6** with 21 weights. It is a port of py-fsrs, MIT-licensed, a single 1,062-line file. Behaviour that affects the design: <ul><li>states are Learning/Review/Relearning only, with **no New state**</li><li>`cardId` is an `int`</li><li>UTC only</li><li>fuzzing is on by default</li><li>learning steps are 1 min and 10 min</li><li>`getCardRetrievability` returns **0** for a never-reviewed card</li><li>the card does **not** track `reps` or `lapses`</li></ul> | Use `fsrs` 2.0.1. Skip `fsrs-rs-dart` for V0.1: it adds a Rust toolchain, and FFI complicates the Web target. Its only V0.1-relevant advantage is the weight optimizer, which §F defers. The package is small, so vendoring it is a cheap fallback if it goes unmaintained. |
| ECO-5 | Riverpod (§M) | `flutter_riverpod` / `riverpod` 3.4.3; `riverpod_generator` 4.0.9. | Use Riverpod 3. See D9 on code generation. |
| ECO-6 | Isar is abandoned (§M) | Confirmed: `isar` 3.1.0+1 was last published 2023-04-25 and constrains the SDK to `<3.0.0`. | Decision stands. |
| ECO-7 | Web is a target (§M) | Drift on web needs `sqlite3.wasm` and `drift_worker.js` in `web/`. Drift documents its SQL math helpers (`sqlPow` etc.) as *"only available in a NativeDatabase"*. **Correction:** in Chromium with the official `sqlite3.wasm` 3.6.0, SQL `pow()` does work on Web ([architecture validation §3.2](../architecture/architecture-validation.md)). The native binaries also enable `SQLITE_ENABLE_MATH_FUNCTIONS`. | Keep FSRS and priority maths **in Dart**, not SQL (ENG-6). The reason is a single source of truth, not a platform limit. Web support needs build-time asset setup. |
| ECO-8 | Open question: "16K page size… profile massive SQL JOINs" (§T) | Google Play's 16 KB page-size requirement is about **ELF alignment of bundled native libraries**. SQLite's database `page_size` is a separate setting and does not change JOIN performance. | Add a release-build check that bundled `.so` files are 16 KB-aligned. Treat JOIN profiling as normal performance work. |

---

## 4. Spaced repetition (§F)

### 4.1 Transcription of §F (source: images in the PDF)

- Retrievability: `R(t,S) = (1 + factor · t/S)^(−w20)`, where `t` is the time elapsed since the last review.
- Successful review (`Grade ≥ 2`) uses stability multiplier `S_inc`:
  `S′r(D,S,R) = S · ( e^(w6·(11−D)) · S^(w7) · ( e^(w8·(1−R)) − 1 ) + 1 )`
- "The weights (`w0` through `w20`) are initialized using the official FSRS-4.5 default parameters."
- Lapse (`Grade = 1`): stability is sharply reduced to `S′f`. No formula is given.

### 4.2 Findings

| ID | Sev. | Finding |
|---|---|---|
| FSRS-1 | Blocker | **The version cannot be satisfied as written.** <ul><li>The text says "FSRS 4.5 or 5.0" initialized with the "FSRS-4.5 default parameters".</li><li>FSRS-4.5 has 17 weights (`w0–w16`) and FSRS-5 has 19 (`w0–w18`). Both use a fixed decay of −0.5 and factor 19/81.</li><li>Weights `w0–w20` and a decay of `−w20` exist only in **FSRS-6**, so the §F retrievability formula cannot be evaluated with FSRS-4.5 parameters.</li><li>`factor` is also undefined. In FSRS-6 it is `0.9^(1/decay) − 1`, which makes `R(S,S) = 0.9`.</li></ul> **Recommendation:** adopt FSRS-6 as implemented by `fsrs` 2.0.1 (D1). |
| FSRS-2 | Blocker | **The recall-stability formula is wrong.** FSRS-6, as implemented in `fsrs` 2.0.1, is `S′r = S · (1 + e^(w8) · (11−D) · S^(−w9) · (e^(w10·(1−R)) − 1) · HardPenalty(w15) · EasyBonus(w16))`. The spec's version differs in four ways: <ol><li>`(11−D)` is inside the exponent, so it is exponential instead of linear.</li><li>`S^(+w7)` replaces `S^(−w9)`, so growth speeds up for well-established memories. The spec's own prose says it should slow down.</li><li>It uses `w6–w8`, which in FSRS ≥ 4 are *difficulty* parameters. The layout resembles the older FSRS v3 formula.</li><li>It drops the Hard penalty and Easy bonus, so Hard, Good and Easy give identical stability.</li></ol> The impact is measured in the table below. **Recommendation:** treat the §F equations as non-normative and never hand-code them. All FSRS maths goes through the package, pinned by golden-value tests. |
| FSRS-3 | High | **The `fsrs_state` schema (§E) does not match the package.** <ul><li>State `0: New` does not exist in the package.</li><li>`difficulty`, `stability` and `last_review` are *required*, but are null before the first review.</li><li>`due` and `step`, which the scheduler needs, are missing.</li><li>§D says `ReviewState` stores **Retrievability**, but R depends on the current time. A stored value is stale on read.</li></ul> **Recommendation:** use a `review_state` row with `state (1–3)`, `step`, `stability`, `difficulty`, `due`, `last_review` (UTC), plus app-maintained `reps` and `lapses`. The absence of a row means New. Compute R when it is read. |
| FSRS-4 | High | **`lapses` is not tracked by the package.** §G's lapse multiplier depends on it. <br>**Recommendation:** The review service must count Review → Again transitions itself, in the same transaction that appends the `review_event`. |
| FSRS-5 | High | **No grading policy for auto-graded formats.** MCQ and recognition answers are binary, but FSRS takes a 1–4 grade. <br>**Recommendation (D7):** wrong answer → Again; correct → Good; Hard/Easy only on self-graded flashcards. Record `format` and `response_ms` on every event. Note that recognition (MCQ) and recall share one memory state, which overstates stability. Accept this for V0.1 and log the format so it can be corrected later. |
| FSRS-6 | Medium | **Intra-session scheduling is not designed.** The default learning steps bring an item back after 1 min and 10 min, which a "top 15 items" session must handle. Fuzzing uses an unseeded `Random`. <br>**Recommendation:** Re-queue learning-step items within the session. Inject `Scheduler.customRandom` or disable fuzzing in tests. Inject a clock (`package:clock`) everywhere time is read. |
| FSRS-7 | Low | `ReviewEvent` "elapsed time" is ambiguous: it could mean days since the last review or answer duration. <br>**Recommendation:** Store both (`elapsed_days`, `response_ms`). |

**How much FSRS-2 matters.** Stability is 3 days, the review happens on schedule (R = 0.9), and the rating is Good. At 90% target retention the next interval equals S′ in days. Weights are the `fsrs` 2.0.1 defaults.

| Difficulty D | Spec §F formula | …capped at `maximumInterval` | FSRS-6 (package) |
|---:|---:|---:|---:|
| 1 | 635,293,914 d | 36,500 d (100 y) | 16.1 d |
| 3 | 9,591,603 d | 36,500 d | 13.5 d |
| 5 | 144,816 d | 36,500 d | 10.8 d |
| 8 | 272 d | 272 d | 6.9 d |
| 10 | 7.1 d | 7 d | 4.3 d |

At D = 5, Hard, Good and Easy all give 144,816 d under the spec's formula, against 4.7 / 10.8 / 26.5 d under FSRS-6. The growth factor S′/S rises from about 47,900× to 50,200× as S goes from 1 to 1,000. FSRS-6 falls from 3.96× to 2.36×, as the spec's prose intends.

---

## 5. Adaptive study engine (§G)

§G defines `Score_priority = (W_U·U) × (W_C·C) × (W_L·L) × (W_P·P)` with `U = 1 − R` (transcribed from images).

| ID | Sev. | Finding |
|---|---|---|
| ENG-1 | Blocker | **The weights have no effect on ranking.** The product equals `(W_U·W_C·W_L·W_P) · U·C·L·P`, a constant times the unweighted score. Appendix A reranks four sample items under four very different weight vectors and gets the same order every time. **Recommendation (D2):** use a weighted geometric form, `U^αU · C^αC · L^αL · P^αP · J^αJ`. That is linear in log space, so weights genuinely trade factors off, and a weight of 0 makes a factor neutral. |
| ENG-2 | Blocker | **Cold start starves reviews.** A never-reviewed item has R = 0 (this is also the package's return value), so U = 1. A due review at R = 0.9 has U = 0.1. New items therefore outrank due reviews tenfold, all else equal, and outrank even a badly overdue item (R = 0.7) about 3×. Review debt accumulates until every new item has been introduced. **Recommendation:** new items do not compete on U. Each session takes all due reviews by score, then a bounded **new-item budget**. New items are ordered core-first and prerequisites-first (topological order). |
| ENG-3 | Medium | "Urgency increases exponentially (U = 1 − R)": `1 − R` is linear. <br>**Recommendation:** Default to `U = 1 − R` (monotonic, simple). Revisit only if tuning shows it is needed. |
| ENG-4 | High | **Zero factors wipe out the score.** `L` and `C` are undefined. If `L = lapses`, any item that has never lapsed scores 0. <br>**Recommendation:** Define floors: `L = 1 + λ·lapses`; `C`: core 1.0 / secondary 0.5 / tertiary 0.25. Items not mapped to the active track are *filtered out* rather than scored 0. |
| ENG-5 | High | **`P` is not specified.** <ul><li>The prose mixes up prerequisite *items* (`prerequisite_item_ids`) with prerequisite *nodes*.</li><li>There is no formula, depth limit, or decay.</li><li>"Forcing the user to repair" suggests gating, which is not the same as boosting.</li></ul> <br>**Recommendation:** For V0.1, boost only: `P_i = 1 + β · max over transitive dependents j of γ^depth(j) · (1 − R_j)`, counting only reviewed dependents. |
| ENG-6 | High | **TASK-005 says to compute the score in "a SQL query".** R is a power function. SQL `pow()` works on native and on Web (ECO-7, corrected), but computing R in SQL would duplicate the FSRS maths outside the package that does the scheduling, and the two could drift apart. <br>**Recommendation:** SQL selects candidates (reviewed items with `due ≤ now + horizon`, filtered by track). Dart computes R through the package and scores them. This scales comfortably to thousands of items. |
| ENG-7 | Blocker (Phase 5) | **The formula has no journal term,** yet §J and Phase 5 require journal entries to "influence the priority queue". <br>**Recommendation:** Add `J = 1 + η·e^(−days_since_logged/τ)` for items whose subject or object is a linked node, or one hop from one. |
| ENG-8 | High | **Certification tracks do not inherit.** Seed item `ki_chablis_grape` is tagged `WSET_L2` and `CMS_CERTIFIED`, but V0.1 offers only `WSET_L3` and `CMS_CERTIFIED`. A WSET L3 candidate would never see it. <br>**Recommendation:** Make tracks cumulative (`certification.includes`): L3 ⊇ L2 ⊇ L1, and Certified ⊇ Introductory (D4). |
| ENG-9 | Medium | `minimum_depth` (1–5) is required by the schema but never used or defined. <br>**Recommendation:** Store it; leave it unused in V0.1. Define it when the depth-aware selector exists. |

---

## 6. Data model (§C–§E)

| ID | Sev. | Finding |
|---|---|---|
| DM-1 | High | **Inconsistent names.** <ul><li>`KnowledgeRelation` (§D) vs `KnowledgeEdge` (§O, §P)</li><li>`ReviewState` (§D) vs `FsrsState` (TASK-001) vs `fsrs_state` (§E)</li><li>`PERMITS_PRINCIPAL_GRAPE` (§D, §E) vs `PERMITS_GRAPE` (§Q)</li><li>ID prefixes: `node_app_chablis` / `ki_fr_burgundy_chablis_grape` (§E) vs `n_geo_chablis` / `ki_chablis_grape` (§Q)</li></ul> **Recommendation:** one glossary. `knowledge_edge` and `review_state` for tables. `n_<type>_<slug>` and `ki_<slug>` for IDs. IDs are immutable and never reused. |
| DM-2 | Blocker (Phase 1) | **The §E JSON Schema and the §Q YAML seed disagree.** <ul><li>Field names differ: `domain_id`/`domain`, `subject_node_id`/`subject_ref`, `object_node_id`/`object_ref`, `relation_type`/`edge_ref`, `assertion_text`/`assertion`, `track_id`/`track`.</li><li>The seed omits the required `versioning` block and `minimum_depth`.</li><li>The schema covers only items and `fsrs_state`. Nodes, edges, certifications, domains, citations and templates have no schema.</li><li>Putting `fsrs_state` (user data) in the "canonical curriculum" schema breaks §D's separation.</li></ul> **Recommendation:** write a single distribution schema that covers every canonical entity, with no user state. Validate the YAML against it at build time. |
| DM-3 | High | **Missing entities and junction tables.** <ul><li>item ↔ certification (with `importance`, `minimum_depth`)</li><li>item ↔ prerequisite</li><li>item ↔ citation</li><li>journal entry ↔ nodes (several grapes per entry)</li><li>user profile (the active track is in V0.1 scope)</li><li>curriculum metadata (version, checksum)</li><li>node aliases (journal matching)</li><li>a relation-type registry</li><li>node attributes: nodes carry only `id`/`type`/`name`, but §H's "other prominent **black** grapes" needs colour and prominence</li></ul> <br>**Recommendation:** Proposed schema: §13. |
| DM-4 | High | **Integrity rules are incomplete.** <ul><li>§S.1 checks edges → nodes but not **items → edges**. An item's (subject, relation, object) triple must be an existing edge.</li><li>§S.2 says "no item is a prerequisite for itself". That catches self-loops but not longer cycles (A→B→A).</li><li>SQLite does not enforce foreign keys unless `PRAGMA foreign_keys = ON` is set on each connection. Drift requires it in `beforeOpen`.</li></ul> <br>**Recommendation:** Enforce item → edge with a composite FK onto `UNIQUE(subject, relation, object)`. Check for cycles of any length with a recursive CTE. Enable FKs and test that they fire. |
| DM-5 | High | **No policy for curriculum updates.** Signed delta updates (§A, §T) are unspecified: format, signing, key management, and what happens to review history when an item changes or is removed. <br>**Recommendation:** V0.1 ships a versioned, bundled curriculum. Ingestion upserts by stable string ID and **never hard-deletes**; `valid_until` marks retirement. User tables reference curriculum by string ID with no cascading deletes. Signing is deferred. |
| DM-6 | Medium | **Node and relation types are not enumerated.** Relations also need cardinality: with 1:N relations, "What is *the* primary grape of Burgundy?" is ambiguous. Some relations are transitive (`LOCATED_IN`), and geography is a DAG with multiple parents, not a tree. <br>**Recommendation:** A relation registry with subject/object types, cardinality, transitivity, inverse label, and templates. |
| DM-7 | Medium | Should the materialized `Question` (§D) be persisted? <br>**Recommendation:** No. Log `template_id`, the RNG seed and the option IDs on `review_event`. |
| DM-8 | Low | Episodic flashcards (§J) need review state for items that are user data rather than canonical items. <br>**Recommendation:** Defer past V0.1. |

---

## 7. Seed dataset and content (§Q, §R)

| ID | Sev. | Finding |
|---|---|---|
| SEED-1 | Blocker (Phase 1) | The seed has **8 nodes, 5 edges and 2 items**. TASK-002 acceptance requires **50 nodes and 50 edges**. |
| SEED-2 | Blocker (Phase 2) | **The seed fails the spec's own distractor check (§S.3).** <ul><li>The answer *Chardonnay* has one sibling grape (*Pinot Noir*); three are needed.</li><li>*Kimmeridgian Clay* has no sibling soils.</li><li>There is one appellation.</li></ul> Phase 2's "4-option MCQ" cannot be generated from it. The distractors in sample Q1 (*Sauvignon Blanc*, *Chenin Blanc*) are not in the seed. |
| SEED-3 | High | **Sample Q4 is a closed-world error.** <ul><li>It asks for a *region*, but the answer is an *appellation* while the distractors are regions.</li><li>Kimmeridgian marl also underlies much of **Sancerre** (Loire) and the **Côte des Bar** (Aube, Champagne), so two of the three "wrong" answers are defensible.</li></ul> A missing edge does not make a statement false. Mitigation: <ul><li>per-relation `exclusive`/`complete` flags</li><li>exclude any candidate that holds the tested relation</li><li>curated `distinctive` flags for reverse recall</li><li>expert review</li></ul> |
| SEED-4 | Medium | Sample Q3, an "older, heavily sedimented" Premier Cru Chablis to be decanted over a light source, is atypical for a white wine. The textbook case is an aged red or vintage Port. This is a small example of why content needs sommelier review. |
| SEED-5 | Medium | `ki_chablis_grape` is in domain *viticulture*, but sample Q1 labels it *Geography*. No item has citations, though §E requires them. |
| SEED-6 | Blocker (plan) | **Nobody is assigned to author the content.** V0.1 needs a few hundred accurate, cited triples with enough density for distractors, and no task covers this (D3). |

---

## 8. Question engine (§H)

| ID | Sev. | Finding |
|---|---|---|
| QE-1 | High | **Two different distractor algorithms.** <ul><li>§H: go from the *subject's* parent (N. Rhône → France) to "other prominent black grapes grown in France".</li><li>TASK-004: go from the answer to its parent, then take "sibling nodes of the same type".</li></ul> Grapes have no parent node, and colour and prominence are not modelled. **Recommendation:** use the §H approach (subject-side scope traversal plus type and attribute filters), with fallback to wider scopes: region → country → all of the type. |
| QE-2 | High | **Distractor validity.** A distractor must not satisfy the tested relation. For "Which grape is permitted in Burgundy?", *Pinot Noir* is correct. Also exclude duplicate display names and the answer itself. |
| QE-3 | Medium | A single generic template ("What is the primary {Node:Category} of {Node:Subject}?") cannot phrase every relation. <br>**Recommendation:** Write templates per relation type and direction (forward/reverse), including article handling. |
| QE-4 | Medium | "Deterministic" generation should not mean a fixed answer position, or users memorize where the answer sits. <br>**Recommendation:** Shuffle with a seed, and log the seed. Tests stay deterministic and users see variety. |

---

## 9. Tasting engine (§I)

| ID | Sev. | Finding |
|---|---|---|
| TAST-1 | High | §I says every palate element uses "low, medium-, medium, medium+, high". WSET L3 SAT uses different scales for sweetness (dry…luscious) and body (light…full), and adds finish. The L4 Diploma SAT differs from L3. TASK-008's "only WSET terminology" needs an authoritative lexicon, which runs into the IP issue in LEGAL-2. |
| TAST-2 | Medium | Define grids as **versioned data**: framework → section → attribute → ordered allowed values. Validation and UI are then generated from the data. Store `tasting_descriptor(session, attribute_key, value_key)`. |
| TAST-3 | Low | There is no answer key or scoring. V0.1 captures tastings only. Optionally, the user reveals the wine's identity afterwards. |

---

## 10. Wine journal (§J)

| ID | Sev. | Finding |
|---|---|---|
| JRNL-1 | High | §J says users capture label photographs, but V0.1 says "manual data entry only". Photo capture brings camera permissions, file storage, and a separate Web path (D6). |
| JRNL-2 | Medium | The matching strategy is unspecified. **Recommendation:** use typeahead pickers bound to nodes, backed by normalized aliases (case, diacritics, AOC/DOCG suffixes). Keep the raw text. Defer fuzzy matching. |
| JRNL-3 | Blocker (Phase 5) | The journal needs a way to influence priority. See ENG-7. |

---

## 11. Roadmap and backlog (§O, §P)

| ID | Sev. | Finding |
|---|---|---|
| PLAN-1 | Medium | "TASKS 001, 003, and 006 can be executed simultaneously", but TASK-003 lists TASK-001 as a dependency. |
| PLAN-2 | Low | Phase 0 lists three tables; TASK-001 lists five. |
| PLAN-3 | Medium | "Runs smoothly… without jank" is not measurable. Define a criterion, e.g. no frames over budget in profile mode on scripted flows. Acceptance covers Android and iOS only, while §M targets five platforms. |
| PLAN-4 | High | V0.1 scope items without backlog coverage (table below). |

**Traceability from V0.1 scope (§N) to the backlog:**

| V0.1 scope item | Tasks | Gap |
|---|---|---|
| Drift schema + seed ingestion | 001, 002 | Schema covers 5 of about 13 entities plus junctions. The seed must be authored (SEED-6). |
| Certification profile selection | — | **No task.** |
| Question engine: recall, reverse, MCQ | 004, 007 | No task for the template engine or `QuestionTemplate`. |
| FSRS + adaptive queue | 003, 005 | No task for `ReviewEvent`. Grading policy undefined (FSRS-5). |
| Tasting trainer | 008 | No task for persistence tables or grid data. |
| Journal (manual entry) | 009 | No task for the table or CRUD list. |
| Analytics (retention, coverage) | 006 (partial) | Metrics are undefined. Needed: measured retention (share of review-state events graded ≥ 2), predicted retention (mean R), and coverage (share of track items introduced or mastered). |
| Validation §S.1–3 | 010 | §S.4 (version-expiry alerts) has no task. |
| Five-tab navigation shell (§M) | — | **No task.** |
| CI | — | **No task.** |

---

## 12. Legal, licensing and integrity risks

These are engineering flags for qualified counsel, not legal advice.

| ID | Finding |
|---|---|
| LEGAL-1 | "WSET", "Court of Master Sommeliers", "SAT" and "Deductive Tasting Grid" are marks or titles of the examining bodies. Use track names descriptively, show a non-affiliation disclaimer, and review before public release. |
| LEGAL-2 | Reproducing the SAT/DTM grid structure and vocabulary is required by TASK-008 but is exactly what §L says will not be copied. This needs a counsel decision before Phase 4. |
| LEGAL-3 | Open Food Facts is a consumer product database, not viticultural reference data. Its ODbL share-alike clause could require releasing the derived curriculum database under ODbL. Recommend **not** using it for the canonical curriculum. |
| LEGAL-4 | LWIN's licence is cited through a third party's attribution page. Verify it directly with Liv-ex before the scanner work, which is deferred anyway. |
| LEGAL-5 | "Factual assertions are not subject to copyright" is broadly right. In the EU, however, the *sui generis* database right protects substantial extraction from a database. Author facts from primary legal sources (INAO *cahiers des charges*, the EU eAmbrosia register, TTB) rather than from a compiled atlas or database. |
| LEGAL-6 | Several works cited are third-party re-hosted copies of WSET specifications, forum and blog posts, or a document-sharing upload. None are suitable as `SourceCitation` provenance. |
| LEGAL-7 | Certification facts need checking. For example, the matrix gives a 75% pass mark for CMS Advanced; my understanding is 60% for Advanced and 75% for Master. Formats also vary by CMS chapter. In V0.1 these facts only feed configuration text. |

---

## 13. Proposed Phase 0 scope

The goal is a buildable, tested foundation that does not depend on any unresolved blocker.

**In scope**

1. **Flutter project**
   - pinned to Flutter 3.47.x
   - Android, iOS and Web built; macOS and Windows scaffolded
   - Material 3 app with a five-tab placeholder shell
2. **Dependencies:** `flutter_riverpod` 3.x, `drift` + `drift_flutter` + `drift_dev` + `build_runner`, `clock`. `fsrs` and `yaml` are added in the phases that use them.
3. **Drift schema v1**, with `PRAGMA foreign_keys = ON` and Drift schema snapshots so migration tests exist from day one:

   | Table | Key columns and constraints |
   |---|---|
   | `certification` | `id` TEXT PK, `organization`, `name`, `includes_id` FK nullable |
   | `curriculum_domain` | `id` TEXT PK (six fixed values) |
   | `knowledge_node` | `id` TEXT PK, `type`, `name`, `attributes_json`, `valid_until` |
   | `knowledge_edge` | `subject_id` FK, `relation`, `object_id` FK, `UNIQUE(subject_id, relation, object_id)` |
   | `knowledge_item` | `id` TEXT PK, `domain_id` FK, the triple as a composite FK to `knowledge_edge`, `assertion_text`, `valid_from`, `valid_until`, `last_verified_at` |
   | `item_certification` | `item_id`, `track_id`, `importance`, `minimum_depth` |
   | `item_prerequisite` | `item_id`, `prerequisite_id`, `CHECK(item_id <> prerequisite_id)` |
   | `review_state` | the columns defined in FSRS-3 |

4. **Data access:** a repository layer plus Riverpod providers. Tests use an in-memory database.
5. **Tests**
   - CRUD for every table
   - an FK violation is rejected (a dangling edge; an item whose triple has no edge)
   - the CHECK constraint fires
   - generated code is up to date
6. **CI:** GitHub Actions running `flutter analyze`, `flutter test`, a stale-codegen check, and an Android debug build.
7. **Agent ergonomics:** a `CLAUDE.md` with conventions, and a cloud SessionStart hook that installs the pinned SDK.

**Out of scope for Phase 0:** seed ingestion, FSRS, question generation, and all real UI.

**Acceptance:** `flutter analyze` is clean and `flutter test` is green in both CI and the cloud session.

---

## 14. Decisions needed

Recommended defaults apply unless overridden.

| ID | Decision | Recommended default | Blocks |
|---|---|---|---|
| D1 | FSRS version | FSRS-6 through `fsrs` 2.0.1. The §F formulas are non-normative. | Phase 3 (and the `review_state` columns in Phase 0) |
| D2 | Priority-score form | Weighted geometric, new-item budget, `J` term; `U = 1 − R` | Phases 3 and 5 |
| D3 | Who authors and reviews curriculum content | I draft a seed from primary public sources, marked *unverified* until a qualified reviewer signs off | Phase 1 |
| D4 | Track model | Cumulative tracks; V0.1 offers `WSET_L3` and `CMS_CERTIFIED` | Phase 0 schema (minor) |
| D5 | Platforms verified in V0.1 | Android + iOS + Web smoke test; macOS and Windows scaffolded only | CI (Phase 0) |
| D6 | Journal photos in V0.1 | A nullable column in the schema; no capture UI | Phase 5 |
| D7 | Grading for MCQ | Wrong → Again, correct → Good. Self-graded flashcards use 1–4. | Phase 3 |
| D8 | Licensing on a public repository | Choose a LICENSE for code, possibly a separate one for curriculum content. Should the spec be committed? | Before content is pushed |
| D9 | Riverpod code generation | Hand-written providers; only Drift uses `build_runner` | Phase 0 |
| D10 | Legal review of SAT/DTM lexicon and trademark use | Obtain it before Phase 4 or a public release | Phase 4 |

---

## Appendix A — Reproducing the numbers in §4 and §5

```python
import math
# fsrs 2.0.1 defaultParameters (FSRS-6)
w = [0.2172,1.1771,3.2602,16.1507,7.0114,0.57,2.0966,0.0069,1.5261,0.112,1.0178,
     1.849,0.1133,0.3127,2.2934,0.2191,3.0004,0.7536,0.3332,0.1437,0.2]
decay = -w[20]; factor = 0.9 ** (1/decay) - 1          # R(S,S) == 0.9

def spec_Sr(D, S, R):   # spec section F, as printed
    return S * (math.exp(w[6]*(11-D)) * S**w[7] * (math.exp(w[8]*(1-R)) - 1) + 1)

def fsrs6_Sr(D, S, R, g=3):  # fsrs 2.0.1 Scheduler._nextRecallStability
    hp = w[15] if g == 2 else 1.0; eb = w[16] if g == 4 else 1.0
    return S * (1 + math.exp(w[8]) * (11-D) * S**(-w[9]) * (math.exp((1-R)*w[10]) - 1) * hp * eb)

print(spec_Sr(5, 3, 0.9), fsrs6_Sr(5, 3, 0.9))          # 144816.0  10.8

# Section G: the weights factor out of the product, so ranking never changes
items = {"A": (0.70, 1.0, 1.0, 1.0), "B": (0.85, 0.2, 2.5, 1.0),
         "C": (0.88, 1.0, 1.0, 3.0), "N": (0.00, 1.0, 1.0, 1.0)}  # (R, C, L, P); N never reviewed
for W in [(1,1,1,1), (10,.1,1,1), (.01,50,3,.2), (1,1,100,.001)]:
    s = {k: (W[0]*(1-R))*(W[1]*C)*(W[2]*L)*(W[3]*P) for k,(R,C,L,P) in items.items()}
    print(W, sorted(s, key=s.get, reverse=True))          # always ['N', 'C', 'A', 'B']
```
