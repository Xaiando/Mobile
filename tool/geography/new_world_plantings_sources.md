# Dated New Zealand grape-ranking questions

`new_world_plantings.mjs` reproduces twelve source-cited facts and six complete **top-two ranking** sets. They use existing licensed atlas markers and require no new geometry.

Primary source: [New Zealand Winegrowers Vineyard Report 2026](https://www.nzwine.com/media/5fzng52v/vineyard-report-2026-final.pdf), published 26 February 2026 according to the publisher's [report index](https://www.nzwine.com/en/media/statistics-reports/vineyard-reports/). Research retrieval: 26 September 2026. PDF SHA-256: `4066a3575ac5e914f89941428f98396aeff19e78068ceb3593ea10eaf6c94a03`.

The ranking comes from the **observed 2025 planted-area columns** on printed pages 21–22, ranked across all individual-variety rows. The contents page incorrectly describes section 5 as producing area; the actual table heading, figures and regional 2025 columns establish planted area. The 2026–2028 prediction columns and producing hectares are excluded. Both complete table pages were extracted and rendered for verification. No PDF, source illustrations or full table are bundled.

The relation `TOP_PLANTED_GRAPE` denotes this bounded historical ranking. It is independent of permitted-grape relations, does not assert a complete list of cultivated varieties, and does not claim that a region's largest plantings define all of its characteristic wine styles. Every question names the measure and year. A future planting report requires distinct dated facts or an explicit versioned retirement; these historical questions must not silently become current-year claims.

The map format keeps candidates and co-items within the exact relation family. Only regions with a cited complete ranking are selectable, and every represented valid alternative is accepted. Selecting a place matching one of two clues grades each underlying fact independently. Unrepresented regions remain map context, not graded negative answers.

Run `node tool/geography/new_world_plantings.mjs` from the repository root. Its optional research-cache hash is printed if `.dart_tool/nz-vineyard-report-2026.pdf` exists. Regression tests cover ranking membership, typed and MCQ answers, deterministic combination wording, all valid map alternatives and partial grading.
