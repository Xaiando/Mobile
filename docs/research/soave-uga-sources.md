# Soave additional geographical units — first six markers

Authored 27 September 2026 on `grok/soave-ugas`. This does not finish the 33-name list. All new items stay `unverified`.

## Legal list

The list that may appear on Soave, Soave Classico and Soave Colli Scaligeri labels was published in the Gazzetta Ufficiale on 4 November 2019 and communicated in [OJ C 72, 5 March 2020](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=CELEX:52020XC0305(04)). It has **33** names. Colombara and Froscà are separate. `Roncà - Monte Calvarina` is one name. Press lists that write "Colombara Froscà" as a single cru are wrong.

## Accepted markers

| Legal unit | Reference | Parent municipality | Why it was accepted |
|---|---|---|---|
| Brognoligo | GeoNames 8948888, CC BY 4.0 | Monteforte d'Alpone | Combined Brognoligo-Costalunga locality reference; not a standalone village centre, the Costalunga UGA, or a legal boundary |
| Castelcerino | Wikidata Q18504312, CC0; same point as GeoNames 3179731 | Soave | Settlement and Wikidata agree |
| Colombara | GeoNames 8962832, CC BY 4.0 | San Giovanni Ilarione | Only Colombara inside a Soave municipality |
| Duello | GeoNames 8956774, CC BY 4.0 | Roncà | Roncà is in the Soave production area |
| Fittà | GeoNames 8954880, CC BY 4.0 | Soave | No separate Wikidata item |
| Roncà–Monte Calvarina | GeoNames 6949595, the summit, CC BY 4.0 | Roncà | One legal unit; the point is the summit, not the boundary |

GeoNames Italy dump retrieved 27 September 2026 from <https://download.geonames.org/export/dump/IT.zip>.

## Map layers

Each source retains its own open licence and attribution. The six served points retain their historical layer identities so existing datasets can upgrade; a legacy layer ID does not describe current provenance:

- `ml_soave_uga_wikidata_markers` — Castelcerino from Wikidata (CC0) and the corrected Brognoligo-Costalunga reference from GeoNames (CC BY 4.0), two served points with both sources attributed.
- `ml_soave_uga_geonames_markers` — Colombara, Duello, Fittà and the Monte Calvarina summit (four served points), GeoNames CC BY 4.0.

The pinned source snapshots remain one Wikidata point and five GeoNames points. Gazetteer selection serves Brognoligo exactly once, in its historical layer with the corrected GeoNames coordinate; it is excluded from the second layer. No wrong-coordinate alias or legal boundary is retained.

Coordinates were checked again on 8 October 2026. Castelcerino retains Wikidata P625 claim `Q18504312$7251A6E5-600F-4317-8CF4-73866056F23C`. The former Brognoligo claim `Q3645230$AD7DF2FA-08E9-4503-B695-678670F85A9D` was copied faithfully but failed independent physical-locality reconciliation; it is preserved only as historical evidence. Brognoligo now uses openly licensed GeoNames 8948888, the combined Brognoligo-Costalunga locality [11.29379, 45.44869], not a standalone Brognoligo village centre or either UGA boundary. The five GeoNames rows sit in Monteforte d'Alpone (023050), Soave (023081), San Giovanni Ilarione (023070) or Roncà (023063). The regional government commune table confirms those codes.

## Rejected this pass

- **Costalunga.** No separate Costalunga UGA marker is claimed. GeoNames 8948888 is used only as an explicitly combined-locality reference for the Brognoligo node; it does not establish either legal unit boundary.
- **Costeggiola.** The populated place is in Negrar di Valpolicella.
- **Campagnola.** Hits are in Zevio, Verona and Costermano, not in a Soave municipality.
- **Ca' del Vento.** The populated place is in Roverè Veronese.
- **Pigno.** The populated place is in Lazise.

The other legal names had no same-name settlement inside Soave, Monteforte d'Alpone, San Martino Buon Albergo, Mezzane di Sotto, Roncà, Montecchia di Crosara, San Giovanni Ilarione, San Bonifacio, Cazzano di Tramigna, Colognola ai Colli, Caldiero, Illasi or Lavagno. They stay unmapped. No town centre was reused for a different cru.

## Second pass — the other 27 stay unmapped

Checked again on 27 September 2026 against the same GeoNames Italy dump and a Wikidata entity search. No further marker was accepted. Dataset 0.20.6 is unchanged.

Exact names with **no Italy row**: Broia, Corte del Durlo, Froscà, Foscarino, Menini, Monte di Colognola, Ponsara, Pressoni, Rugate, Sengialta, Tenda, Tremenalto, Zoppega.

Exact names that exist, but **not in a Soave municipality**:

| Name | Where the hits actually are |
|---|---|
| Ca' del Vento | Roverè Veronese, GeoNames 8959615 |
| Campagnola | Including Zevio, Verona and Costermano; none in a Soave municipality |
| Carbonare | Trento, not Verona |
| Casarsa | Pordenone and Salerno |
| Castellaro | None in Verona |
| Costalta | Piacenza, Belluno, Vicenza and Reggio Emilia |
| Coste | None in a Soave municipality |
| Croce | The Verona hit is outside the Soave municipalities |
| Monte Grande | Bologna, Grosseto, Caserta, Imperia and Forlì-Cesena |
| Paradiso | None in a Soave municipality |
| Volpare | Vicenza, GeoNames 8978227 |

A name fragment inside the production area is still not enough:

- GeoNames 10378406 is Ca' Rugate Azienda Agricola, feature `V.VIN`, in Montecchia di Crosara. That is a producer vineyard, not the Rugate unit.
- The only Costalunga string in a Soave municipality remains GeoNames 8948888, Brognoligo-Costalunga.
- Colognola ai Colli is the municipality seat, not Monte di Colognola.

Wikidata entity search returned no item for Foscarino, Broia, Zoppega, Sengialta, Tremenalto, Ponsara, Pressoni or Corte del Durlo. The Froscà and Rugate hits were unrelated. Menini was rate-limited and was not accepted from an unseen record. The authored set remains the first six.
