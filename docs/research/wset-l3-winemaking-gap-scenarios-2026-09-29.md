# WSET Level 3 winemaking principle practice: source audit

This local batch adds 40 item-specific, four-option production decisions to existing
`PRINCIPLE_EXPLANATION` assertions in the **winemaking** domain: 12 fault and packaging,
12 sparkling, 12 fortified and four regional production examples. They were selected
from the 184 unserved Level 3 core winemaking-principle IDs measured at the
`a8eb1a7` base, after the earlier 37-question Level 3 winemaking batch. The IDs
do not overlap any pre-existing authored-choice template. All assertions remain
`unverified` pending qualified wine educator review.

[WSET Level 3 Award in Wines, Specification (2022, Issue 2)](https://www.wsetglobal.com/media/11731/wset_l3wines_specification_en_highres_may2022_issue2.pdf)
and the [current qualification overview](https://www.wsetglobal.com/qualifications/wset-level-3-award-in-wines)
frame this as application of winery, maturation and bottling factors to wine style
and quality, including still, sparkling and fortified wines. The choice prompts
are original study cases, not WSET examination questions or a credential claim.
The regional and producer examples illustrate bounded cellar choices; they are
not universal rules for an appellation or proof of a wine's quality.

## Evidence checked

Each choice records the existing knowledge item's linked `sourceCitationId` in
`wset_l3_winemaking_gap_scenarios.yaml`. The following are the 29 distinct
primary source records used. Source-to-item attribution and HTTPS links are
checked by the focused test.

| Source records | Publisher and bounded claim |
| --- | --- |
| [`src_fault_faults_overview`](https://www.awri.com.au/industry_support/winemaking_resources/sensory_assessment/recognition-of-wine-faults-and-taints/wine_faults/) | AWRI: oxygen lets acetic acid bacteria convert ethanol to acetic acid. The direct page timed out in one browser request; publisher-indexed text and the independent [AWRI microbiological hazes page](https://www.awri.com.au/industry_support/winemaking_resources/fining-stabilities/hazes_and_deposits/microbiological/) confirmed the same mechanism. |
| [`src_fault_sulfur`](https://www.awri.com.au/industry_support/winemaking_resources/storage-and-packaging/pre-packaging-preparation/removal-volatile-sulfur-compounds/) | AWRI: aeration, disulfide formation, copper treatment limits and multiple causes of sulfur faults. |
| [`src_fault_brett_control`](https://www.awri.com.au/files/attachment/brett-fact-sheet/) | AWRI: controlling Brett cells does not erase dissolved phenolic taint; diagnose microbial haze. |
| [`src_fault_oxidation_white`](https://www.extension.iastate.edu/wine/oxidation-white-wine) | Iowa State Extension: polyphenol oxidase and early white-must browning. |
| [`src_srv_awri_light`](https://www.awri.com.au/wp-content/uploads/2018/07/s2018.pdf) | AWRI: light, riboflavin and sulfur-containing precursors in light-struck aroma. |
| [`src_win_packaging`](https://www.awri.com.au/wp-content/uploads/2015/05/1704-tran-et-al-WVJ-30-2-2015.pdf) | AWRI: packaging-line inputs, contact points and post-filtration microbial risk. |
| [`src_spark_base_wine`](https://www.wolfblass.com/en-au/about/our-craft/sparkling.html) | Wolf Blass producer account: early-picked, high-acid base-wine style; producer practice, not a mandatory method. |
| [`src_spark_blending`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/blending-champagne) | Comité Champagne: complementary base-wine blending. |
| [`src_spark_pressing`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/pressing) | Comité Champagne: separate press fractions for selection and blending. |
| [`src_spark_fermentation`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/fermentation) | Comité Champagne: full, partial or absent malolactic fermentation as a style choice. |
| [`src_spark_tirage`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/bottling-and-second-fermentation) | Comité Champagne: tirage yeast and sugar yield alcohol and trapped carbon dioxide. |
| [`src_spark_carbon_dioxide`](https://www.extension.iastate.edu/wine/carbon-dioxide-tis-season-bubbles) | Iowa State Extension: temperature dependence of dissolved carbon dioxide. |
| [`src_spark_gas_recovery`](https://www.awri.com.au/wp-content/uploads/2025/01/s2430.pdf) | AWRI: pressure management and gas retention during sparkling processing. |
| [`src_spark_disgorgement`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/disgorgement) | Comité Champagne: bottle opening and renewed air contact at disgorgement. |
| [`src_spark_dosage`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/dosage) | Comité Champagne: dosage wine can shape aroma as well as sweetness. |
| [`src_spark_maturation`](https://www.champagne.fr/en/about-champagne/how-champagne-is-made/maturation) | Comité Champagne: lees maturation and evolving aroma or texture; no quality guarantee from duration alone. |
| [`src_spark_australian_methods`](https://www.australianwine.com/experience/articles/how-sparkling-wine-is-made) | Wine Australia: bottle fermentation and lees ageing precede bulk tank filtration in the transfer method. |
| [`src_spark_gushing`](https://www.awri.com.au/wp-content/uploads/2021/01/s2195.pdf) | AWRI: particles and crystals can nucleate gushing. |
| [`src_fort_madeira_process`](https://vinhomadeira.com/o-vinho-madeira/vinificacao-e-envelhecimento) | Madeira wine institute (IVBAM): Canteiro cask ageing, Estufagem heating, and fortification timing for sweetness. |
| [`src_fort_port_making`](https://www.ivdp.pt/en/wines/port-wines/the-winemaking/) | IVDP: spirit interrupts Port fermentation while grape sugar remains. |
| [`src_fort_port_intro`](https://www.ivdp.pt/en/wines/port-wines/introduction/) | IVDP: Ruby youth/fruit compared with Tawny cask development. |
| [`src_fort_sherry_fortification`](https://www.sherry.wine/sherry-wine/production/fortification) | Sherry Consejo: sensory classification, flor-permitting fortification and stronger oxidative route. |
| [`src_fort_sherry_flor2`](https://www.sherry.wine/news/biological-ageing-sherry-veil-flor-part-2) | Sherry Consejo article: younger wine refreshes flor nutrients. |
| [`src_fort_sherry_oloroso`](https://www.sherry.wine/sherry-wine/dry-sherry-wines/oloroso) | Sherry Consejo: fully fermented, dry Oloroso with oxidative richness. |
| [`src_fort_vdn_process`](https://www.roussillon.wine/wp-content/uploads/2023/05/dossier-de-presse-2022-gb-_compressed.pdf) | CIVR: mutage retains fruit sugar; Ambré/Tuilé air-contact maturation contrasts with youthful styles. This is a producer-body account, not a legal-conditions update. |
| [`src_reg_fs_madiran_cellar`](https://madiran-pacherenc.com/les-vins/les-vins-de-madiran/) | Madiran regional body: tannin maturity, maceration and extraction trials. |
| [`src_reg_gr_santorini`](https://winesofgreece.org/pdo/pdo-santorini/) | Wines of Greece: fine lees and sometimes oak for richer Assyrtiko white. |
| [`src_reg_na_cristom`](https://cristomvineyards.com/winemaking/) | Cristom producer: whole-cluster Pinot can add tannin and spicy or herbal notes, varying by lot. |
| [`src_reg_ib_mancha_ferment`](https://lamanchawines.com/7514-2/) | La Mancha wine body: temperature-controlled fermentation can support fresh, aromatic young Airén. |

## Measured practice effect and limits

The same-date Level 3 coverage report rose from **1,467 to 1,507 useful core
practice items out of 2,232**. Winemaking rose from **189 to 229 of 451** core
items. The unserved winemaking pool is still **222**: 144
`PRINCIPLE_EXPLANATION`, 22 `CASE_REASON`, 19 `CASE_LIMITATION`, 18
`CASE_ACTION`, 18 `CASE_TRADEOFF`, and one `CAUSES_STATE`. These counts
measure the app's practice formats, not learner mastery. The batch does not
complete Level 3 winemaking, written-response practice, tasting, or the WSET
qualification. It does not add or alter the underlying facts.

All 40 answers require expert adjudication for viticultural and cellar
nuance, distractor ambiguity and level fit. The automated checks establish
source linkage, distinct options, answer-position balance, ingestion and useful-practice
delivery, not professional content verification.
