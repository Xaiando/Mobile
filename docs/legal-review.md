# Legal and Licensing Review Register

| | |
|---|---|
| **Status** | Open. Every item must be reviewed by qualified counsel **before any public release**. |
| **Decision** | D10: development does not wait for legal review. This register tracks what must be cleared later. |
| **Nature** | Engineering flags, not legal advice. |

## Rules in force now

- No proprietary WSET or CMS exam questions, syllabus text or tasting-grid artwork is reproduced (D10).
- Curriculum facts cite authoritative public sources and stay `unverified` until reviewed. Generated content is never treated as authoritative without sources (D3).
- The product specification PDF stays out of the repository, and the project is proprietary with no open-source license (D8).

## Open items

| ID | Topic | Question for review | Current handling | Origin |
|---|---|---|---|---|
| L-1 | Trademarks of the examining bodies | Is using "WSET", "Court of Master Sommeliers" and "CMS" to name study tracks acceptable descriptive use? | Names are used descriptively only, with no logos. Since Phase 3, Home shows a non-affiliation disclaimer; its wording needs review before release. | Audit LEGAL-1 |
| L-2 | Tasting vocabularies | May the tasting grids' structure and terms be represented as data (TASK-008)? | Grids are data in our own wording, built from public descriptions; no artwork. Review before Phase 4 content ships. | Audit LEGAL-2 |
| L-3 | ODbL datasets | Would a share-alike licence (e.g. Open Food Facts) extend to the curriculum database? | Not used for the canonical curriculum. | Audit LEGAL-3 |
| L-4 | LWIN | What are the terms of Liv-ex's LWIN licence? | Not used; the label scanner is deferred. | Audit LEGAL-4 |
| L-5 | EU database right | Does authoring facts risk substantial extraction from compiled databases? | Facts are authored from primary legal sources, not copied from compilations. | Audit LEGAL-5 |
| L-6 | Source quality | The specification's works cited cannot serve as provenance. | Only primary and authoritative sources are cited. | Audit LEGAL-6 |
| L-7 | Certification facts | Are the exam formats and pass marks stated in the specification accurate (e.g. the CMS Advanced pass mark)? | Not stored in V0.1. | Audit LEGAL-7 |
| L-8 | Proprietary code in a public repository | Visitors can read the code but receive no rights. Should the repository become private before release? | No LICENSE file; the README states that all rights are reserved. | D8 |
| L-9 | Third-party notices | Are the licences of bundled software satisfied? This includes pub packages (MIT/BSD), the vendored `sqlite3.wasm` (from sqlite3.dart; SQLite itself is public domain), `drift_worker.js` (from Drift) and fonts bundled by Flutter. | Flutter's licence page collects pub package licences. Verify that the vendored web files and fonts are covered. | Phase 0 |
| L-10 | App name | Is "Sommelier" clear for store listings? Titles such as "Master Sommelier" may be marks of the examining bodies. | Working title only. The bundle ID `com.xaiando.sommelier` is a placeholder until store setup. | Phase 0 |
| L-11 | User data and privacy | Journal entries and future photos are personal data. What do store privacy labels and GDPR require? | All data stays on the device in V0.1, with no telemetry. | Phase 0 |
| L-12 | AI-drafted content | What accuracy and attribution obligations apply to content drafted with AI assistance? | Content is cited, marked `unverified`, and reviewed by an expert before release (D3). | D3 |
| L-13 | Reuse of public legal texts | Dataset 0.1.0 restates facts from INAO cahiers des charges and MASAF disciplinari. Are there attribution or reuse terms to honour, e.g. France's Licence Ouverte for public information? | Facts are restated in our own words; only titles, section names and identifiers are quoted. Each item cites its source. | Phase 1 |
| L-14 | Certification mappings | Mapping items to WSET and CMS levels is an editorial judgement. Could it be read as a claim about exam content? | Mappings are marked editorial in the dataset, hold no syllabus text (CM-7), and stay `unverified`. | Phase 1 |
| L-15 | Map data licences | Do the geography sources permit bundling derived shapes in a proprietary app, and how must attribution appear? The sources are Natural Earth (public domain); IGN ADMIN EXPRESS, INAO aires géographiques and INAO parcel delimitations (Licence Ouverte 2.0); BKG VG250 and the RLP Einzellagen register (dl-de/by-2-0, with "[data edited]"); ISTAT boundaries (CC BY, version to confirm); UC Davis AVAs (CC0); SRTM (public domain). | Only these sources are used (GEO-5). Each is recorded in `tool/geography/sources.yaml` with its licence, date and attribution. Every map shows its layers' attributions, and *About* lists them all (GEO-14). | Geography design |
| L-16 | Excluded map sources | Confirm the exclusions. Eurostat GISCO / EuroGeographics boundaries are non-commercial only. OpenStreetMap's ODbL share-alike could reach a bundled derived database. Wine-atlas and trade-body maps are copyrighted artwork. | None of them is used. OpenStreetMap could be reconsidered for a separately licensed layer after review. | Geography design |
| L-17 | Service standards | The CMS publishes proprietary service standards. How close may service scenarios come to widely taught practice? | Scenarios draw on general, cited public sources and never reproduce CMS standards text (D10). | Question-system design |
| L-18 | Food pairing and tasting guidance | Pairing and style descriptions are partly subjective. Is framing them as principles, with sources, enough? | Presented as principles with citations; no health claims. | Question-system design |
| L-19 | Private classification names | VDP.GROSSE LAGE, GROSSES GEWÄCHS and similar terms are trademarks of a private association. How may the Spätburgunder pack explain them? | Described only as a private classification, never presented as law or used as the app's own labels. Legal terms of the German wine law are used as law. | Study-packs design |
| L-20 | Synthetic labels | Do generated labels risk resembling real products or trade dress? | Invented producer names only; generic layouts; no logos or real label imagery. | Question-system design |
| L-21 | Statistics | Planted-area and similar statistics come from Destatis (dl-de/by-2-0, to confirm). Wine-institute publications are copyrighted. | Figures are restated as cited facts with a survey date, never copied as tables. | Study-packs design |
| L-22 | Competitions | Does "competition training" risk implying affiliation with a named competition? | No competition is named, and no mark is used. | Study-packs design |
| L-23 | Elevation data | The Copernicus DEM requires an "all rights reserved" notice. Is SRTM, which is public domain, sufficient? | SRTM is preferred. The Copernicus DEM is used only with its notice, if ever. | Geography design |
| L-24 | Alcohol-related content | What age rating and age confirmation do Google Play and the App Store require for an alcohol education app? | An age confirmation at onboarding (R1). The rating is chosen at release (R3). | Backlog review |
