import 'package:crypto/crypto.dart';

import 'dart:io';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _retiredSaliceIds = <String>{
  'ki_reg_isi_salice_context',
  'ki_reg_isi_salice_styles',
};
const _saliceSuccessors = <String, String>{
  'ki_reg_isi_salice_context': 'ki_reg_isi_salice_context_2026',
  'ki_reg_isi_salice_styles': 'ki_reg_isi_salice_styles_2026',
};

Map<String, dynamic> _frozen073Release() {
  final bytes = File(
    'test/fixtures/curriculum/diploma_release_0_24_73_complete_frozen.json.gz',
  ).readAsBytesSync();
  expect(
    sha256.convert(bytes).toString(),
    '15a944ed92394c94d4ec67b9fb83388bf3b8718e15e3c3da007af5666e211cdf',
  );
  final frozen =
      jsonDecode(utf8.decode(gzip.decode(bytes))) as Map<String, dynamic>;
  expect(frozen['dataset_version'], '0.24.73');
  return frozen;
}

void main() {
  late Map<String, dynamic> historical;
  late Set<String> historicalIds;
  late Set<String> activeIds;
  setUpAll(() {
    // matcher0.12.20 expects a live test zone, including for hash checks.
    historical = _frozen073Release();
    historicalIds = {
      for (final row in (historical['knowledge_items'] as List))
        (row as Map<String, dynamic>)['id'] as String,
    };
    expect(historicalIds, hasLength(4957));
    activeIds = {
      ...historicalIds.difference(_retiredSaliceIds),
      ..._saliceSuccessors.values,
    };
  });

  // One test opens a second database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late KnowledgeGraph graph;
  late DateTime publishedAt;

  setUp(() async {
    db = openTestDatabase();
    final dataset = bundledDataset();
    publishedAt = dataset.publishedAt.toUtc();
    final releaseClock = Clock.fixed(publishedAt);
    await CurriculumIngester(db, clock: releaseClock).ensureCurrent(dataset);
    graph = KnowledgeGraph(db, clock: releaseClock);
  });
  tearDown(() => db.close());

  List<String> names(List<GraphNode> nodes) => [for (final n in nodes) n.name];

  test('ancestors walk up the containment hierarchy, nearest first', () async {
    expect(names(await graph.ancestors('n_geo_chablis')), [
      'Burgundy',
      'Chablis wine area',
      'France',
      'World',
    ]);
    final volnay = await graph.ancestors('n_geo_volnay');
    expect(
      names(volnay),
      containsAll(['Côte de Beaune', 'Burgundy', 'France']),
    );
    expect(volnay.first.name, 'Côte de Beaune');
    expect(volnay.last.name, 'World');
    expect(
      volnay.map((node) => node.depth).toList(),
      orderedEquals(volnay.map((node) => node.depth).toList()..sort()),
    );
    expect(volnay.singleWhere((node) => node.name == 'Burgundy').depth, 2);
    expect(volnay.singleWhere((node) => node.name == 'France').depth, 3);
    expect(volnay.last.depth, 4);
  });

  test('descendants walk down, nearest first', () async {
    final burgundy = await graph.descendants('n_geo_burgundy');
    expect(
      names(burgundy),
      containsAll(['Chablis', 'Côte de Beaune', 'Volnay']),
    );
    expect(burgundy.map((node) => node.id).toSet(), hasLength(burgundy.length));
    expect(
      burgundy.map((node) => node.depth).toList(),
      orderedEquals(burgundy.map((node) => node.depth).toList()..sort()),
    );
    expect(
      names(await graph.descendants('n_geo_italy')),
      containsAll(['Piedmont', 'Langhe', 'Barolo', 'Chianti Classico']),
    );
  });

  test('siblings share a parent and a node type', () async {
    expect(names(await graph.siblings('n_geo_cornas')), [
      'Château-Grillet',
      'Condrieu',
      'Crozes-Hermitage',
      'Côte-Rôtie',
      'Hermitage',
      'Saint-Joseph',
      'Saint-Péray',
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
      'Chablis wine area',
      'France',
      'World',
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
    expect(all.map((item) => item.id).toSet(), {
      ...historicalIds,
      ..._saliceSuccessors.values,
    });
    final before = (await graph.currentItems()).map((item) => item.id).toSet();
    expect(before, activeIds);
    expect(before, hasLength(all.length - _retiredSaliceIds.length));
    expect(before.intersection(_retiredSaliceIds), isEmpty);
    expect(before, containsAll(_saliceSuccessors.values));
    // Supersession applies independently of the successor's future validity.
    const previouslyFutureLawIds = {
      'ki_d3law_jura_cellar_calendar',
      'ki_d3law_jura_veil_duration',
      'ki_d3law_jura_consumer_release',
      'ki_d3law_jura_clavelin_reserved',
      'ki_d3law_tokaj_applicability',
      'ki_d3law_tokaj_aszu_sugar',
      'ki_d3law_tokaj_optional_puttonyos',
      'ki_d3law_tokaj_consumer_release',
      'ki_d3law_china_standard_status',
      'ki_d3law_china_gi_requirements',
      'ki_d3law_china_special_mark',
      'ki_d3law_china_claim_scope',
      'ki_d3law_case_jura_release_inventory_action',
      'ki_d3law_case_jura_release_inventory_reason',
      'ki_d3law_case_jura_release_inventory_tradeoff',
      'ki_d3law_case_jura_release_inventory_limitation',
      'ki_d3law_case_tokaj_label_release_action',
      'ki_d3law_case_tokaj_label_release_reason',
      'ki_d3law_case_tokaj_label_release_tradeoff',
      'ki_d3law_case_tokaj_label_release_limitation',
      'ki_d3law_case_china_gi_dossier_action',
      'ki_d3law_case_china_gi_dossier_reason',
      'ki_d3law_case_china_gi_dossier_tradeoff',
      'ki_d3law_case_china_gi_dossier_limitation',
    };
    final historicalLawItems = (historical['knowledge_items'] as List)
        .cast<Map<String, dynamic>>()
        .where((item) => (item['id'] as String).startsWith('ki_d3law_'));
    expect(
      historicalLawItems.map((item) => item['id']).toSet(),
      previouslyFutureLawIds,
    );
    final historicalRelations = (historical['knowledge_relations'] as List)
        .cast<Map<String, dynamic>>();
    for (final item in historicalLawItems) {
      final relation = historicalRelations.singleWhere(
        (relation) =>
            relation['subject_id'] == item['subject_id'] &&
            relation['relation_type'] == item['relation_type'] &&
            relation['object_id'] == item['object_id'],
      );
      expect(relation['valid_from'], '2026-10-03');
    }
    expect(
      (await graph.currentItems(on: '2026-10-02'))
          .map((item) => item.id)
          .toSet(),
      historicalIds.difference({
        ..._retiredSaliceIds,
        ...previouslyFutureLawIds,
      }),
    );
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
    expect(
      current.toSet(),
      activeIds.difference({
        'ki_barolo_min_ageing',
        'ki_crozes_hermitage_grape',
      }),
    );
    expect(current, hasLength(activeIds.length - 2));
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
    test(
      'only retained Salice history is expired in the bundled release',
      () async {
        final expired = await graph.expiredItems();
        expect(expired.map((item) => item.itemId).toSet(), _retiredSaliceIds);
        for (final item in expired) {
          expect(item.validUntil, '2026-10-03');
          expect(item.supersededByItemId, _saliceSuccessors[item.itemId]);
        }
      },
    );

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
        [
          'ki_barolo_min_ageing',
          'ki_crozes_hermitage_grape',
          ...(_retiredSaliceIds.toList()..sort()),
        ],
      );
      expect(
        expired
            .singleWhere((item) => item.itemId == 'ki_barolo_min_ageing')
            .validUntil,
        '2026-06-01',
      );
      expect(
        expired
            .singleWhere((item) => item.itemId == 'ki_crozes_hermitage_grape')
            .supersededByItemId,
        'ki_cornas_grape',
      );
      for (final item in expired.where(
        (item) => _retiredSaliceIds.contains(item.itemId),
      )) {
        expect(item.validUntil, '2026-10-03');
        expect(item.supersededByItemId, _saliceSuccessors[item.itemId]);
      }
    });

    test('items not re-verified for 24 months are stale (P-1)', () async {
      expect(await graph.staleItems(), isEmpty);
      final items = await db.select(db.knowledgeItems).get();
      // The immutable prior publication distinguishes later curation instants.
      // A new release date must not erase that boundary or change item dates.
      final historicalPublishedAt = DateTime.parse(
        historical['published_at'] as String,
      ).toUtc();
      DateTime twoYearsAfter(DateTime at) => DateTime.utc(
        at.year + 2,
        at.month,
        at.day,
        at.hour,
        at.minute,
        at.second,
        at.millisecond,
        at.microsecond,
      );
      final twoYearsLater = KnowledgeGraph(
        db,
        clock: Clock.fixed(twoYearsAfter(historicalPublishedAt)),
      );
      const laterCuratedIds = {
        'ki_reg_isi_salice_context_2026',
        'ki_reg_isi_salice_styles_2026',
        'ki_wset_origin_stellenbosch_merlot',
      };
      expect(
        items
            .where((item) => item.lastVerifiedAt.isAfter(historicalPublishedAt))
            .map((item) => item.id)
            .toSet(),
        laterCuratedIds,
      );
      expect(
        {
          for (final item in items)
            if (laterCuratedIds.contains(item.id))
              item.id: item.lastVerifiedAt.toUtc(),
        },
        {
          'ki_reg_isi_salice_context_2026': DateTime.utc(
            2026,
            10,
            3,
            15,
            26,
            2,
            473,
          ),
          'ki_reg_isi_salice_styles_2026': DateTime.utc(
            2026,
            10,
            3,
            15,
            26,
            2,
            473,
          ),
          'ki_wset_origin_stellenbosch_merlot': DateTime.utc(
            2026,
            10,
            3,
            16,
            15,
          ),
        },
        reason: 'Preserved curation dates are independent of publication.',
      );
      final allIds = items.map((item) => item.id).toSet();
      expect(
        (await twoYearsLater.staleItems()).map((item) => item.id).toSet(),
        allIds.difference(laterCuratedIds),
        reason: 'The historical publication precedes three curation instants.',
      );
      expect(
        items.where((item) => item.lastVerifiedAt.isAfter(publishedAt)),
        isEmpty,
        reason: 'This release follows all preserved curation timestamps.',
      );
      final twoYearsAfterRelease = KnowledgeGraph(
        db,
        clock: Clock.fixed(twoYearsAfter(publishedAt)),
      );
      expect(
        (await twoYearsAfterRelease.staleItems())
            .map((item) => item.id)
            .toSet(),
        allIds,
        reason: 'Every item is stale two years after this later publication.',
      );
      final latest = items
          .map((item) => item.lastVerifiedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      final latestIds = items
          .where((item) => item.lastVerifiedAt == latest)
          .map((item) => item.id)
          .toSet();
      expect(latestIds, {'ki_wset_origin_stellenbosch_merlot'});
      final boundary = DateTime.utc(
        latest.year + 2,
        latest.month,
        latest.day,
        latest.hour,
        latest.minute,
        latest.second,
        latest.millisecond,
      );
      for (final offset in [-1, 0, 1]) {
        final atBoundary = KnowledgeGraph(
          db,
          clock: Clock.fixed(boundary.add(Duration(milliseconds: offset))),
        );
        final stale = await atBoundary.staleItems();
        expect(
          stale.map((item) => item.id).toSet(),
          offset <= 0 ? allIds.difference(latestIds) : allIds,
          reason: 'Strict stale cutoff before/at/after the latest instant.',
        );
        if (offset == 1) {
          expect(stale, hasLength(items.length));
        }
      }
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
