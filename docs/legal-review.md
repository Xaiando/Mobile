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
| L-1 | Trademarks of the examining bodies | Is using "WSET", "Court of Master Sommeliers" and "CMS" to name study tracks acceptable descriptive use? | Names are used descriptively only, with no logos. Add a non-affiliation disclaimer before release. | Audit LEGAL-1 |
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
