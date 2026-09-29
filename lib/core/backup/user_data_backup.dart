import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../curriculum/curriculum_catalog.dart';
import '../database/app_database.dart';
import '../database/user_data_rewrites.dart';
import '../journal/journal_photo_store.dart';
import '../journal/recovered_scan_storage.dart';
import '../study/scheduler_config.dart';
import '../time/utc_clock.dart';

/// Why a backup cannot be imported or exported, in words for the learner.
class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How many rows of each table an import brought in.
class ImportSummary {
  const ImportSummary(this.rowsByTable);

  final Map<String, int> rowsByTable;

  int get reviews => rowsByTable['review_events'] ?? 0;
  int get wines => rowsByTable['wine_journal_entries'] ?? 0;
  int get photos => rowsByTable['wine_journal_photos'] ?? 0;
  int get tastings => rowsByTable['tasting_sessions'] ?? 0;
  int get flags => rowsByTable['question_flags'] ?? 0;
}

/// The learner's own data as one JSON document (backlog R1): every user
/// table, so they can keep a copy or move to another device. This API does
/// not upload the export; the operating system may back up saved app data.
///
/// Flags travel in the file too, so curators hear of problems without
/// telemetry.
class UserDataBackup {
  UserDataBackup(
    this.db, {
    Clock? clock,
    this.maxFileBytes = maxBackupFileBytes,
    this.maxRows = maxBackupRows,
    this.maxPhotoBytes = maxBackupPhotoBytes,
    Future<void> Function()? clearRecoveredScans,
    Future<void> Function()? discardLostPickerData,
  }) : assert(maxFileBytes > 0),
       assert(maxRows > 0),
       assert(maxPhotoBytes > 0),
       _clock = clock ?? const Clock(),
       _clearRecoveredScans = clearRecoveredScans ?? clearRecoveredScanStaging,
       _discardLostPickerData = discardLostPickerData ?? _noOp;

  final AppDatabase db;
  final Clock _clock;
  final Future<void> Function() _clearRecoveredScans;
  final Future<void> Function() _discardLostPickerData;
  final int maxFileBytes;
  final int maxRows;
  final int maxPhotoBytes;

  static const format = 'sommelier-user-data';
  static const formatVersion = 2;

  // The current JSON/file-picker path holds several copies in memory. Both
  // directions use the same ceilings until saving can stream an archive.
  static const maxBackupFileBytes = 64 * 1024 * 1024;
  static const maxBackupRows = 250000;
  static const maxBackupPhotoBytes = 24 * 1024 * 1024;
  static const maxExportPhotoBytes = maxBackupPhotoBytes;
  // Commit this with the database erase so a killed process can finish
  // clearing private picker photos on the next launch.
  static const recoveredScanErasePendingSetting =
      'recovered_scan_erase_pending_v1';

  static Future<void> _noOp() async {}

  static String _sizeLabel(int bytes) => bytes % (1024 * 1024) == 0
      ? '${bytes ~/ (1024 * 1024)} MiB'
      : '$bytes bytes';

  /// Reject a picked file before loading it when the platform knows its
  /// size. The byte stream and [import] repeat this check independently.
  static void checkPickedFileSize(int bytes) {
    if (bytes > maxBackupFileBytes) {
      throw BackupException(
        'This backup exceeds the ${_sizeLabel(maxBackupFileBytes)} file '
        'limit. Nothing was imported.',
      );
    }
  }

  /// Guard the file-picker copy even when a caller did not use [exportJson].
  static void checkSavedFileSize(int bytes) {
    if (bytes > maxBackupFileBytes) {
      throw BackupException(
        'Your data exceeds the ${_sizeLabel(maxBackupFileBytes)} backup file '
        'limit. The app will not leave data out of a backup.',
      );
    }
  }

  static int _base64ByteLength(String encoded) {
    final remainder = encoded.length % 4;
    if (remainder == 1) throw _notABackup;
    final padding = encoded.endsWith('==')
        ? 2
        : encoded.endsWith('=')
        ? 1
        : 0;
    if (padding > 0 && remainder != 0) throw _notABackup;
    return (encoded.length ~/ 4) * 3 +
        (remainder == 2
            ? 1
            : remainder == 3
            ? 2
            : 0) -
        padding;
  }

  /// Every user table, parents first. An import inserts rows in this order
  /// and deletes them in reverse, so every foreign key holds throughout.
  static const tables = [
    'scheduler_configs',
    'user_profiles',
    'user_settings',
    'review_states',
    'review_events',
    'review_event_options',
    'question_flags',
    'wine_journal_entries',
    'wine_journal_photos',
    'wine_journal_entry_nodes',
    'tasting_sessions',
    'tasting_descriptors',
  ];

  /// The study progress a reset clears, children first: the review log and
  /// the memory states projected from it.
  static const progressTables = [
    'review_event_options',
    'review_events',
    'review_states',
  ];

  static const _notABackup = BackupException(
    'This file is not a Sommelier backup.',
  );
  static const _newer = BackupException(
    'This backup comes from a newer version of the app. Update the app, '
    'then import it again.',
  );
  static const _missingCurriculum = BackupException(
    'This backup refers to curriculum content that this version of the app '
    'does not have. Update the app, then import it again.',
  );

  /// Every user table's rows, with the versions that wrote them. An export
  /// above [maxPhotoBytes] or [maxRows] fails before any BLOBs are loaded
  /// rather than silently leaving data out of the backup.
  Future<Map<String, Object?>> export() => db.transaction(() async {
    // Check before reading any rows. The read transaction keeps the sum and
    // the exported rows on the same database snapshot.
    final totalPhotoBytes =
        (await db
                .customSelect(
                  'SELECT COALESCE(SUM(length(photo_bytes)), 0) AS total_bytes '
                  'FROM wine_journal_photos',
                )
                .getSingle())
            .read<int>('total_bytes');
    if (totalPhotoBytes > maxPhotoBytes) {
      throw BackupException(
        'Your journal photos exceed the ${_sizeLabel(maxPhotoBytes)} backup '
        'limit. The app will not leave photos out of a backup. Remove some '
        'journal photos and try again.',
      );
    }
    var totalRows = 0;
    for (final table in tables) {
      totalRows +=
          (await db
                  .customSelect('SELECT COUNT(*) AS row_count FROM "$table"')
                  .getSingle())
              .read<int>('row_count');
      if (totalRows > maxRows) {
        throw BackupException(
          'Your data exceeds the $maxRows-row backup limit. The app will not '
          'leave data out of a backup.',
        );
      }
    }
    final release = await CurriculumCatalog(db).installedRelease();
    return {
      'format': format,
      'format_version': formatVersion,
      'schema_version': db.schemaVersion,
      'curriculum_release': release?.version,
      'exported_at': utcNow(_clock).toIso8601String(),
      'tables': {for (final table in tables) table: await _rows(table)},
    };
  });

  /// The export as unencrypted JSON. It includes personal journal photos and
  /// should be kept private unless the learner chooses to share it.
  Future<String> exportJson() async {
    final json = const JsonEncoder.withIndent('  ').convert(await export());
    if (json.length > maxFileBytes || utf8.encode(json).length > maxFileBytes) {
      throw BackupException(
        'Your data exceeds the ${_sizeLabel(maxFileBytes)} backup file limit. '
        'The app will not leave data out of a backup.',
      );
    }
    return json;
  }

  Future<List<Map<String, Object?>>> _rows(String table) async => [
    for (final row
        in await db.customSelect('SELECT * FROM "$table" ORDER BY rowid').get())
      if (table != 'user_settings' ||
          row.data['name'] != recoveredScanErasePendingSetting)
        if (table == 'wine_journal_photos')
          {
            for (final cell in row.data.entries)
              cell.key: cell.key == 'photo_bytes'
                  ? base64Encode(cell.value! as Uint8List)
                  : cell.value,
          }
        else
          row.data,
  ];

  /// Replaces all of the learner's data with the backup in [json]. It runs
  /// in one transaction: if anything is wrong, nothing changes, and a
  /// [BackupException] says why.
  Future<ImportSummary> import(String json) async {
    if (json.length > maxFileBytes || utf8.encode(json).length > maxFileBytes) {
      throw BackupException(
        'This backup exceeds the ${_sizeLabel(maxFileBytes)} file limit. '
        'Nothing was imported.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw _notABackup;
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw _notABackup;
    }
    final version = decoded['format_version'];
    if (version is! int) throw _notABackup;
    final schemaVersion = decoded['schema_version'];
    if (version < 1 ||
        version > formatVersion ||
        (schemaVersion is int && schemaVersion > db.schemaVersion)) {
      throw _newer;
    }
    final data = decoded['tables'];
    if (data is! Map<String, Object?>) throw _notABackup;
    final expectedTables = {
      for (final table in tables)
        if (version != 1 || table != 'wine_journal_photos') table,
    };
    if (data.keys.any((table) => !expectedTables.contains(table))) {
      throw _newer;
    }

    // Preflight every array and its aggregate size before decoding any photo
    // or starting the destructive transaction. App exports use canonical
    // base64, so its encoded length gives the exact decoded byte count.
    var totalRows = 0;
    var estimatedPhotoBytes = 0;
    for (final table in tables) {
      final rows = data.containsKey(table) ? data[table] : const <Object?>[];
      if (rows is! List<Object?>) throw _notABackup;
      totalRows += rows.length;
      if (totalRows > maxRows) {
        throw BackupException(
          'This backup exceeds the $maxRows-row limit. Nothing was imported.',
        );
      }
      if (table == 'wine_journal_photos') {
        for (final row in rows) {
          if (row is! Map<String, Object?> || row['photo_bytes'] is! String) {
            throw _notABackup;
          }
          final encoded = row['photo_bytes']! as String;
          estimatedPhotoBytes += _base64ByteLength(encoded);
          if (estimatedPhotoBytes > maxPhotoBytes) {
            throw BackupException(
              'This backup has more than ${_sizeLabel(maxPhotoBytes)} of '
              'journal photos. Nothing was imported.',
            );
          }
        }
      }
    }

    final rowsOf = <String, List<Map<String, Object?>>>{};
    var decodedPhotoBytes = 0;
    for (final table in tables) {
      // Only format 1 may omit photos. A present null is never an empty table.
      final rows = data.containsKey(table) ? data[table] : const <Object?>[];
      if (rows is! List<Object?>) throw _notABackup;
      final columns = await _columns(table);
      final parsed = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row is! Map<String, Object?> ||
            !row.values.every((v) => v is String || v is num || v == null)) {
          throw _notABackup;
        }
        final copy = Map<String, Object?>.of(row);
        if (table == 'user_settings' &&
            copy['name'] == recoveredScanErasePendingSetting) {
          // A device-local erase retry must never travel in a backup.
          throw _notABackup;
        }
        if (table == 'wine_journal_photos') {
          final mime = copy['mime_type'];
          final encoded = copy['photo_bytes'];
          if (mime is! String || encoded is! String) throw _notABackup;
          final Uint8List bytes;
          try {
            bytes = base64Decode(encoded);
            // The preflight measures canonical base64. Keep a second guard
            // on the actual decoded bytes for hand-edited backups.
            decodedPhotoBytes += bytes.length;
            if (decodedPhotoBytes > maxPhotoBytes) {
              throw BackupException(
                'This backup has more than ${_sizeLabel(maxPhotoBytes)} of '
                'journal photos. Nothing was imported.',
              );
            }
            JournalPhotoStore.validateStoredPhoto(mime, bytes);
          } on FormatException {
            throw _notABackup;
          } on PhotoStoreException {
            throw _notABackup;
          }
          copy['photo_bytes'] = bytes;
        }
        parsed.add(copy);
      }
      rowsOf[table] = parsed;
      if (rowsOf[table]!.any(
        (row) => row.keys.any((c) => !columns.contains(c)),
      )) {
        throw _newer;
      }
    }
    // Keep this after column validation so unknown columns still report that
    // the backup needs a newer app, even if another table is absent.
    if (expectedTables.any((table) => !data.containsKey(table))) {
      throw _notABackup;
    }
    // Import must not erase a pending device-local cleanup marker. If an
    // earlier Erase All could not remove staged photos, finish that request
    // before the imported settings replace the marker.
    await resumePendingRecoveredScanErase();
    await _replace(rowsOf);
    return ImportSummary({
      for (final table in tables) table: rowsOf[table]!.length,
    });
  }

  /// Clears the study progress: every review and every memory state. The
  /// track, settings, journal, tastings and flags stay.
  Future<void> resetProgress() async {
    await db.rewriteUserData(() async {
      for (final table in progressTables) {
        await db.customStatement('DELETE FROM "$table"');
      }
    }, clock: _clock);
    _notify(progressTables);
  }

  /// Deletes all of the learner's data, including interrupted picker photos,
  /// as on a fresh install: onboarding starts again.
  Future<void> eraseAll() async {
    await _replace(const {}, markRecoveredScanErasePending: true);
    await resumePendingRecoveredScanErase();
  }

  /// Idempotent after a crash or a failed file deletion. Startup calls this
  /// before retrieving lost picker data or opening the journal editor.
  Future<void> resumePendingRecoveredScanErase() async {
    final pending =
        await (db.select(db.userSettings)..where(
              (row) => row.name.equals(recoveredScanErasePendingSetting),
            ))
            .getSingleOrNull();
    if (pending == null) return;
    try {
      // Consuming the native lost result before clearing staging prevents a
      // pre-erase picker result from reappearing after a process restart.
      await _discardLostPickerData();
      await _clearRecoveredScans();
    } catch (_) {
      throw const BackupException(
        'Saved data was erased, but an interrupted photo could not be '
        'removed. Try Erase All again. If the app cannot reopen or the '
        'warning persists, clear this app\'s storage in Android settings '
        'to remove the remaining local files.',
      );
    }
    await (db.delete(
      db.userSettings,
    )..where((row) => row.name.equals(recoveredScanErasePendingSetting))).go();
  }

  Future<Set<String>> _columns(String table) async => {
    for (final row
        in await db.customSelect('PRAGMA table_info("$table")').get())
      row.read<String>('name'),
  };

  Future<void> _replace(
    Map<String, List<Map<String, Object?>>> rowsOf, {
    bool markRecoveredScanErasePending = false,
  }) async {
    try {
      await db.rewriteUserData(() async {
        for (final table in tables.reversed) {
          await db.customStatement('DELETE FROM "$table"');
        }
        for (final table in tables) {
          for (final row in rowsOf[table] ?? const <Map<String, Object?>>[]) {
            final columns = row.keys.toList();
            await db.customStatement(
              'INSERT INTO "$table" (${columns.map((c) => '"$c"').join(', ')}) '
              'VALUES (${List.filled(columns.length, '?').join(', ')})',
              [for (final column in columns) row[column]],
            );
          }
        }
        // Every review needs a scheduler configuration (audit FS-8).
        await ensureSchedulerConfig(db, clock: _clock);
        if (markRecoveredScanErasePending) {
          await db
              .into(db.userSettings)
              .insert(
                UserSettingsCompanion.insert(
                  name: recoveredScanErasePendingSetting,
                  value: '1',
                  updatedAt: utcNow(_clock),
                ),
              );
        }
      }, clock: _clock);
    } on BackupException {
      rethrow;
    } catch (error) {
      // Native and web builds raise different exception types, so the
      // message is what tells a missing curriculum row apart.
      if ('$error'.contains('FOREIGN KEY constraint failed')) {
        throw _missingCurriculum;
      }
      throw BackupException('The backup could not be imported: $error');
    } finally {
      _notify(tables);
    }
  }

  /// Raw statements bypass Drift's change tracking, so screens that follow
  /// these tables are told here.
  void _notify(Iterable<String> changed) =>
      db.notifyUpdates({for (final table in changed) TableUpdate(table)});
}
