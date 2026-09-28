# CMS Certified Bulgaria and Romania marker provenance

The nine pinned points in `cms_eastern_europe_points.geojson` are named-settlement orientation references. They are not PDO/PGI/DOC centroids or legal boundaries. The corresponding legal district and grape claims, with item-level locators, are in `assets/curriculum/areas/cms_eastern_europe.yaml`.

GeoNames country dumps were retrieved on 2026-09-28 under [CC BY 4.0](https://www.geonames.org/export/). The exact input files were:

| Download | ZIP SHA-256 | Extracted text SHA-256 |
| --- | --- | --- |
| [BG.zip](https://download.geonames.org/export/dump/BG.zip) | `4c478a0d9d7a2dcbc5ef21ba880842d3266cbf200980b6a11b8d5804fe029689` | `d2b3a3bf359e3de6b9f2b193ed9a3f3c7111322296ff321737e8cce22fd52f99` |
| [RO.zip](https://download.geonames.org/export/dump/RO.zip) | `f5190d58880e5af0202f7f90a4a959b641c9f1afa09dc5f0c98b1b9de16101d0` | `5331ad9cfc2fe3931a1ab82407b81660833356faf26975366666aca73796e18b` |

The checked-in `cms_eastern_europe_points.mjs` requires these extracted-text hashes, exact GeoNames IDs, settlement names, feature codes and country codes before reproducing the snapshot. A changed dump requires renewed legal/source review. The source snapshot SHA-256 is `a695729f83c44a5657714f38b620efcbe4e7b28a948a21052d1d4b688a9af390`.

Legal and regulatory source families used for curriculum facts:

- Bulgaria: the [Ministry of Agriculture's PGI summary](https://www.mzh.government.bg/bg/press-center/novini/poveche-vidimost-na-blgarskite-vineni-destinacii-i/), [Danubian Plain PGI single document](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:52023XC00915), [Melnik PDO amended single document](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=OJ:JOC_2023_272_R_0006) and [approved amendment](https://eur-lex.europa.eu/eli/reg_impl/2023/2536/oj/eng), and the [Lyubimets PDO specification](https://enodata.dionysosvine.eu/sites/default/files/2022-02/zonesh-pdo-lyubimets-bg.pdf) hosted by an EU Interreg project.
- Romania: [ONVPV's DOC regional list](https://www.onvpv.ro/ro/doc/generalitati) and its linked specifications for [Târnave](https://www.onvpv.ro/sites/default/files/caiet_de_sarcini_doc_tarnave_modif_cf_cererii_1154_22.05.2017_no_track_changes_0.pdf), [Cotnari](https://www.onvpv.ro/sites/default/files/caiet_sarcini_doc_cotnari_aprobat_rue_1913_2021_categorii_modif_cf_cerere_1316_10.07.2024.pdf) and [Dealu Mare](https://www.onvpv.ro/sites/default/files/caiet_sarcini_doc_dealu_mare_modif_cf_cererii_1996_01.10.2020_toate_categ_cf_notific_945_din_12.05.2022_4.pdf).

For grape-map questions, only Lyubimets and Cotnari have curated complete permission sets. Lyubimets specification §5 lists five white and fourteen red/rosé varieties; Cotnari specification §IV lists nine white and two red/rosé varieties, with the sparkling and petiant categories repeating members of that union. Each full set has one source-cited `relation_set_assertions` row, effective from this review date. Danubian Plain, Melnik, Târnave and Dealu Mare retain positive grape facts without completeness assertions; their uncurated varieties must not be treated as prohibited in a map question.
