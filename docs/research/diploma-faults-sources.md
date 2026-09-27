# Diploma faults and quality-control source notes

Researched on 27 September 2026 in Europe/Oslo, with the UTC curation boundary on 26 September. This extension adds **38 original principles and five conditional decision cases**, each with four independently reviewable rubric facts: **58 items, 101 nodes, 58 relations, 105 track mappings, 61 answer aliases and 60 item citations using 16 primary technical sources**. Thirteen source records are new; three reuse canonical records from the existing production/service modules. All items remain `unverified` until a qualified reviewer records a review in the ledger.

The authored files are [principles_faults.yaml](../../assets/curriculum/areas/principles_faults.yaml) and [faults_cases.yaml](../../assets/curriculum/templates/faults_cases.yaml). No geographic nodes, map assets or legal limits are added. Shared relation definitions and recall templates are reused from the preceding production release.

## Source register

| Source ID suffix | Primary source | Used for |
|---|---|---|
| `oxidation_white` | [Iowa State: Oxidation in White Wine](https://www.extension.iastate.edu/wine/oxidation-white-wine), Aude Watrelot, 25 February 2020 | Intended style and enzyme-mediated must browning |
| `oxidation_dangers` | [Iowa State: Dangers of Oxidation in Table Wines](https://www.extension.iastate.edu/wine/wp-content/uploads/2021/08/dangers-of-oxidation.pdf), Murli Dharmadhikari | Fruit loss, browning and the peroxide/ethanol mechanism |
| `sulfur` | [AWRI: Removal of volatile sulfur compounds](https://www.awri.com.au/industry_support/winemaking_resources/storage-and-packaging/pre-packaging-preparation/removal-volatile-sulfur-compounds/) | Sulfur species, diagnosis, aeration limits, dissolved copper species and packaging risks |
| `copper_aroma` | [AWRI Annual Report 2024](https://www.awri.com.au/wp-content/uploads/2024/12/AWRI-Annual-Report-2024.pdf), printed p. 38, PDF p. 40 | Potential loss of desirable thiol or flinty aromas with copper treatment |
| `brett_faq` | [AWRI: Brettanomyces FAQ](https://www.awri.com.au/industry_support/winemaking_resources/frequently_asked_questions/brettanomyces-faq/) | Phenol descriptors, matrix effects, misdiagnosis and bottle growth |
| `brett_control` | [AWRI: Controlling Brettanomyces during winemaking](https://www.awri.com.au/files/attachment/brett-fact-sheet/), updated February 2023 | Coordinated prevention, cell versus phenol treatment and remediation tradeoffs |
| `va_technical` | [AWRI: The relationship between acetic acid and volatile acidity](https://www.awri.com.au/wp-content/uploads/2021/04/TR-143.TECHNOTE.03.pdf), Don Buick and Matthew Holdstock, Technical Review 143, April 2003, pp. 40–43 | Volatile-acid measurement and normal fermentation contributions; its historical legal limits are unused |
| `faults_overview` | [AWRI: Wine flavours, faults and taints](https://www.awri.com.au/industry_support/winemaking_resources/sensory_assessment/recognition-of-wine-faults-and-taints/wine_faults/) | Acetic acid bacteria, ethyl acetate, TCA and detection versus rejection |
| `oak_taints` | [AWRI: Wine taints from oak](https://www.awri.com.au/wp-content/uploads/2023/02/s2327.pdf), Adrian Coulter, 2023, printed pp. 56–57 | Non-cork TCA sources and similar musty compounds |
| `taints` | [AWRI: Taints in wine](https://www.awri.com.au/wp-content/uploads/2018/03/s1903.pdf), March 2017, issue 638, printed p. 64 | TCA suppression of desirable fruit |
| `src_srv_awri_light` (reused) | [AWRI: Lightstruck character](https://www.awri.com.au/wp-content/uploads/2018/07/s2018.pdf), Adrian Coulter, July 2018, printed pp. 76–77 | Riboflavin photochemistry, glass transmission and exposure spectrum/intensity |
| `heat_light` | [AWRI: The effects of heat and light on wine during storage](https://www.awri.com.au/wp-content/uploads/TN09.pdf), TN09 | Glass versus display tradeoff and limitations of interpreting physical heat damage |
| `src_srv_awri_storage` (reused) | [AWRI: Transport and storage](https://www.awri.com.au/industry_support/winemaking_resources/storage-and-packaging/post-packaging/transport-and-storage/) | Same-wine holdbacks, multiple assessment methods and package stress |
| `src_win_packaging` (reused) | [AWRI: Microbiological stability of wine packaging in Australia and New Zealand](https://www.awri.com.au/wp-content/uploads/2015/05/1704-tran-et-al-WVJ-30-2-2015.pdf), Tran, Wilkes and Johnson, March/April 2015, printed pp. 46–49 | Refermentation, sporadic contamination, audit inputs, biofilms and sanitation |
| `mousiness` | [AWRI: Avoid mousy, off-flavours](https://www.awri.com.au/wp-content/uploads/2018/04/s1694.pdf), February 2015, printed p. 50 | Delayed retronasal perception, pH and individual sensitivity; old assay-availability statements are unused |
| `sensory_thresholds` | [AWRI: Smoke taint decision-making: simple steps for reliable sensory testing](https://www.awri.com.au/wp-content/uploads/2021/06/Technical_Review_Issue_252_Nandorfy.pdf), Damian Espinase Nandorfy, June 2021, printed p. 11 | Meaning and limits of a panel-specific, matrix-specific detection threshold |

Source access dates describe retrieval, not publication. Living pages use no invented publication date. Some AWRI attachment landing pages returned errors; the threshold citation uses the working publisher-hosted PDF linked by AWRI's technical-notes index. PDF inspection also corrected source titles and printed-page locators before finalisation.

## Assessment and track decisions

All 38 principles map editorially to WSET Level 3 and CMS Certified at depth 2; nine foundational points also map to Level 2. The 20 case facts map directly to Level 4 at depth 3, while Level 4 inherits the lower-level foundations. These are original study selections, not examining-body endorsements or proprietary rubrics.

There are 29 winemaking items, 12 service items and 17 tasting items. Tasting items describe sensory observations and diagnostic limits; they do not promise that an aroma proves a laboratory compound, microorganism, region or grape identity. Service items concern preservation, retail light exposure and shipment assessment. Diploma progress routing is owned by the release integrator; service support is not automatically assigned to a Diploma unit.

All items disable MCQ because plausible alternatives can be defensible. Brief answer labels and aliases support cited typed recall; their qualified assertions carry the fuller explanation. Short answers are self-checked against four canonical items, not automatically marked essays or official Diploma assessment.

Each unique template has exactly one `scope_node_ids` entry:

- `n_fault_case_sulfur_before_bottling`
- `n_fault_case_brett_rising`
- `n_fault_case_lit_display`
- `n_fault_case_hot_delivery`
- `n_fault_case_sporadic_sweet_spoilage`

Scenarios are synthetic teaching premises. Proposed responses and practical tradeoffs are reasoned applications of the cited mechanisms. For example, keeping sale stock protected while using display examples is an editorial application of light-protection evidence; the source does not prescribe every retail layout. Similarly, the time and samples required by a shipment investigation follow from the specified comparison procedures, without asserting a universal commercial cost. Other defensible actions may exist.

No universal sensory fault threshold, chemical treatment recipe, copper dose, sanitiser temperature, safe light exposure time, or fixed decanting duration is authored. The sulfur explanation uses the more recent AWRI guidance on copper species remaining dissolved; it does not repeat the older simplified claim that copper sulfide always precipitates and is removed by filtration. Physical leakage is qualified separately from sensory deterioration, and cell removal separately from existing phenol removal.

This is a further D1 and D3 foundation. Qualified review, physical tasting practice, advanced analytical exercises and complete Diploma coverage remain outstanding. The sources' PDFs and artwork are not bundled; only original text and citation metadata are authored.
