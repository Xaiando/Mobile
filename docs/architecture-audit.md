# Architecture Audit — Contradictions, Gaps and Decisions

| | |
|---|---|
| **Date** | 2026-09-24 |
| **Scope** | Schema and naming consistency, foreign keys, uniqueness and indexes, seed data, FSRS representation, question generation, certification mapping, provenance, versioning of wine-law facts, Web vs native SQLite, code structure (§12), and the planned question system, coverage, geography and study packs (§13–§16) |
| **Companion documents** | [Phase 0 engineering audit](audit/phase-0-engineering-audit.md) covers the spec as a whole. [Architecture validation](architecture/architecture-validation.md) holds the spike evidence. [Domain model](domain-model.md) is the canonical schema. **This document is the decision register** that Phase 0 onward implements. |

Every entry names the conflicting passages of the spec (§A–§T), the problem, and a decision. Decisions come in two kinds:

- **Decided**: settled on technical grounds. This is the default for every row not marked otherwise.
- **Provisional**: a working default that awaited a user decision. §11 records the decisions the user has since made; the P-items are adopted.

Wherever this document says a constraint is enforced by the database, that was tested on the Flutter 3.47.5 spike, on native SQLite 3.53.4 **and** in Chromium through Drift's WASM backend (§10).

---

## 0. Key decisions

1. **One vocabulary.** YAML keys, SQL columns and Dart fields use the same words (§1). The graph edge is `KnowledgeRelation` (`knowledge_relations`), and its type is a `RelationType` (column `relation_type`). Entity names are those of the [domain model](domain-model.md).
2. **The database enforces what the spec only describes.**
   - the curriculum is read-only outside ingestion
   - items can only assert existing relations
   - no duplicate relations or items
   - a question's template must belong to its item's relation type
   - prerequisites cannot point at themselves
   - tasting sessions cannot use another framework's vocabulary, and a single-choice attribute takes one value
   - the review log is append-only
   - timestamps have one canonical UTC format

   All are SQLite constraints or triggers, proven on both platforms (§3).
3. **One item per relation.** An item is *the* testable assertion of one fact, so answering any question about a fact updates that fact's memory state (§3, §5).
4. **Legal validity lives on relations, not items.** Traversal and the sets of correct answers work on relations, so an expired fact must drop out of them (§9).
5. **Literal facts become quantity nodes.** Minimum ageing, yields and service temperatures fit the node-to-node graph without special cases (§4).
6. **Memory state follows FSRS-6 as implemented by the package.** A missing row means New; retrievability is computed, never stored; the scheduler configuration is versioned (§5).
7. **Question formats have two independent axes**: direction (forward/reverse) × mode (flashcard/MCQ). Servable questions are generated during ingestion as read-only curriculum (`Question`), so MCQ eligibility is a stored fact. There are always four options, or the item falls back to a flashcard (§6).
8. **Certification tracks are cumulative.** The nearest mapping along a track's chain applies. Syllabus references are structural identifiers only (§7).
9. **A source citation is evidence for a fact**, drawn from public primary sources. It is never a WSET or CMS document, which resolves a contradiction between §D and §L (§8).
10. **Changed facts are superseded, never edited or deleted.** Staleness means "not re-verified recently", not "a known end date has passed" (§9).
11. **Web runs the same SQL as native.** Platform differences are confined to storage, durability, assets and text normalization, each with a decision (§10).

---

## 1. Naming: canonical vocabulary

| Concept | Names used in the spec | Decision |
|---|---|---|
| Graph edge | `KnowledgeRelation` (§D); `KnowledgeEdge` (§O, TASK-001, §S.1); `edges` (§Q); "junction tables" (§C) | Entity **`KnowledgeRelation`**, table `knowledge_relations`, as in §D. *Revised:* an earlier draft chose `knowledge_edges`; §D, §E and the canonical entity list use KnowledgeRelation. |
| Edge type field | `relation_type` (§E); `relation` (§Q edges); `edge_ref` (§Q items); `RELATION:` (§D prose) | `relation_type`, as in §E. It is a foreign key to `RelationType`. |
| "Permitted grape" relation | `PERMITS_PRINCIPAL_GRAPE` (§D, §E); `PERMITS_GRAPE` (§Q) | Keep `PERMITS_PRINCIPAL_GRAPE`, where §D and §E agree, and add `PERMITS_ACCESSORY_GRAPE`. Wine law distinguishes principal from accessory varieties. Two relation types keep relations free of attributes and let the question templates be precise. The seed's `PERMITS_GRAPE` becomes `PERMITS_PRINCIPAL_GRAPE`. |
| Memory state | `ReviewState` (§D); `FsrsState` (TASK-001, TASK-003); `fsrs_state` (§E) | Table `review_states`. |
| Review log | `ReviewEvent` (§D, §O) | Table `review_events`. |
| Subject and object | `subject_node_id`/`object_node_id` (§E); `subject_ref`/`object_ref` (§Q items, and applied to the *edge* table in §S.1); `subject`/`object` (§Q edges) | `subject_id` / `object_id` on relations **and** items. |
| Item text | `assertion_text` (§E); `assertion` (§Q) | `assertion_text` |
| Domain | `domain_id` (§E); `domain` (§Q) | `domain_id` |
| Track | `track_id` (§E); `track` (§Q) | `track_id` |
| Track identifiers | `WSET_L3`, `CMS_CERTIFIED` (§D, §E); `WSET_L2` (§Q); the §B matrix lists eight certifications | `WSET_L1`, `WSET_L2`, `WSET_L3`, `WSET_L4`, `CMS_INTRODUCTORY`, `CMS_CERTIFIED`, `CMS_ADVANCED`, `CMS_MASTER` |
| Node IDs | `node_app_chablis` (§E); `n_geo_chablis` (§Q) | Keep §Q's form: it is the dataset, and published IDs never change. IDs are **opaque** and match `^n_[a-z0-9_]+$`. A node's type comes from its `node_type` column; code never parses it out of the ID. |
| Item IDs | `ki_fr_burgundy_chablis_grape` (§E); `ki_chablis_grape` (§Q) | Opaque, matching `^ki_[a-z0-9_]+$`. Keep the §Q IDs. |
| Question formats | "Simple Recall", "Reverse Recall", "Multiple Choice" (§H, §N). Sample Q1 is "Multiple Choice (Simple Recall – Geography)" | These are two independent axes: `direction` ∈ {forward, reverse} × `mode` ∈ {flashcard, mcq} (§6). |
| Template placeholders | `{Node:Category}`, `{Node:Subject}` (§H) | `{subject.name}`, `{object.name}`, `{object.type_label}` |
| Where a study session lives | "FAB to launch a study session" on Home (TASK-006); "Study (Curriculum Tree)" and "Practice (Question Engine)" (§M) | **Practice** hosts every session. The Home FAB opens a Practice session. **Study** browses the curriculum and can start a Practice session limited to one subtree. |

**Rule:** a name used in the dataset format is the SQL column name, and Dart uses the camelCase form of the same words. Drift generates row classes with exactly the entity names of the [domain model](domain-model.md).

---

## 2. Schema inconsistencies inside the spec

| ID | Where | Inconsistency | Decision |
|---|---|---|---|
| SI-1 | §E vs §Q | Field names differ throughout (§1). | The YAML keys *are* the column names. |
| SI-2 | §E vs §Q | §E requires the `versioning` block and `minimum_depth`; the seed has neither. | Both are required in the dataset format (their shape is set by §7 and §9). The validator rejects a dataset that omits them. |
| SI-3 | §E | The schema covers only items and `fsrs_state`. Nodes, edges, certifications, domains, citations, templates and tasting grids have no schema. | The authored tables of the [domain model](domain-model.md) *are* the distribution format (its §7). |
| SI-4 | §E vs §D | `fsrs_state`, which is user state, sits inside the "Canonical Curriculum Entity Schema", contradicting §D's separation of the two. | User state never appears in the distribution. |
| SI-5 | §D vs §E | §D stores Retrievability; §E omits it, and also lacks `due`, `step` and `reps`. | §5. |
| SI-6 | §S.1 | Applies the item field names `subject_ref`/`object_ref` to the edge table. | Relations use `subject_id`/`object_id`. |
| SI-7 | §E | `valid_from` is a `date`; `last_verified_at` is a `date-time`. | Correct as designed. Validity dates are legal effective *dates*; verification is an *event*, stored as a UTC timestamp. |
| SI-8 | §D | TastingSession, TastingDescriptor, WineJournalEntry, QuestionTemplate, Question, SourceCitation and the Certification exam configuration have no schema. | Defined in the [domain model](domain-model.md). Exam configuration is deferred along with exam simulators (§N). |
| SI-9 | §D vs §H | `Question` is described as a materialized instance, which implies storage. | **Revised:** stored as *generated* curriculum. `Question` and `QuestionDistractor` are rebuilt on every ingestion and are read-only at runtime. What was shown is logged on `review_events` and `review_event_options` (domain model §4.1). |
| SI-10 | §Q vs §R | Seed item `ki_chablis_grape` is domain `viticulture`; sample Q1 labels the same fact "Geography". | Each relation type has a default domain (`relation_types.default_domain_id`), which an item may override. `PERMITS_*` (appellation law) is geography; `HAS_SOIL`, `HAS_CLIMATE` and `SUSCEPTIBLE_TO` are viticulture. |
| SI-11 | §O vs TASK-001 | Phase 0 lists three tables; TASK-001 lists five. | Phase 0 builds the schema in [schema.drift](../lib/core/database/schema.drift). |
| SI-12 | §Q | The top-level `version: "1.0"` is undefined. | `dataset_version` (semver), recorded in `curriculum_releases` (§9). |

---

## 3. Target schema v1: foreign keys, uniqueness and indexes

**The canonical, column-level schema is the [domain model](domain-model.md), with its executable form [schema.drift](../lib/core/database/schema.drift).** This section records what the spec lacked and the rules the schema follows.

The spec defines exactly one relationship, relation → node (§S.1). Everything else was missing, and two SQLite behaviours matter:

- Foreign keys are enforced only with `PRAGMA foreign_keys = ON` (proven with a negative control).
- SQLite does **not** index foreign-key child columns automatically. A `UNIQUE` constraint does create an index.

**Delete policy:**

- Authored curriculum rows are never deleted (§9). Outside ingestion, triggers make the curriculum read-only (domain model §2). Foreign keys *into* the curriculum use the default `NO ACTION`.
- Children owned by the user use `ON DELETE CASCADE` (journal links, tasting descriptors). A tasting session's link to a journal entry uses `ON DELETE SET NULL`.

### 3.1 What the spec lacked

| Area | In the spec | In the domain model |
|---|---|---|
| Foreign keys | relation → node only | Declared on all 31 tables, including composite keys |
| Relation and node vocabularies | None | `RelationType`, `RelationTypeSignature`, `NodeType` |
| Uniqueness | None | The relation triple (the primary key); one `KnowledgeItem` per relation; normalized node name per node type; one template per relation, direction, mode and locale; grid positions |
| Traversal and query indexes | None | Relations by object; prerequisites by prerequisite; mappings by item; citations by source; review states by `due`; review events by item and by time; journal links by node |
| Track mapping | A free-string `track_id` inside each item | `CertificationKnowledgeMapping`, with a foreign key to `Certification` |
| Prerequisites and citations | String arrays inside each item | `KnowledgeItemPrerequisite` and `KnowledgeItemCitation` |
| Literal facts | Not representable | The `QuantityValue` subtype |
| Alternative names | None | `NodeAlternativeName` |
| Questions | Named, not defined | `QuestionTemplate` (authored); `Question` and `QuestionDistractor` (generated) |
| Tasting vocabularies | Hard-coded in the UI (TASK-008) | `TastingGrid`, `TastingGridAttribute`, `TastingGridValue` |
| Profile and scheduler settings | None | `UserProfile`, `SchedulerConfig` |
| Release metadata and write lock | None | `CurriculumRelease`, `CurriculumIngestion` |

### 3.2 Guarantees proven in the spike (native and Chromium)

| Guarantee | Constraint |
|---|---|
| The curriculum is read-only outside ingestion | `BEFORE INSERT/UPDATE/DELETE` triggers on all 21 curriculum tables. Writes are allowed only while a `CurriculumIngestion` row exists, inside the ingestion transaction. |
| No dangling relations (§S.1) | Relation → node FKs, with the pragma set. With the pragma off, a dangling relation is accepted. |
| Every item asserts an existing relation | Composite FK onto the relation's primary key |
| A question's template belongs to its item's relation type | Two composite FKs through `questions.relation_type` |
| Quantities attach only to quantity nodes | Composite FK (`knowledge_node_id`, `node_type`) |
| Only the session's own framework vocabulary (TASK-008) | Descriptor composite FKs, plus a trigger that allows one value per single-choice attribute |
| An append-only review log | Triggers on `review_events` and `review_event_options` |
| Canonical dates and timestamps | `date(x) IS x`; the exact form `YYYY-MM-DDTHH:MM:SS.sssZ` |
| Review-state invariants | Step coupling, `lapses < reps`, `due > last_review` |
| No self-prerequisites; value ranges; enumerations | `CHECK` constraints |
| Re-ingestion keeps user history | Authored rows are upserted; generated tables are rebuilt without touching any user row |

### 3.3 Rules the validator enforces instead of SQL

These rules span rows or releases, so they cannot be SQL constraints. They run in the build-time validator (TASK-010), and the runtime tests repeat them:

- Every relation's subject and object types match a `relation_type_signatures` row.
- Prerequisites, `LOCATED_IN` and certification chains are acyclic; a recursive CTE finds cycles of any length (proven). Certification chains stay within one organization.
- For `cardinality = 'one'` relation types, a subject has no two relations with overlapping validity (§9).
- Every item has at least one citation (§8) and at least one track mapping (§7).
- Every MCQ question has at least 3 distractors, and none is a correct answer in any validity period (§6).
- No authored row disappears between dataset versions (§9).
- `name_norm` recomputes identically.

### 3.4 Identifiers

- Curriculum rows use stable, opaque TEXT IDs with a prefix per entity (`n_`, `ki_`, `src_`, `qt_`, `tg_`); certifications use track codes.
- Rows the user creates (`review_events`, `wine_journal_entries`, `tasting_sessions`) use **UUID** TEXT IDs.

The reason: §N defers cloud sync, and UUIDs let sync arrive later without re-keying any rows. This is the same "plan now to avoid restructuring later" reasoning §K applies to the scanner.

---

## 4. Seed data

| Requirement in the spec | What the seed has | Decision |
|---|---|---|
| TASK-002: 50 nodes and 50 edges after initialization | 8 nodes, 5 edges, 2 items | **Phase 1 gate:** at least 50 nodes and 50 relations, with every validator rule in §3.3 passing. |
| Phase 2 and §S.3: at least 3 plausible distractors per MCQ item | *Chardonnay* has one sibling grape; *Kimmeridgian* has none; there is one appellation | The gate requires every item to pass MCQ viability or be marked `mcq_disabled`. |
| V0.1 tracks `WSET_L3`, `CMS_CERTIFIED` (§N) | Items tagged `WSET_L2`, `WSET_L3`, `CMS_CERTIFIED`; no certification rows at all | All eight certification rows with their inheritance chains (§7). |
| Citations are required (§E) | None | At least one citation per item (§8). |
| The spec's own examples: Barolo/Nebbiolo (§J), Northern Rhône/Syrah (§H), Piedmont (§F), Châteauneuf-du-Pape/galets roulés (§H), the distractors in §R | None present | Include them. They are the spec's acceptance scenarios. |
| The prerequisite multiplier (§G) | No prerequisites | A small prerequisite DAG, enough to exercise P. |
| **Facts with literal values**: "the required aging duration for Barolo" (§J), service temperatures (§B, §R) | Cannot be represented; relations link node to node only | **Quantity nodes**: a node of type `quantity` with a `QuantityValue` row (e.g. minimum 38, unit month). Distractors then come naturally from the same relation on sibling subjects, e.g. Barbaresco's or Brunello's ageing rules. No special case is needed in the schema or the engine. |
| Service, business and tasting domains (§C) | None | Items in each domain the V0.1 tracks examine. |
| Question templates (§H) | None | At least one forward template per relation used. Reverse templates only for reverse-safe relations (§6). |
| V0.1 release volume | — | **Adopted (P-6):** at least 150 verified items. |

The content itself, including who writes it and who verifies it, remains **D3**.

**Dataset v0.1.0 (Phase 1).** [`assets/curriculum/curriculum.yaml`](../assets/curriculum/curriculum.yaml) meets the Phase 1 gate. Every validator rule passes.

- **Volume:** 65 nodes, 87 relations and 46 items across 14 appellations in France and Italy, all eight certification rows, and a 10-edge prerequisite DAG.
- **Sources:** every item cites one of 14 primary legal texts: INAO cahiers des charges and MASAF disciplinari.
- **Spec examples covered:** Chablis, Barolo/Nebbiolo with its 38-month minimum, the northern Rhône's Syrah, Châteauneuf-du-Pape's galets roulés, and the §R distractors.
- **Still open for V0.1:** the service, business and tasting domains, and the 150 verified items of P-6. Both are content work under D3.

Reading the legal texts corrected the spec's seed in two places:

| ID | The spec says | The primary source says | Decision |
|---|---|---|---|
| SD-1 | Chablis has a "Cool Continental" climate (§Q) | The Chablis cahier des charges describes an oceanic climate modified by continental influences | The dataset follows the legal text. Climate items with overlapping categories are flashcard-only (`mcq_disabled`). |
| SD-2 | Kimmeridgian soils identify Chablis (§R Q4) | The Pouilly-Fumé cahier des charges lists Kimmeridgian marls too | Both relations are in the dataset, which confirms QG-11: no reverse question on that soil. |

---

## 5. FSRS representation

| ID | Decision | Reason |
|---|---|---|
| FS-1 | FSRS-6 through `fsrs` 2.0.1 (21 weights). The §F equations are non-normative. | §F cannot be satisfied as written (audit FSRS-1/2). |
| FS-2 | Memory state is scheduled per `knowledge_item`. Both directions and both modes update the same state. | This is the spec's central idea (§F), kept. Known bias: recognition (MCQ) is easier than recall, so stability runs optimistic. Accepted for V0.1; the mode is logged so it can be modelled later. |
| FS-3 | *New* means there is no `review_states` row. The first review creates it. | The package has no New state, and its `stability` and `difficulty` are null before the first review. |
| FS-4 | Columns: `state` (1–3), `step`, `stability`, `difficulty`, `due`, `last_review`, `reps`, `lapses` (domain model §4.1). `review_states` is a projection of `review_events`: the latest after-state plus the counts. | Mirrors the package's `Card`. A round trip reproduces scheduling exactly, and the projection equals a replay of the log (both proven). |
| FS-5 | Retrievability is computed at read time with `getCardRetrievability`. It is never stored. | R depends on the current time. |
| FS-6 | Grading: a flashcard is self-graded 1–4. An MCQ answer is graded wrong = 1 (Again), right = 3 (Good). Response time is not used for grading. | There is no validated time threshold, and §H does not specify one. |
| FS-7 | A *lapse* is an Again rating while the item is in Review state. `reps` counts every review. Both are maintained by the app. | The package tracks neither. §G's lapse factor needs `lapses`. |
| FS-8 | The scheduler configuration is a **versioned row**: weights, desired retention 0.9 (the spec's 90% threshold), learning steps, maximum interval 36,500 days, fuzzing. Each `review_events` row records `scheduler_config_version`. | §F anticipates later optimization of the weights. The logged events can then be replayed against new weights. |
| FS-9 | All timestamps are UTC ISO-8601 text taken from an injected clock. `elapsed_days` is whole days, as the package computes it. | The package rejects non-UTC times. Drift's default storage loses UTC (negative control). |
| FS-10 | Tests use `Scheduler.customRandom(seed)` or turn fuzzing off. | Reproducible scheduling (proven). |
| FS-11 | An item on a learning step (due within minutes) is re-queued within the current session. | §F and §G say nothing about sessions. The package defaults to 1 min and 10 min learning steps. |
| FS-12 | Switching certification profile neither resets nor forks memory state. | Memory belongs to the fact, not the track. |
| FS-13 | Superseded or expired items keep their state and leave the queue (§9). | Keeps history intact without studying invalid law. |
| FS-14 | A session holds up to 15 items (TASK-005), with at most **5 new** among them (**P-4, adopted**). | Prevents new items crowding out reviews (validation A-2). |
| FS-15 | **Session composition (Phase 3).** Due items fill the session first. New items take only the room left, up to the budget. A new item never comes before a new prerequisite of its own; among the items ready, core items come first, then by ID. The first presentation of a new item uses its easiest format (forward MCQ, then forward flashcard, then reverse). Later presentations draw a served format at random, since every format updates the same state (FS-2). *The random draw is superseded by the difficulty ladder of QF-7 once backlog task F4 lands.* | Reviews are not crowded out (A-2), and foundations come before what builds on them. |
| FS-16 | **Retention (Phase 3).** The Home dashboard's retention is the share of recall attempts on items in Review state rated Hard or better over the last 30 days. It is computed from the log with SQL `lag()`, because the log stores only after-states. Learning-step answers are excluded. | This is FSRS's "true retention". It is comparable with the 0.9 desired retention, which a raw share of correct answers is not. |

### Adaptive study engine (Phase 3)

The adaptive score's form is A-1 to A-6 of the [architecture validation](architecture/architecture-validation.md) (§3.6). Phase 3 adds these decisions.

| ID | Decision | Reason |
|---|---|---|
| A-7 | **Provisional weights**: αU = αC = αL = αP = 1; λ = 0.2, so five lapses double an item's priority; β = 2 and γ = 0.5, so a forgotten direct dependent doubles its prerequisite's priority and a dependent two steps away adds half as much. The journal factor J (A-5) arrives in Phase 5. | §G gives no values. These are round numbers to fit against the logged reviews once real data exists (FS-8). A test proves each exponent can change the ranking. |
| A-8 | In the prerequisite factor P, a dependent **on a relearning step** counts as fully forgotten (1 − R = 1) until it graduates again. Other reviewed dependents count 1 − R; new dependents do not count. | The package counts elapsed time in whole days, so R = 1 on the day of a review, and a lapse would boost nothing until the next day. A lapse is §G's clearest sign of a foundation gap. Failing a *new* item is not. |
| A-9 | **Due order**: items on a learning or relearning step come first, oldest due first. Review-state items follow, by descending score. | On the day of a review R = 1, so U = 0 would rank every step item last. Steps last minutes, so they must be shown promptly (FS-11). |
| A-10 | **Formats served** follow `minimum_depth` (CM-6): forward MCQ from 1, forward flashcard from 2, reverse formats from 3. If none of an item's questions reaches its depth (an MCQ-only depth on a flashcard-only item), the easiest question is served, so a mapped item is never unreachable. | CM-6 defines the depths. The fallback covers `mcq_disabled` items mapped at depth 1. |

---

## 6. Question generation

| ID | Decision | Reason |
|---|---|---|
| QG-1 | Formats are `direction` {forward, reverse} × `mode` {flashcard, mcq}. V0.1 serves all four combinations. | §H and §N name three formats that are really two axes. Sample Q1 is labelled both "Multiple Choice" and "Simple Recall". |
| QG-2 | Templates are canonical content, keyed by (relation, direction, mode, locale), using the placeholders in §1. **English only in V0.1.** | §H's single generic template cannot phrase every relation. The spec is silent on localization. |
| QG-3 | **Eligibility is computed when questions are generated during ingestion.** Each eligible (item, template) pair becomes a `Question` row. An item can be served in a format if: <ul><li>a template exists for it;</li><li>for MCQ, at least 3 valid distractors exist after widening the search scope;</li><li>for reverse, the relation type is `is_reverse_safe` or the item is `is_distinctive`.</li></ul> Curators can override with `mcq_disabled`. The build report lists every item's eligibility. | §S.3 refers to items "flagged for MCQ" but defines no flag. An MCQ `Question` row *is* that flag, and it is recomputed on every ingestion. |
| QG-4 | **Distractors**: start at the subject's geographic scope and widen until 3 candidates exist (region → country → the whole node type). Candidates must: <ul><li>come from relations current at generation (§9);</li><li>share the answer's node type;</li><li>share the answer's value for the relation type's `distractor_match_relation_type`, e.g. `HAS_BERRY_COLOUR`, which gives §H's "other **black** grapes".</li></ul> Exclude every object the subject holds for the relation in **any** validity period (past, current or future), and any name that normalizes to a correct answer's name. The pool is stored as `QuestionDistractor` rows. | Proven in the spike (validation Q-1). §H and TASK-004 describe two different algorithms; this one resolves them. |
| QG-5 | A reverse MCQ distractor must not hold the tested relation to the object in any validity period. | Prevents a second correct answer being marked wrong. |
| QG-6 | Always exactly 4 options, or fall back to a flashcard. Never 2 or 3 options. | Phase 2 acceptance ("4-option"). |
| QG-7 | A fresh seed per presentation draws 3 distractors from the pool. The seed is logged in `review_events` and the options shown in `review_event_options`. Tests pass explicit seeds. | Deterministic for tests, varied for users (proven). |
| QG-8 | Flashcards are revealed and self-graded. There are no typed answers in V0.1. | Typed answers would need fuzzy matching and alias handling in V0.1 for little gain. |
| QG-9 | Questions are stored as generated, read-only curriculum and rebuilt on every ingestion (SI-9, revised). | §D defines Question as materialized. It turns §S.3 into a query and keeps recursive traversal out of runtime queries. No user row references a question, so rebuilding never touches history (proven). |
| QG-10 | Ordering, matching, reasoning, scenario and episodic questions are post-V0.1. *Superseded by QF-1 (2026-09-24): these formats are planned in [backlog.md](backlog.md); R3 fixes which of them ship in V0.1.* | §N scope. |
| QG-11 | **Closed-world risk.** A missing relation does not make a statement false; see sample Q4, where Kimmeridgian soils also occur in Sancerre and the Aube. The mitigations are reverse safety (QG-3), curated `distinctive` flags, and expert review. | This is a content matter, recorded here so it is not treated as an engine bug. |
| QG-12 | **Search levels (Phase 2), refining QG-4.** Each level is a Drift query; the search stops at the first level that brings the pool to 3. <ol><li>Each geographic scope containing the subject, nearest first: the relation's objects held by other subjects inside that scope.</li><li>The relation anywhere in the curriculum.</li><li>Every current node of the answer's type.</li></ol> Levels 2 and 3 widen QG-4's last step: a real answer to the same relation elsewhere is more plausible than an arbitrary node. **Quantities must also share the answer's unit**, so an ageing question never offers a service temperature. For a transitive relation (`LOCATED_IN`), every ancestor is a correct answer and is excluded. A reverse question searches the answer's own geographic peers first, then the relation's subjects, then its node type. | Found while generating the dataset's questions: without the unit rule, the whole-type step mixes units; without the relation step, rare relations fall straight to arbitrary nodes. |
| QG-13 | **Presentation (Phase 2).** The pool keeps each candidate's `scope_rank`. A presentation shuffles each rank with the seed and takes the nearest first, then shuffles the 4 options with the same seed. Seeds are below 2^31, so they round-trip exactly on the web. | The nearest distractors are the most plausible, so they are always shown; the seed varies the rest and the answer's position (QG-7). |
| QG-14 | **Viability report.** Generation reports every skipped (item, template) pair: not reverse-safe, `mcq_disabled`, or too few distractors. The §S.3 gate is a test: every item has an MCQ or is `mcq_disabled`, and every item has a flashcard. | Makes §S.3 and TASK-010's "items with insufficient plausible distractors" a check that fails the build rather than a runtime surprise. |

---

## 7. Certification mapping

| ID | Decision | Reason |
|---|---|---|
| CM-1 | All eight tracks exist as rows. Only `WSET_L3` and `CMS_CERTIFIED` are `selectable` in V0.1. | §B defines eight; §N offers two. Items can still be tagged for any track. |
| CM-2 | Inheritance chains: WSET_L4 → L3 → L2 → L1, and CMS_MASTER → ADVANCED → CERTIFIED → INTRODUCTORY. No chain crosses organizations. | Without it, the seed's `WSET_L2` items would be invisible to a WSET L3 candidate (audit ENG-8). |
| CM-3 | An item's effective mapping for the active track is the **nearest** mapping along that track's chain, the track itself first. The nearest mapping's importance and depth apply. | This rule is deterministic and lets a higher level override a lower one. |
| CM-4 | Items with no effective mapping are excluded from that track's queue and coverage metrics. | Replaces "C = 0", which would wipe out the priority score (audit ENG-4). |
| CM-5 | Importance maps to the relevance factor C as core 1.0 / secondary 0.5 / tertiary 0.25. **Provisional** tuning. | §G gives no values. |
| CM-6 | `minimum_depth` (1–5) is stored as specified. Its V0.1 meaning (**P-2, adopted**): it sets which formats that track serves. <ul><li>1 = recognize (MCQ)</li><li>2 = also forward recall (flashcard)</li><li>3 = also reverse recall</li><li>4–5 = reserved for reasoning formats</li></ul> *QF-6 refines every level for the new formats.* | §E requires the field but never defines it. An undefined column would drift out of use. |
| CM-7 | `certification_knowledge_mappings.syllabus_ref` optionally holds a section identifier. It **never** holds syllabus text. | §L: syllabi are structural blueprints only. |
| CM-8 | Exam formats and pass marks from §B are not stored in V0.1. Track names are descriptive and never imply affiliation. | Exam simulators are deferred (§N). The §B figures need verification (audit LEGAL-7). Trademarks: audit LEGAL-1. |
| CM-9 | The active track lives in `user_profiles` (a single row). Switching it updates the queue and coverage immediately, through Drift streams. | Reactive wiring was proven in the spike. |

---

## 8. Source and provenance representation

**Contradiction.** §D's example of provenance is "authoritative documents (e.g., WSET Specifications)". §L says WSET and CMS documents are *proprietary structural blueprints* and names "public legal frameworks (e.g., French INAO decrees)" as the primary source of truth.

**Decision.** A citation is *evidence for a fact*, taken from public primary sources. Mapping to a syllabus is not a citation (CM-7).

| ID | Decision |
|---|---|
| PR-1 | `source_citations` columns: `id`, `kind`, `title`, `publisher`, `jurisdiction`, `document_identifier` (e.g. a decree number or CFR section), `url`, `published_on`, `accessed_on`, `license`, `attribution_text`. `kind` is one of `legislation`, `regulator_register`, `government_publication`, `academic`, `reference_work`, `dataset`. |
| PR-2 | `knowledge_item_citations(knowledge_item_id, source_citation_id, locator)`, where `locator` is the article, section or page. |
| PR-3 | Every item needs at least one citation (validator). Regulatory relations (`PERMITS_*`, minimum ageing, yields…) need at least one `legislation` or `regulator_register` citation. Examples: an INAO *cahier des charges*, the EU eAmbrosia register, the US TTB. |
| PR-4 | Items carry `last_verified_at` and a `verification_status` (unverified or verified). **Adopted (P-5):** unverified items appear with an "unverified" badge. Under D3, content needs expert review before any public release. |
| PR-5 | Provenance is recorded per item. Structural relations that back no item (e.g. `LOCATED_IN`, used only for traversal) are listed in the build report for curator review rather than each carrying a citation. |
| PR-6 | Citations with an attribution licence (CC-BY, ODbL) feed a generated attributions screen. ODbL sources are kept out of the canonical curriculum, because of share-alike (audit LEGAL-3). |
| PR-7 | The spec's *works cited* list is not usable as provenance: many entries are re-hosted copies, forum or blog posts, or document-sharing uploads (audit LEGAL-6). |
| PR-8 | The regulatory relation types, which need a `legislation` or `regulator_register` citation, are `PERMITS_PRINCIPAL_GRAPE`, `PERMITS_ACCESSORY_GRAPE`, `MIN_AGEING`, `MIN_WOOD_AGEING` and `REQUIRES_METHOD`. The list lives in the validator (`regulatoryRelationTypes`). |
| PR-9 | A French citation's URL is the appellation's page at INAO, which publishes its cahier des charges and every regulatory text; `document_identifier` names the homologating act. Italian citations point to the MASAF page of the disciplinare. Where the homologated PDF could not be downloaded, the facts were read in the version INAO published for the national opposition procedure, and the expert reviewer confirms them (D3). |

---

## 9. Versioning of wine-law facts

The spec provides three things, and none of them explains how the rules behave together:

- item-level `valid_from`, `valid_until` and `last_verified_at` (§E)
- a runtime check that "flags any KnowledgeItem where the `valid_until` date has passed" (§S.4)
- signed delta updates, deferred (§A, §T)

| ID | Decision | Reason |
|---|---|---|
| V-1 | **Legal validity lives on `knowledge_relations`** (`valid_from` required, `valid_until` nullable) and on `knowledge_nodes`. Items carry `revision`, `last_verified_at`, `verification_status` and `superseded_by_item_id`. | Correct-answer sets, distractor pools and traversal all operate on *relations*. An expired fact must stop affecting them, including structural relations that back no item. This changes §E's shape for that concrete reason; §E must be rewritten anyway (SI-3). |
| V-2 | *Current* means `valid_from ≤ today < valid_until` (the end date is exclusive), using the device's local date. The queue and the sets of correct answers use current relations only. Distractor *exclusion* conservatively considers every period (QG-4). | Validity dates are legal dates, not instants. |
| V-3 | **A change in meaning is a supersession.** Add a new relation and a new item, end the old relation with `valid_until`, and set the old item's `superseded_by`. The FSRS state stays with the old item; the new item starts New. Users who studied the old item see a "the rules changed" notice linking both. | This keeps review history intact, never shows invalid law, and fulfils §S.4's intent of telling the user. |
| V-4 | **Staleness is separate from expiry.** Items whose `last_verified_at` is older than a threshold (**P-1, adopted: 24 months**) get a "may be out of date" badge. | A known `valid_until` means the successor is already known. The real risk is a fact nobody has re-checked, which is what §S.4 tries to catch. |
| V-5 | Editing wording without changing meaning keeps the same ID, increments `revision`, and keeps the FSRS state. Curators decide which case applies; the build report lists every revision. | Typo fixes must not reset what the user has learned. |
| V-6 | **Node renames** keep the node ID and change `name`; the old name becomes a `node_alternative_names` row of kind `former_name`. Example: Bourgogne Grand Ordinaire was renamed Coteaux Bourguignons in 2011. An abolished node gets a `valid_until`. | Journal entries for older bottles still match, and history keeps its references. |
| V-7 | The dataset carries a semver `dataset_version` and a checksum, recorded in `curriculum_releases`, and is bundled with the app. It is ingested on first launch and whenever the bundled version is newer, in a single transaction: authored rows by upsert, generated tables rebuilt. **Authored rows are never deleted.** The validator fails the build if an authored row disappears between versions. Retirement is always done with `valid_until`. | An upsert that preserves user state was proven. Hard deletes would orphan history. |
| V-8 | Over-the-air updates remain deferred (§T). When they arrive, ship **signed full snapshots** through the same upsert path. Deltas are unnecessary at this data size. **Provisional.** | One ingestion path, simpler than deltas. |
| V-9 | Much wine law applies by vintage rather than calendar date. Effective dates approximate this, and the assertion text states any vintage conditions. A vintage-aware model is deferred. | Not needed for V0.1 accuracy. Recorded so it is not forgotten. |
| V-10 | Exam syllabi can lag behind current law, so what is legally current may differ from what is examined. Flagged for the content owner (D3). | Out of scope for V0.1. |
| V-11 | A relation whose effective date is not curated yet records `valid_from: 1900-01-01` and is treated as in force. The validator counts these in its report. | `valid_from` is required (V-1), and inventing a date would be worse than a documented placeholder. |
| V-12 | Ingestion policy, Phase 1: <ul><li>no release installed, or the bundle is newer: ingest</li><li>same version, different checksum: re-ingest, which is safe because ingestion only upserts</li><li>installed release newer than the bundle (an app downgrade): keep it</li><li>a release that drops an authored row already in the database: refuse it, and write nothing</li></ul> Foreign keys are deferred to commit inside the transaction, so rows may reference rows later in the same release. | Implements V-7. The removal check runs against the database, so it also covers releases the build never saw. |

---

## 10. Web vs native SQLite

Everything here is measured, from the spike's native tests and from a release Web build probed in headless Chromium. **The SQL is identical on both platforms**, so queries have no platform branches.

| Aspect | Native | Web | Decision |
|---|---|---|---|
| Engine | SQLite **3.53.4**, bundled by `sqlite3` 3.6.0 build hooks (prebuilt binaries, hash-pinned) | SQLite **3.53.4** from `sqlite3.wasm` 3.6.0, a manually supplied asset | Pin the versions through the lockfile. CI checks that the `sqlite3.wasm` and `drift_worker.js` versions match `pubspec.lock`. |
| Foreign keys, CHECK, triggers, `json_valid`, `pow`, recursive CTEs | ✔ | ✔ (probe: `fk=1`, cross-lexicon descriptor rejected, append-only delete rejected, `json_valid` 1/0, `pow=1024`) | No platform-specific SQL. |
| Storage | A file in the app documents directory | Drift picks the best of `opfsShared` (Firefox only), `opfsLocks` (needs COOP/COEP), `sharedIndexedDb`, `unsafeIndexedDb`, `inMemory`. Observed through `onResult` in Chromium: **`sharedIndexedDb`** without the headers, **`opfsLocks`** with them. | Serve Web with COOP/COEP headers. Use `DriftWebOptions.onResult`: <ul><li>`inMemory` → a **blocking warning**, because progress would not survive a reload</li><li>`unsafeIndexedDb` → a warning that multiple open tabs risk data races</li></ul> |
| Durability | Managed by the OS | Browsers may evict site storage unless persistent storage is granted | Request persistent storage on Web. Treat Web as a secondary target in V0.1 (D5). Export and backup come after V0.1. |
| Multiple instances | One process | Many tabs. Drift's shared worker keeps them safe, except with `unsafeIndexedDb`. | See the storage row. |
| Text case and accents | SQLite folds case for **ASCII only**: `lower('RHÔNE')` = `rhÔne`, and `'rhone' ≠ 'rhône'` | Same | Normalize in Dart (lowercase, strip diacritics, drop AOC/AOP/DOCG suffixes) into `name_norm` on `knowledge_nodes` and `node_alternative_names`. SQL never relies on `LIKE` or `lower()` for names. |
| Integers | 64-bit | Dart-to-JS integers are exact only up to 2^53 | Avoid 64-bit integer values. Timestamps are text and user row IDs are UUID text (§3.4). |
| Files (journal photos, if D6 changes) | Filesystem | No filesystem | `photo_ref` is an opaque key, not a path. A `PhotoStore` interface with a native file implementation and a Web blob implementation (OPFS or IndexedDB). |
| Seed ingestion | Bundled asset, one transaction | Same code; each statement crosses to the worker | A single batched transaction. The dataset stays **YAML at runtime, as TASK-002 specifies**; the `yaml` package works on Web. `DriftWebOptions.initializeDatabase` could ship a prebuilt database later if first launch proves slow. |
| Extra startup assets | — | `sqlite3.wasm` (~750 KB), `drift_worker.js` (~360 KB), CanvasKit | Bundle CanvasKit (`--no-web-resources-cdn`); otherwise first load needs the network (validation F-2). |
| Test coverage | `flutter test` on the VM with in-memory `NativeDatabase` | Not covered by `flutter test` | Add a CI Web smoke test: the headless-Chromium probe used here. |
| Android 16 KB pages | The bundled `.so` files must be 16 KB-aligned | — | CI alignment check on release APKs (audit ECO-8). |

---

## 11. User decisions

Decided by the user on 2026-09-24. These rows are no longer provisional.

| ID | Decision |
|---|---|
| D3 | Curriculum content may be drafted from authoritative, public sources, with provenance recorded (`source_citations`). It stays `unverified` until reviewed, and generated content is never treated as authoritative without sources. |
| D5 | Android and iOS are the primary V0.1 targets, with basic web compatibility. The architecture stays compatible with Windows and macOS for later; their platform folders are not created yet. |
| D6 | The schema supports journal photos (`wine_journal_entries.photo_ref`). Camera and photo UI, and label scanning, are deferred. |
| D8 | No open-source license. The project is proprietary despite the public repository, and the product specification PDF stays out of the repository. |
| D10 | Development does not wait for legal review. Proprietary WSET/CMS questions, copyrighted syllabus text and tasting-grid artwork are never reproduced. Legal and licensing uncertainties are tracked in [legal-review.md](legal-review.md) for review before public release. |
| P-1 to P-6 | The recommended defaults are adopted: a 24-month staleness threshold; `minimum_depth` controls which formats are served (CM-6); a 1–5 journal rating; 15-item sessions with at most 5 new items; unverified content shown with a badge; at least 150 verified items for V0.1. |

---

## 12. Code structure

| ID | Decision | Reason |
|---|---|---|
| DL-1 | **Data access.** Repositories are concrete classes in `lib/core` over `AppDatabase`, one per concern: `CurriculumIngester`, `KnowledgeGraph`, `CurriculumCatalog`, `QuestionPresenter`, `ReviewService`, `LearnerProfiles` and `StudyPlanner`. Riverpod providers expose them. Screens, notifiers and app providers never query the database, and a layering test fails the build if they do. `lib/core` imports no widgets. There are no repository interfaces: tests run the real SQL on an in-memory database instead of mocks. An interface is added when a second implementation exists, e.g. sync. | The engineering audit asked for a repository layer (§13 item 4). Tests against real SQLite also exercise the constraints and triggers that a mock would skip. |
| DL-2 | **Migrations.** Schema version 1 is snapshotted in `drift_schemas/`, and CI fails when the snapshot or the generated code is stale. The first schema change bumps `schemaVersion`, runs `drift_dev make-migrations`, and writes the upgrade with the generated step-by-step helpers. It keeps the generated migration test, which must show that user tables survive the upgrade. | Drift generates migration tests once two versions exist (validation D-5). |
| DL-3 | **Schema changes are batched.** All schema changes planned in the backlog land together in task F2 (schema v2). No other task edits `schema.drift` while F2 runs, and later schema changes are scheduled as their own tasks. | Parallel cloud sessions editing one schema file and migration would collide. One reviewed migration is also easier to test (DL-2). |
| DL-4 | **The curriculum is split into files.** A manifest (`curriculum.yaml`) includes one file per area, pack or topic. All files form one release with one version and one checksum (V-7). | Content tasks can then run in parallel. Each touches its own file, and a version bump is a one-line change. |

---

## 13. Question system

The design is [design/question-system.md](design/question-system.md); the tasks are [backlog.md](backlog.md) groups F and Q.

| ID | Decision | Reason |
|---|---|---|
| QF-1 | **A broad catalogue, one memory.** The question system grows from recall, reverse recall and MCQ to the catalogue of question-system §2:<ul><li>typed recall, short written answers self-checked against key points (spec §T), multiple response, matching, ordering, numeric and range, label interpretation;</li><li>map and geography formats;</li><li>climate, viticulture and production reasoning; service and food-pairing scenarios;</li><li>tasting deduction, cross-domain reasoning, episodic recall.</li></ul>Every format practises canonical items and updates their FSRS state. No format has memory of its own (extends FS-2). | A curriculum whose knowledge can only be practised as flashcards does not train a candidate. One memory per fact keeps the scheduler honest across formats. |
| QF-2 | **Formats are registered in code, not in a CHECK list.** Schema v2 checks `question_templates.mode` only as an identifier. The format registry validates membership. | Adding a format needs no migration, so format tasks run in parallel (DL-3). |
| QF-3 | **One review event per graded item.** The events of a composite exercise share an `exercise_id`. Each event stores the learner's answer in `answer_payload` (JSON). | Keeps the log replayable per item (FS-4), and makes composite exercises analysable. |
| QF-4 | **Grading per format** (question-system §4):<ul><li>typed: an exact or alternative name is Good, one edit away is Hard;</li><li>numeric: exact, tolerance and outside bands;</li><li>multiple response: per item of the set;</li><li>matching: per pair;</li><li>ordering: per element, by the longest correctly ordered subsequence;</li><li>drills: per level, stopping at the first wrong level.</li></ul> | Each item gets the grade its own recall earned, not the whole exercise's. |
| QF-5 | **Reasoning chains: credit the chain, blame the target.** A right answer is Good for the primary item and for every supporting item. A wrong answer is Again for the primary item only. | The app cannot tell which link of a failed chain broke. A right answer is evidence for every link. |
| QF-6 | **Depths for the new formats** (refines CM-6):<ul><li>1: recognition (MCQ, labelled map);</li><li>2: recall and structured formats;</li><li>3: reverse recall, blank maps, drills, labels;</li><li>4: reasoning and scenarios;</li><li>5: tasting deduction and cross-domain reasoning.</li></ul> | Gives CM-6's reserved depths 4–5 their meaning. WSET Level 3 core items that need application are mapped at depth 4. |
| QF-7 | **Presentation difficulty ladder** (question-system §5). The format follows the item's stability: recognition while it is new, then recall and structured formats, then spatial and reverse, then reasoning and the hardest map modes. It never repeats the last format when another is served, and one presentation in five is a random draw. Thresholds are provisional. | Desirable difficulty: harder formats as memory strengthens. Supersedes FS-15's random draw. |
| QF-8 | **Closed-world safeguards.**<ul><li>Formats that assert absence (multiple response, "tap all", odd one out) need a `relation_set_assertions` row citing a complete list.</li><li>Rankings use reified statistic nodes from a dated survey.</li><li>Single-answer questions accept any node correct in any period.</li><li>Reasoning distractors must violate a stated principle.</li></ul> | A missing relation is not a false statement (QG-11). |

---

## 14. Coverage

| ID | Decision | Reason |
|---|---|---|
| COV-1 | **Coverage model.** For each track, domain and area, the checker compares:<ul><li>*capability*: the format families each relation type should support, declared in `coverage_policy.yaml`;</li><li>*availability*: the questions and pools generated, filtered by `minimum_depth`.</li></ul>It reports testable, flashcard-only and useful-practice items, family counts and gaps (question-system §8). | Answers which items are testable, by which formats, and where core areas lack practice, per domain and certification profile. |
| COV-2 | **Useful practice** is at least one objective format and at least two families. **Flashcard-only** means the self-graded flashcard is the only served format. | Makes "no boring or missing practice" measurable. |
| COV-3 | **Staged enforcement.**<ol><li>F1: a committed baseline and a ratchet. No metric may fall, and no new core item may be flashcard-only.</li><li>Each format task adds its capabilities and raises the baseline.</li><li>R3: the policy thresholds become a release gate.</li></ol> | Enforceable from now, without blocking today's dataset, and strict by release. |
| COV-4 | The policy and baseline files are authored with the dataset and versioned with it. The first thresholds are provisional. | Coverage is a property of content, so it is reviewed with content. |

---

## 15. Geography

The design is [design/geography.md](design/geography.md); the tasks are [backlog.md](backlog.md) group G. Licensing questions are [legal-review.md](legal-review.md) L-15 to L-23.

| ID | Decision | Reason |
|---|---|---|
| GEO-1 | **Map questions are formats of canonical items.** Tapping Chablis, identifying it when highlighted, and answering "In which region is Chablis?" all update `ki_chablis_location`. | One fact, one memory (FS-2). The user asked for this explicitly. |
| GEO-2 | **Geometry attaches to nodes.** `map_layers` and `node_geometries` (schema v2) reference `knowledge_nodes`. There is no separate geography database. | Keeps geography inside the knowledge graph, with its validity and provenance. |
| GEO-3 | **Offline vector maps.** Geometry ships as TopoJSON assets in the app bundle. There are no tile servers, and no Google Maps or other paid or online service. | Offline-first (spec §M). No running costs or third-party terms. |
| GEO-4 | **Depth follows relevance.** A node is askable, and drawn in full, only if the active track maps items about it. Finer layers appear on zoom. Vineyard-level shapes exist only where a track or pack maps them. | Avoids mapping every vineyard, and keeps each track's maps focused. |
| GEO-5 | **Open-licensed sources only.** Public domain, CC0, CC BY, Licence Ouverte and dl-de/by. Excluded: non-commercial data (Eurostat GISCO), share-alike data (OpenStreetMap), and map artwork. | A proprietary app may redistribute these, with attribution where required. |
| GEO-6 | **The location item rule.** Every map-enabled node has one location item: `LOCATED_IN` to its parent, or `FLOWS_THROUGH` for a river. The validator enforces it. | Map questions need an item to grade. |
| GEO-7 | **Coordinates stay in the assets.** The database holds only bounding boxes, label points and feature keys, verified against the asset's SHA-256 at ingestion. | SQL needs frames and orderings, not megabytes of coordinates. |
| GEO-8 | **Four difficulty modes**: labelled, outline, minimal, and blank zoomed out. The ladder (QF-7) chooses among them within the served depths. | Progressive blank-map practice, as requested. |
| GEO-9 | **Point fallback.** Without an open shape, a node is drawn as a point from an open gazetteer or municipal boundary. Nothing is drawn by hand from copyrighted maps. | Lets geography grow where open shapes do not exist yet. |
| GEO-10 | Appellation areas built from communes are the legal geographical areas, larger than the delimited vineyards, and the map legend says so. | An honest approximation. |
| GEO-11 | **Budgets:**<ul><li>geography assets at most 8 MB in V0.1, and at most 1.5 MB per layer;</li><li>a layer parses in at most 100 ms on a mid-range phone;</li><li>a frame paints in at most 8 ms after warm-up.</li></ul> | App size and smoothness (spec Phase 6). |
| GEO-12 | **Custom renderer:** `CustomPainter` in an `InteractiveViewer`, with the geometry core in pure Dart. `flutter_map` 8.3.2 (BSD-3-Clause) is the fallback. | Quiz maps need exact control of what is drawn and named, and deterministic hit tests. They need none of `flutter_map`'s tile and network dependencies. |
| GEO-13 | Every map question has a non-visual answer mode (a list of names). Colours are safe for colour-vision deficiency, and outcomes are marked by icon. | Accessibility. |
| GEO-14 | Every map shows the attributions of its visible layers. *Settings → About → Data sources* lists every dataset with its licence. | Licence Ouverte, dl-de/by and CC BY require attribution. |

---

## 16. Study packs

The design is [design/study-packs.md](design/study-packs.md); the tasks are [backlog.md](backlog.md) group P.

| ID | Decision | Reason |
|---|---|---|
| PK-1 | **No code specific to one pack.** A pack is data (items, mappings, coverage policy) plus tests. A test fails if a pack ID appears in `lib/`. | A pack is a vertical built on the generic system, as requested. |
| PK-2 | **A pack is a track.** `certifications.kind` is `certification` or `pack` (schema v2). Packs use the same mappings, importance and `minimum_depth`, up to 5. | Reuses the planner, effective mappings and coverage by profile unchanged. |
| PK-3 | **One active track at a time.** Switching keeps memory (FS-12). Studying several tracks at once, with a merged queue, is a later extension. | Simple now, and pack study still strengthens the shared certification items. |
| PK-4 | Each pack has its own section in the coverage policy, stricter than a certification's. | Deep verticals must not be flashcard decks. |
| PK-5 | **Competition training is generic session modes over pack content.** The modes are focused, timed drill and exam-style (task S1). | No competition-specific code. |
