# Vino Nobile Pievi — sources and limits

Authored 27 September 2026 on branch `grok/vino-nobile-pievi`. This is geography for nine of the twelve current Pieve units. It does not add grape-blend rules, ageing rules or unit boundaries. All new items stay `unverified`.

## Legal list

EU communication [C/2025/2742](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=OJ:C_202502742), dated 17 February 2025, approves twelve additional geographical units that may follow the term Pieve on a Vino Nobile di Montepulciano label:

1. Sant'Ilario
2. Ascianello
3. Badia
4. Caggiole
5. Cerliana
6. Cervognano
7. Gracciano
8. Le Grazie
9. San Biagio
10. Sant'Albino
11. Valardegna
12. Valiano

The units lie in the municipality of Montepulciano. Pieve cannot be combined with Riserva. Older planning lists that use **Argiano** or **Ciarliana** are not the approved names. The current names in those places on this list are Sant'Ilario and Cerliana. Neither of those two, nor Valardegna, is mapped in this release.

## What was mapped

Each mapped unit is a `subregion` located in `n_geo_vino_nobile_di_montepulciano`. The point is a Wikidata coordinate whose administrative parent is Montepulciano (`Q91217`), retrieved 27 September 2026 under CC0. It is a hamlet or a named church, not a Pieve boundary and not an official centroid.

| Legal unit | Reference | Wikidata | Why this point |
|---|---|---|---|
| Ascianello | Ascianello hamlet | Q18491433 | Same name, parent Montepulciano |
| Badia | Abbadia hamlet | Q14526941 | Gazetteer spells the hamlet Abbadia; the legal unit is Badia |
| Caggiole | Caggiole hamlet | Q3649627 | Same name, parent Montepulciano |
| Cervognano | Cervognano Montenero hamlet | Q18491579 | Gazetteer name is longer; the legal unit is Cervognano |
| Gracciano | Gracciano hamlet | Q16561529 | Not Gracciano dell'Elsa |
| Le Grazie | Church of Santa Maria delle Grazie | Q3673973 | No hamlet entity was found; the church is only a reference |
| San Biagio | Church of San Biagio | Q1883452 | No hamlet entity was found; the church is only a reference |
| Sant'Albino | Sant'Albino hamlet | Q16600206 | Parent Montepulciano |
| Valiano | Valiano hamlet | Q4007955 | Parent Montepulciano |

## Held back

Sant'Ilario, Cerliana and Valardegna had no Wikidata item that could be checked as a place inside Montepulciano on 27 September 2026. A second pass the same day searched the GeoNames Italy dump (`IT.zip` from download.geonames.org, CC BY 4.0). The dump has no populated place named Cerliana and none named Valardegna. Every Sant'Ilario in that dump is somewhere else: Livorno, Florence, Genoa, Latina, Potenza, Macerata, Reggio Emilia or Calabria. None is in the province of Siena. Those three units are not given a guessed coordinate, the Montepulciano town centre, a producer address, or another town's Sant'Ilario. Argiano is not used as a stand-in.

## Not claimed

This file does not state the Pieve blend, the minimum ageing, or which vintage may be sold. Those rules need their own reading of the product specification before they become cards. Nine mapped units are not the complete set of twelve.
