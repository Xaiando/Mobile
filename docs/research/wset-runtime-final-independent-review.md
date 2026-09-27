# Independent WSET Levels 1–3 delivery review

Reviewed 27 September 2026 in the managed checkout. This is an internal source and runtime review, not an official WSET endorsement, a qualified expert verification of every fact, or a learner examination result. The reviewer authored rehearsal/guided/paired runtime and the general outcome closure pack earlier in this work; this report independently inspects the root-owned progress/catalog integration and the other author's regional grape-role pack. The review of those previously authored runtime paths is an additional defensive audit, not a claim of independent authorship review. The review does not reassess the reviewer's own outcome-closure content as independent evidence.

## Result and remaining gates

The assembled catalog has no static identifier, mapping, dimension or citation-join defect in the checks below. No further concrete defect was found in required/optional progress denominators, focus navigation, currentness, activity distinctions, saved deadlines or backup preservation after the repairs recorded below. The new blocking saved-calibration defect was repaired for the root's SDK run. A subsequent real delivery failure identified two mapping-depth mismatches; a later bank audit also found supporting IDs outside the exact required catalog and a stale web-smoke expectation. Those findings and their exact boundaries are recorded in the follow-up section below. Final acceptance still requires the root's real ingestion/planner availability checks, focused regressions and release checks. All published coverage flags and internal requirement review flags were still false at the original catalog snapshot, intentionally preserving these gates.

Do not enable completion solely from the static counts below. A declared requirement must have an actual available delivery mode, reviewed scope, and the learner must satisfy the separate memory/activity conditions. Diploma completeness is outside this Levels 1–3 review.

## Concrete defect and repair

**P2: imported saved calibration references could crash feedback and count toward progress.** A syntactically valid finished saved case could replace a reference attribute with `missing_attribute`, or a reference value with `missing_value`. The saved-case parser accepted those nonempty strings; `_load` did not compare reference vocabulary with the saved grid, although `_validateCase` did so when starting a fresh case. Feedback's `singleWhere` in `lib/features/tasting_guidance/guided_tasting_screen.dart:378` threw for an unknown attribute, and the participation reader could credit the case.

The repair adds `validateCalibrationVocabulary` in `lib/core/tasting_guidance/guided_tasting.dart:171`, reuses it at fresh-case start, and applies it to saved snapshots before completion reconciliation in `_load`. The helper checks attribute and value identity against the original grid. It deliberately permits multiple acceptable reference values on a single-choice learner attribute: a reference range is not an observed selection. Canonical-item currentness remains a separate start/participation check, so a valid retired case can still be read in history. The progress reader catches only pure vocabulary `FormatException` after the actual grid database read, counts the unreadable record, and continues with other evidence. It does not suppress storage errors or alter the bad saved string.

Added regression coverage in:

- `test/core/tasting_guidance/guided_tasting_test.dart`: unknown saved attribute and value; exact bad bytes preserved through export/erase/import beside a valid finished case; valid reference range; retired canonical links remain readable.
- `test/core/progress/wset_practice_evidence_test.dart`: malformed saved reference earns no calibration credit, cannot hide a valid physical record, increments diagnostics, remains unchanged, and creates no review events or FSRS state.
- `test/features/tasting_guidance/guided_tasting_screen_test.dart`: an actual backup/import with an unknown saved attribute shows the history recovery warning, permits opening valid saved feedback, and does not throw during build.

These new regressions were authored and statically examined by this reviewer; the root runs formatting and SDK tests separately. The previous SQL failure propagation repair also keeps database reads outside snapshot-parser recovery in `wset_practice_evidence.dart`, with a regression that temporarily makes the descriptor table unavailable and requires `SqliteException` rather than empty participation.

## Catalog evidence

The reviewer independently parsed the currently registered curriculum manifest/includes and `assets/progress/wset_scope.json` with Python/PyYAML, without SDK or Git commands. At this snapshot:

| Track | Requirements | Distinct required facts | Unknown facts | Missing cumulative WSET mappings | Duplicate requirement IDs | Invalid kinds or location mismatches |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| WSET L1 | 49 | 132 | 0 | 0 | 0 | 0 |
| WSET L2 | 442 | 703 | 0 | 0 | 0 | 0 |
| WSET L3 | 877 | 1555 | 0 | 0 | 0 | 0 |

The location check rejects a `LOCATED_IN` pin as explanation evidence and requires location dimensions to link actual location facts. Required sets are unions, so a fact legitimately reused by multiple outcomes contributes once to the overall required denominator. Duplicate IDs inside a dimension and duplicate dimension kinds are rejected by `WsetEvidenceDimension.validate` / `WsetRequirement.validate` in `lib/core/progress/wset_requirements.dart`.

Static mapping checks are not equivalent to successful serving. The final root test must continue using the real installed dataset and planner, including actual map shapes/gazetteer features and permitted answer modes. Explanation requirements need a recall mode delivered for their linked facts; a map pin cannot satisfy them. The catalog's latest registered grape-role/outcome-closure/regional-application packs are included by `assets/curriculum/curriculum.yaml`.

## Progress and navigation semantics

- `WsetProgressRepository.snapshot` (`lib/core/progress/wset_progress.dart:295`) rejects unknown required IDs before producing progress. A required fact that is expired, unmapped, too deep for the track, or has none of the dimension's declared modes remains in the required denominator and is unavailable; it cannot silently become optional. The real `StudyPlanner.cards` output determines mode availability.
- `requirementCount` checks all dimensions that reuse a fact, rather than accepting whichever dimension is easiest to serve. Required overall counts use `level.requiredItemIds`; optional material is reported separately.
- `WsetLevelProgress.appLevelComplete` (`lib/core/progress/wset_progress.dart:112`) requires the published coverage flag, a nonempty required set, no unavailable requirements, all required memory mastery, every internally reviewed requirement complete, and required practice participation. The shared FSRS thresholds retain three successful UTC dates spanning seven days, stability of at least seven days, and current retrievability of at least 0.90. Future review events are excluded. Study activity does not automatically mark memory mastered.
- Home uses `milestoneCounts` (`lib/features/progress/wset_progress_card.dart:69`) and warns about unavailable required facts. Progress rows distinguish optional atlas material and unavailable evidence. Requirement taps call `_study` with exactly the requirement's IDs; the level button uses the union of required IDs (`lib/features/progress/wset_progress_screen.dart:102`). `StudyPlanner.plan` filters those IDs before scheduling while retaining shared learner memory.
- The manually recorded examination pass is stored independently in `exam_pass_wset_l*` settings; no rehearsal or tasting code writes it. The UI identifies the app milestone and learner-recorded examination result separately.
- `WsetProgressRepository.watch` observes user settings, curriculum/planner data, tasting sessions, descriptors and grid/vocabulary changes. A legacy observation edit can therefore remove stale guided participation without waiting for another card review. Periodic refresh also recomputes time-sensitive retrievability.

## Participation, timers and saved history

- A finished original MCQ rehearsal counts participation only when every sampled question has an answer and its saved item links remain current and mapped for the target level. It does not require a fabricated official pass score, and produces no automatic FSRS writes.
- Level 3 written participation requires nonblank saved prose for all four prompts and an explicit self-review for each. An honest empty supported-criterion set is a valid self-review, not a pass. Written canonical links derive from the saved criteria; they are checked for currentness.
- Calibration participation counts distinct authored cases, not repeated attempts at one case. Valid retired-item cases remain readable historical snapshots but earn no current calibration participation. After the repair above, malformed saved reference vocabulary cannot count.
- Physical guided records require actual saved observations, required descriptive attributes, nonblank evidence, and an exact agreement with the completed tasting-session snapshot. Legacy edits reopen the guided completion instead of preserving stale evidence. L1/L2 physical wines remain optional; their required authored-case route does not claim to be a practical examination.
- The Level 3 pair requires two completed physical wine snapshots and a saved absolute 30-minute UTC deadline. Its finished observations/evidence are immutable; a later legacy tasting edit cannot rewrite the finished paired record. Linked guided records do not double-count as separate physical evidence in this path.
- Rehearsal snapshots validate exact level-specific durations, canonical UTC timestamps, key/UUID identity, completion boundaries and expiry-at-deadline. Leaving the screen or restarting does not restart elapsed time. A rejected late answer commits expiry before raising the write rejection, rather than rolling the expiry back inside a thrown transaction.
- Rehearsal `resume` persists the selected unfinished historical draft and refuses to hide another running draft. Finished history does not replace the current draft. Guided and pair resume/restart guards likewise preserve existing drafts; repeated/concurrent finishes preserve one finished snapshot.
- All three histories recover per malformed row and show an unreadable-count warning. Actual SQLite failures propagate. Original corrupted setting values remain in the database and backups rather than being silently deleted. A malformed current pointer leads to the existing readable reset/recovery UI rather than an invented empty success state.
- `UserDataBackup.tables` includes settings, tasting sessions and descriptors (`lib/core/backup/user_data_backup.dart:49`). Validly named setting strings round-trip even when an individual activity payload is unreadable. Import runs transactionally with the existing user-data constraints. `resetProgress` clears only review events/states; history, observations and manually recorded examination passes remain settings/tasting data. `eraseAll` is the explicit full reset.

## Independent content review: 27 regional grape roles and 19 regional applications

The reviewer read every assertion and citation join in `assets/curriculum/areas/wset_regional_grape_roles.yaml` and `assets/curriculum/areas/wset_regional_applications.yaml`, together with their evidence/source ledgers. The static join check found **27 points / 38 citation links** and **19 points / 72 citation links**, with no uncited point or unknown source ID. All new teaching assertions remain unverified and disable automatically generated MCQs; this review does not promote their expert-verification status.

No concrete content correction was identified in these two packs. The grape-role additions teach style/blending contributions rather than treating legal grape permission as sufficient explanation. The regional application statements use supplied fruit/plots or comparable lots and explicit production choices. They do not infer quality, retail price, compulsory new oak, or identical cellar treatment from a protected origin, low yield, warm climate, altitude or a grape name. Cellar/labour/capacity costs are editorial applications of cited general mechanisms, clearly labelled as such in the locators.

Representative current primary rechecks on 27 September 2026:

| Exact reviewed teaching points | Primary check and conclusion |
| --- | --- |
| `ki_wset_role_jaen_identity`, `ki_wset_role_jaen_blend` | [IVV Jaen record](https://www.ivv.gov.pt/casta/jaen/) explicitly identifies the Spanish Mencía synonym, traditional Dão association, early ripening and relatively low acidity. Direct stdlib retrieval was used when the web reader timed out. The pack avoids making IVV/ViniPortugal's differing colour descriptions universal and preserves the separate qualified Pirulé legal entry. |
| `ki_wset_role_bonarda_identity`, `ki_wset_role_bonarda_style` | [Wines of Argentina's identity account](https://blog.winesofargentina.com/es/noticias/trends/6-cosas-que-no-sabias-del-vino-argentino/) supports Corbeau/Charbono/Douce Noir and distinguishes the confusing Italian names. Its dated acreage/export statements are not adopted as current claims. The lesson qualifies producer-selected style variation. |
| `ki_wset_role_graciano`, `ki_wset_role_mazuelo` | [Consejo Regulador Rioja's red-variety account](https://riojawine.com/en-gb/blog/discover-the-rioja-red-grape-variety/) supports Graciano late ripening, acidity/colour/tannin contributions and Mazuelo/Carignan identity with acidity, structure and stable colour. The lesson qualifies successful ageing rather than repeating the source's promotional guarantees. |
| `ki_wset_role_friuli_identity`, `ki_wset_role_friuli_white_styles` | [Consorzio's wines page](https://www.colliorientali.com/en/the-consortium/wines/) supports the Pinot Grigio/Sauvignon/Chardonnay/Friulano white range, skin-contact copper Pinot Grigio and Friulano's moderate acidity/apple/floral/almond tendencies. These remain tendencies, not mandatory sensory results. |
| `ki_wset_role_friuli_cellar_cost` | [La Viarte's named Friulano example](https://laviarte.it/en/products/friulano-magnum) identifies Friuli Colli Orientali DOC and the steel/fine-lees route. The lesson names the producer example and does not convert it into the DOC's compulsory method. Cost/texture applications are separately supported general mechanisms. |
| `ki_wset_role_castilla_igp_identity`, `ki_wset_role_castilla_environment`, `ki_wset_role_castilla_styles` | [ITACYL's primary broad IGP specification](https://www.itacyl.es/documents/20143/0/PPCC%2BIGP%2BVTCYL%2B%282%29.pdf/dc9869da-3147-fa5a-273a-592a5e734187) supports multiple colours/varieties, broad regional origin and the continental Mediterranean plateau with local exceptions. Its 2011 revision is explicitly disclosed and separately joined to the 2019 official amendment; no outdated numerical threshold is reproduced. Bierzo's local Atlantic influence is not overwritten by a universal plateau claim. |
| `ki_wset_apply_sauternes_environment`, `ki_wset_apply_sauternes_selection_cost` | [CIVB's Sauternes designation page](https://www.bordeaux.com/en/designations/graves-sauternes/sauternes) supports the Ciron/Garonne fog, sunny afternoons and successive selective picking. The destructive-rot warning and cost-per-unit consequences use established general viticulture/cost mechanisms, without implying botrytis guarantees quality or price. |
| `ki_wset_apply_veneto_local_cooling` | [Consorzio Valpolicella's climate account](https://www.consorziovalpolicella.it/en/the-area/climate-of-valpolicella/) supports Lake Garda moderation and hill/valley breeze differences. Direct stdlib retrieval was used after the web reader failed. The lesson explicitly compares sites rather than extending one cooling result to all Veneto. |

These are representative live primary checks, not a claim that every source URL, every paragraph or every legal document in the entire app was independently reopened in this pass. The source-join check covers all assertions in the two assigned packs; source veracity and qualified expert review remain distinct from join validity.

## Follow-up: real delivery failure, revised bank and browser gates

The root subsequently supplied `build/wset-bundle-diagnostics.log`, whose real bundled delivery test found two unavailable L2 rows. Independent read-only diagnosis identified the exact failing facts, not just their larger requirement rows:

| Requirement | Failing fact | Cause before root's repair |
| --- | --- | --- |
| `extended_grape_origin_l2_nebbiolo_barolo` | `ki_barolo_grape` | Explicit L2 mapping in `assets/curriculum/areas/italy.yaml:223` used depth 1. A principal-grape MCQ existed and therefore served; forward flashcard required depth 2. The required dimension accepted recall modes only. |
| `extended_grape_origin_l2_sangiovese_chianticlassico` | `ki_chianti_classico_grape` | The same explicit L2 depth-1 mapping at `italy.yaml:224` selected MCQ alone, although a forward flashcard was generated. |

`StudyPlanner.servedFormats` in `lib/core/study/study_planner.dart:495` falls back to the easiest nonreasoning format only when **none** is served at the mapped depth. It correctly did not fall back while MCQ existed. The other linked regional principle facts have MCQs disabled, so their recall fallback is available; their explicit L2 mappings and original unverified status are legitimate. The map facts have actual map delivery and are not the failing facts. Requirement review flags do not determine availability, although false review flags still block completed scope.

The honest fix recommended was to raise the two existing L2 mappings to depth 2 so that forward recall is actually served, without upgrading expert-verification status or weakening the required denominator. The legal grape association belongs in the grapes dimension rather than pretending it explains style alone. The root confirmed applying both changes before starting the next full SDK regression window; this reviewer did not modify the registered source or execute SDK commands.

### Rehearsal bank snapshot `2026.09.27-original.2`

The reviewer independently inspected every eligible question's exact links and searched question ID, prompt, explanation and item IDs for the requested exclusions. Result: Level 2 excludes VDN mutage, amber/orange skin-contact questions and Madeira; Level 3 excludes Madeira and Vienna. The retained VDN mutage and amber-style questions are L3 only. No eligible MCQ links are unknown or missing a cumulative WSET mapping. All written criteria also remain cumulatively L3 mapped. This check does not claim that mapped optional material belongs in a required preset.

| Level | Eligible MCQs | Bucket pool sizes | Exact linked IDs absent from that level's required catalog |
| --- | ---: | --- | ---: |
| 1 | 65 | process 12; styles 35; service 18 | 0 |
| 2 | 192 | vine 13; winery 16; principal 61; regional 54; sparkfort 28; service 20 | 7 |
| 3 | 220 | factors 32; still 137; sparkling 16; fortified 15; service 20 | 7 |

The remaining MCQ exact-ID mismatches are:

- **L2 and L3:** `ki_win_gentle_press`, `ki_win_rot_sort`, `ki_spark_base_acidity`, `ki_spark_base_alcohol`, `ki_fort_sherry_amontillado`, `ki_fort_sherry_oloroso`.
- **L2 only:** `ki_win_white_cooling` (the same ID is already a required L3 fact).
- **L3 only:** `ki_win_amber_style`.

These are catalog-join findings, not proof that every topic is outside the qualification. In particular, the current [April 2026 Level 2 specification](https://www.wsetglobal.com/media/19132/wset_l2wines_specification_en_april2026_issue21.pdf), LO5, explicitly names Amontillado and Oloroso. Required canonical `ki_wset_sf_sherry_amontillado_style` and `ki_wset_sf_sherry_oloroso_style` directly support the current bank answers, so exact relinking is appropriate. General sorting, pressing, white cooling and sparkling-base aims can be legitimate reviewed explanation requirements. Add justified catalog evidence or use a required canonical assertion supporting the exact answer; do not silently promote all optional facts or delete a genuine outcome because its particular older ID was omitted.

Written L3 exact-ID mismatches:

| Written prompt | Criterion-linked IDs outside required L3 set |
| --- | --- |
| `written_grape_to_style` | `ki_reg_fr_chablis_quality`, `ki_win_gentle_press` |
| `written_sparkling_methods` | `ki_spark_more_alcohol` |
| `written_sherry_ageing` | `ki_fort_sherry_amontillado`, `ki_fort_sherry_oloroso`, `ki_fort_sherry_ullage` |
| `written_tokaj_selection` | `ki_reg_ah_case_tokaj_selection_action`, `ki_reg_ah_case_tokaj_selection_limitation` |
| `written_region_and_quality` | `ki_reg_ib_case_pt_white_design_action`, `ki_reg_ib_case_pt_white_design_limitation` |

The Tokaj and Portuguese comparison criteria are existing supplied-case decisions/limitations; their reasoning should remain conditional. Preserve their evidence by justified catalog inclusion or by revising/relinking criteria to exact required supporting assertions. A different case or a regional identity fact is not an automatic substitute for the existing decision/rubric. All findings above were delivered to the root for the next coordinated source window.

### Browser smoke strategy and concrete stale check

The current `tool/web_smoke/main.dart` is a real WASM/Drift database, bundled-ingestion, map-hit and single-study-card probe. It initializes Flutter bindings but does not render the app shell, so its success cannot establish phone navigation or the new practice layouts. `tool/web_smoke/run.mjs` runs this probe with COOP/COEP off and on in fresh Chromium pages, which remains useful for storage durability.

**Stale expectation:** `run.mjs:32` hard-codes `mapLayers: 10`, while the current geography manifest registers **38** layers. A correctly ingested current bundle will fail this assertion. Compare the installed count with the bundled manifest count rather than merely changing one magic number. The runner also gives ingestion only 30 seconds; the new bundle's supplied native diagnostic already needed 22 seconds. Measure actual browser ingestion and use a clearly bounded adequate deadline rather than mistaking slow WASM ingestion for corruption.

Recommended root-owned release smoke sequence:

1. Run the existing pinned-web-asset check, release app build, and separate smoke entry build sequentially. Keep the two isolation-mode storage checks. Extend the probe to read the exact progress catalog and confirm zero unavailable required L1–3 facts with real serving modes. Exercise one saved rehearsal/guided/pair settings snapshot through a restart/backup round trip and confirm no automatic FSRS or examination-pass writes from practice. Use the real bundled data and source banks, not fixture content.
2. Serve the normal release app (`lib/main.dart`) separately and use a fresh browser profile. At 320×780, complete onboarding; select each of the five tracks; open Study; find a grape/region and a source; apply a domain filter; exercise empty results/reset. Keep a desktop viewport check and browser accessibility/large-text check as well. Flutter's widget keys are not automatically DOM selectors: use the actual accessibility surface or a supported browser screenshot workflow, and record layout/console errors.
3. From Home's `View WSET progress` button, inspect L1, L2 and L3 required versus optional material and open one exact requirement's focused practice. Progress is a pushed Material route, not an authored `/progress` route. Verify the selected track and visible question belong to the chosen requirement rather than an unrelated optional atlas item.
4. Open `/practice/rehearsal` through the authored Home/Practice entry. Start L2, save one answer, navigate away and reload; confirm the answer and deadline survive and time decreases. Finish/end using the real controls; open finished history and confirm it does not replace another active draft. Do not wait an hour just to test expiry: expiry precision is already covered with controlled-clock core tests.
5. Open `/tasting/guided` through Home/Tasting. Save one authored L2 case's observations/evidence, complete it, inspect delayed training feedback, and reload history. Verify this adds calibration participation rather than fact mastery or an official pass. Check the original `/tasting/new` path still offers legacy grids only.
6. Select L3 and open `/tasting/paired`. Save different observations/evidence for each physical wine and reload; confirm separate wine drafts, the absolute 30-minute deadline, and saved feedback. Finishing incomplete evidence must show missing-evidence status, not a fabricated grade. Confirm phone scrolling exposes wine-switching, evidence and completion controls.

Existing focused widget tests cover the named controls in `test/features/wset_track_selection_test.dart`, `study_search_test.dart`, `wset_progress_test.dart`, and the rehearsal/guided/pair feature directories. Those are meaningful layout/navigation evidence; the separate full-app browser pass covers the actual release renderer, asset loading and persistence between page reloads. No SDK, browser process, Git command, or registered file edit was performed by this reviewer during this read-only follow-up.

### Full-suite semantic-area regression reported by root

The root subsequently reported a concrete coverage-baseline failure caused by the new required-geography country map framing. Independent source inspection confirms `_Areas.load` (`lib/core/coverage/coverage_checker.dart:368`) treats every subject type in a `LOCATED_IN` signature as requiring a container. The new country-to-informal-area signature makes every country look nonroot, including countries without any World edge. `_find` also chooses the farthest ancestor (`coverage_checker.dart:439`), so a supplemental World parent can replace the actual country or its regional bucket. This is a semantic reporting defect; dropping map edges or lowering the existing baseline would hide it.

After the root signalled SDK closed, the authorized repair was implemented in `lib/core/coverage/coverage_checker.dart`. Country subjects are their own semantic coverage roots; other places select an actual country ancestor before regional splitting. A regional candidate must itself reach that country, so an unrelated outer frame cannot become the region through a shortest-depth tie. Geography/graph containment and country map framing remain intact. New `test/core/coverage/coverage_country_frames_test.dart` regressions isolate the signature-only failure, France/Germany World parents, an explicit mapped country-subject fact, unchanged Burgundy/Beaujolais/Germany buckets, preserved World ancestry, and an outer-frame shortcut. Existing no-country/unplaced behavior and all baseline thresholds remain unchanged. The source/tests are frozen for root SDK verification; no SDK or Git command was executed by the reviewer.

### Shared map-pair suppression by a sparse lower track

The root's full suite additionally found `ki_vouvray_location` missing the generated `map_pair` row despite a valid `map_locate` row. Independent inspection confirmed `MapPairFormat.isEligible` chose the unscoped nearest geometry frame first, then required enough mapped peers in that same frame for every selectable track serving the primary. Vouvray's narrow Touraine frame contained detailed atlas locations unavailable to L2. That lower track therefore globally suppressed the shared pair, including for higher tracks. Removing scope guards would leak advanced co-items; weakening the atlas assertion would hide the regression.

The authorized repair uses `GeometryRepository.frameOf(eligibleNodeIds: ...)` with the actual mapped current location subjects for each serving track and the template's minimum place count. Sparse tracks can widen their geometry frame until they contain enough legitimate peers. Ingestion and presentation use the same scoped frame rule. Peer filtering occurs before subject deduplication, so an unmapped alternative location fact cannot shadow the mapped co-item. Candidates and chosen co-items both remain scoped; seeded selection, varied wording and independent per-location grading remain unchanged.

`MapFormat` now offers an overridable `frameFor` hook in `lib/core/questions/formats/map/map_exercise.dart`; simple maps keep their original frame selection. `MapPairFormat` overrides it and reuses the current mapped-location set within each presentation. `lib/core/questions/exercise_presenter.dart` now carries explicit session certification scope to `map_pair`, as it already did for reasoning. Without that bounded addition, a changed active learner profile could still override the track of an existing practice session. The requested primary must itself be served by that explicit track.

New `test/core/questions/map_pair_track_frame_test.dart` uses a real bundled geometry fixture with a deliberately sparse L2 location scope: Vouvray plus Chablis, which lies outside Vouvray's default nearest frame. It requires shared pair generation to survive, higher-track presentation to remain valid, lower candidates/co-items to contain only the two mapped locations, repeated seeds to reproduce the same question, explicit L2 session scope to win over an active L3 profile, and an unmapped advanced primary to be rejected. It also checks no review event is manufactured by presentation. Existing map validity/track-depth tests continue to cover current versus retired location facts and per-place grading. These registered source/tests were authored only after SDK closed and are frozen for the root's focused SDK run.
