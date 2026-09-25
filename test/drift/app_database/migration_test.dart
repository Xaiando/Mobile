// dart format width=80
// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';

import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;

/// A v1 database's rows, in v1's column order (audit DL-2): a curriculum,
/// a learner's profile, reviews with the options shown, and a journal.
const _v1Curriculum = [
  "INSERT INTO curriculum_releases VALUES ('0.1.0', 'sha256:v1', '2026-09-24T00:00:00.000Z', '2026-09-24T00:00:00.000Z')",
  "INSERT INTO curriculum_domains VALUES ('geography', 'Geography', 1)",
  "INSERT INTO certifications VALUES ('WSET_L2', 'WSET', 2, 'WSET Level 2', NULL, NULL, 0), ('WSET_L3', 'WSET', 3, 'WSET Level 3', 'WSET_L2', NULL, 1)",
  "INSERT INTO node_types VALUES ('region', 'region'), ('appellation', 'appellation'), ('grape', 'grape variety')",
  "INSERT INTO relation_types VALUES ('LOCATED_IN', 'is located in', 'contains', 'many', 1, 0, 'geography', NULL), ('PERMITS_PRINCIPAL_GRAPE', 'permits the principal grape', 'is a principal grape of', 'many', 0, 0, 'geography', NULL)",
  "INSERT INTO relation_type_signatures VALUES ('LOCATED_IN', 'appellation', 'region'), ('PERMITS_PRINCIPAL_GRAPE', 'appellation', 'grape')",
  "INSERT INTO knowledge_nodes (id, node_type, name, name_norm) VALUES ('n_geo_burgundy', 'region', 'Burgundy', 'burgundy'), ('n_geo_chablis', 'appellation', 'Chablis', 'chablis'), ('n_grape_chardonnay', 'grape', 'Chardonnay', 'chardonnay'), ('n_grape_pinot_noir', 'grape', 'Pinot Noir', 'pinot noir'), ('n_grape_aligote', 'grape', 'Aligoté', 'aligote'), ('n_grape_gamay', 'grape', 'Gamay', 'gamay')",
  "INSERT INTO knowledge_relations VALUES ('n_geo_chablis', 'LOCATED_IN', 'n_geo_burgundy', '1938-01-13', NULL), ('n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', '1938-01-13', NULL)",
  "INSERT INTO knowledge_items (id, subject_id, relation_type, object_id, domain_id, assertion_text, last_verified_at) VALUES ('ki_chablis_grape', 'n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', 'geography', 'Chardonnay is the principal grape of Chablis.', '2026-09-24T00:00:00.000Z')",
  "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L3', 'ki_chablis_grape', 'core', 1, NULL)",
  "INSERT INTO source_citations (id, kind, title, publisher, accessed_on) VALUES ('src_inao_chablis', 'legislation', 'Cahier des charges « Chablis »', 'INAO', '2026-09-24')",
  "INSERT INTO knowledge_item_citations VALUES ('ki_chablis_grape', 'src_inao_chablis', NULL)",
  "INSERT INTO question_templates VALUES ('qt_ppg_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'forward', 'mcq', 'en', 'Which grape is the principal grape of {subject.name}?')",
  "INSERT INTO questions VALUES ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'PERMITS_PRINCIPAL_GRAPE', 'Which grape is the principal grape of Chablis?')",
  "INSERT INTO question_distractors VALUES ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_pinot_noir', 0), ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_aligote', 0), ('ki_chablis_grape', 'qt_ppg_fwd_mcq', 'n_grape_gamay', 1)",
];

const _v1UserData = [
  "INSERT INTO user_profiles VALUES (1, 'WSET_L3', 15, 5, '2026-09-24T08:00:00.000Z', '2026-09-24T08:00:00.000Z')",
  "INSERT INTO scheduler_configs VALUES (1, '[0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]', 0.9, '[60, 600]', '[600]', 36500, 1, '2026-09-24T08:00:00.000Z')",
  "INSERT INTO review_events VALUES ('00000000-0000-4000-8000-000000000001', 'ki_chablis_grape', 'qt_ppg_fwd_mcq', '2026-09-24T09:00:00.000Z', 3, 4200, 7, 'n_grape_chardonnay', 1, 1, 1, 2.3065, 2.1181, '2026-09-24T09:10:00.000Z')",
  "INSERT INTO review_event_options VALUES ('00000000-0000-4000-8000-000000000001', 1, 'n_grape_pinot_noir'), ('00000000-0000-4000-8000-000000000001', 2, 'n_grape_chardonnay'), ('00000000-0000-4000-8000-000000000001', 3, 'n_grape_aligote'), ('00000000-0000-4000-8000-000000000001', 4, 'n_grape_gamay')",
  "INSERT INTO review_states VALUES ('ki_chablis_grape', 1, 1, 2.3065, 2.1181, '2026-09-24T09:10:00.000Z', '2026-09-24T09:00:00.000Z', 1, 0)",
  "INSERT INTO wine_journal_entries (id, tasted_on, producer_name, vintage, rating, created_at, updated_at) VALUES ('00000000-0000-4000-8000-0000000000aa', '2026-09-20', 'Example Producer', 2022, 4, '2026-09-24T08:30:00.000Z', '2026-09-24T08:30:00.000Z')",
  "INSERT INTO wine_journal_entry_nodes VALUES ('00000000-0000-4000-8000-0000000000aa', 'n_geo_chablis')",
];

/// The tables a learner's data lives in, which ingestion never touches.
const _userTables = [
  'user_profiles',
  'scheduler_configs',
  'review_states',
  'review_events',
  'review_event_options',
  'wine_journal_entries',
  'wine_journal_entry_nodes',
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('simple database migrations', () {
    // These simple tests verify all possible schema updates with a simple (no
    // data) migration. This is a quick way to ensure that written database
    // migrations properly alter the schema.
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  group('from 1 to 2 (F2)', () {
    late AppDatabase db;
    late Map<String, List<Map<String, Object?>>> before;

    setUp(() async {
      final schema = await verifier.schemaAt(1);
      final raw = schema.rawDatabase;
      // v1's curriculum tables accept rows only during an ingestion.
      raw.execute(
        "INSERT INTO curriculum_ingestions VALUES (1, '2026-09-24T00:00:00.000Z')",
      );
      _v1Curriculum.forEach(raw.execute);
      raw.execute('DELETE FROM curriculum_ingestions');
      _v1UserData.forEach(raw.execute);
      before = {
        for (final table in _userTables)
          table: [
            for (final row in raw.select('SELECT * FROM $table ORDER BY rowid'))
              Map.of(row),
          ],
      };
      db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 2);
    });
    tearDown(() => db.close());

    Future<List<Map<String, Object?>>> rows(String table) async => [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ];

    test('keeps every user row, with the new columns empty', () async {
      for (final table in _userTables) {
        final after = await rows(table);
        expect(after, hasLength(before[table]!.length), reason: table);
        for (final (i, row) in before[table]!.indexed) {
          for (final MapEntry(:key, :value) in row.entries) {
            expect(after[i][key], value, reason: '$table.$key');
          }
        }
      }
      final event = (await rows('review_events')).single;
      expect(
        (event['exercise_id'], event['answer_payload']),
        (null, null),
        reason: 'a v1 review graded one item',
      );
    });

    test('keeps the curriculum, with the v2 defaults', () async {
      final certifications = await db.select(db.certifications).get();
      expect(certifications.map((c) => (c.id, c.kind, c.level)), [
        ('WSET_L2', 'certification', 2),
        ('WSET_L3', 'certification', 3),
      ]);
      final template = await db.select(db.questionTemplates).getSingle();
      expect(
        (template.mode, template.variant, template.parameters),
        ('mcq', '', null),
      );
      final types = await db.select(db.relationTypes).get();
      expect(types.map((t) => t.isSymmetric), [false, false]);
      expect(await db.select(db.questionDistractors).get(), hasLength(3));
    });

    test('keeps the guards of the tables it rebuilt', () async {
      final rejected = throwsA(isA<SqliteException>());
      const event = "'00000000-0000-4000-8000-000000000001'";
      for (final statement in [
        'UPDATE review_events SET rating = 1',
        'DELETE FROM review_event_options WHERE review_event_id = $event',
        'UPDATE review_event_options SET position = 9 WHERE position = 1',
        "INSERT INTO certifications (id, organization, level, display_name) VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4')",
        "UPDATE question_templates SET prompt_template = 'Changed'",
        "INSERT INTO map_layers VALUES ('ml_x', 'X', 'area', 'x.topo.json', '${'ab' * 32}', 0, 4, NULL)",
      ]) {
        await expectLater(
          db.customStatement(statement),
          rejected,
          reason: statement,
        );
      }
    });

    test('leaves no broken reference and records the version', () async {
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      expect(version.read<int>('user_version'), 2);
    });
  });
}
