# WSET Levels 1–3 completion plan and task ledger

Started 27 September 2026 at the user's explicit request. This is a sustained implementation goal, not a plan-only response. Root coordinates content, software, critique, source review and debugging; work continues across checkpoints until the gates below are met or a concrete external dependency prevents further progress.

## Scope and completion definition

Complete the app's wine study coverage for the current public WSET Level 1, Level 2 and Level 3 Award in Wines specifications. Every required teaching topic needs explicit original lessons and appropriate practice at its level. Required regional study must teach grapes, environment, production, style and the relevant quality/price or labelling concepts; a location pin does not satisfy an explanatory requirement. Optional atlas detail remains optional.

Use WSET documents to establish scope and assessment shape, not as the source of legal or scientific wine facts. Original content cites primary regulators, regional bodies, technical authorities and university sources as appropriate. No copied examination questions, official marking scheme or proprietary tasting grid is authored. Existing fact review status remains intact; internal source review is distinct from qualified expert verification.

App completion means the reviewed study plan is implemented and its required material and practice can be completed. It does not award a qualification or objectively certify performance on an unknown physical wine. Actual course participation and official examinations remain external. Written rehearsal feedback is educational and explicitly identifies self-assessment. Tasting practice teaches observation and evidence-based conclusions, with calibrated original training cases and space for physical wine practice.

Grok separately owns essential wine history from Areni 1 through the present, including Roman and Napoleonic developments, and the sommelier beer, spirits/liquor, cider, cigars and basic sake strand. Those topics must not be used to inflate completion of the Wines qualifications. Codex does not edit Grok's side-mission files. Ownership and SDK windows are recorded in the shared `D:\Apps\Sommelier study companion\GROK_COORDINATION.md`.

## Working state and safeguards

- Branch: `codex/wset-levels-1-3-completion` in the existing managed checkout, from numeric `6ca7bc1`, business `b95c59a` and merged base `b551996`.
- Grok's completed Soave and Alto Adige work (`b66d5d3`, `3bf6a21`) is being integrated. Source merge conflicts are resolved; release summaries, aggregate tests and baseline remain to be reconciled and validated.
- Combined pre-authoring source baseline: 2,896 facts; Level 1 zero; cumulative Level 2 103; Level 3 2,392; CMS 2,400. These are content counts, not course completion denominators.
- Provisional dataset 0.21.0 and app 0.3.0+15. Reconcile against actual parallel releases before publication.
- Preserve prior maps and their licensed bytes/attributions; preserve the 704 Diploma D3 IDs, all previous business/reasoning material, China's eight optional atlas references and Diploma-only analysis, schema compatibility and shared FSRS memory.
- Preserve the shared checkout's five pre-existing dirty files. Root alone performs Git integration and sequential Dart/Flutter validation. Agents own disjoint paths and do not run the SDK.
- Retain existing tasting grids and saved vocabulary; new teaching/calibration grids or versions append rather than redefine saved keys. New persistent practice must be backed up and migration-safe.

## Task ledger

States: open, active, implemented (review/tests pending), passed. A task is passed only when its explicit acceptance evidence is recorded. Fact counts alone cannot close a task.

| ID | Task and concrete acceptance evidence | Owner | State |
|---|---|---|---|
| W01 | Verify current official L1/L2/L3 specifications, dates and assessment shape; pin direct URLs | research + critic | passed |
| W02 | Integrate numeric/business and completed Soave/Alto Adige; preserve all ancestor content and pins | root | active |
| W03 | Build original granular outcome/topic matrix with exact lesson IDs, learning dimensions and practice evidence | root + researchers | active |
| W04 | Independently challenge matrix sufficiency, required vs optional topics and atlas-only matches | critic | active |
| W05 | Snapshot pre-authoring facts, mappings, scope, source bytes and legacy tasting data for preservation comparisons | root | passed |
| W10 | Dedicated L1 introductory pack: wine types/styles, grape components, growing/ripening and basic production | research | implemented |
| W11 | L1 required common grape/style profiles and named wine examples at beginner depth | research | implemented |
| W12 | L1 storage, temperature, glassware, still/sparkling opening, preservation and faults | content | implemented |
| W13 | L1 food interactions and safe/responsible service; conditional examples, not universal pairings | content | implemented |
| W14 | L1 tasting description practice and original 30-question rehearsal delivery | runtime + root | active |
| W20 | L2 eight principal grape profiles: structure, typical aromas, environment and production effects | research | implemented |
| W21 | L2 all required regional grapes, with canonical nodes/aliases and basic style lessons | research | implemented |
| W22 | L2 required GIs and regional style comparisons: complete named scope with proper explanatory evidence | content | active |
| W23 | L2 growing/production/maturation decisions and quality/style effects; remap existing suitable lessons | content | active |
| W24 | L2 sparkling and fortified methods, required examples and style labels | content | open |
| W25 | L2 origin/style/quality label terms, service, storage, food interactions and wine faults | content | active |
| W26 | L2 tasting-description practice and original 50-question rehearsal delivery | runtime + root | active |
| W30 | L3 vine cycle, climate/weather/soil, site selection and ripening factors | content + critic | active |
| W31 | L3 vineyard management, training/pruning, hazards, pests/diseases and production approaches | content + critic | active |
| W32 | L3 white/red/rosé/sweet routes, adjustments, extraction/fermentation choices and style implications | content + critic | active |
| W33 | L3 maturation/blending/clarification/stability, packaging/closures and cost/quality implications | content + critic | active |
| W34 | L3 France: required region/GI names, grapes, environment, cellar choices, style, quality/price and labels | critic + content | implemented |
| W35 | L3 Italy: same explanatory dimensions for every required region/style; distinguish laws from typicity | critic + content | implemented |
| W36 | L3 Spain/Portugal: required region/styles/labels and their explanatory dimensions | critic + content | implemented |
| W37 | L3 Germany/Austria/Hungary/Greece: required region/styles/labels and explanatory dimensions | critic + content | implemented |
| W38 | L3 North/South America: required region/grape/style and growing/production/quality-price links | critic + content | active |
| W39 | L3 Australia/New Zealand/South Africa: same required regional explanatory dimensions | critic + content | active |
| W40 | L3 sparkling regions/methods/labels, including genuine category and named-place omissions | critic + content | active |
| W41 | L3 fortified regions/methods/styles/labels and quality/price links | critic + content | active |
| W42 | L3 wine service/storage, recommendations, food interactions, faults and responsible consumption | content | implemented |
| W43 | L3 written explanation cases: original prompts, saved prose, clear criteria, delayed feedback and self-review | runtime + root | implemented |
| W44 | L3 tasting: structured observation, aroma/flavour development, quality/ageing evidence and calibration | runtime + content | implemented |
| W45 | Required geography omissions: defensible names/aliases and licensed reference geometry, never invented boundaries | root + critic | active |
| W50 | L1/L2 selectable tracks with scoped cumulative membership and no advanced-content leakage | root + debugger | implemented |
| W51 | Responsive five-track picker at phone widths and large text sizes | debugger | passed |
| W52 | Searchable Study with domain/topic focus, empty/reset states and retained item sources/memory | debugger | passed |
| W53 | Requirement-based progress with explicit required vs optional material and separate rehearsal/tasting evidence | root | implemented |
| W54 | Original level rehearsal presets/timers/answer persistence and deferred feedback | runtime + root | implemented |
| W55 | Tasting calibration/evidence UI; retain legacy sessions and support physical practice notes | runtime + root | implemented |
| W56 | Backup/restore, reset/erase, expiry/currentness, duplicate submission and cross-level memory safeguards | debugger + root | active |
| W60 | Independent source/content review: all required dimensions, cautious sensory claims and current legal context | reviewer | active |
| W61 | Lint, scope/coverage ratchets, targeted content/runtime/widget/backup tests and clean analysis | root | active |
| W62 | Broader/full regression run; repair failures, then rerun the affected gates against frozen source | root | open |
| W63 | Fresh release web build, bundled-asset/pinned-runtime checks and narrow-screen smoke | root | open |
| W64 | Final outcome audit: zero required study topics still open, no atlas-only explanation credit | critic + root | open |
| W65 | Update learner completion metadata from measured outcome audit; retain explicit expert-review and exam distinctions | root | open |
| W66 | Commit coherent integration, record exact handoff for Grok and remaining external review/device checks | root | open |
| W67 | Shared-topic typed practice: uniquely targeted original cues, responsive accepted phrases, primary-only grading and independent cue review | research + critic + debugger | active |
| W68 | Written explanation pools: current served members of the selected track only, with a valid single-point scoped exercise | debugger + root | active |

## Evidence matrix rules

1. Use original requirement IDs and concise original labels. Every matrix row records level, subject/topic, required learning dimensions and authoritative scope source/version.
2. Attach exact current canonical `knowledge_item` IDs per dimension and the actual mapped level. Empty selectors or broad region matches are not accepted evidence. Existing suitable lessons can be reused through explicit mappings rather than cloned facts.
3. For a region, location/map evidence is separate from grapes, environment, production, style, labels and quality/price. Require only dimensions demanded by that level's scope. An individual cru's detailed soil is not invented as a universal compulsory requirement.
4. Required grape profiles teach characteristic structure/style and their variation. Legal permission lists alone do not satisfy a profile. Typicity is phrased conditionally and is not a guaranteed blind-tasting identification.
5. Required practice distinguishes objective recall, written explanation/self-review, and tasting observation/calibration. A synthetic tasting note has authored training feedback; an unknown physical wine has no fabricated universal correct answer.
6. Include storage/service and food interactions in every applicable level, not only the sommelier side mission.
7. Rows close only after an independent reviewer checks sources, actual lesson/practice delivery and level appropriateness. Record deficiencies and repair them before changing completion metadata.

## Work sequence and checkpoints

- Phase A: sources, integration baseline and three independent audits (W01–W05).
- Phase B: parallel beginner content, required regional explanations and wine-service/tasting foundations (W10–W45). Root assembles mappings/matrix; batches are reviewed before source freeze.
- Phase C: selectable levels, Study navigation, progress, saved written rehearsal and tasting calibration (W50–W56).
- Phase D: source critique, focused tests and coverage checks. Fix real gaps; do not satisfy a failed coverage gate by weakening its requirement (W60–W61).
- Phase E: broad regression, release build, final independent outcome audit and coherent handoff (W62–W66).

Implementation and review findings are appended below as batches finish. Unresolved rows remain visible across continuations; no partial checkpoint is labelled complete.

## Current findings

- Grok's assessment correctly identifies the high atlas share, but absence of a `HAS_SOIL` row does not itself prove absence of teaching: original regional explanation items already cover Bordeaux gravel/clay and Hautes-Côtes comparisons.
- Some individual cru/history depth suggestions exceed the mandatory L3 scope. Genuine named omissions and weak categories still need closure; the critic's direct specification comparison determines these.
- All five learner tracks are selectable. The new beginner foundation/grape packs install successfully and supply dedicated Level 1/2 lessons. Their independent content review remains open.
- Official Level2 currently links Issue2.1 (2026); the app must not silently build against an obsolete outline. Full exact source/version findings follow in W01/W03.
- Persisted timed rehearsal, delayed written self-review, guided calibration and two-wine Level 3 practice are implemented. Focused restart/expiry/snapshot/backup checks pass; the real rehearsal bank and complete required-topic catalog are still being finished.

## Validated implementation checkpoint — 27 September 2026

Official scope is pinned to Level 1 June 2022 Issue 1.2, Level 2 2026 Issue 2.1 and Level 3 May 2022 Issue 2. The ignored immutable source baseline captures all 2,896 prior facts, mappings, licensed map bytes, legacy grids, schema and dependency/runtime pins. W01/W05 are closed with that evidence. Responsive five-track selection and focused Study search pass their narrow/large-text widget checks (W51/W52).

New beginner content has 147 original points (51 first taught at Level 1, 96 at Level 2), the service strand 72 points plus 12 case facts, and tasting teaching 39 points. All retain unverified factual review status. Their focused content checks and real bundled SQLite ingestion pass. Three appended teaching grids and nine original calibration cases work without modifying saved legacy vocabulary. The European regional pack adds 101 points and explicit suitable existing mappings; its source validator and bundled installation pass after canonical citation deduplication. These counts describe delivery, not a completion verdict.

Practice progress now distinguishes shared fact memory from original rehearsal participation, explicit written self-review, distinct calibration cases, physical guided observations and timed two-wine snapshots. Five activity-evidence regressions pass, including stale legacy edits, corrupt history recovery, honest zero-criterion self-review and absence of FSRS/pass writes. Partial required-topic progress installs without unavailable items. All coverage flags remain false while the complete matrix, regional/general additions, missing canonical geography and independent review remain open.

The paired core and UI checks pass; the timer, ended state and errors remain visible above scrolling observations. Full analysis, complete suite and final asset/build verification await a final source freeze. No partial checkpoint closes W64–W66.

## Final semantic review and delivery repairs

The independent scope refresh finds no remaining required Level 1–3 instructional topic gap after 43 explicit grape-structure lessons, the final service and regional-role closures, 149 Level 2 grape/origin pairs and 22 Level 3 sparkling/fortified families. The catalog selects 49/442/888 topic rows and 132/752/1,625 distinct required facts. This is semantic acceptance; runtime gates remain open.

Final integration includes Grok's registered fifteen history and twenty-two other-beverage facts, preserving its unregistered newer course candidates. Candidate combined release is dataset 0.23.0 / app 0.3.0+16. All 2,896 original assertions, 3,371 nodes, 3,007 relations, legacy grids, Diploma selectors and runtime pins pass preservation comparison. Geometry reproduces 38 layers identically; eighteen geography checks pass with three optional authoring-cache checks skipped. Analysis is clean and curriculum lint has zero errors.

The coverage ratchet exposed actual delivery weaknesses and therefore refused a baseline update. Exact introductory explanatory mappings were depth 1, preventing generated typed/written recall at depth 2; those precise mappings are raised without making optional material compulsory. Fifty-two older location recall floors are restored after an overly broad promotion had lowered them. Six protected-origin labels now serve their existing typed recall. Prior baseline metrics are retained while repairs are validated.

W67/W68 address two additional correctness defects: a broad shared-subject typed answer could accept one sibling phrase but credit a different primary fact; and a written explanation pool could choose an unavailable sibling outside its track. Original point-specific cues and scoped written membership close those defects without changing the facts, legal multi-answer behaviour or qualified-review status. Full regression was interrupted after 159 passing checks and the confirmed coverage failure; it is not recorded as a passing full suite. Complete acceptance will run after these repairs freeze.
