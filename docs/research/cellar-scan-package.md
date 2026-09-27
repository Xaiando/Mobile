# Cellar photos and label scanning

Implementation package. Nothing in this file is installed. No camera plugin, schema migration, or dependency was added. Flutter/Dart validation is pending while Codex may be using the SDK. Synthetic fixtures are not recognition accuracy.

Baseline code: `grok/wine-history-beverages` at `8de2d4e`. The PDF was read in full on 27 September 2026: *Architectural and Strategic Blueprint for a Computer Vision-Driven Wine Cellar Application*, 16 pages, local path `C:\Users\Kaged\Downloads\Wine Scanner App Development Guide.pdf`. Page numbers below are that reading.

## Current app evidence

Code review of `docs/research/incoming/cellar-code-map.md`, read against the worktree, repaired the earlier draft of this package:

- `JournalDraft` writes producer, cuvée, vintage, non-vintage, appellation, grapes, alcohol, a 1–5 rating, and notes. It has no photo field. `create` and `update` omit `photoRef`, so a new row stores null and an edit does not clear a key that was already stored.
- `wine_journal_entries.photo_ref` is one nullable TEXT column. It is unused by cellar screens. One key cannot be both a label photo and a glass photo. Overloading it with a packed string is rejected.
- `TastingSession` has an optional `wineJournalEntryId` (`ON DELETE SET NULL`), blindness, times, and notes. It has no photo column. The tasting screens show the wine's title, not an image.
- `UserDataBackup` format `sommelier-user-data` version 1 exports row values, including `photo_ref` if it were set, and only string, number, or null cells. It does not export image bytes. `file_picker` in this app is that JSON dialog.
- Architecture decision D6 defers camera UI. The PhotoStore sentence is documentation. There is no `PhotoStore` type in `lib/`.
- `pubspec.yaml` has no `image_picker`, `camera`, or ML Kit dependency. The main Android manifest has no camera or photo permission. A validation note that says `photo_path` does not match the column, which is `photo_ref`.

## Requirement dispositions

| PDF page | Requirement in the guide | Disposition | Why, in this app |
| --- | --- | --- | --- |
| 1 | Point a camera at a label and retrieve metadata, prices, and community reviews | Implement the capture and a confirmed prefill only. Reject prices and community reviews | This is a study cellar. Prices and crowd reviews are a different product |
| 1 | Classical OpenCV edge detection is a poor general label finder | Defer as a warning, do not implement OpenCV | The first ship is still photos plus text recognition, which the guide itself says is brittle |
| 2 | On-device neural nets, Core ML or LiteRT, EfficientDet or YOLO | Defer | No model is licensed or bundled. Do not add a detector in this mission |
| 3–4 | CLIP embeddings and a Qdrant index of millions of labels | Reject for this app | Needs a label corpus, a server, and a network. A cellar with no signal cannot use it. OCR is not that index |
| 4 | Cold start for unseen labels | Implement as manual entry | An unknown label stays a draft the learner types |
| 4–5 | LWIN-7, LWIN-11, LWIN-16, LWIN-18 as the identity key | Defer until a real lookup exists | Do not invent an LWIN from OCR text. Store one only after the learner accepts a result from a legitimate source |
| 5–6 | Wine-Searcher, WineLabs, WineAPI.io, critic scores | Reject | Paid services and critic averages are out of scope. Nothing is purchased |
| 6–7 | Vinmonopolet stock and wholesale portals | Reject | Not this user's cellar, and the restricted APIs are someone else's inventory |
| 7 | Offline-first local database | Implement within scope, already true | Drift/SQLite is the store. Keep writes local |
| 7–8 | PowerSync, Supabase, multi-device sync | Reject for this mission | The app's backup is a learner-held JSON file. Sync is a later product decision, not a scanner requirement |
| 8–9 | React Native grids and chart libraries | Reject | The app is Flutter. Do not rewrite it |
| 9–10 | Copy the WSET Systematic Approach to Tasting into the form | Reject | The app already has its own structured and deductive grids. Official wording is not copied |
| 10–11 | Crowd ratings and a recommendation engine | Reject | No community database, and the guide's bias statistics are not curriculum facts |
| 11–15 | Staffing plan and hourly rates | Reject | Not a software requirement |
| 9 | Attach a personal note to a bottle | Already implemented as `tastingNotes` and tasting `notes` | Photos are the missing piece |

## What to build, in dependency order

No step below is done. Each definition of done assumes a later SDK window.

### S1. Photo store, no camera yet

Affected: a new `PhotoStore` behind the existing opaque-key idea. Not `lib/` until authorized.

Proposed interface:

```dart
abstract class PhotoStore {
  /// Copies bytes into app-private storage and returns an opaque key.
  /// Throws [PhotoStoreException] if the decoded image is over 8 MB
  /// or is not JPEG or PNG.
  Future<String> put(Uint8List bytes, {required PhotoKind kind});

  Future<Uint8List?> read(String key);
  Future<void> delete(String key);
}

enum PhotoKind { label, glass, other }
```

Rules: the key is not a path and is not shown as one. EXIF GPS is stripped before `put`. Orientation is applied so the stored JPEG is upright. A missing key renders as "photo unavailable", not a crash. Deleting a wine deletes its keys. A weekly or launch sweep deletes keys that no row references. Backup format becomes version 2: the JSON plus a map of key to base64, or a zip the import unpacks. Version 1 backups still import, with no photos. Web uses the same interface over IndexedDB or OPFS, as D6 already allows.

Failure cases: corrupt bytes, oversize image, storage full, key present in JSON but absent on disk, two devices restoring the same backup (last restore wins on that device; there is no server merge).

Done when: a fixture round-trips put/read/delete; an orphan key is removed; a version-1 backup still imports; GPS EXIF does not survive `put`.

### S2. Show photos on the cellar entry and the linked tasting

The existing column cannot hold two photos. The specification, not a migration, is a child table `wine_journal_photos` with `entry_id`, opaque `photo_key`, and `kind` (`label` or `glass`). That table is not created in this mission. Until it exists, the UI must not pretend the single `photo_ref` is a pair of pictures. An edit of the wine must keep omitting `photoRef` so it does not wipe a key, which is already how `update` behaves.

The tasting screen reads the linked wine's photos and does not gain its own column in the first slice. Blind tastings hide the label photo until the tasting is completed. The glass photo stays hidden while blind as well, unless a later decision says a glass close-up cannot identify the bottle. Default is to hide both.

Done when: a widget fixture with a fake `PhotoStore` shows, replaces, and removes a photo; a blind session does not show the label photo before completion.

### S3. Capture and import

Camera permission denied: stay on the form and explain that a photo can be chosen from the library or skipped. Library permission denied: same. No camera on the device: library and skip only. Android and iOS permission strings are required before a store build. Windows desktop, if shipped, may have no camera; import from a file still works. The web cannot promise a camera on every browser; file input is the fallback.

Done when: each denial path leaves the draft unsaved and unchanged.

### S4. Label text is a proposal, not an identity

Separate the steps. Capture writes a photo key. Text recognition reads that image on device. A parser proposes fields. The learner accepts or edits each field. Only then does `JournalDraft` save.

Offline: use a platform text-recognition API that runs on device after any model the operating system already has. If the chosen plugin must download a model on first use, the screen says so before the first scan and works with manual entry until the download finishes. Do not ship a private model in this mission.

OCR failure: empty proposals, photo still kept, manual form still there. Low confidence: show the raw text and leave the fields blank rather than guessing a producer.

Parser rules, all overridable:

- A four-digit token from 1800 to 2100 may be offered as vintage. If two such tokens exist, offer neither vintage and show both in the raw text.
- The words "NV", "non-vintage", or "sans année" offer the non-vintage flag and no vintage.
- A percent token may be offered as alcohol only if it is between 0 and 30. A 2020 next to a percent is not alcohol.
- Producer, cuvée, and appellation are not inferred by splitting the raw text on commas. Those fields start empty unless the learner copies a line.
- Do not build an LWIN, a barcode identity, or a critic score from the text.

Duplicate scan: if producer, cuvée, and vintage match an existing row after confirmation, ask whether this is another bottle of that wine or a new card. Do not merge silently. Two bottles of the same wine may share a card or not; the learner chooses. The default offered is "another bottle", and the card then needs a count that this schema does not have yet. Until a count exists, the safe default is a new card, with the match shown as a warning. That limitation is explicit.

Done when: the synthetic corpus below produces the expected proposals, including the failures, and no test treats those strings as real bottles.

### S5. Optional lookup, still confirmed

Only after S4. A lookup client is an interface:

```dart
abstract class LabelLookup {
  Future<List<LabelCandidate>> search(LabelProposal proposal);
}

class LabelCandidate {
  final String displayName;
  final String? lwin;
  final String sourceName;
}
```

A null client means lookup is off. A candidate is stored only if the learner taps it. The photo and the typed fields remain the record if they disagree; the chosen candidate is a separate accepted identity, not a silent overwrite.

Done when: lookup off changes nothing; lookup on with an empty result leaves the draft; a chosen candidate is visible as "accepted from {source}" and can be cleared.

## Synthetic corpus

File: `docs/research/cellar-scan/synthetic_labels.json`. Every row is invented text. None is a real producer. Expected proposals are part of the fixture. They measure the parser, not a camera.

## Acceptance scenarios

1. Learner saves a wine with no photo. Export version 2 still imports on a fresh database.
2. Learner adds a label photo and a glass photo, kills the app, and both return.
3. Learner deletes the wine. Both files are gone and no orphan key remains.
4. Learner starts a blind tasting of that wine. The label photo is hidden until completion.
5. Learner denies the camera. The form is intact.
6. Synthetic label "CHATEAU EXAMPLE 2016 2018 13.5%" proposes no vintage, proposes alcohol 13.5, and does not invent a producer.
7. Synthetic label "CUVEE EXAMPLE NV" proposes non-vintage and no year.
8. The same confirmed text scanned twice warns of a possible duplicate and does not merge by itself.

## Privacy and licensing

Photos are personal data. They stay on device unless the learner exports a backup. Do not upload them for a recommendation engine. Strip location metadata. A future lookup vendor needs its own licence review; none is chosen here. ML Kit or Apple Vision, if used later, must be checked for their current offline terms before the dependency is added. That check is not done.

## Pending

SDK tests of S1–S5: not run, because the code is not written and a Dart run is withheld while Codex may hold the SDK. Expert review: pending. This package does not implement a feature.
