# Alto Adige bilingual settlement references — 30 September 2026

Two previously unresolved names now have primary municipal name-identity evidence and licensed settlement coordinates. The additional map references are Montiggl / Monticolo and Missian / Missiano. They join the five existing Alto Adige markers. This does not complete the additional geographical-unit atlas, delimit vineyards or establish whether a parcel can use a name.

## Evidence chain

The current [Alto Adige DOC legal specification, Article 7.2](https://www.gazzettaufficiale.it/atto/serie_generale/caricaArticolo?art.versione=1&art.idGruppo=0&art.flagTipoArticolo=1&art.codiceRedazionale=24A05379&art.idArticolo=7&art.idSottoArticolo=1&art.idSottoArticolo1=10&art.dataPubblicazioneGazzetta=2024-10-17&art.progressivo=0) names both units under Appiano. Its eligibility conditions and separate delimitations are not reproduced as settlement boundaries.

The official [Eppan / Appiano municipal development plan](https://www.comune.appiano.bz.it/system/web/GetDocument.ashx?cts=1761816820&fileId=1517923) pairs the German and Italian locality names on PDF page 54. Root and an independent agent visually inspected that page; page 40 was also checked. The 92-page, 33,725,536-byte PDF has SHA256 `b29822c6d0e83744ad961da7a2be9147344c31f31177b443e6ebc9bbd53c66f9`. It supplies name identity only. No municipal map image, coordinate, geometry or vineyard boundary is copied or traced.

Coordinates come from the already pinned 27 September GeoNames Italy snapshot, under CC BY 4.0. The archive SHA256 is `3ed52ee0c4d41b259db1ccb1b608beba3c89361d99668e1bbf8049d3db42c647`. Both raw records are populated settlements (`P.PPL`) in Bolzano province (`BZ`) and Appiano municipality (`admin3=021004`); both last changed on 19 January 2014. Independent review checked the archive hash and both raw records. German alternatives were not assumed from GeoNames.

| Authored reference | GeoNames record | Longitude | Latitude |
|---|---:|---:|---:|
| Montiggl / Monticolo | 3172679 | 11.27682 | 46.41792 |
| Missian / Missiano | 3173347 | 11.25418 | 46.48500 |

The updated seven-point input snapshot has SHA256 `c227ff6ddc22016271bd29ae1001f981d722110a69d10e909c604b9c8228dede`. Existing coordinates are preserved. The geography pipeline regenerated the bundled seven-point topology, manifest and report. Its byte-identical reproducibility check passed: 41 layers and 2,633.3 KB of the 8 MB budget. All 21 Node tests passed with zero skips using the existing pinned raw caches. The three new real-map tests also passed, covering correct, wrong and missed taps, source identity and optional study scope. The combined Flutter suite remains a separate final acceptance gate.

## Study scope and acceptance

Both new facts remain unverified and optional (`secondary`, depth 2) in WSET Level 3 and CMS Certified. Diploma inherits the Level 3 atlas. They do not expand compulsory lower-level completion requirements. Each links the legal naming source, municipal bilingual identity and licensed coordinate provenance. Learners can practise locating or identifying the supplied settlement reference, with its limits stated in the lesson.

The three remaining Vino Nobile Pievi references and Paardeberg South still lack accepted licensed geometry in this pipeline. A name match or a restrictive map is insufficient. The bounded next action is to obtain an authoritative identity together with a reusable coordinate or boundary source, then independently review each reference before bundling it. No guessed coordinates, parcel outlines or licence exceptions are used.
