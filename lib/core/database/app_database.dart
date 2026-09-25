import 'package:drift/drift.dart';

import 'app_database.steps.dart';

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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Each step builds on the schema snapshot of its version in
    // drift_schemas/, never on the current schema (audit DL-2).
    onUpgrade: stepByStep(from1To2: _from1To2, from2To3: _from2To3),
    beforeOpen: (details) async {
      // SQLite enforces foreign keys only when asked, per connection. They
      // stay off while a migration runs, so tables can be rebuilt.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Schema v2 (backlog F2): composite exercises, completeness assertions,
/// symmetric relations, study packs and map geometry.
Future<void> _from1To2(Migrator m, Schema2 schema) async {
  // SQLite cannot change a column's constraints in place, so these tables
  // are rebuilt with their rows. Drift re-creates their triggers, so the
  // curriculum and review-log guards survive.
  await m.alterTable(
    TableMigration(
      schema.certifications,
      newColumns: [
        schema.certifications.kind,
        schema.certifications.description,
      ],
    ),
  );
  await m.alterTable(
    TableMigration(
      schema.questionTemplates,
      newColumns: [
        schema.questionTemplates.variant,
        schema.questionTemplates.parameters,
      ],
    ),
  );
  await m.alterTable(TableMigration(schema.reviewEventOptions));

  await m.addColumn(schema.relationTypes, schema.relationTypes.isSymmetric);
  await m.addColumn(schema.reviewEvents, schema.reviewEvents.exerciseId);
  await m.addColumn(schema.reviewEvents, schema.reviewEvents.answerPayload);
  await m.create(schema.reviewEventsByExercise);

  for (final entity in <DatabaseSchemaEntity>[
    schema.relationSetAssertions,
    schema.mapLayers,
    schema.mapLayerCitations,
    schema.nodeGeometries,
    schema.exercisePools,
    schema.exercisePoolsByTemplate,
    schema.exercisePoolItems,
    schema.exercisePoolItemsByItem,
    schema.relationSetAssertionsReadOnlyInsert,
    schema.relationSetAssertionsReadOnlyUpdate,
    schema.relationSetAssertionsReadOnlyDelete,
    schema.mapLayersReadOnlyInsert,
    schema.mapLayersReadOnlyUpdate,
    schema.mapLayersReadOnlyDelete,
    schema.mapLayerCitationsReadOnlyInsert,
    schema.mapLayerCitationsReadOnlyUpdate,
    schema.mapLayerCitationsReadOnlyDelete,
    schema.nodeGeometriesReadOnlyInsert,
    schema.nodeGeometriesReadOnlyUpdate,
    schema.nodeGeometriesReadOnlyDelete,
    schema.exercisePoolsReadOnlyInsert,
    schema.exercisePoolsReadOnlyUpdate,
    schema.exercisePoolsReadOnlyDelete,
    schema.exercisePoolItemsReadOnlyInsert,
    schema.exercisePoolItemsReadOnlyUpdate,
    schema.exercisePoolItemsReadOnlyDelete,
  ]) {
    await m.create(entity);
  }
}

/// Schema v3 (backlog R1): the learner's settings and question flags.
Future<void> _from2To3(Migrator m, Schema3 schema) async {
  await m.createTable(schema.userSettings);
  await m.createTable(schema.questionFlags);
  await m.create(schema.questionFlagsByItem);
}
