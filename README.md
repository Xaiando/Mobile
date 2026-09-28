# Sommelier Study Companion

A Flutter study app for wine certification candidates on the WSET and Court of Master Sommeliers tracks. It combines spaced repetition over a canonical wine knowledge graph with structured tasting practice and a personal wine journal. It works fully offline.

**Status: active development.** The bundled curriculum loads on first launch. All five tracks are selectable: WSET Levels 1, 2 and 3, WSET Level 4 Diploma, and CMS Certified. Level 1–3 delivery is mapped to the public specifications: Level 1 June 2022 Issue 1.2, Level 2 2026 Issue 2.1 and Level 3 May 2022 Issue 2. The [completion plan](docs/research/wset-1-3-completion-plan.md) and [delivery validation](docs/research/wset-1-3-delivery-validation.md) record the required topics, exact lesson evidence, review boundary and release gates. Diploma remains incomplete; its broader production, business, regional analysis, sparkling, fortified, tasting and research requirements are tracked in the [Diploma gap audit](docs/research/wset-level-4-gap-audit.md).

The candidate release is **app 0.4.0+17 / dataset 0.24.0**, with 125 registered curriculum includes, 3,989 factual items and 38 map layers. The [final outcome audit](docs/research/wset-levels-1-3-final-outcome-audit.md) finds no remaining mandatory Level 1–3 instructional or exact-reference gap in the reviewed study catalog. Levels 1–3 app study coverage is internally reviewed and its delivery gates pass. Learner milestones require mastery and recorded practice; official qualification and expert factual verification remain separate. Diploma remains incomplete.

| Level | Required topic rows | Distinct required facts |
|---|---:|---:|
| WSET 1 | 49 | 132 |
| WSET 2 | 442 | 752 |
| WSET 3 | 888 | 1,625 |

These cumulative app study selections separate required explanations from optional mapped material; they are not official examination-topic counts. Geographic location, grape/style, growing environment, production, labels and quality/price have their own exact teaching evidence.

A learner chooses a track on Home, then practises through multiple choice, flashcards, typed recall, numeric answers, short written profiles, causal reasoning and offline map questions. FSRS-6 shares each item's memory across formats, and a difficulty ladder adjusts its presentations. Study searches lesson text, names and aliases without requiring accents, offers a topic filter, and retains each item's memory state and sources. Unfinished required topics can start focused practice using their exact lesson IDs.

Shared-topic principles use 522 original point-specific typed cues covering all 520 required shared points and two additional optional points. Each cue accepts its finite responsive phrases, so a different sibling lesson or an unresponsive broad title cannot earn credit for the selected fact. Written explanation exercises use the selected track's currently served points and explicit self-assessment; they do not automatically grade prose.

Maps include finding two to four named places with separate grading, and finding an area from grape clues. Legal grape questions use cited permission lists; dated planting questions use a separate survey-year cohort. Every represented correct alternative is accepted and each requested fact is reviewed independently. Point markers show reference locations rather than wine-area boundaries. The atlas retains its European core and expanded American and Southern Hemisphere coverage; [geography coverage](docs/research/geography-coverage.md) records its inventory and remaining finer-region gaps.

Original timed rehearsals save answers and prompt snapshots, with feedback after the attempt ends. A 220-question original MCQ bank supplies scoped pools of 65/190/220 questions for Levels 1/2/3; presets sample 30 questions in 45 minutes, 50 in 60 minutes, and 50 plus four written prompts in 120 minutes respectively. Level 3 draws from twelve original extended cases with saved responses and explicit self-review against explanatory criteria. Guided tasting adds three original teaching grids and nine fictional calibration cases, physical wine notes and a timed Level 3 two-wine practice. Existing tasting sessions and vocabulary remain usable. Rehearsal participation, written self-review and tasting evidence are recorded separately from FSRS reviews; they do not award official examination grades or passes. Saved work is included in backup and restore, and unreadable practice records are reported without hiding valid history.

Home → **Your WSET progress** separates required Level 1–3 teaching from optional atlas material, shows studied and currently mastered facts, and records the level's practice evidence. An app study milestone requires a scope explicitly marked complete, every required topic mastered and its required practice recorded. Spaced successful reviews establish mastery; later failures or fading memory can reduce it. Diploma topic groups show supporting material and outstanding gaps. Learners can independently record exam passes as self-reported results. App milestones do not award a WSET qualification. [Progress behaviour and validation](docs/wset-learner-progress.md).

Internal research and critique assess scope and delivery against the public specifications. New factual lessons retain their unverified review status pending qualified expert review. Wine history now has a chronological Study view for CMS Certified and WSET Level 4; the sommelier strand adds beer, spirits, cider, sake and cigar basics with applied written practice. These optional strands do not count toward WSET Levels 1–3 Award in Wines requirements. The cellar journal accepts local label and glass photos, with on-device label-text suggestions on Android/iOS and manual transcription elsewhere. Backups include those photos in an unencrypted JSON file and should be kept private. [The completion plan](docs/research/history-beverage-scanner-completion-plan.md) records the implementation boundaries; [docs/backlog.md](docs/backlog.md) tracks remaining work.

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
| `lib/core/progress/` | Required and optional WSET material, current mastery, recorded practice, Diploma groups and self-reported exam settings |
| `lib/core/rehearsal/`, `lib/core/tasting_guidance/`, `lib/core/tasting_pair/` | Original timed rehearsals, guided calibration and saved two-wine practice |
| `assets/curriculum/` | The curriculum release, teaching grids, expert-review ledger, coverage policy and baseline |
| `assets/study/` | Original rehearsal bank, point-specific typed cues, presets and guided tasting calibration cases |
| `assets/progress/` | Exact required-topic evidence, completion metadata and level-specific practice requirements |
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
- [Learner progress](docs/wset-learner-progress.md): required and optional material, lasting mastery, recorded practice and independently recorded exam results.
- [WSET Level 1–3 delivery validation](docs/research/wset-1-3-delivery-validation.md): specification scope, original practice, preservation checks and release evidence.
- [Final Level 1–3 outcome audit](docs/research/wset-levels-1-3-final-outcome-audit.md): exact required selections, semantic review, optional boundaries and remaining release gates.

## Historical release snapshots

These counts describe earlier bundles and are not the current inventory or qualification completion denominators.

- **0.20.0–0.20.4:** objective causal reasoning grew to eight exercises over 41 Diploma-only points, with sources and explanations shown after answering. A correct answer reviews the full chain; a wrong answer reviews its conclusion. The 0.20.4 bundle had 2,853 points and nine mapped Vino Nobile Pievi. [Initial reasoning validation](docs/research/diploma-reasoning-continuation.md), [climate continuation](docs/research/diploma-climate-reasoning-continuation.md) and [0.20.1 source corrections](docs/research/fact-check-2026-09-27.md).
- **0.20.5:** 16 producer-model/channel principles and four original written cases added 32 Diploma-only points, taking that bundle to 2,885 points. The cases compare ownership, outsourcing, cooperative resources and routes to market under stated conditions. [Business validation](docs/research/diploma-business-channels-continuation.md).
- **0.20.7:** the atlas then mapped 1,432 noncountry places across 20 countries with 1,433 cited location facts. Numeric practice added structured questions for ten existing ageing requirements and eleven dated vineyard statistics, plus range grading and Celsius/Fahrenheit conversion; it added no facts. [Numeric validation](docs/research/numeric-practice-continuation.md).

The current work preserves the original 704 Diploma D3 selectors, China's eight optional atlas references and its 44 Diploma-only analytical lessons. Detailed historical counts and preservation checks are retained in the linked audit records.

## License

Proprietary. This repository is publicly visible, but no license is granted and all rights are reserved.

