import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/fixture.dart';

/// The constraints schema v2 adds (backlog F2), on top of the fixture.
Matcher get rejected => throwsA(isA<SqliteException>());

const _ts = "'2026-01-01T09:00:00.000Z'";

/// A well-formed SHA-256, as SQL text.
const _sha =
    "'abababababababababababababababababababababababababababababababab'";

String _uuid(int n) =>
    "'00000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}'";

/// A review event [n] of the fixture's MCQ, in exercise [exercise].
String _event(int n, {String exercise = 'NULL', String payload = 'NULL'}) =>
    'INSERT INTO review_events (id, knowledge_item_id, question_template_id, '
    'reviewed_at, rating, scheduler_config_version, state_after, step_after, '
    'stability_after, difficulty_after, due_after, exercise_id, '
    "answer_payload) VALUES (${_uuid(n)}, 'ki_chablis_grape', "
    "'qt_ppg_fwd_mcq', $_ts, 3, 1, 1, 1, 2.3, 5.0, "
    "'2026-01-01T09:10:00.000Z', $exercise, $payload)";

/// A map layer [id] with the given columns, the others valid.
String _layer(
  String id, {
  String sha = _sha,
  String zoom = '4, 10',
  String parent = 'NULL',
}) =>
    'INSERT INTO map_layers VALUES '
    "('$id', 'A layer', 'area', 'assets/geography/$id.topo.json', $sha, "
    '$zoom, $parent)';

/// Chablis's geometry in [layer], with the given box and label point.
String _geometry(
  String layer, {
  String node = 'n_geo_chablis',
  String box = '3.6, 47.7, 4.0, 47.9',
  String label = '3.8, 47.8',
}) =>
    "INSERT INTO node_geometries VALUES ('$node', '$layer', '$node', "
    '$box, $label)';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = openTestDatabase();
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
  });
  tearDown(() => db.close());

  Future<void> curriculum(String statement) =>
      db.writeCurriculum(() => db.customStatement(statement));

  test('a new database is at the current schema version', () async {
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });

  test('a pack has neither an examining body nor a level (PK-2)', () async {
    await curriculum(
      'INSERT INTO certifications (id, display_name, kind, description, '
      'includes_certification_id, is_selectable) VALUES '
      "('BURGUNDY_PACK', 'Burgundy in depth', 'pack', 'A test pack.', "
      "'WSET_L3', 1)",
    );
    final pack = await (db.select(
      db.certifications,
    )..where((c) => c.id.equals('BURGUNDY_PACK'))).getSingle();
    expect((pack.kind, pack.organization, pack.level), ('pack', null, null));
    final wset = await (db.select(
      db.certifications,
    )..where((c) => c.id.equals('WSET_L3'))).getSingle();
    expect(wset.kind, 'certification', reason: 'the default kind');

    for (final row in [
      "('PACK_WITH_BODY', 'X', 'pack', 'WSET', NULL)",
      "('PACK_WITH_LEVEL', 'X', 'pack', NULL, 5)",
      "('CERT_WITHOUT_LEVEL', 'X', 'certification', 'CMS', NULL)",
      "('CERT_WITHOUT_BODY', 'X', 'certification', NULL, 5)",
      "('BUNDLE', 'X', 'bundle', NULL, NULL)",
    ]) {
      await expectLater(
        curriculum(
          'INSERT INTO certifications (id, display_name, kind, organization, '
          'level) VALUES $row',
        ),
        rejected,
        reason: row,
      );
    }
  });

  test('a template mode is any format ID, and a variant tells templates of '
      'one format apart (QF-2)', () async {
    String template(String id, String mode, {String variant = "''"}) =>
        'INSERT INTO question_templates (id, relation_type, direction, mode, '
        "prompt_template, variant) VALUES ('$id', 'PERMITS_PRINCIPAL_GRAPE', "
        "'forward', $mode, 'Which grapes does {subject.name} permit?', "
        '$variant)';

    // A format the schema has never heard of needs no migration.
    await curriculum(template('qt_ppg_fwd_mr', "'multiple_response'"));
    // The fixture's MCQ has the variant ''; another variant may join it.
    await curriculum(
      template('qt_ppg_fwd_mcq_hard', "'mcq'", variant: "'hard'"),
    );
    await expectLater(
      curriculum(template('qt_ppg_fwd_mcq_again', "'mcq'", variant: "'hard'")),
      rejected,
      reason: 'the same format, variant and locale twice',
    );
    for (final mode in ["'Multiple choice'", "''", "'1mcq'"]) {
      await expectLater(
        curriculum(template('qt_ppg_bad', mode)),
        rejected,
        reason: mode,
      );
    }
    await expectLater(
      curriculum(template('qt_ppg_bad', "'mcq'", variant: "'Hard'")),
      rejected,
    );

    Future<void> parameters(String value) => curriculum(
      'UPDATE question_templates SET parameters = $value '
      "WHERE id = 'qt_ppg_fwd_mr'",
    );
    await parameters('\'{"criterion": "latitude"}\'');
    await expectLater(
      parameters("'[1, 2]'"),
      rejected,
      reason: 'not an object',
    );
    await expectLater(parameters("'not json'"), rejected);
  });

  test('a relation type is symmetric only when marked', () async {
    final types = await db.select(db.relationTypes).get();
    expect(types.map((t) => t.isSymmetric), everyElement(false));
    await curriculum(
      'INSERT INTO relation_types (id, label, reverse_label, cardinality, '
      "default_domain_id, is_symmetric) VALUES ('BORDERS', 'borders', "
      "'borders', 'many', 'geography', 1)",
    );
    await expectLater(
      curriculum(
        "UPDATE relation_types SET is_symmetric = 2 WHERE id = 'BORDERS'",
      ),
      rejected,
    );
  });

  test('the events of one exercise share its ID and keep the answer '
      '(QF-3)', () async {
    final exercise = _uuid(100);
    await runSql(db, [
      _event(1, exercise: exercise, payload: '\'{"order": [2, 1, 3]}\''),
      _event(2, exercise: exercise, payload: '\'{"order": [2, 1, 3]}\''),
    ]);
    final events = await (db.select(
      db.reviewEvents,
    )..where((e) => e.exerciseId.equals(exercise.replaceAll("'", '')))).get();
    expect(events, hasLength(2));
    expect(events.first.answerPayload, '{"order": [2, 1, 3]}');

    await expectLater(
      db.customStatement(_event(3, exercise: "'exercise-1'")),
      rejected,
      reason: 'an exercise ID is a UUID',
    );
    await expectLater(
      db.customStatement(_event(4, payload: "'{order: 2}'")),
      rejected,
      reason: 'the payload is JSON',
    );
    await expectLater(
      db.customStatement(
        "UPDATE review_events SET answer_payload = '{}' "
        'WHERE id = ${_uuid(1)}',
      ),
      rejected,
      reason: 'the log stays append-only',
    );
  });

  test('a presentation may show more than four options', () async {
    await db.customStatement(_event(5));
    for (final (position, node) in [
      (1, 'n_grape_chardonnay'),
      (5, 'n_grape_pinot_noir'),
    ]) {
      await db.customStatement(
        'INSERT INTO review_event_options VALUES (${_uuid(5)}, $position, '
        "'$node')",
      );
    }
    await expectLater(
      db.customStatement(
        'INSERT INTO review_event_options VALUES (${_uuid(5)}, 0, '
        "'n_grape_nebbiolo')",
      ),
      rejected,
    );
  });

  test('a completeness assertion names its set, its dates and its '
      'source (QF-8)', () async {
    String assertion({
      String direction = "'forward'",
      String until = 'NULL',
      String source = "'src_inao_chablis'",
    }) =>
        'INSERT INTO relation_set_assertions VALUES '
        "('n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', $direction, 'grape', "
        "'1938-01-13', $until, $source, 'Article II')";

    await curriculum(assertion());
    await expectLater(curriculum(assertion(direction: "'sideways'")), rejected);
    await expectLater(
      curriculum(assertion(direction: "'reverse'", until: "'1930-01-01'")),
      rejected,
      reason: 'ends before it starts',
    );
    await expectLater(
      curriculum(assertion(direction: "'reverse'", source: "'src_none'")),
      rejected,
      reason: 'an unknown source',
    );
  });

  test('a map layer is well formed', () async {
    await curriculum(_layer('ml_regions'));
    await curriculum(_layer('ml_appellations', parent: "'ml_regions'"));
    for (final (reason, statement) in [
      ('an ID without ml_', _layer('regions_x')),
      ('a short hash', _layer('ml_x', sha: "'abc'")),
      ('an upper-case hash', _layer('ml_x', sha: "'${'AB' * 32}'")),
      ('an empty zoom range', _layer('ml_x', zoom: '10, 10')),
      ('a negative zoom', _layer('ml_x', zoom: '-1, 4')),
      ('its own parent', _layer('ml_x', parent: "'ml_x'")),
      ('an unknown parent', _layer('ml_x', parent: "'ml_none'")),
      (
        'an asset used twice',
        _layer('ml_regions_copy')
            .replaceFirst('ml_regions_copy.topo.json', 'ml_regions.topo.json'),
      ),
    ]) {
      await expectLater(curriculum(statement), rejected, reason: reason);
    }
  });

  test("a layer's citations are ordered for its attribution", () async {
    await curriculum(_layer('ml_regions'));
    await curriculum(
      "INSERT INTO map_layer_citations VALUES ('ml_regions', "
      "'src_inao_chablis', 1)",
    );
    await expectLater(
      curriculum(
        "INSERT INTO map_layer_citations VALUES ('ml_regions', "
        "'src_other', 2)",
      ),
      rejected,
      reason: 'an unknown source',
    );
    await curriculum(
      'INSERT INTO source_citations (id, kind, title, publisher, '
      "accessed_on) VALUES ('src_ign', 'dataset', 'Boundaries', 'IGN', "
      "'2026-09-25')",
    );
    for (final position in ['0', '1']) {
      await expectLater(
        curriculum(
          "INSERT INTO map_layer_citations VALUES ('ml_regions', 'src_ign', "
          '$position)',
        ),
        rejected,
        reason: 'position $position',
      );
    }
  });

  test("a node's geometry has a box around its label point", () async {
    await curriculum(_layer('ml_appellations'));
    await curriculum(_geometry('ml_appellations'));
    await curriculum(_layer('ml_other'));
    for (final (reason, statement) in [
      ('a label outside the box', _geometry('ml_other', label: '4.5, 47.8')),
      ('a box inside out', _geometry('ml_other', box: '4.0, 47.7, 3.6, 47.9')),
      (
        'a longitude past 180',
        _geometry('ml_other', box: '3.6, 47.7, 190, 47.9'),
      ),
      ('an unknown node', _geometry('ml_other', node: 'n_geo_nowhere')),
      (
        'a feature key used twice in one layer',
        _geometry(
          'ml_appellations',
          node: 'n_geo_gevrey',
        ).replaceFirst("'n_geo_gevrey', 3.6", "'n_geo_chablis', 3.6"),
      ),
    ]) {
      await expectLater(curriculum(statement), rejected, reason: reason);
    }
  });

  test('an exercise pool ranks its items once each, and takes them with '
      'it', () async {
    await curriculum(
      "INSERT INTO exercise_pools VALUES (1, 'qt_ppg_fwd_mcq', "
      "'n_geo_burgundy', 'Order these appellations from north to south.')",
    );
    await curriculum(
      "INSERT INTO exercise_pool_items VALUES (1, 'ki_chablis_grape', 1)",
    );
    await expectLater(
      curriculum(
        "INSERT INTO exercise_pool_items VALUES (1, 'ki_chablis_soil', 1)",
      ),
      rejected,
      reason: 'a rank taken',
    );
    await expectLater(
      curriculum(
        "INSERT INTO exercise_pool_items VALUES (1, 'ki_chablis_soil', 0)",
      ),
      rejected,
      reason: 'ranks start at 1',
    );
    await curriculum('DELETE FROM exercise_pools WHERE id = 1');
    expect(await db.select(db.exercisePoolItems).get(), isEmpty);
  });
}
