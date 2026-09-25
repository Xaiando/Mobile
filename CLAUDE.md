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

To run the web smoke test:

```sh
flutter build web -t tool/web_smoke/main.dart -o build/web_smoke --no-web-resources-cdn
node tool/web_smoke/run.mjs build/web_smoke   # after npm ci in tool/web_smoke
```

## Planning

Work is planned in docs/backlog.md: one task per session, each naming its design note in docs/design/. Respect the backlog's hot-spot rules (§4) so parallel sessions do not collide. The first schema change belongs to task F2 only (audit DL-3).

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
- **The first schema change** also keeps the migration test that `make-migrations` generates, showing user tables survive the upgrade (audit DL-2).

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

## Study engine

`lib/core/study/` holds the FSRS reviews (`ReviewService`), the learner's track (`LearnerProfiles`) and session planning (`StudyPlanner`, `StudySession`). The decisions are FS-1 to FS-16, CM-3 to CM-6 and A-1 to A-10.

- Record reviews only through `ReviewService`. It writes the event, the options shown and the projected `review_states` row in one transaction, and counts `reps` and `lapses`.
- When upserting a data class, pass `toCompanion(false)`. The default drops NULL columns from the update, so a stale `step` would survive graduation.
- Retrievability comes from the package (`retrievabilityOf`); never recompute it in SQL or by hand. It counts whole days, so R is 1 on the day of a review.
- Scheduling tests disable fuzzing with `unfuzzedScheduler` and move time with `TestClock` (`test/support/study_fixture.dart`).
- Screens follow the database through Drift stream queries. Write app widget tests with `testApp` (`test/support/app_fixture.dart`), which unmounts the app so Drift's stream-closing timers run before the test ends.

## Content and legal

These rules come from decisions D3, D8 and D10 in docs/architecture-audit.md §11.

- Never reproduce proprietary WSET or CMS exam questions, syllabus text or tasting-grid artwork.
- Curriculum content must cite authoritative public sources (`source_citations`) and stays `unverified` until a qualified reviewer checks it. Generated content is never authoritative without sources.
- Never commit the product specification PDF. The project is proprietary: do not add an open-source license.
- Record new legal or licensing uncertainties in docs/legal-review.md.
