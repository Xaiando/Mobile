# Cellar and tasting photos: what the app already does

Read of the Flutter app as it stands. This note maps where a cellar photo and a tasting photo would have to attach. It does not add a schema, a migration, or another client.

Schema version in code is 4 (`AppDatabase.schemaVersion` in `lib/core/database/app_database.dart`). `photo_ref` is already on `wine_journal_entries` in that schema. It is not a column waiting to be added.

## 1. Journal draft does not write `photo_ref`

`lib/core/journal/wine_journal.dart`

`JournalDraft` fields are only:

- `tastedOn` (`YYYY-MM-DD` or null)
- `producerName`, `cuveeName`
- `vintage`, `isNonVintage`
- `appellationText`, `grapesText`
- `abvPercent`
- `rating` (1–5)
- `tastingNotes`

There is no photo field. `JournalDraft.of(WineJournalEntry)` copies those same fields from the row and does not read `entry.photoRef`.

`_columns()` builds a `WineJournalEntriesCompanion` from those fields only. `create` inserts that companion plus `id`, `createdAt`, and `updatedAt`. `update` writes that companion plus `updatedAt`. Because `photoRef` is omitted, Drift leaves it absent: a new row stores NULL, and an edit does not clear a value that was already in the column.

`WineJournal.delete` deletes the journal row. The schema sets a linked tasting’s `wine_journal_entry_id` to NULL (`ON DELETE SET NULL`). Nothing deletes a file, because no photo store is called.

`watch`, `watchAll`, and `entry` select the whole row, so a non-null `photoRef` would be on the `WineJournalEntry` object. No caller in `lib/` outside generated Drift code reads `photoRef`.

**Absent:** any assignment to `photo_ref` / `photoRef` from journal create, update, or the draft.

## 2. Cellar screens show text only

### `lib/features/cellar/cellar_screen.dart`

The list is `journalEntriesProvider`. Each `JournalEntryTile` is a `ListTile`:

- leading: `CircleAvatar` with `Icons.wine_bar` (not an image)
- title: `journalTitle` — producer and cuvée, else appellation, else grapes, else “A wine”
- subtitle: `journalSubtitle` (appellation, NV or vintage, grapes) and, if set, “Tasted {date}”
- trailing: `RatingStars` when `rating` is set

Tap goes to `/cellar/{id}`. The empty state is the wine-bar icon and copy about logging wines. No camera control and no read of `photoRef`.

### `lib/features/cellar/journal_editor.dart`

Controllers and state: producer, cuvée, vintage, appellation, grapes, alcohol, notes, tasting date, non-vintage switch, 1–5 rating, and confirmed knowledge-node links.

`_draft()` passes those into `JournalDraft`. Save calls `WineJournal.create` or `update` with the draft and the visible node ids.

The form widgets are those text fields, the non-vintage switch, the date picker, the star rating, the notes field, and link chips. No image widget, picker, or preview.

### `lib/features/cellar/journal_entry_screen.dart` (detail, not the editor)

Shows subtitle, stars, tasted date, producer, cuvée, appellation, grapes, vintage or “Non-vintage”, alcohol, notes, linked nodes, and tastings of this wine (`wineTastingsProvider`). App-bar actions: start a tasting at `/tasting/new?wine={id}`, edit, delete. No image.

**Absent:** any cellar widget that displays or captures a photo.

## 3. Backup exports table rows, not files

`lib/core/backup/user_data_backup.dart`

- Document `format` is the string `sommelier-user-data`.
- `formatVersion` is `1`.
- `export()` also writes `schema_version` (the open database’s schema version), `curriculum_release`, and `exported_at`.
- `tables`, parents first: `scheduler_configs`, `user_profiles`, `user_settings`, `review_states`, `review_events`, `review_event_options`, `question_flags`, `wine_journal_entries`, `wine_journal_entry_nodes`, `tasting_sessions`, `tasting_descriptors`.

Each table is `SELECT * … ORDER BY rowid`. A non-null `wine_journal_entries.photo_ref` would therefore appear as a JSON string on that row. There is no separate photo table and no file payload.

Import accepts a cell only when it is a `String`, a `num`, or null. An unknown table name or an unknown column is rejected as a newer backup. A future extra table or column would not import into format version 1. Binary image bytes are not a legal cell.

`lib/features/settings/your_data.dart` saves and opens that JSON through `file_picker` (`application/json`, extension `json`). That picker is the backup dialog, not a photo picker.

**Absent:** export of image bytes, a photo directory, or a second format version for files.

## 4. Schema columns

`lib/core/database/schema.drift`

`wine_journal_entries` columns, in order:

| Column | Type | Constraint in this table |
|---|---|---|
| `id` | TEXT PK | UUID shape |
| `tasted_on` | TEXT | null or a date |
| `producer_name` | TEXT | |
| `cuvee_name` | TEXT | |
| `vintage` | INTEGER | null or 1800–2100 |
| `is_non_vintage` | BOOLEAN | 0 or 1, default 0 |
| `appellation_text` | TEXT | |
| `grapes_text` | TEXT | |
| `abv_percent` | REAL | null or (0, 100) |
| `rating` | INTEGER | null or 1–5 |
| `tasting_notes` | TEXT | |
| `photo_ref` | TEXT | none: nullable, no CHECK, no foreign key |
| `created_at` | DATETIME | UTC millisecond text |
| `updated_at` | DATETIME | UTC millisecond text, not before `created_at` |

Table checks: non-vintage cannot also have a vintage; `updated_at >= created_at`. Index on `tasted_on` only.

Generated `WineJournalEntry` (`lib/core/database/app_database.g.dart`) has `final String? photoRef`. `WineJournalEntriesCompanion.photoRef` defaults to `Value.absent()`.

`tasting_sessions` columns:

| Column | Type | Notes |
|---|---|---|
| `id` | TEXT PK | UUID |
| `tasting_grid_id` | TEXT NOT NULL | FK to `tasting_grids` |
| `wine_journal_entry_id` | TEXT | FK to `wine_journal_entries`, `ON DELETE SET NULL` |
| `is_blind` | BOOLEAN NOT NULL | default 1 |
| `started_at` | DATETIME NOT NULL | |
| `completed_at` | DATETIME | null until finished; must be ≥ `started_at` |
| `notes` | TEXT | |

`UNIQUE (id, tasting_grid_id)`. Indexes on `started_at` and `wine_journal_entry_id`.

`tasting_descriptors` stores `(tasting_session_id, attribute_key, value_key)` plus the grid id. No image column.

**Absent on tastings:** any photo column. The only photo-shaped column in user data is the single nullable `wine_journal_entries.photo_ref`. One key cannot name both a label photo and a glass photo. `docs/domain-model.md` §3.7 and §4.2 say the same thing in prose: `photo_ref` is “an opaque key for a future photo store, not a file path,” and “There is no capture UI in V0.1 (D6).”

`docs/architecture/architecture-validation.md` J-4 still says a nullable `photo_path` column. The column that was implemented is `photo_ref`, not `photo_path`.

## 5. Tasting screens link a journal id and show no image

### `lib/features/tasting/new_tasting_screen.dart`

`NewTastingScreen` takes an optional `wineId` (route query `wine` from the cellar entry). The form is: grid radio list, blind switch, and `WinePicker` over `journalEntriesProvider`. `WinePicker` is a dropdown of journal titles and subtitles, or “No wine”. Empty journal copy tells the learner to log a wine in the Cellar.

Start calls `TastingPractice.start(gridId, isBlind:, journalEntryId: _wineId)` and opens `/tasting/{session.id}`.

### `lib/core/tasting/tasting_practice.dart`

`start` inserts `id`, `tastingGridId`, `isBlind`, `wineJournalEntryId`, `startedAt`. No other column.

`linkWine(id, journalEntryId)` updates only `wineJournalEntryId` (null unlinks).

`setNotes` updates only `notes`. Descriptor writes are attribute/value keys. `watchSessions(journalEntryId:)` filters sessions for one journal row; the cellar detail screen uses that.

### `lib/features/tasting/tasting_session_screen.dart`

The last stepper step is “Notes and wine”: a notes field (`setNotes` as the learner types) and either the sentence “The wine is revealed when you finish.” (blind and a wine already chosen) or `WinePicker`, whose change calls `linkWine`.

The finished `_Summary` shows the date, “Blind” if applicable, a `Card`/`ListTile` with `Icons.wine_bar`, `journalTitle`, and `journalSubtitle` when `wineJournalEntryId` resolves, then grid answers and notes. The card’s tap goes to `/cellar/{wine.id}`. It does not read `wine.photoRef`.

**Absent:** an image on the new-tasting form, the session stepper, or the summary. A tasting does not own a photo. The only existing hook from a tasting to a cellar photo is the optional `wine_journal_entry_id`, and the UI never loads that entry’s `photoRef`.

## 6. Decision D6 and the PhotoStore sentence

`docs/architecture-audit.md`

Section 10, Web vs native, row “Files (journal photos, if D6 changes)”:

> `photo_ref` is an opaque key, not a path. A `PhotoStore` interface with a native file implementation and a Web blob implementation (OPFS or IndexedDB).

Section 11, user decisions:

> D6. The schema supports journal photos (`wine_journal_entries.photo_ref`). Camera and photo UI, and label scanning, are deferred.

**Absent in code:** a type or file named `PhotoStore`. Search of `lib/` finds `PhotoStore` nowhere. `photoRef` appears only in generated Drift (`app_database.g.dart`, `app_database.steps.dart`).

## 7. Dependencies and permissions

`pubspec.yaml` dependencies: `flutter`, `clock`, `crypto`, `cupertino_icons`, `drift`, `drift_flutter`, `flutter_riverpod`, `fsrs`, `go_router`, `yaml`, `file_picker` 13.1.0. Dev: `build_runner`, `drift_dev`, `flutter_lints`, `flutter_test`, `integration_test`.

**Absent from `pubspec.yaml` and `pubspec.lock`:** `image_picker`, `camera`, ML Kit (`google_ml_kit`, `google_mlkit_*`), and `mobile_scanner`.

`docs/architecture/architecture-validation.md` lists `image_picker` 1.2.3 as a dry run (“Journal photos (if D6 changes)”). It is not a dependency of this app.

Android manifests under `android/app/src/` declare `INTERNET` on debug and profile only. The main manifest has no `CAMERA`, `READ_MEDIA_IMAGES`, or `READ_EXTERNAL_STORAGE` permission. No iOS `NSCameraUsageDescription` or photo-library usage string was found.

## What is absent, in one place

- No writer sets `wine_journal_entries.photo_ref`.
- No screen reads it. Cellar tiles, the editor, the entry page, and the tasting summary use a wine icon.
- No `PhotoStore`, camera, gallery, or label-scan code.
- No `image_picker`, `camera`, or ML Kit package, and no camera or photo permission string.
- `tasting_sessions` and `tasting_descriptors` have no image column. A tasting photo has no column to attach to.
- The journal has one optional text key, not two (label and glass).
- Backup format version 1 copies SQL rows as JSON. It would copy a `photo_ref` string if one existed. It would not copy image files.
- `file_picker` is used only to save and open that JSON backup.
