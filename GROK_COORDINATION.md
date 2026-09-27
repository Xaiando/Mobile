# Codex / Grok coordination

Updated 27 September 2026. The user asked us to continue in parallel and confirmed that Grok committed and merged while Codex was validating.

## Current shared checkout

`D:\Apps\Sommelier study companion` is at `711206a`, following `050a4e7`. Codex preserves Grok's release 0.20.1 and both Italy corrections. Do not undo those commits.

Five final Codex changes remain uncommitted here: `test/core/curriculum/curriculum_dataset_test.dart`, `docs/research/diploma-reasoning-continuation.md`, `docs/research/codex-handoff.md`, `docs/research/wset-level-4-gap-audit.md`, and `docs/wset-learner-progress.md`. Preserve them when committing. The parser assertion now tests defaults only for authored rows that omit the optional fields; all 61 reasoning/parser tests pass. Final analysis, curriculum lint, coverage and the web build passed. The reasoning report records the broad run's sole failure and successful repair honestly.

## Work division for this continuation

**Codex owns Q6 / D1 climate and weather reasoning content.** Its managed isolated worktree starts from `711206a`, named `diploma-climate-reasoning`. It will author `assets/curriculum/areas/reasoning_climate_frost.yaml` and `reasoning_climate_ripening.yaml`, corresponding files under `assets/curriculum/templates/`, source notes under `docs/research/reasoning-climate-*-sources.md`, focused content tests and a continuation report. IDs use `n_climate_frost_` / `n_climate_ripen_` and corresponding `ki_` / `qt_` prefixes. The existing engine and database schema remain the foundation.

Codex will edit curriculum includes/version, coverage baseline, the Diploma scope/progress notes and release summaries **inside that worktree only**. Please avoid authoring the same climate-reasoning IDs/files. Shared release metadata must be reconciled once both branches are ready; independently generated coverage baselines must be regenerated after integration.

**Suggested independent Grok work:** source checking or the remaining fine-region atlas gaps listed in `docs/research/wset-level-4-gap-audit.md`, especially Italian subdivisions. Use separate area/layer files and your own worktree for implementation. Choose a region set and record ownership here before editing it. Keep licensed reference points where defensible boundaries are unavailable. Alternatively continue release/CI checks for the already merged 0.20.1. Do not commit/push Codex's in-progress worktree while its validation runs.

Use separate checkouts for Git changes. Avoid resetting, cleaning, switching branches or blanket staging another agent's checkout. Run Flutter/Dart commands sequentially against a stable snapshot; Codex will record when its final SDK checks begin and finish. Node/source research can run independently.

## Persistent user preferences

- The whole companion targets WSET Level 4 Diploma. Available-pack mastery is not official qualification completion; all four level scopes still have gaps.
- China's eight older map facts stay optional atlas references for general tracks. Its 44 analytical points remain Diploma-only.
- Author original study material with primary citations. All new facts remain `unverified` pending qualified review.

## Status

**Merged.** [PR #20](https://github.com/Xaiando/Mobile/pull/20) is on `main` as `b551996`. Release **0.20.4** contains the climate reasoning points and the nine mapped Pievi. Level 3 is 2,381 facts and Level 4 is 2,853. Sant'Ilario, Cerliana and Valardegna remain unmapped. Curriculum lint was clean and the climate, production and coverage tests passed.

Codex's business branch `codex/diploma-business-channels` is rebased onto merged `origin/main` `b551996`, preserving the Pievi, and uses dataset **0.20.5**. 0.20.4 is already the combined release. Grok will not edit `business_producer_models` or `business_routes_to_market`. Soave's 33 legal UGAs are Grok's current atlas set. Codex keeps business producer/route files. Grok will not edit those. Dataset for the Soave work will be **0.20.6** so it does not take Codex's 0.20.5.

## Grok pass log

1. Claimed Soave UGAs. Legal list remains the 33 names in Gazzetta Ufficiale 4 November 2019, not the concatenated press list. Work starts from `origin/main` `b551996` in `D:\Apps\sommelier-soave`, branch `grok/soave-ugas`.
2. Accepted Castelcerino. Wikidata Q18504312 and GeoNames 3179731 both put it in Soave.
3. Accepted Fittà. GeoNames 8954880 is in Soave. No separate Wikidata item.
4. Accepted Colombara. GeoNames 8962832 is the only Colombara in a Soave municipality: San Giovanni Ilarione.
5. Accepted Duello. GeoNames 8956774 is in Roncà, which is inside the Soave production area.
6. Accepted Brognoligo from Wikidata Q3645230, a settlement in Monteforte d'Alpone. Did not use GeoNames 8948888, because that point is the combined name Brognoligo-Costalunga.
7. Accepted Roncà–Monte Calvarina as one legal unit. The marker is GeoNames 6949595, the Monte Calvarina summit in Roncà, not a boundary of the whole unit.
8. Rejected Costalunga as its own marker. Rejected Costeggiola (Negrar), Campagnola (Zevio and Verona), Ca' del Vento (Roverè Veronese) and Pigno (Lazise). Those are real places outside the Soave municipalities.
9. Wrote the six location items, the source note and `soave_uga_test.dart` in `D:\Apps\sommelier-soave`. Dataset stays **0.20.6**. Geometry was not wired yet at the end of that pass.
10. Not pushed. Lint, coverage and the branch push were still pending, so Codex can still use 0.20.5.
11. Licence split. `tool/geography` allows only one open licence per source, so one mixed-licence layer would fail the checker. Brognoligo and Castelcerino stay Wikidata CC0. Fittà, Colombara, Duello and the Monte Calvarina summit stay GeoNames CC BY 4.0. Two layers, not one. Wikidata P625 claims Q3645230 and Q18504312 were re-read. GeoNames 8954880, 8962832, 8956774 and 6949595 were re-read from the local IT.zip and are in Soave, San Giovanni Ilarione, Roncà and Roncà. GeoNames 8948888 remains Brognoligo-Costalunga and is still unused.
12. Wrote `tool/geography/soave_uga_wikidata_points.geojson` (sha256 `84318aa93919b7b7457199cafe5286170bce2dc2d88984a39428a3cb9e4f6e18`) and `soave_uga_geonames_points.geojson` (sha256 `75268a41d8728dbc7aad7c69d632567673c3826465d9d37a83f8f6971f020221`). Both are LF.
13. Wrote the two TopoJSON assets in tidy key order. Wikidata asset sha256 `58b561ce5e6fdc0cab8468eb717ac2de02dfa97615aee6792740780fbd7289fc`, 373 bytes. GeoNames asset sha256 `bb39be13e53ca7ea50297721ae2dd76e45099d0a2189fefbb27ac668343fd881`, 599 bytes.
14. Registered both sources in `tool/geography/sources.yaml` with those snapshot hashes. Licences are `CC0 1.0` and `CC BY 4.0`, which the checker accepts.
15. Appended `ml_soave_uga_wikidata_markers` and `ml_soave_uga_geonames_markers` at the end of `layers.yaml`, so layer order still matches the manifest.
16. Added the two dataset citations in `assets/curriculum/areas/geography.yaml`, appended both layers before `node_geometries`, and appended the six geometry rows. Rounded manifest coordinates use six decimal places.
17. Moved the Soave worktree's count checks to Level 3 **2,387**, CMS **2,395** and Level 4 **2,859**. Codex is editing those same two test files on the business branch; the edits here are only in `D:\Apps\sommelier-soave`.
18. Updated README, learner progress, the Italy gap-audit row, the geography inventory and the Soave source note in the Soave worktree only. The shared checkout's dirty Codex copies of the progress and gap-audit files were not touched. 1,438 noncountry places and 1,439 location facts: the old 1,423/1,424 figures plus nine Pievi and these six units.
19. Curriculum lint passed: 90 files, release 0.20.6, 2,859 items, 0 errors. The three warnings are the existing uncurated-date, structural-relation and unverified notices. `node check.mjs` reported no Soave layer, hash or geometry errors. It still reports the pre-existing stale geography cache on Windows; those sources were already stale on main and were not rewritten.
20. Coverage baseline rewritten for release 0.20.6 on 2026-09-27. CMS items are 2,395. Core stayed 1,022 because these six facts are secondary. Zero known gaps.
21. Flutter tests passed, 23 tests: `soave_uga_test`, `climate_reasoning_content_test`, `production_curriculum_test`, `bundled_coverage_test` and `geography_atlas_test`. Level 3 is 2,387, CMS is 2,395 and Level 4 is 2,859. Every new Soave location has geometry and a clickable map question.
22. Pushed `grok/soave-ugas` as `b66d5d3` to origin. The branch tracks `origin/grok/soave-ugas`, not main. Not merged, so 0.20.5 stays free for Codex. Grok saw Codex's SDK validation window, dated 2026-09-27T14:42:54.669Z, after these Dart commands had already finished. No further Flutter or Dart command will be started while that window is active.
23. `geography_release_test.dart` on main still omitted `ml_vino_nobile_pievi_markers`, which would fail the ordered layer list. Grok inserted that id where Codex's business worktree already expects it, then appended `ml_soave_uga_wikidata_markers` and `ml_soave_uga_geonames_markers` in manifest order. Did not re-run Flutter during the active SDK window. Integrated totals, when both branches land, should keep Level 3 at 2,387 and CMS at 2,395, and add Codex's 32 business points on top of Level 4 2,859. Grok will not merge that itself.
24. Starting the remaining 27 Soave names. Codex's final SDK window from 2026-09-27T14:59:27.981Z is still recorded as active, so this pass is GeoNames/Node only. No Flutter or Dart until that window is closed. Dataset stays 0.20.6 unless a new licensed point is actually accepted.

## Codex next continuation — D2 producer structures and routes to market

The user asked both agents to continue. Codex now owns only the new business-content files `assets/curriculum/areas/business_producer_models.yaml`, `business_routes_to_market.yaml`, matching scoped case templates under `assets/curriculum/templates/`, source notes `docs/research/business-*-sources.md`, focused tests and `docs/research/diploma-business-channels-continuation.md`. Prefixes: `n_biz_models_` / `ki_biz_models_` / `qt_biz_models_` and corresponding `biz_routes` prefixes. Plan: original cited Diploma-only producer-model and channel comparisons, with conditional written cases using the existing format; no schema or atlas changes.

Codex is reusing the free managed checkout `C:\Users\Kaged\.codex\worktrees\diploma-climate-reasoning\Sommelier study companion` on `codex/diploma-business-channels`. Rebase onto merged `origin/main` `b551996` is complete: release 0.20.4 and all nine mapped Pievi are preserved. This business continuation uses dataset **0.20.5** and app **0.2.11+13**. Grok owns Soave UGAs separately for 0.20.6. **Codex SDK validation window finished at 2026-09-27T14:57:45.717Z; Flutter/Dart are free for Grok.** All stated final gates and the fresh web asset/pin check passed. The local business branch is ready for its integration commit; the exact hash will be recorded here after committing.

## Codex validation and combined-release reminders

Codex business authoring is frozen and reviewed. Current checks: curriculum lint 93 files/zero errors, clean analysis, coverage baseline with zero known blocking gaps. The broader affected run was 248 tests: 245 passed, three stale expectations failed. Root repaired the inherited ordered geography-layer expectation (missing the merged Pievi) and two old D2 totals (38 to 70). The subsequent 23-test business/production/geography run passed, including all five new business tests. Final checksum is `sha256:287e68f9aa7fbc52723930a97e0c34aa9cf0711aa48503a52c4866d5b3821ec4`. Fresh web build and all 126 bundled-asset/runtime-pin checks passed. The SDK window is finished and Flutter/Dart are free.

For Grok integration: retain Codex's new geography_release_test.dart Pievi expectation and append both Soave layers in their actual manifest order. With the six currently authored Soave items plus this 32-point business pack, the merged totals should be Level 3 **2387**, CMS **2395**, Level 4 **2891**, D2 **70**. Reconcile all count tests, including the new business_channels_content_test.dart, plus dataset/app release metadata, summaries and coverage baseline. The isolated business version 0.20.5 should not overwrite a newer published 0.20.6; select the final integrated version from the actual merge/publication state. Preserve all 32 business facts/four cases, climate content, nine mapped Pievi, China preferences, 704 D3 IDs and four incomplete-level flags. Shared-root five dirty files remain preserved.

**Codex final byte cleanup complete at 2026-09-27T15:02:26.569Z.** Exactly one surplus trailing newline was removed from each of the producer template and its source note. Independent byte/parsed-content comparisons passed; the refreshed runtime report and new web build passed, including all 126 assets and runtime pins. Final checksum: `sha256:287e68f9aa7fbc52723930a97e0c34aa9cf0711aa48503a52c4866d5b3821ec4`. The SDK window is closed; Flutter/Dart are free. Business branch is ready for local commit.
