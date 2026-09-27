# European atlas completion source notes

`assets/curriculum/areas/europe_atlas_completion.yaml` adds **152 geography nodes and cited location items**: **131 in Italy and 21 in Spain**. Each item has editorial mappings to both offered certification tracks and remains unverified pending qualified review. The additions have 12 administrative regions, 34 wine localities, 45 geographical subregions, 59 appellations and two informal study areas. They add no grape-permission or wine-production-rule assertions.

## Covered geography

Italy gains the remaining 12 administrative regions, completing its 20-region framework; all 11 Barolo communes; the Barbaresco, Neive, Treiso and San Rocco Seno d’Elvio localities; all 11 Chianti Classico UGAs; all eight current Chianti subzones; Valpolicella Classico and Valpantena; the five Classico communes; Soave Classico and Colli Scaligeri; Soave and Monteforte d’Alpone localities; Cartizze; the six Alto Adige DOC subzones; and Friuli Colli Orientali's principal geographical subzones. Rosazzo's Ribolla Gialla and Pignolo subzones share a geographical study area, explicitly classified as informal rather than a fabricated new legal unit. Additional missing appellations cover Alto Piemonte, Tuscany, Veneto, Trentino, Lombardy, Friuli, Emilia-Romagna, central Italy, southern Italy, Sicily and Sardinia.

Spain gains the ten current Marco de Jerez production and ageing municipalities, all four Cava zones and seven Cava subzones. Existing content already covers the three Rioja zones, five Rías Baixas subzones, three Douro subregions, nine Vinho Verde subregions and eight Alentejo subregions. Those authored nodes and items were retained without duplicates.

## Primary factual authorities and corrections

The new content registers 13 primary citations and reuses `src_atlas_it_dop_2026`, MASAF's national DOP register updated 18 March 2026. The latter proves appellation identity and administrative region, not an appellation's detailed boundary. Multiregional Lugana, Orvieto and Prosecco use Italy as their common parent. The administrative regions use Istat's 21 February 2026 classification. The informal Alto Piemonte grouping uses the official Visit Piemonte regional tourism description.

The detailed geographical facts use the Barolo specification consolidated 4 March 2026, Barbaresco's consolidated 13 July 2021 specification, Chianti Classico's 1 July 2023 specification and its UGA annex, the current Chianti decree of 5 June 2026, Valpolicella's specification hosted on MASAF's 3 August 2023 consolidated-specification page, Soave's 24 October 2019 consolidated specification, Friuli Colli Orientali's 7 July 2025 consolidated specification, and the respective recognised consortia for Cartizze, Alto Adige, Cava and Jerez. Exact citation URLs and entry locators are in the YAML.

- **Chianti now has eight subzones.** The current 2026 specification, Annex A article 1.1, adds **Terre di Vinci** to Colli Aretini, Colli Fiorentini, Colli Senesi, Colline Pisane, Montalbano, Montespertoli and Rufina. The older seven-zone planning list is stale. Source: [Gazzetta Ufficiale 26A02927](https://www.gazzettaufficiale.it/atto/vediMenuHTML?atto.codiceRedazionale=26A02927&atto.dataPubblicazioneGazzetta=2026-06-12&tipoSerie=serie_generale&tipoVigenza=originario).
- **Municipal inclusion can be partial.** Barolo's three wholly included communes and eight partly included communes are distinguished in each fact. Barbaresco includes only the specified part of San Rocco Seno d’Elvio in Alba. Soave Classico comprises parts of Soave and Monteforte d’Alpone. Municipality locality nodes have their administrative regional parent; they do not assert that every hectare of a municipality lies within an appellation.
- **The Sherry Triangle is historical geography, not the current exclusive ageing limit.** The council's 14 November 2025 description identifies ten municipalities, including Puerto Real and San José del Valle. The facts do not restrict Sherry ageing to the three historic triangle towns. Source: [Consejo Regulador](https://www.sherry.wine/news/the-sherry-triangle-evolves-from-three-to-ten).
- **Vino Nobile's current Pieve name is Sant’Ilario, not Argiano.** The current 2025 legal list was checked against [EU C/2025/2742](https://eur-lex.europa.eu/legal-content/IT/TXT/PDF/?uri=OJ:C_202502742). Its fine-scale points are not yet included in this completion snapshot; the old planning entry must not be authored as a current legal name.

The 11 Chianti Classico UGAs are geographical facts here. These items make no current labelling or vintage claim concerning the staged availability of Lamole, Montefioralle and Vagliagli. Moscato d’Asti was not invented as a separate map region: it belongs to the Asti designation geography already represented in the curriculum.

## Coordinate snapshot and reuse

`europe_atlas_completion_points.geojson` contains **152 exact Earth-coordinate statements from Wikidata**, retrieved **26 September 2026**. Each feature preserves its entity ID, statement ID, entity and JSON URLs, named reference place, source description, coordinate precision and **CC0 1.0** licence. Every marker is explicitly a gazetteer, settlement or municipality reference, never a legal boundary or a computed legal-area centroid. Cartizze uses the named Santo Stefano locality within Valdobbiadene; it does not reuse the town centre as if it were a vineyard polygon.

Snapshot SHA-256: `9dcaeb6a4f1fd7ad3b65bb5d53ed7f585efb2fd72e948f0b61e4263b76a384e9`.

Normal builds must consume this pinned checked-in snapshot. `europe_atlas_completion_points.mjs --author`, run from the repository root with Node 22.13 or later, performs an explicit factual and coordinate refresh; it does not edit manifests, sources or layers. Its title references and ambiguous-name entity IDs are curated, and it refuses to write content if any coordinate is missing or an authored node/item/source would be removed. API response caches live in ignored `.dart_tool/europe_atlas_completion/`. A refresh needs renewed factual/source review, retrieval dates and the pipeline's pinned hash before integration. [Wikidata licensing](https://www.wikidata.org/wiki/Wikidata:Licensing) permits proprietary bundling of the structured CC0 coordinate data.

Local checks found no duplicate node IDs, unknown parents or same-type coordinate collisions. All nodes have one location relation, one location item, a primary factual citation and two track mappings. Manifest integration, map rebuilding and the app's curriculum/coverage checks remain the parent task's responsibility.

## Remaining fine-scale scope

This file does not claim exhaustive European registry coverage. Barolo and Barbaresco MGAs, Vino Nobile's 12 Pievi, Soave's full UGA set, Alto Adige's 86 individual UGAs, Priorat's complete village/single-vineyard lists and Rioja's vineyard register remain separate fine-scale research. Neither reference points nor a primary source automatically constitute expert verification of the curriculum.
