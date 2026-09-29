# Level 3 general viticulture practice — source and scope audit

Release `0.24.30` adds 22 item-specific, four-option decisions for existing
Level 3 core `PRINCIPLE_EXPLANATION` items. The batch adds a recognition family
alongside recall; it does not add new curriculum assertions, mappings or a
claim that any item has received qualified expert verification. All 22 items
remain `unverified` in the dataset.

| Decision theme | Existing item IDs | Primary evidence already linked to each item |
| --- | --- | --- |
| Vine identity, crossing, grafting | `ki_wset_prod_species_variety`, `ki_wset_prod_cross_hybrid`, `ki_wset_prod_graft_not_cross` | Penn State Extension grape production; Cornell grape-breeding resource |
| Climate and site interpretation | `ki_wset_prod_climate_types`, `ki_wset_prod_warmth_categories`, `ki_wset_prod_continental_diurnal`, `ki_wset_prod_water_moderation`, `ki_wset_prod_site_fog`, `ki_wset_prod_soil_heat` | UK Met Office climate zones; Wine Australia; Australian Bureau of Meteorology; UC Davis; NC State Extension |
| Vineyard design and winter protection | `ki_wset_prod_trellis_untrellis`, `ki_wset_prod_planting_density`, `ki_wset_prod_winter_hilling` | Penn State Extension canopy and grape production; University of Maryland Extension |
| Health and farming systems | `ki_wset_prod_virus_bacteria`, `ki_wset_prod_conventional_ipm`, `ki_wset_prod_sustainable`, `ki_wset_prod_organic_winery`, `ki_wset_prod_biodynamic` | UC Statewide IPM; Wine Australia; European Commission organic rules; Demeter standard |
| Harvest, water and nutrition | `ki_wset_prod_harvest_whole_bunch`, `ki_wset_prod_harvest_cost_quality`, `ki_wset_prod_irrigation_methods`, `ki_wset_prod_nutrition_test`, `ki_wset_prod_dormancy_budburst` | Australian Wine Research Institute; Australian Productivity Commission; NSW DPI; Penn State and NC State Extension |

The template names one `sourceCitationId` for each answer, and the focused
regression asserts the citation is linked to that exact knowledge item. The
original URLs and locators are in the curriculum's `source_citations` and
`knowledge_item_citations` tables. Spot-checks of the official [Met Office
climate classification](https://weather.metoffice.gov.uk/climate/climate-explained/climate-zones),
[UC grape IPM guidelines](https://ipm.ucanr.edu/agriculture/grape/),
[European Commission organic-production rules](https://agriculture.ec.europa.eu/farming/organic-farming/organic-production-and-products_en),
and [Wine Australia's sustainability program](https://www.wineaustralia.com/sustainability/sustainable-winegrowing-australia)
support the bounded decisions in those topics. The AU program explicitly
covers environmental, social and economic dimensions; the choice does not
equate its certification with organic certification.

The questions deliberately avoid a promised flavour from a soil name, a
universal quality ranking for harvest method, or inferring annual climate
from a single diurnal observation. These distinctions matter more at Level 3
than recall of a term alone. Correct answers are distributed 6/6/5/5 and none
is uniquely longest or shortest among its options. The aggregate test verifies
ingestion and Level 3 serving; the coverage report measures the batch as 22
new core items with useful practice, 1,546 to 1,568 of 2,232. This metric is
study-tool availability, not an official exam pass or full syllabus audit.
