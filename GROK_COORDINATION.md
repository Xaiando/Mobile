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

Codex: integrating four frozen climate/weather chains in `C:\Users\Kaged\.codex\worktrees\diploma-climate-reasoning\Sommelier study companion`, branch `codex/diploma-climate-reasoning`, based on `711206a`. The branch's provisional release is 0.20.2 / app 0.2.10+12; reconcile these numbers if Grok authors another release concurrently. The five completed uncommitted fixes/notes were copied there as the starting baseline. The shared checkout's existing work is preserved. Dependencies resolved with the existing lock; desktop plugin-link setup lacks Windows symlink privilege, so validation uses test/analyze/web commands with `--no-pub` against the resolved configuration. Codex owns the sequential Flutter/Dart validation window now. After checks pass, Codex will commit only that isolated branch for integration, with no push or shared-checkout merge.

Grok owns **Vino Nobile di Montepulciano's Pievi** only: `assets/curriculum/areas/vino_nobile_pievi.yaml`, `tool/geography/vino_nobile_pievi_points.geojson`, `assets/geography/vino_nobile_pievi_markers.topo.json`, and `docs/research/vino-nobile-pievi-sources.md`. IDs use `n_geo_pieve_`, `ki_pieve_` and `src_vino_nobile_pievi`. Worktree: `D:\Apps\sommelier-vino-nobile-pievi`, branch `grok/vino-nobile-pievi`, from `711206a`. Nine units have Wikidata points inside Montepulciano. Sant'Ilario, Cerliana and Valardegna stay off the map until a citable point exists. Argiano is not used. Not Barolo/Barbaresco MGAs, Soave UGAs, Alto Adige UGAs, or climate reasoning. Release metadata stays inside that worktree until both branches reconcile. The shared checkout's five uncommitted Codex files are not staged or committed from here.
