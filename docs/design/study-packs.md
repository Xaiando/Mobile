# Study Packs

| | |
|---|---|
| **Status** | Design for backlog group P ([backlog.md](../backlog.md)). Decisions are registered in [architecture-audit.md](../architecture-audit.md) §16. |
| **Builds on** | Certification tracks (CM-1 to CM-9), the question system ([question-system.md](question-system.md)), geography ([geography.md](geography.md)) |

A **study pack** is a curated vertical: a deep, focused curriculum on one subject, such as a grape, a region or a competition. It goes beyond what a certification level asks. A pack is built entirely from the generic system:

- items, mappings, formats, maps and coverage policy;
- **no code specific to one pack** (PK-1).

A new pack is a data change plus tests, never a new screen.

---

## 1. Model

- **A pack is a track** (PK-2). `certifications` gains a `kind` column, `certification` or `pack` (schema v2, F2). A pack has no examining body (`organization` is null), is selectable, and may include a base track through `includes_certification_id`.
- **Mappings work as they do for certifications.** `certification_knowledge_mappings` states each item's importance (C = 1.0, 0.5 or 0.25) and its `minimum_depth`. Packs use depths 4 and 5 widely, since reasoning and deduction are their point.
- **One active track** (PK-3). The learner studies a certification or a pack. Switching keeps every memory state (FS-12), so pack study also strengthens the certification items it shares. Studying several tracks at once, with a merged queue, is a later extension.
- **Coverage policy per pack** (PK-4). `coverage_policy.yaml` has a section for each pack, stricter than for certifications:
  - every core pack item has at least three families;
  - spatial formats wherever geometry exists;
  - reasoning for every core viticulture, winemaking and tasting item.
- **Session modes are generic** (PK-5). A pack uses the focused and timed modes of task S1: a region or domain focus, timed drills, and an exam-style run with feedback at the end. "Competition training" is a pack plus those modes, not a separate feature.

---

## 2. First vertical: Spätburgunder mastery and competition training

**Goal:** deep command of German Pinot Noir (Spätburgunder), for competitions and for advanced certification candidates. It covers geography, climate, soils, viticulture, winemaking, tasting, comparison with the world's other Pinot Noir regions, labels and deductive tasting.

The outline below is a **scope list, not content.** Every fact is authored in the pack tasks (P2, P3), with citations to primary sources. It stays `unverified` until an expert reviews it (D3).

| Area | Scope | Formats | Primary sources to use |
|---|---|---|---|
| Regions and hierarchy | The 13 Anbaugebiete; the Bereiche that matter for Spätburgunder; flagship Einzellagen | map locate, identify and drills down to Einzellage for flagship sites; ordering by planted area | German wine law (*Weingesetz*, *Weinverordnung*); state vineyard registers (e.g. Weinbergsrolle RLP, dl-de/by-2-0); Destatis vineyard survey |
| Physical geography | Rivers (Rhine, Ahr, Main, Neckar, Nahe); ranges and landforms (Kaiserstuhl, Haardt, Taunus, Black Forest) | map feature questions; `SHELTERED_BY`, `LIES_ALONG` | Natural Earth, BKG, public geological surveys |
| Climate | The Upper Rhine Graben's warmth; rain shadows; valley and slope heat in the Ahr; climate change and ripening | climate reasoning, map deduction | German Weather Service (DWD) publications; academic papers |
| Soils and geology | Slate and greywacke; volcanic soils and loess on the Kaiserstuhl; limestone; red sandstone | map soils; matching soil to site | State geological surveys; Weinbergsrolle descriptions |
| Viticulture | Clones and selections; yields; canopy; site selection; disease pressure | viticulture reasoning; matching | Public research institutes (e.g. Geisenheim publications), extension services |
| Winemaking | Maceration and extraction choices; whole-cluster use; malolactic conversion; oak (German and French); rosé, Blanc de Noirs and Sekt | production reasoning; ordering of process steps | Academic and government sources; German wine law for style terms |
| Tasting | Structural and aromatic profiles by region and site, in the app's own lexicon (T1) | tasting deduction; matching profile to region | The pack's own profiles, cited to published sensory research where possible |
| Comparisons | Burgundy, Alsace, Switzerland, Austria, Alto Adige, Oregon, California, New Zealand, Tasmania and others | cross-domain reasoning; tasting deduction against other Pinot Noir regions | Each country's legal texts and public sources (content tasks C2–C4) |
| Labels | German label law: quality levels, Prädikate, sweetness terms, origin terms, sparkling wine terms | label interpretation on synthetic labels; label error spotting | *Weingesetz*, *Weinverordnung*; EU wine labelling rules |
| Competition drills | Timed map speed rounds; blind deduction series; label and wine-list error spotting | generic session modes (S1) over the formats above | as above |

### Legal notes for this pack

- **Private classifications.** Terms such as VDP.GROSSE LAGE and GROSSES GEWÄCHS are trademarks of a private association. They are explained descriptively as a private classification, never used as the app's own labels, and never presented as law (L-19).
- **Competitions.** The pack names no competition and implies no affiliation (L-22).
- **Statistics.** Planted areas are cited to Destatis (dl-de/by-2-0, to confirm) and restated, not copied as tables (L-21).
- **Labels.** Synthetic labels use invented producer names only (L-20).

---

## 3. Acceptance for the pack as a whole

The pack is complete when:

1. it is selectable next to WSET Level 3 and CMS Certified, and studying it runs through the same planner, formats and FSRS state;
2. its coverage policy passes: no core pack item is flashcard-only, and every core item has at least three families;
3. every core geography item has a spatial format, down to the Einzellage level where the pack maps sites;
4. a timed competition drill and a blind deduction series run on pack content;
5. no line of code names the pack (a test searches `lib/` for its ID).
