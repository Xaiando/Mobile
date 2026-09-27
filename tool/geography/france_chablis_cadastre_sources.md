# Chablis Premier Cru cadastral reference points

Six existing curriculum nodes now have separate, source-derived point locations in `france_chablis_cadastre_points.geojson`. These are interior points of named cadastral lieux-dits, not legal climat borders, appellation centroids or manually traced wine-map geometry.

## Primary sources and licence

- Coordinates and polygons: [Cadastre Etalab, Chablis commune 89068, lieux-dits, 1 June 2026](https://cadastre.data.gouv.fr/data/etalab-cadastre/2026-06-01/geojson/communes/89/89068/cadastre-89068-lieux_dits.json.gz), retrieved 26 September 2026. The [government dataset](https://www.data.gouv.fr/datasets/cadastre) publishes these data under the original Licence Ouverte / Open Licence 1.0. Its [metadata API](https://www.data.gouv.fr/api/1/datasets/cadastre/) identifies `fr-lo` and links the original licence, rather than `lov2`. DGFiP's PCI supplies the original data, redistributed by DINUM/Etalab. The geography pipeline accepts both versions of Licence Ouverte; the snapshot preserves the published version.
- Name matching: the [INAO Chablis Premier Cru product page](https://www.inao.gouv.fr/produit/chablis-premier-cru-fourchaume-23059), regulatory-text table of climat names and cadastral lieux-dits. The table identifies the source lieu-dit names used below. The historical regulatory table is used to identify the named places, not to assert that the cadastre polygons are current legal vineyard delimitations.

| Curriculum climat | Matched cadastral lieu-dit | Commune |
| --- | --- | --- |
| Montée de Tonnerre | MONTEE DE TONNERRE | Chablis 89068 |
| Vaulorent | LES QUATRE CHEMINS | Chablis 89068 (Poinchy) |
| Vaillons | LES VAILLONS | Chablis 89068 |
| Montmains | LES MONTS-MAINS | Chablis 89068 |
| Côte de Léchet | LA COTE DE LECHET | Chablis 89068 (Milly) |
| Beauroy | SOUS BOROY | Chablis 89068 (Poinchy) |

Vaulorent and Beauroy use one named constituent lieu-dit. Montmains follows the table's cadastral spelling, with the source dataset's hyphenation preserved. Every match is unique within the commune file. Other constituent lieux-dits and legal vineyard boundaries are not included in this snapshot.

## Derivation and reproduction

1. Download the pinned June 2026 source file and decompress its GeoJSON.
2. Select the six exact `properties.nom` strings above, all in commune `89068`.
3. Retain their original geometries and attach the curriculum IDs.
4. Run mapshaper 0.7.67 `-points inner`; this computes one point inside the largest polygon ring.
5. Preserve the source name, commune, source dataset edition, source feature update date, retrieval date, method, name-association source and SHA-256 of the decompressed source in every feature.

Each feature includes a `label_note` explaining that it is a cadastral reference point. The geography pipeline should retain that qualification in the map attribution or detail view. The source polygons are openly licensed; no OSM data or copyrighted wine-map tracing is used.
