# Sommelier

A Flutter study app for wine certification candidates on the WSET and Court of Master Sommeliers tracks. It combines spaced repetition over a canonical wine knowledge graph with structured tasting practice and a personal wine journal. It works fully offline.

**Status: Phase 0 (foundation).** The app shell, the database built from the canonical domain model, and CI are in place. Study, practice, tasting and journal features arrive in later phases.

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
| `lib/core/time/` | The UTC millisecond clock used for every stored timestamp |
| `lib/features/` | Home, Study, Practice, Tasting and Cellar |
| `test/` | Schema, CRUD, write-lock, clock and widget tests |
| `tool/` | Web asset pinning, the web smoke test and the Android 16 KB alignment check |
| `drift_schemas/` | Schema snapshots for migration tests |
| `docs/` | Audit, architecture validation, decision register and domain model |

## Documentation

- [Domain model](docs/domain-model.md): the canonical entities, data classes and ER diagrams.
- [Architecture audit](docs/architecture-audit.md): the decision register, including every user decision.
- [Architecture validation](docs/architecture/architecture-validation.md): package compatibility evidence.
- [Phase 0 engineering audit](docs/audit/phase-0-engineering-audit.md): the review of the product specification.
- [Legal review register](docs/legal-review.md): items to clear before any public release.

## License

Proprietary. This repository is publicly visible, but no license is granted and all rights are reserved.
