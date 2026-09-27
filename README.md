# Sommelier Study Companion

A Flutter study app for wine certification candidates on the WSET and Court of Master Sommeliers tracks. It combines spaced repetition over a canonical wine knowledge graph with structured tasting practice and a personal wine journal. It works fully offline.

**Status: active development.** The bundled curriculum dataset (release 0.20.4) loads on first launch. It retains the German, Austrian, Swiss, Hungarian and Greek core and maps 1,423 noncountry places across 20 countries, supported by 1,424 cited location facts. French coverage includes seven Chablis Grand Cru climats, all 40 named Premier Cru label climats, all 32 Côte d'Or Grand Cru appellations and all 51 Alsace Grand Crus. Italy has all 20 administrative regions and important appellations and subregions; the United States and Southern Hemisphere have substantially expanded regional coverage. The full Diploma curriculum remains unfinished; the atlas also has documented finer-region gaps. [Geography coverage](docs/research/geography-coverage.md) records the current inventory and limits.

The whole companion targets WSET Level 4 Diploma; production, business, regional analysis, sparkling and fortified wines, tasting and research support are tracked in the [Diploma gap audit](docs/research/wset-level-4-gap-audit.md). A learner picks WSET Level 3, WSET Level 4 Diploma or CMS Certified on Home, then practises through multiple choice, flashcards, typed recall, short written profiles, causal reasoning and offline map questions. Maps include finding two to four named places, with a separate grade for each, and finding one area from one to three grape clues. Legal grape questions use cited complete permission lists; dated planting questions use a separate cited survey-year cohort. Every represented correct alternative is accepted and each requested fact is reviewed independently. Point markers show reference locations rather than wine-area boundaries. FSRS-6 shares each item's memory across formats, and a difficulty ladder adjusts its presentations. Study lists items with their memory state and sources; structured tasting, a personal wine journal, onboarding and data export are implemented. Content awaits qualified expert review, and certification parity is not yet claimed. [docs/backlog.md](docs/backlog.md) tracks the remaining work.

Release 0.20.0 adds objective causal reasoning and 21 cited Diploma-only points across four controlled vineyard/winery mechanisms. Release 0.20.1 does not add items: it corrects two Italian explanations after a source check. [Fact check](docs/research/fact-check-2026-09-27.md). A correct answer reviews the full chain; a wrong answer reviews only its conclusion. Sources and explanations appear after answering, and only already-studied support can join the exercise. Release 0.20.2 adds four climate/weather exercises and 20 further Diploma-only points, bringing reasoning to eight exercises across 41 points. Release 0.20.4 joins that work with nine mapped Vino Nobile Pieve units. The bundle has 2,853 items. Its 704 D3 regional analysis points and all earlier maps remain intact. Sant'Ilario, Cerliana and Valardegna stay unmapped. China analysis stays Diploma-only, with eight older optional atlas references retained. All facts await qualified review. [Initial reasoning validation](docs/research/diploma-reasoning-continuation.md) and [climate continuation](docs/research/diploma-climate-reasoning-continuation.md).

Home → **Your WSET progress** shows studied and currently mastered material for Levels 1–4, missing curriculum coverage, Diploma topic groups and the next facts to study. Spaced successful reviews establish mastery; later failures or fading memory can reduce it. Learners can independently record exam passes as self-reported results. All four level scopes remain explicitly incomplete, so mastering the available material cannot claim a completed WSET qualification. [Progress behaviour and validation](docs/wset-learner-progress.md).

## Install

Every CI run on `main` builds the app for Windows and Android. Open the latest run of the **CI** workflow under the repository's *Actions* tab, and download its artifacts:

| Artifact | What to do |
|---|---|
| `sommelier-windows-installer` | Unzip it and run `SommelierStudyCompanion-<version>-setup.exe`. It installs for your user, with no administrator rights, and adds a Start menu entry. Windows SmartScreen may warn about an unsigned installer: choose *More info → Run anyway*. |
| `sommelier-windows-portable` | Unzip it anywhere and run `sommelier.exe`. |
| `sommelier-android-apk` | Unzip it, copy `app-release.apk` to the phone, and open it. Android asks you to allow installing apps from that source once. |

Everything runs offline. Your progress is stored on the device: on Windows in `%APPDATA%\Xaiando\Sommelier Study Companion`, which uninstalling and upgrading keep.

**Android updates** install over the previous version and keep your progress only if every APK carries the same signature. APKs from `main` are signed with the repository's private release key, once it exists. Create it once, on a PC with a JDK and the GitHub CLI signed in: `powershell -ExecutionPolicy Bypass -File tool\android\make_release_key.ps1`. It stores the key as the repository's Actions secrets and keeps a copy in `%USERPROFILE%\.sommelier`; back that folder up. Until then, and on pull requests, APKs are signed with a throwaway debug key: they install fresh, but cannot update one another.

### Building the installable apps yourself

- **Windows** needs Visual Studio's *Desktop development with C++* tools, and Windows *Developer Mode* (Settings → System → For developers), because Flutter links its plugins with symbolic links. Then run `flutter build windows --release`. The installer needs [Inno Setup 6](https://jrsoftware.org/isinfo.php): `iscc /DAppVersion=<version> windows\installer\sommelier.iss`.
- **Android** needs the Android SDK and a JDK 17 or later: `flutter build apk --release`.

## Getting started

Requires Flutter **3.47.5**, pinned in `.fvmrc`. If you use [FVM](https://fvm.app), run `fvm use`.

```sh
flutter pub get
flutter test
flutter run
```

After changing `lib/core/database/schema.drift` or other Drift code:

```sh
dart run build_runner build          # regenerate Drift code; commit the *.g.dart files
dart run drift_dev make-migrations   # after a schema change: bump schemaVersion first
```

### Web

The web build needs Drift's runtime files in `web/`, pinned to the resolved package versions:

```sh
tool/web_assets.sh check    # verify sqlite3.wasm and drift_worker.js
tool/web_assets.sh fetch    # after upgrading sqlite3 or drift
flutter build web --no-web-resources-cdn
```

`--no-web-resources-cdn` bundles the CanvasKit renderer, so the app does not need Google's CDN to start. Serve the build with these headers so the database can use the Origin Private File System (OPFS); without them it falls back to IndexedDB:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

## Platforms

Windows, Android and iOS are configured targets. The web gets basic support.

## Project layout

| Path | Contents |
|---|---|
| `lib/app/` | App widget, theme, router and the five-tab shell |
| `lib/core/database/` | `schema.drift` (the canonical schema), `AppDatabase`, the curriculum write lock |
| `lib/core/curriculum/` | Dataset parser, validator, ingestion and graph traversal queries |
| `lib/core/questions/` | Question generation (templates, eligibility, distractors) and seeded presentation |
| `lib/core/study/` | FSRS reviews, the learner's track, the priority score and session planning |
| `lib/core/coverage/` | The question coverage checker: which items each track can practise, and how; the policy and the baseline ratchet |
| `lib/core/progress/` | Cumulative WSET material counts, current mastery, Diploma groups and self-reported exam settings |
| `assets/curriculum/` | The curriculum release: a manifest that includes one YAML file per area and per question format; beside it, the expert-review ledger, the coverage policy and baseline, and the certification scope manifest |
| `lib/core/time/` | The UTC millisecond clock used for every stored timestamp |
| `lib/features/` | Home (dashboard and track picker), Study (curriculum browser), Practice (sessions), Tasting and Cellar |
| `test/` | Schema, CRUD, write-lock, curriculum, question, study engine, clock and widget tests |
| `tool/` | The curriculum tools (`lint`, `report`, `verify`), the question coverage report, web asset pinning, the web smoke test and the Android 16 KB alignment check |
| `drift_schemas/` | Schema snapshots for migration tests |
| `docs/` | Audit, architecture validation, decision register and domain model |

## Documentation

- [Domain model](docs/domain-model.md): the canonical entities, data classes and ER diagrams.
- [Architecture audit](docs/architecture-audit.md): the decision register, including every user decision.
- [Architecture validation](docs/architecture/architecture-validation.md): package compatibility evidence.
- [Phase 0 engineering audit](docs/audit/phase-0-engineering-audit.md): the review of the product specification.
- [Legal review register](docs/legal-review.md): items to clear before any public release.
- [Phase status](docs/phase-status.md): each phase's acceptance criteria and where they stand.
- [Implementation backlog](docs/backlog.md): 48 session-sized tasks, with status, dependencies and a parallel plan.
- Content plans: the [Spätburgunder study tree](docs/content/spaetburgunder-study-tree.md), with a blind-tasting playbook, and the [sub-region atlas](docs/content/subregion-atlas.md) of the famous regions.
- Design notes: [question system and coverage](docs/design/question-system.md), [geography and maps](docs/design/geography.md), [study packs](docs/design/study-packs.md).
- [Geography coverage](docs/research/geography-coverage.md): the bundled countries and location facts, map formats, source methods and remaining atlas work.
- [Learner progress](docs/wset-learner-progress.md): available material, lasting mastery, incomplete levels and independently recorded exam results.

## License

Proprietary. This repository is publicly visible, but no license is granted and all rights are reserved.
