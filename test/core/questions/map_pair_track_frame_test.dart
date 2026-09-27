import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map_pair/map_pair_format.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late ExercisePresenter presenter;
  const primary = 'ki_vouvray_location';
  const peer = 'ki_chablis_location';
  const templateId = 'qt_located_in_fwd_map_pair';
  const lowerNodes = {'n_geo_vouvray', 'n_geo_chablis'};

  setUpAll(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    final data = copyOf(bundledDatasetMap());
    final locations = {
      for (final item in rowsOf(data, 'knowledge_items'))
        if (item['relation_type'] == 'LOCATED_IN') item['id'],
    };
    // The lower track knows one location in the nearest Touraine frame and
    // another elsewhere in France. Higher tracks retain their detailed atlas.
    rowsOf(data, 'certification_knowledge_mappings').removeWhere(
      (row) =>
          const {'WSET_L1', 'WSET_L2'}.contains(row['certification_id']) &&
          locations.contains(row['knowledge_item_id']),
    );
    for (final id in [primary, peer]) {
      rowsOf(data, 'certification_knowledge_mappings').add({
        'certification_id': 'WSET_L2',
        'knowledge_item_id': id,
        'importance': 'core',
        'minimum_depth': 1,
      });
    }
    final mappings = rowsOf(data, 'certification_knowledge_mappings');
    for (final id in locations) {
      if (!mappings.any((row) => row['knowledge_item_id'] == id)) {
        // Preserve fixture validity for facts formerly mapped only at L2,
        // without putting them back into the deliberately sparse lower track.
        mappings.add({
          'certification_id': 'WSET_L4',
          'knowledge_item_id': id,
          'importance': 'secondary',
          'minimum_depth': 2,
        });
      }
    }
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(datasetOf(data));
    presenter = ExercisePresenter(db, clock: time.clock);
  });
  tearDownAll(() => db.close());

  test('a sparse lower track widens the shared pair without suppressing higher tracks', () async {
    final defaultFrame = await GeometryRepository(db)
        .frameOf('n_geo_vouvray', on: '2026-10-01');
    expect(defaultFrame, isNotNull);
    expect(
      defaultFrame!.candidates.map((n) => n.id),
      isNot(contains('n_geo_chablis')),
    );
    expect(
      (await db.select(db.questions).get()).any(
        (q) =>
            q.knowledgeItemId == primary && q.questionTemplateId == templateId,
      ),
      isTrue,
      reason: 'A lower track can widen instead of globally deleting this pair.',
    );
    final item = (await KnowledgeGraph(db).currentItems(on: '2026-10-01'))
        .singleWhere((i) => i.id == primary);
    final template = (await db.select(db.questionTemplates).get()).singleWhere(
      (t) => t.id == templateId,
    );
    expect(
      await const MapPairFormat().isEligible(
        GeneratorContext(
          db,
          today: '2026-10-01',
          items: await KnowledgeGraph(db).currentItems(on: '2026-10-01'),
        ),
        item,
        template,
      ),
      isTrue,
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    final scope = await StudyPlanner(db).effectiveMappings('WSET_L3');
    final higher = await presenter.present(
      primary,
      templateId,
      seed: 9,
    ) as MapPairExercise;
    expect(higher.places.length, inInclusiveRange(2, 4));
    expect(higher.itemIds.every(scope.containsKey), isTrue);
  });

  test(
    'lower pairs expose only mapped locations and keep deterministic co-items',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L2');
      for (var seed = 0; seed < 4; seed++) {
        final pair = await presenter.present(
          primary,
          templateId,
          seed: seed,
        ) as MapPairExercise;
        final repeated = await presenter.present(
          primary,
          templateId,
          seed: seed,
        ) as MapPairExercise;
        expect(pair.itemIds, [primary, peer]);
        expect(pair.map.candidateIds, unorderedEquals(lowerNodes));
        expect(repeated.itemIds, pair.itemIds);
        expect(repeated.prompt, pair.prompt);
        expect(
          pair.map.frame.box.contains(
            pair.map.frame.candidates.first.geometry.labelLon,
            pair.map.frame.candidates.first.geometry.labelLat,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    'an explicit session track takes precedence over a changed active profile',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final lower = await presenter.present(
        primary,
        templateId,
        seed: 12,
        certificationId: 'WSET_L2',
      ) as MapPairExercise;
      expect(lower.itemIds, [primary, peer]);
      expect(lower.map.candidateIds, unorderedEquals(lowerNodes));
      final lowerScope = await StudyPlanner(db).effectiveMappings('WSET_L2');
      final advanced = (await KnowledgeGraph(db).currentItems(on: '2026-10-01'))
          .firstWhere(
            (i) =>
                i.relationType == 'LOCATED_IN' && !lowerScope.containsKey(i.id),
          );
      await expectLater(
        presenter.present(
          advanced.id,
          templateId,
          seed: 12,
          certificationId: 'WSET_L2',
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );
}
