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

Codex: local climate/weather validation is complete on `codex/diploma-climate-reasoning`, based on `711206a`, in `C:\Users\Kaged\.codex\worktrees\diploma-climate-reasoning\Sommelier study companion`. Four new exercises / 20 Diploma-only points bring the branch to eight reasoning exercises and 2,844 items. Provisional release 0.20.2 / app 0.2.10+12. Broad tests: 800 passed, two new test-filter failures repaired; all five climate tests then passed. Final analysis and lint pass, authored-policy coverage has no blocking gaps, fresh web build and all 120 asset/hash checks pass. The Windows Drift-worker text-conversion issue is fixed by the new `.gitattributes` rule; retain that rule. The sequential SDK validation window has finished. Codex is committing only this isolated branch for integration. The five completed shared-root fixes/notes are included in it; preserve and reconcile their shared-root copies. Combine both authored additions, reconcile release metadata and regenerate the merged coverage baseline/checksum before release. No push or shared-root merge was performed.

Grok's Pieve branch is dataset **0.20.3**, not 0.20.2. Codex keeps 0.20.2 for the climate release. The nine mapped units are unchanged. A GeoNames Italy-dump search found no Siena Sant'Ilario, and no Cerliana or Valardegna at all, so those three stay unmapped. Soave's 33 UGAs are not started: the legal list is Gazzetta Ufficiale 4 November 2019, and press lists that glue Colombara to Froscà are wrong.

Grok owns **Vino Nobile di Montepulciano's Pievi** only: `assets/curriculum/areas/vino_nobile_pievi.yaml`, `tool/geography/vino_nobile_pievi_points.geojson`, `assets/geography/vino_nobile_pievi_markers.topo.json`, and `docs/research/vino-nobile-pievi-sources.md`. IDs use `n_geo_pieve_`, `ki_pieve_` and `src_vino_nobile_pievi`. Worktree: `D:\Apps\sommelier-vino-nobile-pievi`, branch `grok/vino-nobile-pievi`, from `711206a`. Nine units have Wikidata points inside Montepulciano. Sant'Ilario, Cerliana and Valardegna stay off the map until a citable point exists. Argiano is not used. Not Barolo/Barbaresco MGAs, Soave UGAs, Alto Adige UGAs, or climate reasoning. Release metadata stays inside that worktree until both branches reconcile. The shared checkout's five uncommitted Codex files are not staged or committed from here.
