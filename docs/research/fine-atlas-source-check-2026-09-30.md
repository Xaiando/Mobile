# Fine-atlas source checkpoint — 30 September 2026

A fresh primary-source check did not unblock Paardeberg South or the three remaining Vino Nobile Pievi. The two independently supported Appiano settlement references are documented separately in [the Alto Adige source note](alto-adige-bilingual-references-2026-09-30.md). No additional coordinate or outline is imported by this checkpoint.

## Paardeberg South

The [SAWIS production-area portal](https://www.sawis.co.za/cert/productionareas.php) publicly exposes a [January 2026 ward overview PDF](https://www.sawis.co.za/cert/download/Wards_-__Jan2026.pdf). This corrects an overly broad historical authentication description: public overview maps exist despite the portal's industry-login banner. It does not resolve precision or reuse rights.

The one-page PDF is 4,072,381 bytes, SHA256 `0467495ba539ae2904ce3f6268df81f9aa65fd18998920fe4abd58eed106fcc0`. Its metadata identifies Esri ArcMap 10.2.2, creation 21 January and modification 22 January 2026. The bounded check found no standard PDF `/VP`, `/Measure` or `/LGIDict` geospatial keys. [SAWIS terms](https://www.sawis.co.za/terms.php) provide no accepted GEO-5 reuse grant. Absence of those keys does not prove that a PDF cannot contain any georeferencing, and a government/authority host alone does not establish a compatible licence.

The [Swartland route map](https://swartlandwineandolives.co.za/map-of-the-swartland-wine-and-olive-route/) is expressly restricted by [its terms](https://swartlandwineandolives.co.za/terms-of-use/), clauses 8–10. Its regional description distinguishes both wards without assigning an observed property specifically to South. A Council for Geoscience service was also marked copyright/all rights reserved. None supplies accepted reusable wine-area geometry or a defensible precise interior reference.

## Three remaining Pievi

A new compatible source was tested: [ISTAT's 2021 locality-point archive](https://www.istat.it/storage/cartografia/basi_territoriali/2021/LocalitaPuntuali_21.zip). [Primary documentation](https://www.istat.it/wp-content/uploads/2024/07/Descrizione-dei-dati-Basi-territoriali.pdf) states CC BY 4.0 on page 2 and EPSG:32632 on page 4.

Its complete `Localita_2021_Point.csv` member contains 69,003 rows and 39 records for Montepulciano (`PRO_COM=52015`). None matches Sant'Ilario/Ilario, Cerliana/Ciarliana or Valardegna/Vallardegna/Villardegna. The complete CSV is 5,877,410 bytes, SHA256 `fa58ac05ba0bc33704de1c296c847642dc400582cebf64621586748d88f521df`. The archive was obtained only partially through bounded range delivery; no complete ZIP hash or full-archive inspection is claimed. The [municipal SIT portal](https://cloud.ldpgis.it/montepulciano/cartobase) reserves cartographic rights and supplies no compatible derivative grant.

The bounded next action is to obtain an explicitly licensed authority Pieve/ward layer, or authority-confirmed precise in-unit references paired with independently reusable coordinates. No publisher was contacted and no licence guard is weakened. Settlement identity, precision and reuse permission must all be established before a new practice reference is bundled.
