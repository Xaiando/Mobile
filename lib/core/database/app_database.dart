import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'storage_durability.dart';

part 'app_database.g.dart';

/// The app's SQLite database, generated from `schema.drift`.
///
/// `schema.drift` is the canonical domain model described in
/// docs/domain-model.md. Curriculum tables are read-only except inside
/// `writeCurriculum` (see curriculum_writes.dart).
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the on-device database: a file on native platforms, and Drift's
  /// WASM backend on the web.
  ///
  /// [onWebStorage] reports how durable the web storage Drift chose is. It is
  /// never called on native platforms.
  factory AppDatabase.open({void Function(StorageDurability)? onWebStorage}) {
    return AppDatabase(
      driftDatabase(
        name: 'sommelier',
        web: DriftWebOptions(
          sqlite3Wasm: Uri.parse('sqlite3.wasm'),
          driftWorker: Uri.parse('drift_worker.js'),
          onResult: (result) => onWebStorage?.call(
            StorageDurability.fromWebImplementation(
              result.chosenImplementation.name,
            ),
          ),
        ),
      ),
    );
  }

  /// Opens the connection, running any migration. Drift connects lazily, so
  /// startup calls this to surface a failure at once.
  Future<void> ensureOpen() => customSelect('SELECT 1').get();

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      // SQLite enforces foreign keys only when asked, per connection.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
