# Shared Level 2/3 grape practice review, provisional 0.24.12

The older [0.24.6 gap audit](wset-1-3-practice-gap-audit-2026-09-29.md) named 62 shared grape profile and structure IDs. At the 0.24.9 PR25 base, 32 already had registered authored choices. PR29's Level 2 application choices then served 10 more of the same IDs. This rebased batch adds the **final 20 distinct IDs**: 3 profile/variation, 9 berry-skin and 8 structural facts. It does not turn on generic MCQ or assign study-game coverage. The source assertions remain marked unverified for qualified wine review.

| App track | Core useful practice at 0.24.11 | Provisional 0.24.12 | Net |
| --- | ---: | ---: | ---: |
| WSET Level 2 | 535 / 744 | 555 / 744 | +20 |
| WSET Level 3 | 1,219 / 2,228 | 1,239 / 2,228 | +20 |
| WSET Level 4 | 1,227 / 2,649 | 1,247 / 2,649 | +20 incidental shared coverage |

These are app-defined useful-practice counts measured by `tool/coverage_report.dart`, not exam results or a WSET pass. All 20 are served in both L2 and L3 by the authored-choice engine; their existing flashcards supply the second format family under the app's coverage policy. Question counts rose from 565 to 585 in the Level 1–3 authored-choice regression. The 20 keys use answer positions 0/1/2/3 **5/5/5/5** times. The original 62-ID pool is now fully served; the total remaining core useful-practice gaps are 189 in L2 and 989 in L3 across other areas.

## Source-to-choice audit

Each new question cites one source already associated with the knowledge item, except Zinfandel berry colour, for which this batch adds the direct [UC Davis variety-registry source](https://fps.ucdavis.edu/FGRfamilies.cfm?varietyid=1200) to the item's citation list. The cited passage supports the keyed conclusion; alternatives are contradicted by the cited fact or make an unsupported universal claim. The questions use conditional language when site, maturity, extraction or maturation can alter the wine. Berry-skin classification is explicitly distinguished from finished-wine colour. The Pinotage variation asks for oak-note attribution rather than repeating PR29's profile question; the Albariño structure item asks for sugar-to-potential-alcohol reasoning rather than repeating PR29's acidity recognition.

| Source and scope checked | New item IDs (prefixes `ki_wset_grape_` or `ki_wset_structure_`) |
| --- | --- |
| [Amarone DOCG](https://www.consorziovalpolicella.it/en/types-of-wines/amarone-della-valpolicella-docg/) dried-grape dry wine | structure `corvina_structure` |
| [Wines of South Africa Wine Wise](https://www.wosa.co.za/wosadocs/WINE_WISE_English.pdf), Pinotage chapter | grape `pinotage_variation` |
| [Soave DOC specification](https://www.ilsoave.com/wp-content/uploads/2020/11/Soave-DOC-consolidato-definitivo.pdf) qualitative acid balance | structure `garganega_structure` |
| [UC Davis / UC Agriculture and Natural Resources Assessments of Ripeness](https://my.ucanr.edu/repository/fileaccess.cfm?article=95501&p=AAOEPD), fermentable sugar and potential alcohol | structure `albarino_structure` |
| [Montepulciano d'Abruzzo DOC specification](https://www.vinidabruzzo.it/wp-content/uploads/2024/02/Montepulciano-dAbruzzo-Disciplinare.pdf), article 6 | grape `montepulciano_variation`; structure `montepulciano_structure` |
| [Wine Australia Chardonnay](https://www.wineaustralia.com/market-insights/regions-and-varieties/chardonnay), regional and cellar-style spectrum | grape `descriptor_context` |
| [vitisDB Barbera](https://vitisdb.it/varieties/pdf/979?extended=true), [Cortese/Corvina list](https://vitisdb.it/varieties/list?page=15), [Garganega ampelography](https://vitisdb.it/accessions/ampelography/16362) | grape `barbera_berry_colour`, `corvina_berry_colour`, `cortese_berry_colour`, `garganega_berry_colour` |
| [Italian regional vine register](https://burc.regione.campania.it/eBurcWeb/directServlet?ATTACH_ID=212314&DOCUMENT_ID=00140879), VBN entry; [UC Davis Primitivo/Zinfandel registry](https://fps.ucdavis.edu/FGRfamilies.cfm?varietyid=1200), identity and black berry colour | grape `montepulciano_berry_colour`, `zinfandel_berry_colour` |
| [Wines of South Africa red grapes](https://www.wosa.co.za/The-Industry/Viticulture/Introduction/); [regional Verdicchio listing](https://www.regione.lazio.it/sites/default/files/documentazione/AGC_DD_G00384_15_01_2018.pdf); [Irpinia Fiano](https://consorziovinidirpinia.it/vitigni/fiano-di-avellino-vitigno/) | grape `pinotage_berry_colour`, `verdicchio_berry_colour`, `fiano_berry_colour` |
| [Verdicchio dei Castelli di Jesi](https://imtdoc.it/vino/verdicchio-dei-castelli-jesi/); [Gavi Cortese](https://www.consorziogavi.com/en/gavi-docg-2/); [Irpinia Fiano](https://consorziovinidirpinia.it/vini/fiano-di-avellino-docg-vino/) | structure `verdicchio_structure`, `cortese_structure`, `fiano_structure` |
| [Grand Tokaj 2024 Furmint](https://summit2025.bor.hu/wines/grand-tokaj-terroir-selection-furmint/), named bottle only | structure `furmint_structure` |

Content checks deliberately avoid claiming every wine of a variety has the cited example's exact acid, oak, alcohol, body or colour. In particular, the Furmint question names the 2024 bottle and does not generalise it to all Furmint. The Montepulciano question uses the DOC's sensory range and does not generalise a producer's acidity.

The template parameter validator and authored-choice ingestion regression check four distinct options, in-range keys, item-linked citations and generated serving without re-enabling generic MCQ on `mcq_disabled` facts. The release lint still reports the three pre-existing dataset curation warnings (effective dates, orphan relations, expert review); it reports no new error. Qualified review of wine wording and distractors remains an editorial release step.
