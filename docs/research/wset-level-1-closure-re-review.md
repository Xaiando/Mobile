# Independent Level 1 closure re-review — 27 September 2026

Verdict: the repaired content now covers every concrete outcome gap identified in the first independent review. It is ready for **internal app coverage review after the two wording/citation refinements below and root-owned real ingestion/runtime/release checks**. This is not expert factual verification, accreditation, an official pass, or proof of every learner's attainment. Assertions remain unverified. No SDK, Git, content or runtime edits were made for this review.

The review compares the registered source/YAML/JSON with the [current Level 1 Issue 1.2 specification](https://www.wsetglobal.com/media/11682/wset_l1wines_spec_en_jun2022_issue12.pdf), still linked by the live qualification page. The earlier audit remains in `build/wset-level-1-independent-audit.md`; this note records the repaired state rather than overwriting its historical findings.

## Required catalog and delivery integrity

Read all currently registered includes, certification inheritance and `assets/progress/wset_scope.json`. Level 1 has 49 distinct requirements and 132 distinct required item IDs. No repeated requirement IDs, repeated required item IDs, missing required items, unavailable Level 1 mappings, or missing source-citation IDs in the closure pack were found. None of the non-location explanation dimensions relies on MAP_LOCATION facts. Requirements declare flashcard/short-answer practice for the explanatory facts; root's runtime checks confirm actual served modes separately.

The new nine `ki_wset_l1_*` lessons are registered. Explicit Level 1 mappings for the existing four umami/intensity lessons and `ki_wset_taste_palate_flavours` are present. New original Level 1 grid descriptors/cases/evidence now include tasted flavours, with observed associations distinct from structural sensations. The existing legacy grids remain separate. Three fictional calibration cases are required; physical wine observations are optional for Levels 1–2 (`physicalWines: 0`). This removes the earlier unnecessary compulsory alcohol-sampling hurdle without suggesting app cases replace an official course/examination.

The existing eight beginner grape profiles, seventeen familiar examples, three wine types, storage/preservation, style-sensitive service, controlled opening, faults, glassware and contextual food effects remain available. The original Level 1 rehearsal remains a varied 65-question eligible pool sampled into 30 questions/45 minutes, with the 6/18/6 educational blueprint; no copied official questions or official grading claim is introduced. Newly added teaching does not have to be repeated as every question in one finite random rehearsal.

## Previously missing outcomes now repaired

- White/red/rosé route lessons now teach a complete elementary sequence through separation, fermentation, maturation and bottling. Step definitions distinguish crushing, draining and pressing. Typical-route qualifications preserve real production alternatives rather than claim a universal technical sequence.
- Umami and flavour intensity now appear in the Level 1 required scope as well as accessible lessons. Preference-dependent explanations remain conditional.
- Young Chianti, Grenache-led Côtes du Rhône, red Châteauneuf-du-Pape and Tempranillo-led Rioja now have beginner sensory/body/structure examples with blend, site and maturation variation acknowledged.
- Cool/warm growing conditions now include a conditional ripening/sugar/acidity comparison and exceptions for extreme heat, water stress, harvest timing and local cooling.
- Tasted flavours now appear in the original Level 1 recorder, evidence prompt and all three fictional calibration notes.

## Primary-source cross-checks

These are representative source checks of the closure statements, not expert verification of every app assertion.

- [University of Georgia C717](https://fieldreport.caes.uga.edu/publications/C717/winemaking-at-home/), Crushing/Fermentation: separates white juice before fermentation and retains skins for red colour extraction; red solids are later pressed. [Rioja red winemaking](https://riojawine.com/en-gb/the-designation/types-of-wine/red-wines/), production/ageing/bottling, supplies commercial route context. Their unrelated home recipes, outdated legal advice and universal cellar recommendations are not adopted. UGA's simplified home process is not treated as the sole commercial process.
- [WSET rosé types](https://www.wsetglobal.com/knowledge-centre/blog/2023/november/29/types-of-ros%C3%A9-from-around-the-world), opening method paragraphs, directly supports brief maceration followed by pressing, and separated juice fermentation like white wine. The current app assertion is a sound common route; installing this direct locator would strengthen the existing indirect combination. Later blanket EU blending statements on that webpage are not needed and should not be adopted.
- [Chianti sensory identikit](https://www.consorziovinochianti.it/chianti-identikit/?lang=en), sensory section, supports dry fruit/floral character and changing tannin with age; public CMS Sangiovese markers supply the conditional structural context already installed.
- [Inter Rhône Côtes du Rhône](https://www.vins-rhone.com/en/rhone-valley-vineyards/appellations/aoc-cotes-du-rhone), Varieties and flavours, supports Grenache fruit/warmth/body and Syrah/Mourvèdre spice/firmness. [Grenache](https://www.vins-rhone.com/en/grenache-noir-grape-variety), In the cellars, supplies variable body/alcohol/style context. Promotional health and guaranteed-quality claims are excluded.
- [Inter Rhône Châteauneuf-du-Pape](https://www.vins-rhone.com/fr/aoc-cru-des-cotes-du-rhone-chateauneuf-du-pape), Cépages et saveurs, supports Grenache dominance, powerful structured reds and the separate white production. The lesson appropriately frames a typical red profile rather than a legal universal recipe.
- [Rioja Tempranillo](https://riojawine.com/en-us/the-designation/grape-varieties/tempranillo/), Aromas/Hints, supports fresh red/black fruit versus maturation-derived character. Rioja red production supplies wood/maturation context; the app does not promise every Rioja tastes of oak.
- [NMSU grapevine phenology](https://pubs.nmsu.edu/_h/H338/), growth/ripening, supports climate-dependent ripening and sugar accumulation. The conditional climate lesson is appropriate, subject to the precise sugar/alcohol wording below.

## Two small refinements sent to root

1. `ki_wset_l1_climate_ripeness` says “fermented sugar raises potential alcohol.” Potential alcohol comes from available grape sugar before fermentation; the amount fermented affects actual alcohol. Replace that clause with “more grape sugar gives higher potential alcohol if fermented” (or equivalent). This is precision, not a missing topic.
2. Add the direct WSET rosé method citation above to `ki_wset_l1_rose_route`, using only opening direct-pressing/short-maceration paragraphs. The present mechanism is correct, but its existing locators indirectly combine a colour distinction, white juice separation and red maturation/bottling.

After those refinements, this independent read-only source/scope review finds no remaining named Level 1 topic gap. Root must still finish required ingestion, curriculum currentness, progress, rehearsal, guided-tasting and release/device checks before changing the internal coverage metadata. The completion wording must continue to distinguish app study coverage from official qualification achievement.

Follow-up inspection: both small refinements are now present in the registered closure YAML. The climate statement uses grape sugar/potential alcohol accurately, and the rosé route includes the direct WSET method citation with its opening-method locator. Source/scope refinements are therefore resolved; only root-owned validation/release gates remain for the Level 1 internal coverage flag.
