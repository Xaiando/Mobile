# Soave additional geographical units — first six markers

Authored 27 September 2026 on `grok/soave-ugas`. This does not finish the 33-name list. All new items stay `unverified`.

## Legal list

The list that may appear on Soave, Soave Classico and Soave Colli Scaligeri labels was published in the Gazzetta Ufficiale on 4 November 2019 and communicated in [OJ C 72, 5 March 2020](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX:52020XC0305(04)). It has **33** names. Colombara and Froscà are separate. `Roncà - Monte Calvarina` is one name. Press lists that write "Colombara Froscà" as a single cru are wrong.

## Accepted markers

| Legal unit | Reference | Parent municipality | Why it was accepted |
|---|---|---|---|
| Brognoligo | Wikidata Q3645230, CC0 | Monteforte d'Alpone | The item is Brognoligo alone |
| Castelcerino | Wikidata Q18504312, CC0; same point as GeoNames 3179731 | Soave | Settlement and Wikidata agree |
| Colombara | GeoNames 8962832, CC BY 4.0 | San Giovanni Ilarione | Only Colombara inside a Soave municipality |
| Duello | GeoNames 8956774, CC BY 4.0 | Roncà | Roncà is in the Soave production area |
| Fittà | GeoNames 8954880, CC BY 4.0 | Soave | No separate Wikidata item |
| Roncà–Monte Calvarina | GeoNames 6949595, the summit, CC BY 4.0 | Roncà | One legal unit; the point is the summit, not the boundary |

GeoNames Italy dump retrieved 27 September 2026 from <https://download.geonames.org/export/dump/IT.zip>.

## Map layers

The geography checker accepts one open licence per source. These six points therefore use two layers, not one mixed-licence layer:

- `ml_soave_uga_wikidata_markers` — Brognoligo and Castelcerino, Wikidata CC0.
- `ml_soave_uga_geonames_markers` — Colombara, Duello, Fittà and the Monte Calvarina summit, GeoNames CC BY 4.0.

Coordinates were checked again on 27 September 2026. Wikidata P625 claims `Q3645230$AD7DF2FA-08E9-4503-B695-678670F85A9D` and `Q18504312$7251A6E5-600F-4317-8CF4-73866056F23C` still match the markers. The four GeoNames rows still sit in Soave (023081), San Giovanni Ilarione (023070) or Roncà (023063).

## Rejected this pass

- **Costalunga.** GeoNames 8948888 is named Brognoligo-Costalunga. One point cannot be both units.
- **Costeggiola.** The populated place is in Negrar di Valpolicella.
- **Campagnola.** Hits are in Zevio, Verona and Costermano, not in a Soave municipality.
- **Ca' del Vento.** The populated place is in Roverè Veronese.
- **Pigno.** The populated place is in Lazise.

The other legal names had no same-name settlement inside Soave, Monteforte d'Alpone, San Martino Buon Albergo, Mezzane di Sotto, Roncà, Montecchia di Crosara, San Giovanni Ilarione, San Bonifacio, Cazzano di Tramigna, Colognola ai Colli, Caldiero, Illasi or Lavagno. They stay unmapped. No town centre was reused for a different cru.
