# Vineyard mechanisms and original Diploma cases

Authored 27 September 2026 for the next curriculum release. This adds a first
production module to the existing atlas; it does not complete the Diploma
production syllabus or establish expert verification.

The two curriculum files are
[`principles_viticulture.yaml`](../../assets/curriculum/areas/principles_viticulture.yaml)
and [`viticulture_cases.yaml`](../../assets/curriculum/templates/viticulture_cases.yaml).
They contain 40 individual learning points in 20 coherent principles and five
original conditional scenarios with four cited rubric points each. There are 60
items, 85 nodes, 120 answer aliases, 60 relations, 140 track mappings, 18 sources
and 60 item citations. No geographic nodes or map assets are added.

Each point is original prose, based on the public science and extension sources
below. No examining body's questions, explanation prose, grading criteria or
tasting artwork is reproduced. All items remain `unverified` until a qualified
reviewer checks them through the existing review ledger. Their timestamps record
this authoring pass, not an expert review.

## Content and level mapping

The principles cover fruit-bearing shoots and the two-season reproductive cycle;
stored carbohydrates; leaf light exposure and photosynthesis; flowering and fruit
set; veraison and ripening; rootstocks and pest resistance; plant and soil water
measurements; severe water stress; regulated deficit irrigation and its limits;
fruit-zone exposure; leaf-removal timing; air and soil drainage; frost types;
overhead frost protection; powdery mildew, downy mildew and Botrytis; crop balance;
representative maturity sampling; and the benefits and risks of longer hang time.

Thirty foundation facts map to WSET Level 2 at depth 2. All 40 principle facts map
to WSET Level 3 at depth 2 and CMS Certified at depth 2. Ten of the more analytical
principle facts additionally map explicitly to WSET Level 4 at depth 3. All 20
scenario rubric facts map to Level 4 at depth 3. The higher WSET levels inherit
the lower levels through the existing cumulative track model. These are editorial
practice mappings, not a claim that a syllabus objective or a level is complete.

The five scenarios are:

| Situation | Evaluated reasoning |
|---|---|
| Dense humid fruit zone after fruit set | Selective opening, airflow and drying, sunburn trade-off, and site/cultivar limits |
| Dry root zone and wilting leaves after veraison | Relieve excessive stress, preserve photosynthesis, avoid excessive lateral growth, and measure plant/soil conditions |
| Calm frost at budbreak with warmer air above | Suitable wind-machine operation, inversion mixing, cost/noise, and limitations in an advective freeze |
| Replant after phylloxera with nematodes and limited water | Resistant grafted roots, root-feeding mechanism, effects on vigour, and species-specific resistance |
| Nearly mature injured fruit before prolonged rain | Consider earlier picking, wet/injured berry rot mechanism, foregone flavour development, and chemical/sensory assessment |

Each scenario asks for a defensible choice under the stated circumstances.
It does not claim there is one uniquely optimal action. The short-answer rubric
is self-checked and each point updates its own FSRS memory. Each template is
restricted by `scope_node_ids` to its case, so another case's points must never
appear beneath the wrong scenario. The existing format selects two to four
points according to its serving rules; this is practice feedback, not an official
exam mark or automated essay assessment.

## Sources and locators

All links were inspected on 27 September 2026. Source editions are identified
only where the document actually states them; an access date does not become a
publication date. University extension publications are classified `academic`;
the NSW Department of Primary Industries guide is `government_publication`.
Sources are cited as evidence for factual principles. Their PDF artwork, tables,
photographs and page layouts are not redistributed in the app.

| ID suffix (`src_vit_…`) | Primary source | Evidence used |
|---|---|---|
| `phenology` | [NMSU, Grapevine Phenology: Annual Growth and Development, H-338](https://pubs.nmsu.edu/_h/H338.pdf) | p. 1: two-season cycle; pp. 6–8: veraison, flowers, fertilization and set; pp. 8–9: ripening chemistry and extended hang-time trade-offs |
| `reserves` | [GWRDC, Post-harvest care of grapevines: Irrigation and nutrition, April 2014](https://www.wineaustralia.com/getmedia/71d11299-dddd-4cc4-ac8f-9b3e94df6170/201404_post-harvest-care-of-grapevines-irrigation-and-nutrition.pdf) | pp. 1–2: early growth draws on perennial reserves and active leaves replenish them |
| `canopy` | [OSU, The role of canopy management in vine balance, EM 9071](https://extension.oregonstate.edu/sites/extd8/files/catalog/auto/EM9071.pdf) | p. 2: outer-leaf light capture and low photosynthesis in deeply shaded inner leaves; edition states June 2013, reviewed 2026 |
| `balance` | [OSU, Understanding Vine Balance, EM 9068](https://extension.oregonstate.edu/sites/extd8/files/documents/em9068.pdf) | Definition, environment, cultivar/rootstock effects and crop-load discussion; site resources determine appropriate vine balance |
| `phylloxera` | [UC IPM, Grape Phylloxera](https://ipm.ucanr.edu/agriculture/grape/grape-phylloxera/) | Description and Management/Cultural Control: root injury, resistant roots, clean stock and local suitability |
| `nematodes` | [UC IPM, Nematodes in grape](https://ipm.ucanr.edu/agriculture/grape/nematodes/) | Rootstocks section and species-specific host-status table; phylloxera resistance does not establish nematode resistance |
| `water_status` | [NSW DPI, Monitoring vine water status, Part 1](https://www.dpi.nsw.gov.au/__data/assets/pdf_file/0004/1158124/Monitoring-vine-water-status-part-1.pdf) | Grapevine management guide 2014–15, pp. 12–13: plant plus soil measures, pressure chamber, soil variability and growth-stage effects |
| `rdi` | [AWRI, An introduction to Regulated Deficit Irrigation, RTP 0037](https://www.awri.com.au/wp-content/uploads/2_irrigation_introduction_to_rdi.pdf) | pp. 1–2: deficit period, sensitivity at flowering, functioning canopy, lateral growth and severe-stress risks; printed 2010 |
| `rdi_limits` | [AWRI, Limitations of Regulated Deficit Irrigation, RTP 0038](https://www.awri.com.au/wp-content/uploads/3_irrigation_limitations_of_rdi.pdf) | p. 1: climate and soil drying/rewetting constraints; printed 2010 |
| `leaf_removal` | [Penn State, Grapevine Fruit Zone Leaf Removal](https://extension.psu.edu/grapevine-fruit-zone-leaf-removal) | Hickey/Centinari video transcript: airflow, spray penetration, timing, fruit-set effects and afternoon sunburn |
| `frost` | [Penn State, Understanding and Preventing Spring Frost and Freeze Damage to Grapes](https://extension.psu.edu/understanding-and-preventing-spring-frost-and-freeze-damage-to-grapes) | Site selection/air drainage, types of frost, and Wind Machines; page states updated 16 February 2026 |
| `frost_ncsu` | [NC State, Prevention and Management of Frost Injury in Wine Grapes](https://content.ces.ncsu.edu/prevention-and-management-of-frost-injury-in-wine-grapes) | Overhead Sprinkler Systems: latent heat, continuous application, supply, coverage, low-wind conditions and drainage |
| `waterlogging` | [UC IPM, Phytophthora Crown and Root Rot of Grape](https://ipm.ucanr.edu/home-and-landscape/phytophthora-crown-and-root-rot-of-grape/) | Life cycle and Damage: saturated soil, zoospores and root infection |
| `powdery` | [UC IPM, Powdery Mildew in grape](https://ipm.ucanr.edu/agriculture/grape/powdery-mildew/) | Comments on the Disease, Management and Resistance Management: early inoculum and effective mode-of-action rotation |
| `downy` | [UC IPM, Downy Mildew in grape](https://ipm.ucanr.edu/agriculture/grape/downy-mildew/) | Comments on the Disease and Management: moisture-driven spread, preventive timing and new unprotected growth |
| `botrytis` | [UC IPM, Botrytis Bunch Rot of Grapes, or Gray Mold](https://ipm.ucanr.edu/home-and-landscape/botrytis-bunch-rot-of-grapes-or-gray-mold/) | Identification, Life cycle and Solutions: wet canopy, berry injury, airflow and earlier picking ahead of wet weather |
| `sampling` | [Ohio State, Determining Grape Maturity and Fruit Sampling, HYG-1436-13](https://ohiograpeweb.cfaes.ohio-state.edu/sites/grapeweb/files/imce/pdf_factsheets/determining%20Fruit%20Maturity.pdf) | pp. 2–3: repeated representative samples, vineyard variation and consistency; document copyright 2013 |
| `maturity` | [Iowa State, Grape Sampling for Maturity Analysis, FS 0049A](https://www.extension.iastate.edu/wine/grape-sampling-maturity-analysis-grape-maturity-series) | Product Description, dated 9 December 2020: trends, soluble solids, pH, titratable acidity and sensory evidence |

The NMSU and Ohio source PDFs were downloaded for factual/page checks into an
ignored local research folder. The byte hashes of the copies read were:

| Source | SHA-256 |
|---|---|
| NMSU H-338, 4,560,535 bytes | `2ebef192d4de2070fc1fb66320733dd448b0f522d771cfb673669b55991eb5d2` |
| Ohio HYG-1436-13, 119,941 bytes | `0e5ad200191fc53b3977881acc4776afb54e7fe88366606ee328bbc7f15a4834` |

Direct downloads of the two Oregon PDFs returned HTTP 403 in this environment.
Their contents were inspected through the primary-site web reader/search index;
no downloaded byte hash is claimed for them. Penn State HTML page opens likewise
returned 403, while indexed article text and the publisher's video transcript
were available. Those limitations do not justify inventing edition metadata.

## Qualification and review safeguards

All new facts set `mcq_disabled: true`. General practices overlap, and the
conditional cases admit other defensible choices; three wrong learning points
cannot safely be fabricated from an absence of edges. Typed recall accepts the
authored names and meaningful aliases for the cited learning points. It tests
recall of a named point, not the completeness of an essay or independent expert
judgment.

No pesticide product doses, universal irrigation volumes, numeric crop-yield
targets, statutory requirements or global harvest sugar/pH thresholds are
authored. California/US/Australian management examples are generalized only to
their stated mechanisms and conditions. For example, phylloxera resistance is
not treated as resistance to every soil pest, water deficit is not always
beneficial, the lowest yield is not declared the best, and wind-machine
protection is not presumed in every freeze.

The NC State page includes a broad sentence suggesting every active frost method
relies on an inversion. The curriculum does not reproduce that broad claim.
It uses the explicit sprinkler mechanism section for continuous freezing-water
protection and the Penn State wind-machine section for inversion dependence.

Remaining production work includes more detailed climate/site comparisons,
soil/rootstock matching, vine nutrition, pruning/training choices, planting
density, vineyard-floor practices, sustainability and economics, broader pest
and disease reasoning, and harvest logistics. The new cases and facts provide
practice within that unfinished programme and need qualified review before any
public claim of complete Diploma parity.
