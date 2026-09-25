# Sommelier Study Companion

A Flutter study app for wine certification candidates on the WSET and Court of Master Sommeliers tracks. It combines spaced repetition over a canonical wine knowledge graph with structured tasting practice and a personal wine journal. It works fully offline.

**Status: Phase 3 (FSRS and study engine) complete.** The bundled curriculum dataset (release 0.2.0: 65 nodes, 87 relations, 46 cited items) loads on first launch and generates 91 questions (43 multiple-choice, 48 flashcards), with distractors chosen by walking the knowledge graph. A learner picks WSET Level 3 or CMS Certified on Home. Practice then runs adaptive sessions: FSRS-6 schedules every item, and a priority score picks what to study. Study lists the track's items with their memory state and sources. Tasting and journal screens arrive in later phases; [docs/phase-status.md](docs/phase-status.md) tracks every phase's acceptance criteria.

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

Android and iOS are the primary targets. The web gets basic support. Nothing in the code is mobile-specific, so desktop can be added later with `flutter create --platforms=windows,macos .`.

## Project layout

| Path | Contents |
|---|---|
| `lib/app/` | App widget, theme, router and the five-tab shell |
| `lib/core/database/` | `schema.drift` (the canonical schema), `AppDatabase`, the curriculum write lock |
| `lib/core/curriculum/` | Dataset parser, validator, ingestion and graph traversal queries |
| `lib/core/questions/` | Question generation (templates, eligibility, distractors) and seeded presentation |
| `lib/core/study/` | FSRS reviews, the learner's track, the priority score and session planning |
| `lib/core/coverage/` | The question coverage checker: which items each track can practise, and how; the policy and the baseline ratchet |
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
- [Implementation backlog](docs/backlog.md): the remaining work as 45 session-sized tasks, with dependencies and a parallel plan.
- Content plans: the [Spätburgunder study tree](docs/content/spaetburgunder-study-tree.md), with a blind-tasting playbook, and the [sub-region atlas](docs/content/subregion-atlas.md) of the famous regions.
- Design notes: [question system and coverage](docs/design/question-system.md), [geography and maps](docs/design/geography.md), [study packs](docs/design/study-packs.md).

## License

Proprietary. This repository is publicly visible, but no license is granted and all rights are reserved.
