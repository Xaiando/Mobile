import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The app's SQLite database, generated from `schema.drift`.
///
/// `schema.drift` is the canonical domain model described in
/// docs/domain-model.md. Curriculum tables are read-only except inside
/// `writeCurriculum` (see curriculum_writes.dart).
///
/// This library needs no Flutter, so the curriculum tools run it with
/// `dart run`. The app opens its on-device file with `openAppDatabase`
/// (database_connection.dart).
@DriftDatabase(include: {'schema.drift'})
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

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
