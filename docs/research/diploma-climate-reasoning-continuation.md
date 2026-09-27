# Diploma climate and weather reasoning — provisional 0.20.2

This isolated continuation adds **four original causal exercises and 20 cited Diploma-only points** to the reasoning engine introduced in [0.20.0 and validated with 0.20.1](diploma-reasoning-continuation.md). It extends D1 study with frost protection, ripening physiology and wet-weather disease risk. It does not complete the climate syllabus, written analysis, tasting, regional study or research requirements.

## Conditional mechanisms

| Exercise | Assessed two-edge route and supplied limits |
|---|---|
| Wind-machine mixing | A measured reachable warm inversion and suitable fan operation allow warmer air to mix down to vine level, raising canopy-air temperature relative to an otherwise matched unmixed comparison. Mixing redistributes existing heat; it does not promise a fixed gain, uniform protection or bud survival. |
| Overhead freezing | Adequate continuous freshwater supply freezes on uniformly wetted tissue, releasing latent heat and maintaining near-freezing temperature at that tissue while the specified heat balance persists. Coverage, re-wetting and wind/wet-bulb conditions must remain within design capacity. An ice coat or warmer dry-bulb reading alone does not prove safe protection or shutoff. |
| Respiratory malate balance | Non-damaging post-veraison warming accompanies an explicitly measured increase in malate-consuming respiratory flux. Matched starting pools, replenishment, other losses and berry volume allow the isolated respiratory difference to leave less malate per berry. Temperature alone, warmer nights and fixed wine-pH or style predictions are not assumed. |
| Botrytis infection risk | Susceptible mature grapes with viable conidia remain surface-wet longer within a conducive temperature/wetness range. That supplies a more favorable germination and infection opportunity, increasing risk relative to rapid drying. Humidity alone is not substituted for free surface water, and greater risk does not mean every berry becomes diseased. |

These are original hypothetical comparisons with explicit controls, not reports of measured vineyards or operational prescriptions for an unassessed frost or disease event. The [frost source note](reasoning-climate-frost-sources.md) and [ripening and wet-weather source note](reasoning-climate-ripening-sources.md) identify the exact passages, controls and distinct wrong-option justifications.

The frost pack uses live primary NC State and FAO material for inversion mixing, freezing heat, continuous supply and wet-bulb risk, including one reused canonical NC State reference. The ripening pack uses Rienth's live original microvine study and Sweetman's original indexed study passages with their stage and thermal-regime qualifications. Latorre's live primary abstract supplies the laboratory free-water germination evidence; Ciliberti's indexed original Methods, Results and Discussion supply the controlled mature-berry risk evidence. Direct opening of Sweetman encountered a browser challenge, APS returned 403, and the linked Botrytis PDFs failed in the author's browser checks. Those failures are not presented as successful live full-PDF retrieval. All relevant supporting passages were read through the successful live or indexed primary routes recorded in the notes.

## Material and learner behaviour

The addition contains 24 nodes, 20 relations, 20 aliases, 20 mappings, seven new sources and 29 citation links. Its eight primary references include one reused source identity. Four final conclusions are WSET_L4 core depth 4; four supporting edges are core depth 3; twelve direct contradiction facts are secondary depth 2. All 20 points remain **unverified** pending qualified review, and generic MCQ is disabled. No new types, relation signatures or recall templates are required.

Together with the starter, the app now authors **eight reasoning chains over 41 Diploma-only points**: eight depth-4 conclusions, nine depth-3 supports and 24 depth-2 contradiction facts. Only the eight final conclusions count as independently served reasoning targets. Supports and option explanations do not inflate that count.

Each new exercise retains the existing complete-chain and grading contract. Three distinct wrong choices have explicit current cited `CONTRADICTS` evidence from the starting premise. A correct answer reviews both assessed positive points once as Good; a wrong answer reviews only the final point as Again. Supporting points must already have review states and all assessed members must be current and mapped to the active track. Feedback includes the ordered chain and sources; contradiction evidence receives no additional credit. The engine's existing seed, shown-choice and review-event persistence remains unchanged.

D1 receives these viticulture points through its existing domain routing. The continuation adds no lower-track mappings or geography. China's 44 analytical points remain Diploma-only, its eight older supplementary map facts remain optional atlas support, and D3 retains its 704 analytical identifiers. Maps, existing regional comparisons and certification inheritance are not expanded by these mechanisms. All four level scopes retain `curriculumComplete: false`; mastery of available app material and self-reported examination passes remain separate from qualification completion.

An independent parse of the integrated provisional manifest inventories 86 includes and the following totals. Runtime generation and coverage also confirm these counts; they describe authored app material rather than an official assessment syllabus.

| Object | Count |
|---|---:|
| Nodes | 3,299 |
| Relations | 2,955 |
| Knowledge items | 2,844 |
| Certification mappings | 5,762 |
| Aliases | 1,475 |
| Sources | 841 |
| Item citations | 3,381 |

## Validation — local checks complete

The isolated curriculum version is **0.20.2**, published at **2026-09-27T13:43:14.717Z**, and the app version is **0.2.10+12**. The measured dataset checksum is `sha256:57ea8d3c2867ef129463ce4056108159f42e4c9bb638e014d0cae45ab458f494`.

- The full Flutter suite completed **802 tests: 800 passed and two new climate tests failed** because their shared prefix filter also selected three existing recall templates. The filter now requires reasoning mode. All **five climate tests then passed**, covering exact controlled prompts, ordered paths, current cited alternatives, Diploma-only depths, canonical source reuse and actual D1 routing after 20 reviews. This is a broad run followed by a successful targeted repair, not a second full-suite pass.
- The full run also passed the expanded real-bundle reasoning integration checks: eight final targets, studied support, selected-track restrictions, target-only coverage, complete-chain credit, wrong-target blame, atomic rollback and answer backup/restoration. The prior parser-default repair is included and passed in the broad run.
- Final `flutter analyze --no-pub` reported no issues. Curriculum lint checked **88 files with zero errors**, retaining three warning categories: 1,835 uncurated dates, 111 structural relations requiring curator review, and all 2,844 items awaiting qualified review.
- Runtime generation yields **11,783 single-item presentations and 377 pools**: 31 profiles, 244 paired explanations, 94 cases and eight reasoning chains. Coverage has 2,380 CMS Certified points, 2,372 WSET Level 3 points and 2,844 Level 4 points, with zero blocking gaps against the authored policy. The regenerated baseline records eight independent reasoning conclusions, six viticulture and two winemaking. Useful practice in Level 4 rises to 1,686; this does not establish complete official syllabus coverage.
- Independent checks confirm all **116 prior curriculum/geography/schema/lock hashes**, all 82 older includes in their relative order, the six frozen new content/source-note hashes, all 704 D3 identifiers and four incomplete level flags. The only progress-scope change is the D1 gap description. Lower mappings, maps, schema and dependency lock remain unchanged.
- A fresh release web build with local resources succeeded, including its Wasm dry run. All **120 bundled curriculum, geography and progress assets** match source bytes; the SQLite Wasm and Drift worker match both pinned SHA-256 values and package versions. Build metadata identifies 0.2.10+12.

The first fresh worktree checkout converted the vendored Drift worker from LF to CRLF on Windows, causing its pinned checksum to fail. The existing pinned upstream bytes were restored, and `.gitattributes` now disables text conversion for that file. A second fresh web build and strict integrity check passed. Neither the runtime version nor its lock changed. Dependencies resolved from the existing lock, but desktop plugin-link refresh lacked Windows symlink privilege; analysis, tests and web builds used `--no-pub` against the resolved configuration. No Windows desktop build or system-setting change is claimed.

The work is ready for integration on managed branch **`codex/diploma-climate-reasoning`**, based on **`711206a`**. The shared-root coordination note records Grok's separate Pievi ownership and the integration commit. The five previously uncommitted parser/validation fixes are included in this branch; preserve their shared-root copies while reconciling Git integration. Release metadata remains provisional for the combined release: retain both sourced additions, reconcile version numbers and regenerate the merged coverage baseline, checksum and release evidence. Combined integration, publication, device installation and remote CI remain separate work. All broader Diploma gaps and qualified review remain open.
