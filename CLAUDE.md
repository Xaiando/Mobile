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

## Content and legal

These rules come from decisions D3, D8 and D10 in docs/architecture-audit.md §11.

- Never reproduce proprietary WSET or CMS exam questions, syllabus text or tasting-grid artwork.
- Curriculum content must cite authoritative public sources (`source_citations`) and stays `unverified` until a qualified reviewer checks it. Generated content is never authoritative without sources.
- Never commit the product specification PDF. The project is proprietary: do not add an open-source license.
- Record new legal or licensing uncertainties in docs/legal-review.md.
