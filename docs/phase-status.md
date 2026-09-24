# Phase Status

| | |
|---|---|
| **Roadmap** | Product specification §O (phases 0–6), backlog §P (TASK-001 to TASK-010) and validation strategy §S |
| **Decisions applied** | [architecture-audit.md](architecture-audit.md) (the decision register) and [domain-model.md](domain-model.md) |
| **Audit baseline** | Commit `ad0f369` (end of Phase 0) |

Each phase lists its acceptance criteria: the spec's own, plus the gates the decision register adds. **Status at audit** is the state of the repository at the baseline commit. **Status now** is the state after the work recorded in the last column.

✅ satisfied · ◐ partly satisfied · ❌ missing

---

## Phase 0: Repository and schema bootstrap

**Complete.** Flutter 3.47.5, Riverpod 3 and Drift 2.35. The canonical schema has 31 tables, and 84 tests pass (CRUD on every table, plus the domain-model guarantees). CI is green on Android, iOS and web. See [Xaiando/Mobile#1](https://github.com/Xaiando/Mobile/pull/1).

---

## Phase 1: Database and curriculum ingestion

Spec §O: *"Build YAML/JSON parser to ingest the seed dataset. Implement relational JOIN queries simulating graph traversal."* Acceptance: *"Seed dataset successfully hydrates the local database on initial launch."*

| ID | Criterion | Source | Status at audit | Status now |
|---|---|---|---|---|
| P1-1 | Relational tables for the curriculum graph, with foreign keys | §O, TASK-001 | ✅ Phase 0 schema: 31 tables, composite FKs, `PRAGMA foreign_keys = ON` | ✅ |
| P1-2 | The curriculum is read-only outside ingestion; ingestion is one transaction | Register §3.2, V-7 | ✅ Guard triggers and `writeCurriculum` (tested) | ✅ |
| P1-3 | A release table recording the dataset version and checksum | V-7 | ✅ `curriculum_releases` in the schema | ✅ |
| P1-4 | A YAML parser for the canonical dataset format: section = table, key = column | §O, TASK-002, DM-2, domain model §7 | ❌ | ✅ `CurriculumDataset.parse` (`lib/core/curriculum/curriculum_dataset.dart`) rejects unknown sections and columns, missing required columns and malformed dates |
| P1-5 | A bundled dataset asset in the canonical format | TASK-002, §Q | ❌ Only a test fixture (16 nodes, 13 relations) | ✅ [`assets/curriculum/curriculum.yaml`](../assets/curriculum/curriculum.yaml), release 0.1.0 |
| P1-6 | The dataset hydrates the local database on initial launch | §O acceptance, TASK-002 | ❌ Startup opens the database only | ✅ `appStartupProvider` ingests the bundle before the app is ready; shell test *hydrates the bundled curriculum on first launch* |
| P1-7 | At least 50 nodes and 50 relations after initialization | TASK-002 acceptance, register §4 | ❌ | ✅ 65 nodes, 87 relations and 46 items; asserted by the ingestion test and the web smoke test |
| P1-8 | Re-ingestion when the bundled version is newer: authored rows upserted, never deleted; generated tables rebuilt; user data untouched | V-7, domain model §2 | ◐ Upsert proven in the spike; the app has no ingestion service | ✅ `CurriculumIngester`: install, upgrade, refresh on a changed checksum, keep a newer release, refuse removals; user history kept (tested) |
| P1-9 | A validator for the dataset (§3.3 rules): relation signatures, acyclic prerequisites, `LOCATED_IN` and certification chains, `cardinality = one`, citations and mappings on every item, regulatory citations, no authored row removed between releases, `name_norm` | Register §3.3, TASK-010 | ❌ | ✅ `validateDataset`: every §3.3 rule except the question rules, which Phase 2 adds; one negative test per rule |
| P1-10 | `name_norm` computed in Dart: lower case, no diacritics, no appellation suffix | Register §10 | ❌ | ✅ `normalizeName`, identical on native and web (tested) |
| P1-11 | Dangling-edge detection (§S.1): relations must reference existing nodes | §S.1, TASK-010 | ◐ Enforced by FKs in the schema; no test in the app suite; no build-time check on the dataset | ✅ Validator rule `dangling-relation`, plus a database test that the FK rejects a dangling relation |
| P1-12 | DAG integrity (§S.2): no item is its own prerequisite, directly or through a cycle | §S.2, TASK-010 | ◐ Self-reference blocked by a CHECK (untested in the app); no recursive cycle query | ✅ Validator rule `cycle`, the recursive query `prerequisiteCycles()` (finds a 3-item cycle in its test), and a test of the self-reference CHECK |
| P1-13 | Relational JOIN queries simulating graph traversal (ancestors, descendants, a node's relations) | §O | ❌ Proven in the spike only | ✅ `KnowledgeGraph`: ancestors, descendants, siblings, a node's relations and prerequisite chains, as recursive CTEs over the current date |
| P1-14 | Version-expiry and staleness checks (§S.4): expired relations and items not re-verified for 24 months | §S.4, V-2, V-4, P-1 | ❌ | ✅ `expiredItems()` and `staleItems()` (tested). Showing them to the learner is Phase 3 UI |
| P1-15 | Seed content requirements: all 8 certification rows with their chains, a citation per item from a primary source, the spec's example appellations, a prerequisite DAG, quantity nodes, templates for every relation that carries an item | Register §4, D3 | ❌ | ✅ Every requirement in register §4 except the V0.1 content volume (see P1-16) |
| P1-16 | Content drafted from public primary sources, marked `unverified` | D3, D10 | ❌ | ✅ 46 items drafted from 14 INAO and MASAF legal texts, all `unverified` until expert review (the review and the 150-item V0.1 volume of P-6 are content work, not Phase 1 criteria) |
| P1-17 | Ingestion works on the web as well as native | Register §10, D5 | ❌ The web smoke test covers the database only | ✅ The web smoke test ingests the bundle in Chromium, with and without COOP/COEP |
| P1-18 | CI green | Phase 0 practice | ✅ | ✅ [CI run for `db25d15`](https://github.com/Xaiando/Mobile/actions/runs/36002138687): Android, iOS, web and tests |

**Result:** every Phase 1 criterion is met. The bundled dataset hydrates the database on first launch, on native platforms and in Chromium, and the validator, ingestion and traversal queries are tested (68 new tests).

---

## Phase 2: Question engine

Spec §O: *"QuestionTemplate, QuestionGenerator. String templating and distractor selection logic."* Acceptance: *"Engine dynamically generates a 4-option multiple-choice question without duplicate distractors."*

| ID | Criterion | Source | Status at audit | Status now |
|---|---|---|---|---|
| P2-1 | `QuestionTemplate`, `Question` and `QuestionDistractor` tables; the template must match the item's relation type | §D, QG-9 | ✅ Phase 0 schema (tested) | ✅ |
| P2-2 | String templating with `{subject.name}`, `{object.name}` and `{object.type_label}` | §H, QG-2 | ❌ | ✅ `renderPrompt` (`lib/core/questions/template_renderer.dart`); 20 templates in the dataset |
| P2-3 | Distractors from graph traversal: the subject's geographic scope first, widened step by step; same node type; matching berry colour | §H, TASK-004, QG-4 | ❌ | ✅ `QuestionGenerator.distractorPool`: Drift queries over the subject's scopes, then the relation, then the type (QG-12); colour and unit filters. Tests replay §R Q1 and §H |
| P2-4 | No distractor is a correct answer in any validity period, and none repeats a correct answer's name | QG-4, QG-5 | ❌ | ✅ Every correct answer in any period is excluded, and so is any name that normalizes to one; tested on every generated distractor |
| P2-5 | Exactly 4 options, or fall back to a flashcard | QG-6, §O acceptance | ❌ | ✅ MCQ only with at least 3 distractors, else a flashcard; the presenter always shows 4 options |
| P2-6 | Formats: forward and reverse × flashcard and MCQ; reverse only when the relation is reverse-safe or the item distinctive | §N, QG-1, QG-3 | ❌ | ✅ Forward and reverse × flashcard and MCQ; reverse for the distinctive Barolo and Barbaresco ageing items only |
| P2-7 | Questions generated during ingestion as read-only curriculum, with rebuilds never touching user history | QG-9 | ◐ The rebuild is tested against the fixture; no generator | ✅ Generated inside the ingestion transaction; regeneration is idempotent and leaves review history intact (tested) |
| P2-8 | A fresh seed per presentation, with deterministic results for a given seed | QG-7 | ❌ | ✅ `QuestionPresenter.present(seed:)`: the same seed gives the same options and order; fresh seeds vary them (QG-13) |
| P2-9 | Distractor viability (§S.3): every MCQ question has at least 3 valid distractors; every item has an MCQ question or is marked `mcq_disabled` | §S.3, TASK-010, register §4 | ❌ | ✅ 91 questions (43 MCQ, 48 flashcards); the §S.3 gate test passes: every item has an MCQ or is `mcq_disabled` (QG-14) |
| P2-10 | CI green | Phase 0 practice | | |

**Result:** the spec's acceptance criterion holds. The test *Phase 2 acceptance* presents each of the 43 generated MCQs with 25 seeds. Every presentation has 4 options: the answer and 3 distractors, with no duplicate node or name among them. In Chromium the web smoke test generates the same 91 questions and presents one MCQ.

---

## Phase 3: FSRS and study engine

Audited after Phase 2.
