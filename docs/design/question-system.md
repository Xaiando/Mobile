# Question System and Coverage

| | |
|---|---|
| **Status** | Design for the tasks in [backlog.md](../backlog.md) groups F and Q. Decisions are registered in [architecture-audit.md](../architecture-audit.md) §13 and §14. |
| **Builds on** | FS-2 (one memory state per item), QG-1 to QG-14 (generation), CM-6 (`minimum_depth`), A-1 to A-10 (the study queue) |
| **Companions** | [geography.md](geography.md) (map formats), [study-packs.md](study-packs.md) (packs) |

The app already asks three kinds of question: flashcard recall, reverse recall and four-option multiple choice. They are enough to prove the engine but too few to train a candidate. With only these, most facts could end up practised only as a flashcard. This design widens the question system while keeping one rule: **every question, whatever its format, practises canonical knowledge items and updates their FSRS state.** No format creates memory of its own.

---

## 1. Vocabulary

| Term | Meaning |
|---|---|
| **Item** | A `KnowledgeItem`: one testable relation, and the unit of FSRS memory (FS-2). |
| **Format** | How a question is put and answered. A format has a prompt modality, an answer modality, a direction and an arity. |
| **Format family** | A group of formats that train the same skill: *recall*, *recognition*, *spatial*, *structured* or *reasoning* (§3). |
| **Exercise** | One presentation. A *single-item* exercise practises one item. A *composite* exercise (matching, ordering, multiple response, drills, reasoning chains) practises several. |
| **Template** | The authored phrasing of a format for a relation type (`question_templates`), in English for V0.1 (QG-2). |
| **Pool** | Generated candidates from which a presentation draws with a seed: distractors for an MCQ (QG-13), pairs for a matching exercise, elements for an ordering. |

---

## 2. Format catalogue

The **depth** column refines CM-6, and audit QF-6 records it. A track serves a format for an item only when the item's effective `minimum_depth` reaches it. The fallback of A-10 still guarantees that a mapped item is never unreachable.

| ID | Format | Family | Prompt → answer | Items practised | Prerequisites in the data | Depth | Status |
|---|---|---|---|---|---|---|---|
| `flashcard` | Simple recall | recall | text → self-graded reveal | 1 | a template | 2 | built |
| `mcq` | Multiple choice | recognition | text → 1 of 4 options | 1 | ≥ 3 valid distractors (QG-12) | 1 | built |
| *reverse* | Reverse recall | recall / recognition | the object asks for the subject | 1 | reverse-safe or distinctive (QG-3) | 3 | built for flashcard and MCQ |
| `typed` | Typed recall | recall | text → typed answer, graded by name matching | 1 | answer names and alternative names | 2 | Q1 |
| `short_answer` | Short written answer (spec §T) | recall | an "explain" prompt → free text, then a self-check against key points | 2–4, one per key point | key points that are items (principles, facts) | 4 | Q1 |
| `multiple_response` | Select all that apply | recognition | text → any number of options | all items of one complete set | a completeness assertion (§6) | 2 | Q2 |
| `matching` | Matching | structured | two columns → pairs | 3–5 | a pool of items sharing a relation type in a scope | 2 | Q3 |
| `ordering` | Ordering | structured | list → order | 3–6 | an order key: tier chain, process chain, quantity or latitude | 2 | Q3 |
| `numeric` | Numeric or range answer | structured | text → number and unit | 1 | a quantity object with a unit and tolerance | 2 | Q4 |
| `label` | Label interpretation, wine-list error spotting | structured | synthetic label or list → MCQ, typed or tap | 1–3 | label-term items and a label layout | 3 | Q5 |
| `map_*` | Map and geography formats | spatial | see [geography.md](geography.md) §4 | 1–n | geometry for the answer or prompt node | 1–3 | G4–G9 |
| `reasoning` | Climate, viticulture and production reasoning | reasoning | premise → most plausible consequence | chain of 2–3 | principle relations reachable from the item (§7) | 4 | Q6 |
| `scenario` | Service and food-pairing scenarios | reasoning | situation → best action or wine | chain of 1–3 | service or pairing principles (§7) | 4 | Q7 |
| `tasting_deduction` | Tasting deduction | reasoning | structured tasting note → grape, region, climate, age | 2–5 | style-profile relations for the candidates | 5 | Q8 |
| `cross_domain` | Cross-domain reasoning | reasoning | a chain across ≥ 2 domains | 3–5 | a path across domains in the graph | 5 | Q9 |
| `episodic` | Episodic recall from the journal | recall | "the Barolo you tasted in May…" → answer | 1 | a journal entry linked to the item's nodes | 2 | J3 |

**Not planned:**

- true/false, since half the answers are guesses;
- machine-graded essays, since there is no reliable offline grading, and paid AI APIs are deferred by §N and §T (short answers are self-checked instead);
- image identification, since V0.1 has no licensed images.

---

## 3. Families and useful practice

| Family | Trains | Graded | Formats |
|---|---|---|---|
| recall | producing an answer from memory | self-graded or objective | flashcard, typed, short answer, episodic, reverse recall |
| recognition | choosing among plausible answers | objective | MCQ, multiple response, map identify |
| spatial | knowing where things are and how places relate | objective | every `map_*` format |
| structured | relations among several facts, quantities and terms | objective | matching, ordering, numeric, label |
| reasoning | applying principles to reach a conclusion | objective | reasoning, scenario, tasting deduction, cross-domain |

A format is **objective** when the app grades it; only the flashcard and the short written answer are self-graded.

**Useful practice** for an item means at least one objective format *and* at least two families. The coverage checker (§8) measures both. An item whose only served format is the flashcard is **flashcard-only**, the state this design exists to prevent.

---

## 4. Grading and FSRS attribution

Every graded item gets exactly one `review_events` row, whichever format produced it. Rows from one composite exercise share an `exercise_id`. Each row stores the format's answer in `answer_payload` (JSON): the options chosen, the order given, the number typed, or the coordinate tapped. Audit QF-3 to QF-5 record these rules.

| Format | Graded per | Rule |
|---|---|---|
| flashcard | item | The learner grades 1–4 (FS-6). |
| short answer | each key point's item | After writing, the learner ticks the key points the answer covered. Ticked is Good; not ticked is Again. The text is stored in `answer_payload` and is never machine-graded in V0.1 (spec §T). |
| MCQ, map identify, map locate | item | Right is Good; wrong is Again (FS-6). |
| typed | item | An exact match after `normalizeName`, or an alternative name, is Good. One edit away on the normalized form is Hard. Anything else is Again. |
| numeric | item | Within the template's exact band is Good, within the tolerance band is Hard, outside is Again. Legal minima are exact. A range answer is right when it falls inside the stated range. |
| multiple response | each item of the set | A correct option selected is Good, or Hard if the learner also selected a wrong option. A correct option missed is Again. |
| matching | each pair's item | A right pair is Good; a wrong pair is Again. |
| ordering | each element's item | Elements in the longest correctly ordered subsequence are Good; the rest are Again. |
| drill (map hierarchy) | each level's item | Each tap is graded as a map locate. The drill stops at the first wrong level, and deeper levels are not graded. |
| reasoning, scenario, cross-domain | the chain | **Credit the chain, blame the target.** A right answer is Good for the target (primary) item and for every supporting item. A wrong answer is Again for the primary item only, because the app cannot tell which link failed. |
| tasting deduction | the chain | Same as reasoning. The primary items are the style markers that separate the correct answer from the distractor chosen. |

Two further rules apply:

- A composite exercise never grades the same item twice.
- Items in an exercise that were not due are still graded, because FSRS handles early reviews through elapsed time (FS-9). Pools prefer due and new items when they draw co-items, so composite exercises do not inflate early reviews.

---

## 5. Presentation difficulty ladder

FS-15 lets later presentations draw a served format at random. The ladder (QF-7) replaces that draw: the format follows the item's stability S, within the formats the track serves.

| Stability | Preferred families | Example for *Chablis is located in Burgundy* |
|---|---|---|
| New or on a learning step | recognition | MCQ, or a labelled map of Burgundy's appellations |
| S < 7 days | recall, structured | typed recall, or an outline map without labels |
| 7 ≤ S < 30 days | spatial, structured, reverse | a blank map, or a hierarchy drill |
| S ≥ 30 days | reasoning and the hardest spatial modes | a blank map zoomed out to France; map deduction |

Two variety rules apply: never repeat the item's last format when another is served, and once in five presentations pick at random from the served formats so the ladder does not overfit. The thresholds are provisional, like the weights of A-7.

---

## 6. Closed-world safeguards

A missing relation does not make a statement false (QG-11). Formats that assert *absence* need explicit support (QF-8):

- **Completeness assertions.** Multiple response, "tap all" maps and odd-one-out need a `relation_set_assertions` row. It states that the objects recorded for (subject, relation type) are the complete set on that date, and cites the source. Example: the Champagne cahier des charges lists seven permitted varieties, so a multiple-response question may ask for all seven.
- **Ranked statistics.** Questions such as "the most important regions for Spätburgunder" use reified statistic nodes (`n_stat_*`) holding a planted area or a share, from a cited survey with a survey date. They never rely on a missing relation.
- **Any correct answer counts.** A single-answer question accepts every node that satisfies the relation in any validity period. The same rule excludes such nodes as distractors (QG-4).
- **Reasoning distractors violate a stated principle.** Absence from the graph alone never qualifies a wrong answer.

---

## 7. Principles: the knowledge behind reasoning formats

Reasoning, scenario and deduction questions need general knowledge as well as appellation facts. It is modelled with the same nodes and relations, cited like any other fact:

| Principle kind | Example relation | Node types |
|---|---|---|
| Climate → style | *cool climate* `TENDS_TO_PRODUCE` *high acidity* | `climate`, `style_trait` |
| Geography → climate | *Alsace* `SHELTERED_BY` *Vosges* (rain shadow) | see [geography.md](geography.md) §2 |
| Viticulture | *spring frost* `MITIGATED_BY` *aspersion (sprinklers)* | `hazard`, `viticultural_practice` |
| Production | *malolactic conversion* `REDUCES` *malic acidity*; `PRODUCES` *diacetyl (buttery) notes* | `winemaking_method`, `style_trait` |
| Service | *aged red wine with sediment* `CALLS_FOR` *decanting off the sediment* | `wine_style`, `service_action` |
| Food pairing | *high-acid wine* `BALANCES` *rich, fatty dishes* | `wine_trait`, `food_trait` |
| Tasting style profile | *Spätburgunder from the Ahr* `TYPICAL_ACIDITY` *medium+* | `style_trait` values from the tasting lexicon (T1) |

A reasoning template names a path pattern, for example `region –HAS_CLIMATE→ climate –TENDS_TO_PRODUCE→ style_trait`. The generator enumerates the paths that match. The item on the last edge is the **primary** item, and the items on the other edges are **supporting**. Distractors are traits that the principles attach to contrasting premises, such as the styles of a warm climate.

Principles come from public, citable sources (government publications, academic papers, extension services). They never come from WSET or CMS materials (D10). Service scenarios use general hospitality practice, never the CMS service standards (legal review L-17).

---

## 8. Coverage checker

### Questions it answers

For each track (certification or pack) and each curriculum domain:

1. Which items are **testable**, meaning the track serves at least one format for them?
2. Which formats **can** test each item (capability) and which formats **do** (the generated questions and pools)?
3. Which core curriculum **areas** lack useful practice?

### Model

- **Capability** is declared per relation type: the format families that relation *should* support, with a reason for each exclusion. The first version lives in `assets/curriculum/coverage_policy.yaml`, and dataset validation checks that every relation type is listed. A capability exists only when its data prerequisites hold (§2).
- **Availability** is computed after ingestion: the formats for which the generator produced a question or a pool containing the item, filtered by the track's `minimum_depth`.
- **Areas** group items by domain and by their subject's top-level geographic ancestor (a country, or a region for France and Italy). Non-geographic items are grouped by the principle kind of §7.
- **Metrics** for each track, domain and area:
  - items, core items and testable items;
  - flashcard-only items;
  - items with useful practice (§3);
  - items per family;
  - spatial coverage of geography items that have geometry;
  - reasoning coverage of core items.

### Policy and enforcement

`coverage_policy.yaml` holds the thresholds for each track and domain. The enforcement stages are audit COV-3 and COV-4:

| Stage | Task | Enforced |
|---|---|---|
| 1. Report and ratchet | F1 | A committed `coverage_baseline.json`; the build fails if any metric falls below it. A new core item that is flashcard-only fails the build. |
| 2. Policy for formats built | each Q and G task | The task adds its format's capability rows and raises the baseline. |
| 3. Release gate | R3 | The policy thresholds themselves must pass: no core item flashcard-only; at least 90 % of core items with useful practice; spatial formats for core geography items that have geometry; reasoning formats for at least half of the core items in the viticulture, winemaking, service and tasting domains. The numbers are provisional and set in the policy file. |

### Output

- `dart run tool/coverage_report.dart --track WSET_L3 --format md` prints the matrix and the gap list. `--format json` prints the same for tools.
- A test runs the checker on the bundled dataset for every selectable track and pack and applies the policy.
- The generation report of QG-14 gains a coverage section, so authors see gaps as they write content.

A learner-facing *curriculum coverage* metric (spec §N, "how much of the track have I studied") is a separate Phase 6 analytics view (task S2). It reuses the checker's grouping.

### As built (F1)

**Code layout.**

- `lib/core/coverage/`:
  - `coverage_formats.dart`: the catalogue of built formats, with family and objectivity. F3 moves it into the format registry.
  - `coverage_policy.dart`: the policy.
  - `coverage_checker.dart`: the checker.
  - `coverage_model.dart`: the metrics and gaps.
  - `coverage_baseline.dart`: the ratchet.
- `tool/coverage_report.dart` prints the report.
- `assets/curriculum/coverage_policy.yaml` and `coverage_baseline.json` sit beside the manifest and are not bundled.

**Served formats.** The checker reads an ingested database and serves formats exactly as the study planner does:

- effective mappings (CM-3);
- `StudyPlanner.servedFormats`, which applies the depths of CM-6 and the fallback of A-10.

Only items in force that the track maps are counted (CM-4). A reverse question counts in its format's family.

**Capabilities are declared per format, not per family.** For each relation type, every built format is either under `supports` or under `excludes` with a reason. A format task therefore adds one line per relation type, as stage 2 above says. An expected format that produced no question is listed with the generator's reason: `mcq_disabled`, too few distractors, not reverse-safe, or no template.

**Areas.**

- The policy's `regional_countries` (France and Italy) are split by region. Every other country is one area.
- A place that should lie inside another but reaches no country is *unplaced*.
- An item whose subject is not a place is counted under the subject's node type, until the principle kinds of §7 exist.

**Metrics.** They are counts of items, taken for the whole track, each domain and each area:

- `items`, `core`, `testable`;
- `flashcard_only`, `useful_practice`;
- one metric per family;
- `core_flashcard_only`, `core_useful_practice`, `core_reasoning`.

The spatial coverage of items with geometry waits for G2.

**Gaps.**

- *Blocking gaps*, which fail the build unless the baseline lists them:
  - an untestable item;
  - a flashcard-only item, at any importance (COV-6).
- *Reported gaps*:
  - a core item without useful practice;
  - an expected format that produced no question.

**Ratchet.** The ratchet (COV-3) compares every metric where more is better, at every level. A fall fails the build; a rise passes and suggests raising the baseline. `--update-baseline` rewrites the metrics and keeps the known gaps that are still open.

**Measurement date.** Coverage is measured on the release's publication date, with the questions generated for that date (COV-5).

**Where the policy is enforced.**

- The checker refuses a policy that leaves out a relation type the release has, or names one it lacks.
- `tool/curriculum/lint.dart` reports the same mismatch.
- `tool/curriculum/report.dart` ends with each track's coverage summary.

**Thresholds.** They are parsed and measured on every track and domain, and shown in the report. R3 makes them a gate.

### Scope objectives (SCOPE-1)

The coverage report also measures each track against its official scope, as the research audit asks. `assets/curriculum/track_scope.yaml` pins each track to one body's document and version (CM-10). It lists the scope's objectives as editorial IDs with labels in our own words (L-27): 42 for WSET Level 3 and 31 for CMS Europe Certified.

An objective is accounted for by `covers`, which selects items by domain, place, relation type or node type; by `tasks`, which plan it; or by `excluded`, with a reason (COV-7). The report gives each objective its matched items, core items and items with useful practice, and a status:
- *represented*: the objective has items;
- *planned*: it has none yet, but its tasks will author it;
- *excluded*;
- *missing*: required, but nothing accounts for it.

Release 0.1.1 represents 11 of WSET Level 3's objectives and 7 of CMS Europe Certified's. The rest are planned by C2–C7, C5, Q-tasks and T-tasks. For CMS, the physical service technique is excluded, because the app cannot judge it.

`lint` checks the manifest:
- against the release (every selectable track has a scope; every place and type named exists);
- against the backlog (every task exists);
- against the curriculum's citations: a scope document is never a fact's source.

It also warns when a document was compared more than a year ago. The task that adds a region's node also adds that region's `covers`, so its objectives become represented as the content lands.

---

## 9. Generation and runtime architecture

- **Format registry.** One format per file, each providing:
  - `lib/core/questions/formats/<id>/`: a generator (eligibility and pools, run at ingestion) and a presenter (seeded presentation, QG-7);
  - a grader (§4);
  - a coverage contribution (§8);
  - `lib/features/practice/formats/<id>_view.dart`: the practice view.

  Registering a format is one line in each registry, so format tasks can run in parallel (backlog wave plan).
- **Generated tables.** `questions` and `question_distractors` keep serving single-item formats. `exercise_pools` and `exercise_pool_items` hold composite pools. All are rebuilt on every ingestion and read-only at runtime (QG-9).
- **Session integration.** The planner still selects items (A-2). For each selected item, the ladder (§5) picks a format. A composite format draws its co-items from the item's pool, preferring due items. Graded co-items count as bonus reviews and do not use a session slot.
- **Accessibility.** Every format has a screen-reader-usable answer mode. Map formats fall back to a list of candidate names, and ordering falls back to move-up and move-down buttons (R1).
