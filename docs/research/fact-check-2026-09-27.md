# Fact check — 27 September 2026

Release **0.20.1** is a correction on top of 0.20.0. It does not add nodes, relations or items. Every item remains `unverified`: a source check is not qualified expert review, and passing counts are not a WSET or CMS qualification.

## What was checked

The bundled manifest was parsed independently. These inventory figures match the 0.20.0 research notes and the README:

| Object | Count |
|---|---:|
| Included files | 82 |
| Knowledge nodes | 3,275 |
| Knowledge relations | 2,935 |
| Knowledge items | 2,824 |
| Certification mappings | 5,742 |
| Alternative names | 1,455 |
| Sources | 834 |
| Item citations | 3,352 |
| Geographical nodes | 1,443 (20 countries and 1,423 other places) |
| Cited `LOCATED_IN` items | 1,424 |

The 20 country frames are France, Italy, Germany, Austria, Switzerland, Hungary, Greece, Spain, Portugal, the United States, Canada, Chile, Argentina, Australia, New Zealand, South Africa, Georgia, Lebanon, the United Kingdom and China. Items that omit `verification_status` are stored as `unverified` by the dataset parser (357 items). No item is `verified`.

This pass did **not** re-read all 2,824 assertions against their sources. It re-checked the inventory, the ageing and blend statements learners are most likely to be marked on, the 2024 German Spätburgunder statistics, and the Tokaj wood-ageing rules that a March 2026 EU notice could be mistaken for.

## Corrections in 0.20.1

### Chianti Classico Gran Selezione

`ki_chianti_classico_grape` said Gran Selezione must already be at least 90% Sangiovese. Article 2 of the cited production rules does require 90–100% Sangiovese for Gran Selezione, and only Colorino, Canaiolo, Ciliegiolo, Mammolo, Pugnitello, Malvasia Nera, Foglia Tonda and Sanforte in the rest. The same article delays that rule until the fifth harvest after approval. The amendment was approved in 2023. WSET and Italian Wine Central both date the mandatory vintage to **2027**. Until then, vineyards that meet the Annata/Riserva rule (80–100% Sangiovese) remain eligible.

The explanation now states both the 80% rule and the 2027 transition. The studied answer is still Sangiovese.

Sources: [Chianti Classico production code (2023), Art. 2](https://www.chianticlassico.com/wp-content/uploads/2024/01/Production-Code-2023.pdf); [EU communication C/2024/1036](https://eur-lex.europa.eu/legal-content/EN/TXT/PDF/?uri=OJ:C_202401036); [WSET, 9 May 2024](https://www.wsetglobal.com/knowledge-centre/blog/2024/a-comprehensive-guide-to-chianti-classifications); [Italian Wine Central](https://italianwinecentral.com/?p=20991).

### Barolo soils

`ki_barolo_soil` stated as geography that most of the zone lies on Tortonian marls and sands. The March 2026 consolidated Barolo specification, Article 10, does say that most of the territory belongs to the Tortonian formation of stratified marls and sands. The explanation now attributes that sentence to the specification instead of stating it as an independent survey. The flashcard answer remains the specification's term, Tortonian marl.

Diploma study also separates older Serravallian formations, including the Lequio Formation in Serralunga d'Alba and much of Monforte d'Alba. That distinction is not in the cited article, so it was not added as a learner-facing fact. It remains a content gap, not a second soil card.

`ki_barbaresco_soil` still says most of Barbaresco lies on Tortonian marls and sands. Its cited specification was not re-opened in this pass, so that sentence was left unchanged.

## Checked and kept

- **Barolo ageing.** At least 38 months from 1 November of the harvest year, of which 18 in wood; Riserva 62 months. This matches the item text and the usual reading of Art. 5. A general encyclopedia's "60 months" for Riserva is the wrong figure; the bundle is not following it.
- **Barolo and Barbaresco grapes.** Both specifications require Nebbiolo only. Kept.
- **Brunello.** The item says 100% Sangiovese and at least two years in oak. That is the cited specification's wood rule, not the full release calendar (1 January of the fifth year after harvest, including bottle time). The shorter wood fact is not false. Not rewritten.
- **German Spätburgunder, 2024.** Destatis and the German Wine Institute's *Deutscher Wein Statistik 2025/2026* give Germany 11,437 ha (11.0%), Baden 4,910 ha (31.8%), Pfalz 1,757 ha (7.4%), Rheinhessen 1,529 ha (5.5%), Württemberg 1,284 ha (11.5%) and Ahr 346 ha (64.9%). The bundle's hectare and share items match. Older "Ahr is over 80% Spätburgunder" claims do not match this 2024 census.
- **Tokaj wood ageing for grapes harvested from 1 August 2025.** Aszú at least 18 months, dry Szamorodni at least 24 months, sweet Szamorodni at least 6 months. That is the national specification version applied by the bundle. Official Journal C/2026/1380 (6 March 2026) is an *application* for a Union amendment, dated 13 March 2018, opening an opposition period. It is not the specification in force, and its six-month dry-Szamorodni figure must not replace the August 2025 rule.

## Not claimed

No systematic re-proof of the 704 regional comparisons, the 30 grape-permission unions, the French cru lists, or the atlas coordinates was done in this pass. Those remain `unverified`, with the limits already written in [geography coverage](geography-coverage.md) and the [Diploma gap audit](wset-level-4-gap-audit.md). A March 2026 Tokaj application and the Chianti Classico transition are reminders that a legal citation can be real and still be the wrong vintage of the rule.
