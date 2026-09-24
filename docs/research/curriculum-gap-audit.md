# Curriculum Gap Audit

**Date checked:** 2026-09-24

## Executive finding

The architecture is ahead of the curriculum volume. The app already has the canonical knowledge graph, ingestion/validation, FSRS memory, adaptive planning, learner UI, and the G3 offline map renderer. The principal release risk is now **content completeness and qualified verification**, not the data model.

The bundled curriculum is still a pilot. It must not be marketed as WSET Level 3 or CMS Certified parity until the scope and verification gates below pass.

## Scope decisions

1. **WSET Level 3** is a V0.1 target. Official scope includes factors affecting style/quality/price of the principal still, sparkling and fortified wines of the world, plus systematic tasting. Assessment includes multiple choice, short-written answers and a two-wine blind tasting. Source: [WSET Level 3 Award in Wines](https://www.wsetglobal.com/qualifications/wset-level-3-award-in-wines).
2. **CMS Certified in V0.1 means CMS Europe Certified**, pinned to the current 2026/27 public syllabus. Do not silently blend CMS Europe and CMS Americas. Sources: [CMS Europe 2026/27 syllabus](https://courtofmastersommeliers.org/wp-content/uploads/2026/02/Syllabus-202627-1.pdf) and [Certified Sommelier Certificate](https://courtofmastersommeliers.org/certified-sommelier-certificate-1-day/).
3. WSET L4, CMS Advanced/Master, ASI and SWE/CSW remain future tracks unless separately scoped.
4. Exam-body documents define **scope and assessment shape**. Regulatory facts still cite legislation, official GI specifications/registers or other primary authorities.
5. Physical service can be taught through knowledge, scenarios, sequencing and checklists, but the app must not claim to validate actual pouring, tray handling or decanting technique.

## What the current backlog already covers

Do not duplicate these systems:

- regional wine content: C2–C6;
- general viticulture, winemaking, faults, service, pairing and business principles: C5;
- maps and spatial learning: G1–G13; G3 is complete;
- typed/short answers, structured formats, labels, reasoning, scenarios and tasting deduction: Q1–Q9;
- WSET-style and CMS-style tasting practice: T1–T2;
- Spätburgunder competition training: P1–P3 + G12;
- FSRS and adaptive study: already built.

The canonical-memory rule remains mandatory: map, text, reasoning and tasting presentations of the same fact update the same KnowledgeItem review state.

## Genuine V0.1 gaps

### SCOPE-1 — certification scope manifest

Create a versioned, non-copyright-infringing structural checklist for WSET L3 and CMS Europe Certified. Every required scope objective maps to authored curriculum or an explicit exclusion. F1 must report objective coverage as well as item/question coverage.

### C7 — CMS Certified beverage/service/business core

C5's current “spirits, beer and sake basics” is too vague for CMS Europe Certified. Add a dedicated content stream covering, at appropriate Certified depth:

- major spirit families and core production/service knowledge;
- beer **and cider/perry**;
- sake production, categories/labels, service and pairing;
- aperitif wines, liqueurs and bitters;
- classic cocktails and recommendations;
- bottle sizes, event-quantity arithmetic, markup/gross-profit calculations;
- beverage-list/cellar/service scenarios.

This should reuse the canonical graph and existing question formats. Do not build a separate beverage subsystem.

### Expert verification release gate

Draft content may remain `unverified` during development, but publicly marketed core certification content must be reviewed. V0.1 target: 100% of core WSET L3/CMS-EU items verified by a qualified reviewer, with provenance.

### Content volume

C2–C6 must author enough actual facts to cover the official structural scope. A schema that can represent Champagne, Sherry or German law does not count as curriculum coverage.

## Valuable V0.1 additions

- **S3 certification rehearsal presets** using original questions and existing formats;
- explicit source-hierarchy validation;
- current-law vs syllabus-scope separation;
- geography licence/attribution CI gate;
- 100% structural scope representation in addition to question-format coverage.

## CMS data modelling

Only add new node/relation types when C7 proves they are needed. Candidate data concepts include spirit categories, beer/cider styles, sake categories, cocktails, ingredients, service actions and business metrics. Reuse the existing quantity model for bottle sizes, temperatures and calculations.

F2 owns schema changes. Prefer data-only node/relation additions where possible.

## Question-format release targets

- 100% of required scope objectives represented;
- no core item flashcard-only;
- at least 90% of core items have “useful practice” under the existing coverage definition;
- core geographic facts with cleared geometry have spatial practice;
- at least half of core viticulture, winemaking, service and tasting items support reasoning;
- Spätburgunder remains stricter: aim for >=3 question families per core item where suitable.

Composite/reasoning grading keeps the existing **credit the chain, blame the target** rule.

## Geography and licensing

Keep the existing offline architecture and TopoJSON renderer. Do not introduce Google Maps/Mapbox as a required study dependency.

Preferred sources:

- world context: [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/) — public domain;
- French AOC/AOP geometry: [INAO SIQO geographic areas](https://www.data.gouv.fr/datasets/delimitation-des-aires-geographiques-des-siqo) — record Licence Ouverte 2.0 metadata and treat official specifications/commune lists as authoritative where geometry differs;
- French administrative context: official IGN ADMIN EXPRESS;
- German administrative context: [BKG VG250](https://gdz.bkg.bund.de/index.php/default/wfs-verwaltungsgebiete-1-250-000-stand-01-01-wfs-vg250.html) — record required attribution;
- German vineyard/site names and boundaries: official state registers such as [Landwirtschaftskammer Rheinland-Pfalz Weinbergsrolle](https://www.lwk-rlp.de/weinbau/rebflaechen/weinlagen), but **do not bundle copied geometry until redistribution rights are documented**.

When a legally reusable polygon is unavailable, use a truthful point/marker. Never invent an appellation/vineyard boundary.

Provisional budgets for G1/G7 to validate: <=30 MB compressed certification-core map assets, <=5 MB extra Spätburgunder detail, normally <=2 MB per frequently loaded layer, three LOD levels for dense layers, and CI failure for missing source/date/hash/licence/attribution metadata.

## Source hierarchy

1. Official WSET/CMS material for scope and assessment shape.
2. Legislation and official GI specifications/registers for legal facts.
3. Official statistics for planted area/ranking, always with survey year.
4. Official vineyard registers for legal names/hierarchy/boundaries.
5. OIV for technical/varietal terminology and statistics.
6. VDP only for VDP's private classification and rules.
7. Government, university and extension sources for climate/viticulture/production.
8. Regional bodies for contextual education, checked against primary regulatory sources when a claim is legal.

Primary links:
- [WSET Level 3](https://www.wsetglobal.com/qualifications/wset-level-3-award-in-wines)
- [CMS Europe syllabus 2026/27](https://courtofmastersommeliers.org/wp-content/uploads/2026/02/Syllabus-202627-1.pdf)
- [CMS Europe resources](https://courtofmastersommeliers.org/resources/)
- [OIV viticulture databases](https://www.oiv.int/what-we-do/viticulture-database-report)
- [DWI Spätburgunder](https://www.deutscheweine.de/rebsorte/94/sp%C3%A4tburgunder)

Statistics are dated facts, not timeless trivia. Sensory/regional tasting claims remain heuristics unless supported and expert-reviewed; preserve the Spätburgunder tree's `(H)` distinction.

## CI/release checks to add

- official-scope parity/orphan check;
- F1 coverage ratchet;
- core verification gate;
- source-hierarchy check for regulatory assertions;
- current-law conflict check;
- closed-world assertion gate for “all/none/select all” exercises;
- geography licence and attribution gate;
- geometry/node integrity and reproducible-build checks;
- spatial coverage gate;
- pack-genericity test;
- certification-rehearsal profile test;
- cross-platform smoke;
- release-size gate;
- About/attribution snapshot test.

## Dependency-correct critical path

```text
NOW: C1 + F1 + G1 + SCOPE-1 in parallel
          |
          +--> F2
                 |--> F3
                 |--> G2 (also needs G1)
                          |
                          +--> G4 (also needs F3; G3 is done)

After C1: C5 + C6 + C7 + T1 can author in parallel.
After F2: C2 + C3 + C4 can fan out.
```

The first vertical milestone should be:

> a verified curriculum item -> real licensed geometry -> map question -> same FSRS state as text question -> F1 reports textual + spatial coverage.

## Release claim discipline

“Exam preparation” is appropriate only after the corresponding scope/verification gates pass. Do not claim affiliation, accreditation, official endorsement, guaranteed exam readiness, or validation of physical service technique.
