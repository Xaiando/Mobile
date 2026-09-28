# CMS Greece principal-wine geography references

The [CMS Europe 2026/27 examination syllabus, p. 15](https://courtofmastersommeliers.org/wp-content/uploads/2026/02/Syllabus-202627-1.pdf) places Slopes of Meliton and Patras among the principal Greek wines in its Introductory column, and asks for principal regions on a map. `CMS_CERTIFIED` inherits `CMS_INTRODUCTORY` in this curriculum. The new facts are introductory geography only; they do not assert detailed wine styles, production rules or legal borders.

## Factual geography

- The [Hellenic Ministry Slopes of Meliton PDO technical file](https://www.minagric.gr/images/stories/docs/agrotis/POP-PGE/TEXNIKOI%20FAKELOI%20OINON%20POP-PGE%20ENGLISH/PDO%2026/Technical%20file%20related%20to%20PDO%2026%20Plagies%20Melitona.pdf), section 5, places the delimited area around Neos Marmaras in Sithonia, Halkidiki. Its geographical-link section discusses the Macedonian/Halkidiki context. [Wines of Greece: Halkidiki](https://winesofgreece.org/regions/halkidiki/) identifies the Sithonia peninsula and slopes of Mount Meliton.
- The [Hellenic Ministry Patra PDO technical file](https://www.minagric.gr/images/stories/docs/agrotis/POP-PGE/TEXNIKOI%20FAKELOI%20OINON%20POP-PGE%20ENGLISH/PDO%2024/Technical%20file%20related%20to%20PDO%2024%20Patra.pdf), section 5, lists the delimited Achaea communities, including places around Patras, Aigio and Akrata. [Wines of Greece: Achaia](https://winesofgreece.org/regions/achaia/) locates Achaea's vineyards in the northern Peloponnese.

The appellation **Patra** is distinct from Mavrodaphne of Patras, Muscat of Patras and Muscat of Rio Patras; the CMS syllabus spells the principal wine “Patras.” The curriculum uses the legal PDO name with that spelling as an alias.

## Pinned coordinate snapshot

`cms_greece_points.geojson` contains five named WGS84 orientation references extracted from [GeoNames GR.zip](https://download.geonames.org/export/dump/GR.zip) on 28 September 2026. GeoNames provides [CC BY 4.0 licensed data](https://www.geonames.org/export/). The source ZIP SHA-256 is `e71b24a515472009a99156fc059b1fa9df1e20048e3231698dea64516bafee1c`; extracted `GR.txt` SHA-256 is `d0ac77295171579078dd70a323b35741f6c17ccc89bec63fd48b83218fd421be`. The checked-in GeoJSON SHA-256 is `e29c73a03bcb871b806793c8bf233a54614834f4fa16ca6a743950bd2be3600e`. Rebuild only from that exact text dump with `node tool/geography/cms_greece_points.mjs path/to/GR.txt`; the script rejects another source hash.

| Curriculum node | GeoNames ID | Named reference | Longitude, latitude | Role |
| --- | ---: | --- | --- | --- |
| `n_geo_halkidiki` | [735804](https://www.geonames.org/735804/) | Nomós Chalkidikís | 23.50000, 40.41667 | Regional-unit reference |
| `n_geo_sithonia` | [734264](https://www.geonames.org/734264/) | Chersónisos Sithonías | 23.86828, 40.09788 | Peninsula reference |
| `n_geo_slopes_of_meliton` | [735219](https://www.geonames.org/735219/) | Melítonas | 23.83333, 40.06667 | Named mountain peak reference |
| `n_geo_achaea` | [265712](https://www.geonames.org/265712/) | Achaea | 22.00000, 38.13333 | Named-region reference |
| `n_geo_patra` | [255683](https://www.geonames.org/255683/patra.html) | Pátra | 21.73508, 38.24620 | City reference |

These points are not derived from the PDO polygons and do **not** claim to be official appellation centroids or boundaries. The separate location facts and hierarchy convey the wine areas; map clicks are approximate orientation practice. All new curriculum items remain unverified pending qualified review.
