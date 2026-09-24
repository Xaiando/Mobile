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
| P1-9 | A validator for the dataset (§3.3 rules): relation signatures, acyclic prerequisites, `LOCATED_IN` and certification chains, `cardinality = one`, citations and mappings on every item, regulatory citations, no authored row removed between releases, `name_norm` | Register §3.3, TASK-010 | ❌ | ✅ `validateDataset` checks the rules that need only the dataset, with one negative test per rule. The ingester refuses removed rows by comparing against the database, and Phase 2 adds the question rules |
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
| P2-10 | CI green | Phase 0 practice | | ✅ [CI run for `429dea7`](https://github.com/Xaiando/Mobile/actions/runs/36003105676): Android, iOS, web and tests |

**Result:** the spec's acceptance criterion holds. The test *Phase 2 acceptance* presents each of the 43 generated MCQs with 25 seeds. Every presentation has 4 options: the answer and 3 distractors, with no duplicate node or name among them. In Chromium the web smoke test generates the same 91 questions and presents one MCQ.

---

## Phase 3: FSRS and study engine

Spec §O: *"ReviewState, ReviewEvent. Integrate fsrs package. Build the Score_priority algorithm."* Acceptance: *"Flashcard answers correctly update DSR variables and reorder the study queue."* The backlog adds TASK-003 (a spaced-repetition service), TASK-005 (an adaptive queue of the top 15 items), TASK-006 (the Home dashboard) and TASK-007 (the flashcard and MCQ widget). **Status at audit** is the state after Phase 2 (commit `214009a`).

| ID | Criterion | Source | Status at audit | Status now |
|---|---|---|---|---|
| P3-1 | `ReviewState`, `ReviewEvent`, `ReviewEventOption` and `SchedulerConfig` tables with their invariants | §D, FS-4, FS-8 | ✅ Phase 0 schema: append-only log, step coupling, `lapses < reps`, 21-weight check (tested) | ✅ The step-coupling CHECK caught a real bug during Phase 3: an upsert that dropped NULL columns |
| P3-2 | FSRS-6 via the `fsrs` package; a stored state round-trips exactly; the projection equals a replay of the log | FS-1, FS-4 | ◐ Proven by a test only; `fsrs` was a dev dependency | ✅ `fsrs` is an app dependency. Tests: *stores exactly the D, S and due date the package computes* and *review_states equals a replay of review_events* |
| P3-3 | Scheduler configuration version 1 seeded on first launch (weights, 0.9 retention, steps, fuzzing) | FS-8 | ❌ Only a test fixture seeds it | ✅ `appStartupProvider` seeds version 1, and the review service ensures it too; every event records its version |
| P3-4 | Certification profile: the one-row `user_profiles`, with `WSET_L3` or `CMS_CERTIFIED` chosen by the learner | §N, CM-1, CM-9 | ❌ No profile row or picker | ✅ `LearnerProfiles` plus a track picker on Home, Practice and Study; other tracks are refused; switching keeps memory state (FS-12, tested) |
| P3-5 | Spaced-repetition service (TASK-003): grade an item 1–4, write the event and the projected state in one transaction, count lapses | TASK-003, FS-3, FS-6, FS-7 | ❌ | ✅ `ReviewService`: one transaction per review; a failed write leaves nothing; `reps` and `lapses` counted as FS-7 defines them (tested) |
| P3-6 | MCQ grading (wrong 1, right 3) and self-graded flashcards; each review logs its seed and the options shown | FS-6, QG-7 | ◐ The presenter produces the seed and options; nothing logged them | ✅ `answerMultipleChoice` and `gradeFlashcard`; seed, options in display order, the choice and the response time are logged (tested) |
| P3-7 | The effective mapping per track: the nearest mapping along the chain; unmapped items excluded; `minimum_depth` picks the formats | CM-3, CM-4, CM-6 | ◐ Mappings and chains ingested; nothing resolved them | ✅ `StudyPlanner.effectiveMappings` (recursive CTE over the chain) and `servedFormats` (A-10); tests cover the chain, the exclusion and the depths |
| P3-8 | Priority score `U^α·C^α·L^α·P^α`: R from the package, SQL to select candidates, scoring in Dart | §G, A-1, A-3, A-6 | ❌ | ✅ `Priority.of` with the provisional weights of A-7; R from `getCardRetrievability`; a test proves every exponent can change the ranking |
| P3-9 | Prerequisite factor P from reviewed dependents | A-4 | ◐ Chains traversable upward only | ✅ `KnowledgeGraph.dependentsOf` and `prerequisiteClosure`; P from the weakest reviewed dependent, with a lapse counting as forgotten (A-8) |
| P3-10 | Session of 15 items: due reviews by score, then at most 5 new items, core items and prerequisites first; learning steps re-queued | TASK-005, A-2, FS-11, FS-14, FS-15, P-4 | ❌ | ✅ `StudyPlanner.plan` and `StudySession`: learning steps first (A-9), then reviews by score; new items fill only the room left, never before their prerequisites; a card on a step comes back in the same session (tested) |
| P3-11 | Expired and superseded items leave the queue; stale and unverified items get a badge | FS-13, V-3, V-4, P-5 | ◐ The queries existed; no queue | ✅ The queue uses items current on today's date; an expired item keeps its state and is listed on Home as "the rules changed". Practice and Study show *Unverified* and *May be out of date* badges |
| P3-12 | Study UI: flashcard and MCQ widgets whose answers grade the item and advance the queue | TASK-007 | ❌ Placeholder screens | ✅ Practice: MCQ options marked right and wrong by icon as well as colour, explanations, flashcard reveal and Again, Hard, Good or Easy. Study lists the track by topic with each item's state and sources |
| P3-13 | Home dashboard: due reviews, retention, and a button that starts a session | TASK-006 | ❌ Placeholder screen | ✅ Track picker, due and new counts, 30-day retention (FS-16), items studied, and a *Start session* button; a non-affiliation disclaimer (L-1) |
| P3-14 | Acceptance: a flashcard answer updates D, S and R and reorders the queue | §O | ❌ | ✅ *flashcard answers update D, S and R and reorder the study queue* (see below) |
| P3-15 | Works on the web as well as native | D5 | ❌ | ✅ The web smoke test picks a track, plans a session and answers a card in Chromium; the memory state round-trips exactly |
| P3-16 | CI green | Phase 0 practice | | ✅ [CI run for `b90fb51`](https://github.com/Xaiando/Mobile/actions/runs/36011387862): Android, iOS, web and tests |

**Result:** the spec's acceptance criterion holds. In the test *flashcard answers update D, S and R and reorder the study queue*, a learner studies five WSET Level 3 items and forgets *Barolo requires 38 months of ageing* (Again) thirty days later. The stored difficulty, stability and due date equal what FSRS-6 computes for that answer. R, recomputed by the package, is 1 just after the answer and fades faster than before. And the queue reorders. The forgotten item waits for its 10-minute relearning step. Its prerequisites, Barolo's grape and location, overtake the item that led the queue. When the step is due, the item leads the queue, and a Good answer raises stability and takes an item out of it. 61 tests were added (238 in total), including five widget tests of the Home, Practice and Study flow and a test that ending a session while an answer saves does not bring it back.

---

## After Phase 3

The spec's Phases 4–6, the question formats beyond recall and MCQ, geography as a map-based study domain, the coverage checker and study packs are planned as 45 tasks in [backlog.md](backlog.md). Each task records its acceptance evidence in the backlog's status column.
