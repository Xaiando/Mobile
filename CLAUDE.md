# CLAUDE.md

Guidance for agents working in this repository.

## Stack

Versions are pinned and were verified together (docs/architecture/architecture-validation.md):

- Flutter 3.47.5 / Dart 3.13 (`.fvmrc`).
- Riverpod 3 with hand-written providers. Do not add `riverpod_generator`. The root `ProviderScope` disables automatic retry (`noProviderRetry`).
- Drift 2.35 through `drift_flutter`. `sqlite3` 3.x bundles SQLite through build hooks; never add `sqlite3_flutter_libs`.
- go_router 18: one `StatefulShellRoute.indexedStack` branch per tab.

## Commands

```sh
flutter pub get
dart run build_runner build          # commit the generated *.g.dart files
dart run drift_dev make-migrations   # after any schema change, with schemaVersion bumped
dart format $(git ls-files --cached --others --exclude-standard '*.dart' ':!:*.g.dart')
flutter analyze
flutter test
tool/web_assets.sh check             # `fetch` after upgrading sqlite3 or drift
```

Google Play requires 16 KB page alignment. After a release build, check it with:

```sh
flutter build apk --release
tool/check_16kb_alignment.sh build/app/outputs/flutter-apk/app-release.apk   # needs ANDROID_HOME
```

`build_runner` 2.16 ignores `--delete-conflicting-outputs`.

Installable builds (backlog R4). CI keeps a Windows installer, a portable Windows folder and a release APK as artifacts of every run:

```sh
flutter build windows --release         # needs Windows Developer Mode for plugin symlinks
iscc /DAppVersion=<version> windows\installer\sommelier.iss   # Inno Setup 6
flutter test integration_test -d windows --dart-define=SOMMELIER_DATABASE=integration
python tool/icons/make_icons.py         # after changing the icon; commit its outputs
```

- The release key is private. CI signs APKs on pushes to `main` with the `ANDROID_KEYSTORE_*` secrets that `tool/android/make_release_key.ps1` creates; the user runs that script, never an agent. Never commit a keystore or `key.properties`, and never make a second key: updates install only over an app signed with the same one (L-28).
- Bump `version` in `pubspec.yaml` for each build you hand out; Windows and Android read it.
- Integration tests pass `SOMMELIER_DATABASE`, so they never open a learner's database.

To run the web smoke test:

```sh
flutter build web -t tool/web_smoke/main.dart -o build/web_smoke --no-web-resources-cdn
node tool/web_smoke/run.mjs build/web_smoke   # after npm ci in tool/web_smoke
```

## Planning

Work is planned in docs/backlog.md: one task per session, each naming its design note in docs/design/. Respect the backlog's hot-spot rules (§4) so parallel sessions do not collide. Schema v2 (task F2) holds every schema change the backlog planned; a later change needs its own scheduled task (audit DL-3).

Research handoff: read `docs/research/claude-handoff.md` before curriculum, coverage, certification-scope, geography-data, or release-gate work. The supporting audit is `docs/research/curriculum-gap-audit.md` and the track matrix is `docs/research/certification-matrix.md`. The research adds SCOPE-1, C7 and S3; it does **not** supersede the canonical domain model or completed G3 renderer.

Content plans live in docs/content/: the Spätburgunder study tree and the sub-region atlas. Author only their cited facts. Resolve each *to verify* item against its primary source first. Never author a heuristic marked **(H)** as a fact (audit PK-7). The task that creates a node also writes its location item (GEO-18).

## Data rules

The canonical model is in docs/domain-model.md.

- `lib/core/database/schema.drift` is the canonical schema, and docs/domain-model.md explains it. Change them together, and record decisions in docs/architecture-audit.md.
- **Curriculum tables are read-only at runtime.** Write them only inside `db.writeCurriculum(...)`; triggers reject anything else. Ingestion never writes user tables.
- **Authored curriculum rows are never deleted.** Retire them with `valid_until` or `superseded_by_item_id`. The generated tables (`questions`, `question_distractors`) are rebuilt on every ingestion.
- **Timestamps** are UTC with whole milliseconds. Use `utcNow()` or `toStorageInstant()`; the schema rejects any other form.
- **IDs:** curriculum text IDs have a prefix (`n_`, `ki_`, `src_`, `qt_`, `tg_`); user rows use UUIDs.
- `review_events` is append-only. `review_states` is its projection, written in the same transaction.
- **FSRS** uses the `fsrs` package (FSRS-6). Never hand-code the product specification's §F formulas; they are wrong (audit §4).
- **Web:** keep `package:drift/wasm.dart` out of code that also compiles for native platforms.
- **Only `lib/core` queries the database.** Screens and providers go through its repositories; `test/architecture/layering_test.dart` enforces this (audit DL-1).
- **`lib/core` is plain Dart**, so the tools run it with `dart run`. Only its `*_providers.dart` files and `database_connection.dart` may import Flutter, `flutter_riverpod`, `drift_flutter` or `dart:ui`; the layering test enforces this.
- **A schema change** bumps `schemaVersion`, runs `make-migrations`, writes the new step in `app_database.dart` against its versioned snapshot, and extends `test/drift/app_database/migration_test.dart` to show user rows and guards survive (audit DL-2, DL-5). A column added to an existing table goes last in `schema.drift`, where `ADD COLUMN` puts it.

## Curriculum dataset

The curriculum is one release in the format of docs/domain-model.md §7: each section is a table, each key a column. `assets/curriculum/curriculum.yaml` is its manifest: `dataset_version`, `published_at` and `includes`, the list of the other files. Content goes in `areas/<area>.yaml`, question templates in `templates/<format>.yaml`. Startup ingests the release (`CurriculumIngester`).

```sh
dart run tool/curriculum/lint.dart     # every problem, with file and line
dart run tool/curriculum/report.dart   # the generation report
dart run tool/curriculum/verify.dart <item> --reviewer <name> --outcome verified|disputed [--notes <text>]
```

- **Any change to any file needs a new `dataset_version`** in the manifest. Ingestion refuses a release that drops an authored row; retire rows with `valid_until` or `superseded_by_item_id`.
- A new file needs an `includes` line; its folder is already bundled. A row's key is unique across all files.
- `lint` must report no errors. `test/core/curriculum/curriculum_validator_test.dart` also runs `validateDataset` on the bundle.
- **Record expert reviews only with `verify`** (D3). It appends to the ledger in `assets/curriculum/reviews/` and sets the item's `verification_status`. Never set `verified` by hand; `lint` rejects a verified item that the ledger does not back.
- Every item cites a primary legal text (`knowledge_item_citations`) and maps to at least one track. Wine-law relation types need a `legislation` or `regulator_register` citation (`regulatoryRelationTypes`).
- When a legal text lists grape varieties, link every listed variety that exists as a node, or it can be offered as a wrong answer.
- Set `mcq_disabled: true` when a wrong answer could be defensible, e.g. overlapping climate types.
- A symmetric relation type (`is_symmetric: true`, e.g. `BORDERS`) stores each pair once, with the smaller node ID as subject.
- A format that asserts absence (multiple response, "tap all") needs a `relation_set_assertions` row citing the complete list (QF-8, QF-9).
- A study pack is a `certifications` row with `kind: pack` and no `organization` or `level` (PK-8).
- A template's `mode` must be a built format (`builtFormats`). `variant` tells two templates of one format apart, and `parameters` is a mapping.
- `valid_from: 1900-01-01` means the effective date is not curated yet.

## Question engine

Ingestion regenerates `questions` and `question_distractors` (`QuestionGenerator`); nothing else writes them.

- Templates use only `{subject.name}`, `{object.name}` and `{object.type_label}`. A relation type that carries items needs a forward template.
- An MCQ exists only with at least 3 valid distractors (architecture audit QG-12). Reverse questions need a reverse-safe relation type or `is_distinctive: true`.
- The test suite fails if an item has neither an MCQ nor `mcq_disabled: true` (§S.3), so after adding items, run the tests and read the generation report (`tool/curriculum/report.dart`).
- Present questions through `QuestionPresenter.present(seed:)`, and log the seed and the options shown with the review (QG-7).

## Question coverage

`tool/coverage_report.dart` measures, for each selectable track, which items can be practised and with which formats (backlog F1, question-system §8). `assets/curriculum/coverage_policy.yaml` holds the policy and `coverage_baseline.json` the ratchet. The app bundles neither.

```sh
dart run tool/coverage_report.dart                    # Markdown; --format json, --track WSET_L3
dart run tool/coverage_report.dart --update-baseline  # after a change that moves coverage
```

- **A new relation type** needs a `capabilities` entry. It lists every built format under `supports`, or under `excludes` with a reason; otherwise `lint` and the checker fail.
- **What fails the build:**
  - a metric that falls below the baseline;
  - an item that is untestable or flashcard-only, unless `known_gaps` lists it with a reason and the task that closes it (COV-6).
- **After a content change**, read the report, run `--update-baseline`, and commit the baseline with the change.
- **A new format** adds itself to `builtFormats` (`lib/core/coverage/coverage_formats.dart`) and to every relation type in the policy.
- **Scope objectives** (`assets/curriculum/track_scope.yaml`, SCOPE-1) pin each track to one body's official document. CMS_CERTIFIED means CMS Europe (CM-10).
  - Objectives are labels in our own words, never syllabus text (L-27).
  - A task that adds a region's node, or the content of a planned objective, adds that objective's `covers`. Only authored items make an objective represented (COV-7).
  - Never cite a syllabus as a fact's source; `lint` rejects it.
  - Re-check the pinned documents yearly; `lint` warns when they are stale.

## Map layers

`tool/geography/` builds the offline map layers in `assets/geography/` from open-licensed sources (backlog G1, geography §7). It needs Node 22.13 or later.

```sh
cd tool/geography && npm ci
npm run fetch   # once, online: downloads and verifies the sources into ~/.cache/sommelier-geography
npm run build   # the layers, assets/geography/manifest.yaml and tool/geography/report.md
npm test        # the pipeline's unit tests
npm run check   # CI runs this; with every source cached it also rebuilds and compares
```

- **Never edit the assets or the manifest by hand.** Change `layers.yaml` or `sources.yaml`, rebuild, read `report.md`, and commit them all together.
- **A source needs a licence that allows bundling in a proprietary app** (GEO-5, legal review L-15). Record its URL, retrieval date, SHA-256, licence and attribution. `npm run fetch -- --record` fills in a `PENDING` hash. A new edition is a new entry.
- **Never trace or invent a boundary.** Where no open shape exists, draw a point (GEO-9).
- **French areas are unions of communes**, taken from INAO's lists. A region without a legal area is a union of appellation areas, and its composition stays provisional until G10 (GEO-19).
- Each task adds only its own entries to `layers.yaml` (backlog §4). The build is deterministic, so other layers come out unchanged. The budgets are 1.5 MB per layer and 8 MB in all (GEO-11).

## Study engine

`lib/core/study/` holds the FSRS reviews (`ReviewService`), the learner's track (`LearnerProfiles`) and session planning (`StudyPlanner`, `StudySession`). The decisions are FS-1 to FS-16, CM-3 to CM-6 and A-1 to A-10.

- Record reviews only through `ReviewService`. It writes the event, the options shown and the projected `review_states` row in one transaction, and counts `reps` and `lapses`.
- When upserting a data class, pass `toCompanion(false)`. The default drops NULL columns from the update, so a stale `step` would survive graduation.
- Retrievability comes from the package (`retrievabilityOf`); never recompute it in SQL or by hand. It counts whole days, so R is 1 on the day of a review.
- The wine journal (`lib/core/journal/`, backlog J1–J2) links entries to knowledge nodes, and the journal factor J lifts the items about them (A-5, A-11). The learner confirms every link; never link a node silently.
- Scheduling tests disable fuzzing with `unfuzzedScheduler` and move time with `TestClock` (`test/support/study_fixture.dart`).
- First launch shows onboarding until the learner confirms their age and picks a track (`LearnerSettings`, backlog R1). App tests start past it: `pumpApp(tester, db)` records it, and `pumpApp(tester, db, onboarded: false)` shows it. In a widget test, await a Drift stream only inside `tester.runAsync`, or it waits forever.
- Screens follow the database through Drift stream queries. Write app widget tests with `testApp` (`test/support/app_fixture.dart`), which unmounts the app so Drift's stream-closing timers run before the test ends.

## Content and legal

These rules come from decisions D3, D8 and D10 in docs/architecture-audit.md §11.

- Never reproduce proprietary WSET or CMS exam questions, syllabus text or tasting-grid artwork.
- Curriculum content must cite authoritative public sources (`source_citations`) and stays `unverified` until a qualified reviewer checks it. Generated content is never authoritative without sources.
- Never commit the product specification PDF. The project is proprietary: do not add an open-source license.
- Record new legal or licensing uncertainties in docs/legal-review.md.
