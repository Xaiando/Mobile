# History, sommelier beverages and cellar scanner completion

28 September 2026. Working branch `codex/history-beverage-scanner` starts at the green WSET Levels 1–3 PR head `1c2b67f`. Grok's `d8c0570` handoff is already an ancestor; do not merge it again. Keep the separate original checkout's five dirty files and the registered WSET Levels 1–3 scope intact.

## Scope and release boundaries

- Finish a source-grounded, teachable wine-history timeline from early archaeology through modern institutions and production, with comparisons and application questions. Avoid claiming a literal exhaustive record or teaching unsupported dates.
- Finish CMS Certified-level basics and varied practice for beer, spirits, cider, cigars and sake. Wine-label and astringency facts may remain Level 4 where their cited scope supports it; do not map new beverage facts to WSET Levels 1–3 or mark Diploma complete.
- Implement a **local** cellar-label scanner: camera on supported mobile devices, photo import everywhere, on-device text recognition on supported mobile devices, and an honest manual-text fallback on desktop/web. A scan proposes fields; the learner confirms them before saving. No automatic bottle identity, LWIN, prices, critic scores, upload or cloud lookup.
- Preserve the WSET `0.23.0` release as immutable history. Register accepted additions in a new dataset version, keep new factual `verification_status: unverified` pending qualified expert review, and keep WSET Levels 1–3 exact required denominators and completion metadata unchanged.

## Tracked tasks

| ID | Deliverable | Acceptance evidence | Owner | State |
| --- | --- | --- | --- | --- |
| G01 | Reconcile Grok handoff and current branch; repair stale source/question statements and deduplicated WHO citation | Candidate checker, source IDs and exact historical corrections checked | root + researchers | done |
| G02 | Complete wine-history lesson graph and applied question template | 102 cumulative source-cited history facts, 29 timeline periods, ten cases; curriculum lint | history researcher | done |
| G03 | Complete beer, spirits, cider, cigar and sake graph and applied question template | 121 new CMS facts, 22 cases, source/legal qualifiers and curriculum lint | beverage researcher | done |
| G04 | Register G02/G03 in a new dataset release without changing lower WSET scope | 0.24.0 ingestion and coverage pass; WSET Levels 1–3 measurements unchanged | root | done |
| G05 | Add private photo storage, two-photo child table, safe deletion, migration and backup v2 | Photo put/read/delete, EXIF removal, schema migration, v1/v2 import and erase round trips | scanner backend | done |
| G06 | Add camera/import, on-device OCR where supported, a conservative parser and per-field confirmation | Synthetic label corpus and explicit-acceptance/duplicate-warning widget cases pass; platform builds pending | root | active |
| G07 | Show label and glass photos in cellar and linked tasting without blind-session leakage | Detail and completed tasting views, plus the blind-reveal widget test, pass | root | done |
| G08 | Run focused/full regression and release gates | Local gates pass, including 1,054/1,054 full Flutter tests and ten browser stages; hosted Android/iOS/Windows/web gates pending | root + independent critic | active |
| G09 | Push a reviewable PR and update Grok coordination handoff | Clean branch, measured test record and explicit practical limitations | root | pending |

## Validation ledger

- The first local full Flutter run finished with 1,046 passes and five failures: the feature-layer database boundary, three cumulative CMS/Level 4 count assertions, and the new schema table inventory. Each was repaired directly; no assertion was weakened or test skipped. The affected and scanner-focused rerun passed 115/115.
- `flutter analyze --no-pub` found no issues. `dart format --output=none --set-exit-if-changed` passed for changed handwritten Dart. `dart run build_runner build` and `dart run drift_dev make-migrations` completed with schema v5.
- Release 0.24.0 lint passed with zero errors and three existing curator-warning classes; the five-track coverage baseline passed with zero gaps. The candidate checker passed its 57 history, 85 beverage and five synthetic-label checks.
- The release web build and Wasm dry run passed. All 125 registered curriculum includes match the built files byte-for-byte; the pinned SQLite/Drift runtime files are present. The ten-stage 320-pixel Chromium UI smoke passed, including manual label transcription, scroll persistence, explicit vintage/alcohol acceptance, web photo selection, and the saved image in the journal detail. The clean full Flutter rerun passed **1,054/1,054** with zero failures. Hosted Android, iOS and Windows builds remain to be checked on the new PR.

## Scanner contract

Use the existing cellar entry as the learner's wine record. The existing nullable `photo_ref` column is not sufficient for distinct label and glass images; retain it for compatibility and add a child relation. The implementation stores bounded, sanitized JPEG/PNG bytes in a private SQLite child table, instead of Grok's proposed file/OPFS store. This makes deletion cascade atomically and lets backup v2 export the actual bytes. Images are decoded and re-encoded after applying orientation, with EXIF removed before persistence or backup. Keep an opaque key out of the UI. Do not save photo or OCR text to a wine merely because a picker returned it. Save only after the learner confirms the draft. A blind tasting must hide both photos until completion.

The desktop picker may return full-resolution originals even when resize options are requested. The sanitizer therefore preflights imports up to 24 MiB, 24 megapixels and 6000 pixels per side, reduces the longest side to 3000 pixels, and stores at most 8 MiB per photo. A large PNG photo may be stored as JPEG when PNG exceeds the storage cap. Temporary OCR text remains in the editor while its form is scrolled and is discarded when the editor closes.

The parser offers a vintage only for exactly one 1800–2100 year token, with no non-vintage phrase. It offers ABV only for a percentage within 0–30. It leaves producer, cuvée and appellation empty until the learner enters or confirms text. Two years leave vintage blank; a value above 30% is never offered as wine ABV. A possible duplicate is a warning, not an automatic merge. An OCR failure still permits manual entry and photo import.

Mobile OCR uses a platform text-recognition plugin with local processing and is never represented as available on unsupported desktop/web targets. [The text-recognition plugin](https://pub.dev/packages/google_mlkit_text_recognition) supports Android and iOS only; [image_picker](https://pub.dev/packages/image_picker) supports photo selection across the app's platforms but desktop camera capture has no default system UI. Plugin versions, platform minimums and permissions must be verified during implementation, then pinned in `pubspec.lock`.

The Grok [scanner package](cellar-scan-package.md) and [code map](incoming/cellar-code-map.md) are starting evidence, not implemented code. The photo backup must include bytes, not just references; format v1 remains importable. No scanner acceptance is inferred from synthetic parser tests alone.
