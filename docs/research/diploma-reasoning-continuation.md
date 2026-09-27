# Diploma causal reasoning — introduced in 0.20.0, validated with 0.20.1

This local continuation implements the Q6 objective reasoning runtime and a small original Diploma starter. It follows the [China continuation](diploma-china-continuation.md) and its [implementation audit](reasoning-engine-implementation-audit.md). Broader climate, written-analysis, regional, tasting and research study remain unfinished.

## Learner behaviour

Four exercises ask the learner to apply stated conditions through a complete two- or three-edge causal chain: observed stomatal restriction, carbohydrate-limited fruit set after leaf removal, isolated malic-to-lactic conversion, and molecular sulphur dioxide at controlled free SO₂, alcohol and temperature. These are conditional mechanisms, not universal vineyard prescriptions or guarantees about a finished wine. The [primary-source note](reasoning-principles-sources.md) records the passages, controls and retrieval limits.

Each exercise has four distinct conclusion choices. Every wrong choice has explicit current cited contradiction evidence for the supplied premise; absence from the graph never establishes an incorrect answer. Full chain explanations and sources appear after answering. A correct answer reviews each assessed chain point once as Good. A wrong answer reviews only the final point as Again. Evidence used solely to explain other choices receives no extra review credit.

Reasoning requires a depth-4 mapping. Only a final target can schedule the exercise; support membership does not claim independent reasoning coverage. All assessed members must be current and mapped to the selected session track, and supporting points must already have review states. Existing recall can introduce those points first. The mature-memory ladder prefers reasoning once it is available. A previously studied branch outside the selected track cannot enter the presented chain.

Core validation checks two or three composable cited edges, starting scope, target role, exact stored pool ranks, unknown references, cycles, ambiguous conclusions and three defensible contrasts. The planner and coverage checker revalidate current evidence, including expired, superseded or uncited contradictions. The presenter checks again and preserves complete chains. Existing star-shaped regional explanations and four-role cases are not reinterpreted as causal paths.

Completed review events retain the seed, starting premise, ordered chain, shown choices and selected answer. Success and wrong-target-only answers use the existing atomic review and backup model. Exact restoration of unfinished questions or drafts remains separate work; no schema or dependency change was introduced.

## Material and progress

The addition contains **21 cited Diploma-only points**: four core conclusions at depth 4, five core supporting edges at depth 3, and twelve secondary contradiction facts at depth 2. All remain unverified pending qualified review. It adds 25 nodes, 21 relations, 21 mappings, 21 aliases, two new sources and 22 citation links, reusing three canonical source identities. Four reasoning templates and six recall templates are included.

The bundle now contains **3,275 nodes, 2,935 relations, 2,824 items, 5,742 mappings, 1,455 aliases, 834 sources and 3,352 citations**. Domains contain 359 viticulture, 390 winemaking, 134 business, 30 service, 17 tasting and 1,894 geography points.

Generation provides 11,743 single-item presentations and 373 pools: 31 regional profiles, 244 paired explanations, 94 cases and four reasoning chains. These are presentations of canonical app learning points, not official examination questions. Only four final conclusions count as independently served reasoning targets: two core viticulture and two core winemaking items. Five supports and twelve explanation facts do not inflate that metric. The coverage baseline records the increase from zero to four.

The final bundle preserves 79 preceding curriculum includes and all 32 geography files byte for byte against the fresh 0.19.0 build. The remaining include, `areas/italy.yaml`, differs only in the two documented [0.20.1 factual corrections](fact-check-2026-09-27.md), including their verification timestamps. The reasoning material and its source note retain their reviewed hashes. D3 retains its 704 analytical points across 224 paired subjects and 64 cases. The new mechanisms support D1 through its existing domain grouping. All four level scopes remain incomplete; available-material mastery and self-reported examination passes remain separate from qualification completion.

China's 44 analytical points remain Diploma-only. At the user's confirmed preference, its eight older supplementary map facts remain optional atlas references for the general tracks. The [pinned WSET Diploma specification](https://www.wsetglobal.com/media/17609/wset_l4wines_specification_en_august-2025.pdf), printed p.12, includes China; this continuation does not introduce China into CMS Certified core regional study.

## Validation

The feature was integrated as 0.20.0 at `2026-09-27T12:35:14.000Z`. A separate commit during validation incorporated it into release 0.20.1 and corrected two Italian explanations. Its recorded publication timestamp, `2026-09-27T20:00:00.000Z`, is retained from that commit; it is metadata, not the measured time of these checks. App version is 0.2.9+11. The current curriculum checksum is `sha256:9b3bd74b7662d14644a311e7068b16923ad65027700abafc9af4434448bdc20f`.

- The final combined run against release 0.20.1 passed all 61 tests: the 40 new engine/path, authored-content, real-bundle integration and widget tests, plus the 21 parser regressions. They cover cited positive and negative evidence, ambiguous paths, exact pool ranks, track and depth restrictions, studied support, review credit, transaction rollback, backup round trips and accessibility at a 320-pixel width.
- The broad `flutter test` run completed 797 tests: 796 passed and one older parser-default assertion failed because the new recall templates have explicit variants. The assertion now selects templates whose authored rows omit both optional fields, while separately checking explicit reasoning parameters. All 21 tests in that parser file then passed. This is a broad run plus a successful targeted repair, not a claim that a second full run was performed.
- Final `flutter analyze` reported no issues. Curriculum lint checked 84 files with zero errors; its three warning categories remain 1,835 uncurated dates, 111 structural relations requiring curator review, and all 2,824 points awaiting qualified verification.
- A fresh release web build succeeded with local resources and a successful Wasm dry run. All 116 bundled curriculum, geography and progress assets match the current source bytes. The SQLite Wasm and Drift worker match their recorded SHA-256 pins and package versions; the build identifies itself as 0.2.9+11.
- The independent inventory check confirms the counts above, the four incomplete level flags, all 704 D3 identifiers, preserved map bytes, unchanged schema and dependency lock, and only the two permitted older Italian assertion/timestamp corrections.

The final report on release 0.20.1 confirms 11,743 single-item presentations and 373 pools. Coverage remains 2,380 cumulative CMS Certified points, 2,372 WSET Level 3 points and 2,824 WSET Level 4 points, with zero blocking gaps against the authored policy. Four final targets gain reasoning coverage in Level 4 only. Policy coverage does not measure completion of the official syllabus.

The local repository advanced separately to `711206a` during this run, incorporating the feature and correction commits. The remaining parser-test repair and validation notes are local changes; this continuation does not publish them. A fresh web compilation does not establish device installation, offline reopening or remote CI. Full Diploma coverage, qualified verification and the remaining work in the [gap audit](wset-level-4-gap-audit.md) remain open.
