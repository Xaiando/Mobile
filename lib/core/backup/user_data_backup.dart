import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../curriculum/curriculum_catalog.dart';
import '../database/app_database.dart';
import '../database/user_data_rewrites.dart';
import '../study/scheduler_config.dart';
import '../time/utc_clock.dart';

/// Why a backup cannot be imported, in words for the learner.
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
  int get tastings => rowsByTable['tasting_sessions'] ?? 0;
  int get flags => rowsByTable['question_flags'] ?? 0;
}

/// The learner's own data as one JSON document (backlog R1): every user
/// table, so they can keep a copy or move to another device. Nothing leaves
/// the device unless the learner saves the file somewhere (legal L-11).
///
/// Flags travel in the file too, so curators hear of problems without
/// telemetry.
class UserDataBackup {
  UserDataBackup(this.db, {Clock? clock}) : _clock = clock ?? const Clock();

  final AppDatabase db;
  final Clock _clock;

  static const format = 'sommelier-user-data';
  static const formatVersion = 1;

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

  /// Every user table's rows, with the versions that wrote them.
  Future<Map<String, Object?>> export() async {
    final release = await CurriculumCatalog(db).installedRelease();
    return {
      'format': format,
      'format_version': formatVersion,
      'schema_version': db.schemaVersion,
      'curriculum_release': release?.version,
      'exported_at': utcNow(_clock).toIso8601String(),
      'tables': {for (final table in tables) table: await _rows(table)},
    };
  }

  /// The export as indented JSON, which a curator can read.
  Future<String> exportJson() async =>
      const JsonEncoder.withIndent('  ').convert(await export());

  Future<List<Map<String, Object?>>> _rows(String table) async => [
    for (final row
        in await db.customSelect('SELECT * FROM "$table" ORDER BY rowid').get())
      row.data,
  ];

  /// Replaces all of the learner's data with the backup in [json]. It runs
  /// in one transaction: if anything is wrong, nothing changes, and a
  /// [BackupException] says why.
  Future<ImportSummary> import(String json) async {
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
    if (version > formatVersion ||
        (schemaVersion is int && schemaVersion > db.schemaVersion)) {
      throw _newer;
    }
    final data = decoded['tables'];
    if (data is! Map<String, Object?>) throw _notABackup;
    if (data.keys.any((table) => !tables.contains(table))) throw _newer;

    final rowsOf = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final rows = data[table] ?? const <Object?>[];
      if (rows is! List<Object?>) throw _notABackup;
      final columns = await _columns(table);
      rowsOf[table] = [
        for (final row in rows)
          if (row is Map<String, Object?> &&
              row.values.every((v) => v is String || v is num || v == null))
            row
          else
            throw _notABackup,
      ];
      if (rowsOf[table]!.any(
        (row) => row.keys.any((c) => !columns.contains(c)),
      )) {
        throw _newer;
      }
    }
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

  /// Deletes all of the learner's data, as on a fresh install: onboarding
  /// starts again.
  Future<void> eraseAll() => _replace(const {});

  Future<Set<String>> _columns(String table) async => {
    for (final row
        in await db.customSelect('PRAGMA table_info("$table")').get())
      row.read<String>('name'),
  };

  Future<void> _replace(Map<String, List<Map<String, Object?>>> rowsOf) async {
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
