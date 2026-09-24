import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  // One test opens a second database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late KnowledgeGraph graph;

  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(db).ensureCurrent(bundledDataset());
    graph = KnowledgeGraph(db, clock: Clock.fixed(DateTime.utc(2026, 10, 1)));
  });
  tearDown(() => db.close());

  List<String> names(List<GraphNode> nodes) => [for (final n in nodes) n.name];

  test('ancestors walk up the containment hierarchy, nearest first', () async {
    expect(names(await graph.ancestors('n_geo_chablis')), [
      'Burgundy',
      'France',
    ]);
    final volnay = await graph.ancestors('n_geo_volnay');
    expect(names(volnay), ['Côte de Beaune', 'Burgundy', 'France']);
    expect([for (final n in volnay) n.depth], [1, 2, 3]);
  });

  test('descendants walk down, nearest first', () async {
    final burgundy = await graph.descendants('n_geo_burgundy');
    expect(names(burgundy), ['Chablis', 'Côte de Beaune', 'Volnay']);
    expect(
      names(await graph.descendants('n_geo_italy')),
      containsAll(['Piedmont', 'Langhe', 'Barolo', 'Chianti Classico']),
    );
  });

  test('siblings share a parent and a node type', () async {
    expect(names(await graph.siblings('n_geo_cornas')), [
      'Condrieu',
      'Crozes-Hermitage',
    ]);
    expect(names(await graph.siblings('n_geo_barolo')), ['Barbaresco']);
  });

  test("a node's relations, with both ends named", () async {
    final chablis = [
      for (final r in await graph.relationsOf('n_geo_chablis')) '$r',
    ];
    expect(
      chablis,
      containsAll([
        'Chablis permits the principal grape Chardonnay',
        'Chablis has soil Kimmeridgian marl',
        'Chablis is located in Burgundy',
      ]),
    );
    final chardonnay = await graph.relationsOf('n_grape_chardonnay');
    expect(
      [for (final r in chardonnay) r.subjectName],
      containsAll(['Chablis', 'Champagne', 'Volnay']),
      reason: 'incoming relations too',
    );
  });

  test('only relations in force on the date are followed (V-2)', () async {
    await db.writeCurriculum(
      () => db.customStatement(
        "UPDATE knowledge_relations SET valid_from = '2027-01-01' "
        "WHERE subject_id = 'n_geo_chablis' AND relation_type = 'LOCATED_IN'",
      ),
    );
    expect(await graph.ancestors('n_geo_chablis'), isEmpty);
    expect(names(await graph.ancestors('n_geo_chablis', on: '2027-06-01')), [
      'Burgundy',
      'France',
    ]);
  });

  test('prerequisites are followed transitively, nearest first', () async {
    expect(await graph.prerequisitesOf('ki_barolo_min_wood_ageing'), [
      ('ki_barolo_min_ageing', 1),
      ('ki_barolo_grape', 2),
      ('ki_barolo_location', 3),
    ]);
  });

  test('dependents are followed transitively, nearest first (A-4)', () async {
    expect(await graph.dependentsOf('ki_barolo_grape'), [
      ('ki_barolo_min_ageing', 1),
      ('ki_barbaresco_min_ageing', 2),
      ('ki_barolo_min_wood_ageing', 2),
    ]);
    expect(await graph.dependentsOf('ki_barolo_min_wood_ageing'), isEmpty);
  });

  test(
    'the closure holds every prerequisite pair at its shortest distance',
    () async {
      final closure = await graph.prerequisiteClosure();
      for (final itemId in [
        'ki_barolo_location',
        'ki_chablis_location',
        'ki_champagne_method',
      ]) {
        expect(
          [
            for (final pair in closure)
              if (pair.prerequisite == itemId) (pair.dependent, pair.depth),
          ]..sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1.compareTo(b.$1)),
          await graph.dependentsOf(itemId),
          reason: itemId,
        );
      }
      expect(
        closure.where((p) => p.dependent == 'ki_barolo_min_wood_ageing'),
        hasLength(3),
      );
    },
  );

  test('current items exclude ended and superseded facts (FS-13)', () async {
    final all = await db.select(db.knowledgeItems).get();
    expect(await graph.currentItems(), hasLength(all.length));
    await db.writeCurriculum(() async {
      await db.customStatement(
        "UPDATE knowledge_relations SET valid_until = '2026-06-01' "
        "WHERE subject_id = 'n_geo_barolo' AND relation_type = 'MIN_AGEING'",
      );
      await db.customStatement(
        "UPDATE knowledge_items SET superseded_by_item_id = 'ki_cornas_grape' "
        "WHERE id = 'ki_crozes_hermitage_grape'",
      );
    });
    final current = [for (final i in await graph.currentItems()) i.id];
    expect(current, hasLength(all.length - 2));
    expect(current, isNot(contains('ki_barolo_min_ageing')));
    expect(current, isNot(contains('ki_crozes_hermitage_grape')));
    expect([
      for (final i in await graph.currentItems(on: '2026-05-31')) i.id,
    ], contains('ki_barolo_min_ageing'));
  });

  group('§S.2 DAG integrity', () {
    test('the bundled prerequisites have no cycle', () async {
      expect(await graph.prerequisiteCycles(), isEmpty);
    });

    test('the recursive query finds a cycle of any length', () async {
      // ki_barolo_location -> grape -> min_ageing -> back to location.
      await db.writeCurriculum(
        () => db.customStatement(
          'INSERT INTO knowledge_item_prerequisites VALUES '
          "('ki_barolo_location', 'ki_barolo_min_ageing')",
        ),
      );
      expect(await graph.prerequisiteCycles(), [
        'ki_barolo_grape',
        'ki_barolo_location',
        'ki_barolo_min_ageing',
      ]);
    });
  });

  group('§S.4 version expiry and staleness', () {
    test('nothing has expired in the bundled release', () async {
      expect(await graph.expiredItems(), isEmpty);
    });

    test('an ended relation or a superseded item is flagged', () async {
      await db.writeCurriculum(() async {
        await db.customStatement(
          "UPDATE knowledge_relations SET valid_until = '2026-06-01' "
          "WHERE subject_id = 'n_geo_barolo' AND relation_type = 'MIN_AGEING'",
        );
        await db.customStatement(
          "UPDATE knowledge_items SET superseded_by_item_id = 'ki_cornas_grape' "
          "WHERE id = 'ki_crozes_hermitage_grape'",
        );
      });
      final expired = await graph.expiredItems();
      expect(
        [for (final e in expired) e.itemId],
        ['ki_barolo_min_ageing', 'ki_crozes_hermitage_grape'],
      );
      expect(expired.first.validUntil, '2026-06-01');
      expect(expired.last.supersededByItemId, 'ki_cornas_grape');
    });

    test('items not re-verified for 24 months are stale (P-1)', () async {
      expect(await graph.staleItems(), isEmpty);
      final items = await db.select(db.knowledgeItems).get();
      final twoYearsLater = KnowledgeGraph(
        db,
        clock: Clock.fixed(DateTime.utc(2028, 10, 1)),
      );
      expect(await twoYearsLater.staleItems(), hasLength(items.length));
    });
  });

  test('works on the test fixture as well as the bundled data', () async {
    final fixtureDb = openTestDatabase();
    addTearDown(fixtureDb.close);
    await seedCurriculum(fixtureDb);
    expect(names(await KnowledgeGraph(fixtureDb).ancestors('n_geo_barolo')), [
      'Piedmont',
      'Italy',
    ]);
  });
}
