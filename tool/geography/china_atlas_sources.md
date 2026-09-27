# China atlas source and coordinate notes

This bounded addition supplies China plus five provincial/autonomous-region names (Ningxia, Shandong, Hebei, Xinjiang and Yunnan) and three useful smaller place references (Helan Mountain eastern foothills, Yantai and Huailai). It closes the obvious country gap for the Diploma geography expansion; it does not establish exhaustive WSET Level 4 Diploma coverage. The province and city/county nodes represent administrative geography, not fabricated wine appellations.

## Point semantics and licence

The snapshot contains eight exact Earth coordinate-location (P625) values from the named Wikidata entities, fetched 26 September 2026. A single nondeprecated P625 statement was available for every selected entity; no interpolation, centroids, geocoding or boundary tracing was used. Province coordinates can be administrative/capital reference points. A city/county reference does not assert that every vineyard lies at that point.

Helan Mountain eastern foothills uses **Zhenbeibu** as its documented wine-cluster reference. Ningxia’s official plan names 西夏区镇北堡 in its winery-cluster review and planning scope. The source describes the wine region in Ningxia; the marker is the town’s Wikidata coordinate, not the full mountain range (which straddles another autonomous region), and not a registered-GI boundary or vineyard centroid.

Wikidata structured coordinates are **CC0 1.0**: [Wikidata licensing](https://www.wikidata.org/wiki/Wikidata:Licensing). Only CC0 coordinate data and basic reference identifiers are included in the GeoJSON. Government publications substantiate location and wine relevance through citations; their photographs, maps, article text and geometry are not copied into the snapshot. No government-publication reuse licence is asserted.

| Curriculum place | Coordinate entity | Entity ID | Captured revision | Longitude, latitude |
| --- | --- | --- | --- | --- |
| Ningxia | Ningxia | Q57448 | 2535502169 | 106.27056, 38.46654 |
| Shandong | Shandong | Q43407 | 2548837613 | 118.4, 36.4 |
| Hebei | Hebei | Q21208 | 2541882132 | 114.50861111111, 38.042222222222 |
| Xinjiang | Xinjiang | Q34800 | 2547886485 | 87.61379, 43.8253 |
| Yunnan | Yunnan | Q43194 | 2535498282 | 102.7088888888889, 25.049444444444443 |
| Helan Mountain eastern foothills | Zhenbeibu | Q14053711 | 2523451554 | 106.0669, 38.6275 |
| Yantai | Yantai | Q210493 | 2526608854 | 121.44777777777777, 37.464444444444446 |
| Huailai | Huailai County | Q1197061 | 2526577303 | 115.51688, 40.4048 |

Each feature also retains the exact statement ID, source URL and coordinate precision. Its associated LOCATED_IN item cites the government location evidence and the coordinate entity separately. The government-source assertions are concise factual paraphrases.

## Primary location evidence

- [Administrative Division](https://english.www.gov.cn/archive/china_abc/2014/08/27/content_281474983873401.htm) — State Council of the People’s Republic of China.
- [Introduction to GIs under the China-EU Agreement on Geographical Indications (39): Wine in Helan Mountain East Region](https://eu.china-mission.gov.cn/eng/zgggfz/cega/202211/t20221111_10972980.htm) — Mission of the People’s Republic of China to the European Union.
- [Yantai mayor interview: coastal city and wine industry (烟台市市长张明康：海洋经济大市，做强微醺经济)](https://ptjj.yantai.gov.cn/col/col1626/art/2026/art_74588db58bde453d914ac1bfcba34685.html) — Yantai Grape and Wine Bureau; interview with the mayor published by Southern Weekly.
- [Response to recommendation 1138 of the first session of the 14th Hebei Provincial People’s Congress: Huailai grape and wine industry](https://gxt.hebei.gov.cn/hbgyhxxht/zfxxgk/fdzdgknr/669481/669482/2025042121450690712/index.html) — Hebei Provincial Department of Industry and Information Technology.
- [NW China’s Xinjiang ushers in grape harvest season](https://english.www.gov.cn/news/202309/15/content_WS65042172c6d0868f4e8df76e.html) — State Council of the People’s Republic of China; CGTN.
- [Response to recommendation 507 of the first session of the 13th Yunnan Provincial People’s Congress: wine grapes in Deqin, Mile and Qiubei](https://nync.yn.gov.cn/html/2018/tianjianyibanli2018_0930/375112.html?cid=3406) — Yunnan Provincial Department of Agriculture.
- [Ningxia Helan Mountain eastern foothills wine industry: 14th Five-Year Plan and 2035 vision, issued 31 December 2021](https://www.nx.gov.cn/zwgk/qzfwj/202202/t20220208_3316559_wap.html) — General Office of the People’s Government of Ningxia Hui Autonomous Region.

The Hebei source is the department’s own signed recommendation response (21 April 2023; published 28 April), rather than a secondary wine article. The Yunnan source is its agriculture department’s own recommendation response (9 May 2018; posted 30 September). The Yantai source records a primary interview with the city’s mayor and gives the northeastern Shandong Peninsula location. The Ningxia plan was signed 31 December 2021 and posted 8 February 2022; although one browser fetch returned 405, its exact official URL returned HTTP 200 via Node fetch and contains the named wine-cluster passage.

## Reproduction and integration

For each listed entity, retrieve the feature’s source_url, find the recorded P625 statement ID at the recorded entity revision, and copy its longitude and latitude unchanged to GeoJSON coordinates in that order. Confirm the Earth globe (Q2) and nondeprecated rank. If checking against the current live entity rather than the recorded revision, treat changed coordinates as a source update that requires review. Source URLs, revision numbers, statement identifiers and precision are embedded for that purpose.

Snapshot SHA-256: `fd3625499b4c7b5fe3d36d4f5348357bccf7101f3921345a806858cdd3f42c47`.

Counts: 9 nodes (country + 8 places); 8 LOCATED_IN edges and cited items; 8 aliases; 16 mappings (WSET_L3 and CMS_CERTIFIED, secondary, depth 2); 15 sources; 22 item citations; 8 CC0 point features. WSET_L4 can inherit the authored L3 geography through the track rules; no full-Diploma completion assertion is made.

Root integration must add Natural Earth CHN for n_geo_china, register the CC0 snapshot source, and map the eight feature node IDs into the appropriate layer. This file does not alter shared manifests, source registries, layers or tests.
