import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_grape/map_grape_format.dart';
import 'package:sommelier/core/questions/formats/map_pair/map_pair_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late ExercisePresenter presenter;
  late TestClock time;
  const pairTemplate = 'qt_located_in_fwd_test_map_pair';
  const grapeTemplate = 'qt_principal_grape_fwd_test_map_grape';
  const unionTemplate = 'qt_permitted_grape_fwd_map_grape';
  const unionPrimary = 'ki_fr_atlas_volnay_permits_grape_pinot_noir';

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    final data = copyOf(bundledDatasetMap());
    // A controlled complete-permission fixture. The atlas may grow without
    // making every positive grape fact a complete legal list.
    rowsOf(
      data,
      'relation_set_assertions',
    ).removeWhere((row) => row['relation_type'] == 'PERMITS_GRAPE');
    const completePermissions = {
      'n_geo_chablis': ['n_grape_chardonnay'],
      'n_geo_volnay': [
        'n_grape_pinot_noir',
        'n_grape_chardonnay',
        'n_grape_pinot_blanc',
        'n_grape_pinot_gris',
      ],
      'n_geo_cornas': ['n_grape_syrah'],
    };
    rowsOf(data, 'knowledge_relations').removeWhere(
      (row) =>
          row['relation_type'] == 'PERMITS_GRAPE' &&
          completePermissions.containsKey(row['subject_id']),
    );
    for (final entry in completePermissions.entries) {
      for (final grape in entry.value) {
        if (!rowsOf(data, 'knowledge_relations').any(
          (r) =>
              r['subject_id'] == entry.key &&
              r['relation_type'] == 'PERMITS_GRAPE' &&
              r['object_id'] == grape,
        )) {
          rowsOf(data, 'knowledge_relations').add({
            'subject_id': entry.key,
            'relation_type': 'PERMITS_GRAPE',
            'object_id': grape,
            'valid_from': '1900-01-01',
          });
        }
      }
      rowsOf(data, 'relation_set_assertions').add({
        'node_id': entry.key,
        'relation_type': 'PERMITS_GRAPE',
        'direction': 'forward',
        'member_node_type': 'grape',
        'valid_from': '1900-01-01',
        'source_citation_id': 'src_inao_cdc_${entry.key.substring(6)}',
        'locator': 'V. Encépagement',
      });
    }
    rowsOf(data, 'question_templates').addAll([
      {
        'id': pairTemplate,
        'relation_type': 'LOCATED_IN',
        'direction': 'forward',
        'mode': 'map_pair',
        'variant': 'test',
        'prompt_template': 'Find the requested places.',
      },
      {
        'id': grapeTemplate,
        'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
        'direction': 'forward',
        'mode': 'map_grape',
        'variant': 'test',
        'prompt_template': 'Find one wine area permitting {object.name}.',
      },
    ]);
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(datasetOf(data));
    presenter = ExercisePresenter(db, clock: time.clock);
  });
  tearDown(() => db.close());

  Future<MapPairExercise> pair({int seed = 8}) async =>
      await presenter.present('ki_chablis_location', pairTemplate, seed: seed)
          as MapPairExercise;
  Future<MapExercise> grape() async =>
      await presenter.present('ki_chablis_grape', grapeTemplate, seed: 12)
          as MapExercise;

  test(
    'the seed fixes two to four named places on one map, with varied wording',
    () async {
      final first = await pair();
      final repeated = await pair();
      expect(first.places.length, inInclusiveRange(2, 4));
      expect(first.itemIds.first, 'ki_chablis_location');
      expect(first.itemIds.toSet(), hasLength(first.itemIds.length));
      expect(
        first.map.candidateIds,
        containsAll(first.places.map((p) => p.nodeId)),
      );
      expect(first.prompt, repeated.prompt);
      expect(first.itemIds, repeated.itemIds);
      for (final place in first.places) {
        expect(first.prompt, contains(place.name));
      }
      final variations = {
        for (var seed = 0; seed < 10; seed++) (await pair(seed: seed)).prompt,
      };
      expect(variations.length, greaterThan(3));
    },
  );

  test(
    'each requested place earns its own grade and shares one exercise event',
    () async {
      final exercise = await pair();
      final selections = {
        for (final place in exercise.places)
          place.itemId: MapLocateAnswer.fromList(place.nodeId),
      };
      // One deliberate swap must not turn the co-item's correct answer into
      // a successful review for the primary location.
      selections[exercise.places.first.itemId] = MapLocateAnswer.fromList(
        exercise.places[1].nodeId,
      );
      final grades = presenter.grade(exercise, MapPairAnswer(selections));
      expect(grades.first.rating, fsrs.Rating.again);
      expect(
        grades.skip(1).map((g) => g.rating),
        everyElement(fsrs.Rating.good),
      );
      expect(grades.map((g) => g.itemId), exercise.itemIds);
      await ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
      ).recordExercise(exercise, grades);
      final events = await db.select(db.reviewEvents).get();
      expect(events, hasLength(exercise.itemIds.length));
      expect(events.map((e) => e.exerciseId).toSet(), hasLength(1));
      expect(events.first.exerciseId, isNotNull);
      expect(events.map((e) => e.seed), everyElement(exercise.seed));
      expect(
        jsonDecode(events.first.answerPayload!),
        containsPair('target', exercise.places.first.nodeId),
      );
    },
  );

  test(
    'missing selections are Again and foreign items or candidates are refused',
    () async {
      final exercise = await pair();
      expect(
        presenter.grade(exercise, MapPairAnswer({})).map((g) => g.rating),
        everyElement(fsrs.Rating.again),
      );
      expect(
        () => presenter.grade(
          exercise,
          MapPairAnswer({
            'ki_foreign': const MapLocateAnswer.fromList('n_geo_chablis'),
          }),
        ),
        throwsArgumentError,
      );
      expect(
        () => presenter.grade(
          exercise,
          MapPairAnswer({
            exercise.primaryItemId: const MapLocateAnswer.fromList('n_foreign'),
          }),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'a multi-place question requires distinct current mapped location facts',
    () async {
      final item = await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals('ki_chablis_location'))).getSingle();
      final template = await (db.select(
        db.questionTemplates,
      )..where((t) => t.id.equals(pairTemplate))).getSingle();
      expect(
        await const MapPairFormat().isEligible(
          GeneratorContext(db, today: '2026-10-01', items: [item]),
          item,
          template,
        ),
        isFalse,
      );
      expect(
        const MapPairFormat().templateProblems(
          template.copyWith(
            parameters: const Value('{"min_places":4,"max_places":2}'),
          ),
          relationTypes: {'LOCATED_IN'},
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'multi-place co-items stay within the selected track and depth',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final original = await pair();
      final excluded = original.itemIds[1];
      // A CMS-only location must not become a bonus review in WSET practice.
      await db.writeCurriculum(
        () =>
            (db.delete(db.certificationKnowledgeMappings)..where(
                  (m) =>
                      m.knowledgeItemId.equals(excluded) &
                      m.certificationId.like('WSET%'),
                ))
                .go(),
      );
      final scope = await StudyPlanner(db).effectiveMappings('WSET_L3');
      expect(scope, isNot(contains(excluded)));
      for (var seed = 0; seed < 10; seed++) {
        final exercise = await pair(seed: seed);
        expect(exercise.itemIds, isNot(contains(excluded)));
        for (final itemId in exercise.itemIds) {
          expect(scope[itemId]?.minimumDepth, greaterThanOrEqualTo(1));
        }
      }
    },
  );

  test('a grape question accepts accessory and principal permissions, including uncarded relations', () async {
    final exercise = await grape();
    expect(exercise.prompt, contains('Chardonnay'));
    expect(exercise.prompt.toLowerCase(), contains('one'));
    expect(exercise.candidateIds, isNot(contains('n_geo_meursault')));
    expect(
      exercise.correctNodeIds,
      containsAll(['n_geo_chablis', 'n_geo_volnay']),
    );
    const format = MapGrapeFormat();
    for (final correct in exercise.correctNodeIds) {
      expect(
        format.grade(exercise, MapLocateAnswer.fromList(correct)).single.rating,
        fsrs.Rating.good,
      );
    }
    expect(
      format.grade(exercise, const MapLocateAnswer()).single.rating,
      fsrs.Rating.again,
    );
    expect(
      () => format.grade(
        exercise,
        const MapLocateAnswer.fromList('n_geo_barolo'),
      ),
      throwsArgumentError,
    );
    // A permission remains a valid answer after its separate study card
    // has been superseded: eligibility is based on current relations.
    final accessory =
        await (db.select(db.knowledgeItems)..where(
              (i) =>
                  i.subjectId.equals('n_geo_volnay') &
                  i.relationType.equals('PERMITS_ACCESSORY_GRAPE') &
                  i.objectId.equals('n_grape_chardonnay'),
            ))
            .get();
    for (final item in accessory) {
      await db.writeCurriculum(
        () => (db.update(db.knowledgeItems)..where((i) => i.id.equals(item.id)))
            .write(
              const KnowledgeItemsCompanion(
                supersededByItemId: Value('ki_chablis_grape'),
              ),
            ),
      );
    }
    expect((await grape()).correctNodeIds, contains('n_geo_volnay'));
    await db.writeCurriculum(
      () =>
          (db.update(db.knowledgeRelations)..where(
                (r) =>
                    r.subjectId.equals('n_geo_volnay') &
                    r.relationType.isIn(MapGrapeFormat.grapeRelations) &
                    r.objectId.equals('n_grape_chardonnay'),
              ))
              .write(
                const KnowledgeRelationsCompanion(
                  validUntil: Value('2026-10-01'),
                ),
              ),
    );
    expect((await grape()).correctNodeIds, isNot(contains('n_geo_volnay')));
  });

  test('grape combinations vary deterministically and grade each permission independently', () async {
    final variants = <MapExercise>[];
    for (var seed = 0; seed < 24; seed++) {
      variants.add(
        await presenter.present(unionPrimary, unionTemplate, seed: seed)
            as MapExercise,
      );
    }
    expect(
      variants.map((v) => v.itemIds.length).toSet(),
      containsAll([1, 2, 3]),
    );
    final chardonnayItems =
        await (db.select(db.knowledgeItems)..where(
              (i) =>
                  i.subjectId.equals('n_geo_volnay') &
                  i.objectId.equals('n_grape_chardonnay') &
                  i.relationType.isIn(MapGrapeFormat.grapeRelations),
            ))
            .get();
    final chardonnayIds = chardonnayItems.map((i) => i.id).toSet();
    final combination = variants.firstWhere(
      (v) => v.itemIds.length > 1 && v.itemIds.any(chardonnayIds.contains),
    );
    final repeated = await presenter.present(
      unionPrimary,
      unionTemplate,
      seed: combination.seed,
    ) as MapExercise;
    expect(repeated.prompt, combination.prompt);
    expect(repeated.itemIds, combination.itemIds);
    expect(combination.prompt, contains('Chardonnay'));
    expect(combination.correctNodeIds, {'n_geo_volnay'});
    expect(combination.inMode(MapMode.outline).itemIds, combination.itemIds);
    final fullyCorrect = presenter.grade(
      combination,
      const MapLocateAnswer.fromList('n_geo_volnay'),
    );
    expect(fullyCorrect.map((g) => g.rating), everyElement(fsrs.Rating.good));
    final partial = presenter.grade(
      combination,
      const MapLocateAnswer.fromList('n_geo_chablis'),
    );
    expect(partial.first.rating, fsrs.Rating.again);
    expect(
      partial.singleWhere((g) => chardonnayIds.contains(g.itemId)).rating,
      fsrs.Rating.good,
    );
    expect(partial.map((g) => g.itemId), combination.itemIds);
    await ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
    ).recordExercise(combination, partial);
    final events = await db.select(db.reviewEvents).get();
    expect(events, hasLength(combination.itemIds.length));
    expect(events.map((e) => e.exerciseId).toSet(), hasLength(1));
    expect(
      jsonDecode(events.first.answerPayload!),
      containsPair('requested_items', combination.itemIds),
    );
  });

  test(
    'grape combination co-items respect the active track and served depth',
    () async {
      await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
      final peers =
          await (db.select(db.knowledgeItems)..where(
                (i) =>
                    i.subjectId.equals('n_geo_volnay') &
                    i.relationType.isIn(MapGrapeFormat.grapeRelations) &
                    i.id.equals(unionPrimary).not(),
              ))
              .get();
      await db.writeCurriculum(
        () =>
            (db.update(db.certificationKnowledgeMappings)..where(
                  (m) =>
                      m.knowledgeItemId.isIn(peers.map((i) => i.id)) &
                      m.certificationId.like('WSET%'),
                ))
                .write(
                  const CertificationKnowledgeMappingsCompanion(
                    minimumDepth: Value(1),
                  ),
                ),
      );
      for (var seed = 0; seed < 6; seed++) {
        final exercise = await presenter.present(
          unionPrimary,
          unionTemplate,
          seed: seed,
        ) as MapExercise;
        expect(exercise.itemIds, [unionPrimary]);
        expect(exercise.prompt, isNot(contains('Chardonnay')));
      }
    },
  );

  test(
    'a positive permission without a current complete union is not a target',
    () async {
      await db.writeCurriculum(
        () =>
            (db.delete(db.relationSetAssertions)..where(
                  (a) =>
                      a.nodeId.equals('n_geo_volnay') &
                      a.relationType.equals('PERMITS_GRAPE'),
                ))
                .go(),
      );
      final exercise = await grape();
      expect(exercise.candidateIds, isNot(contains('n_geo_volnay')));
      expect(exercise.correctNodeIds, isNot(contains('n_geo_volnay')));
      final item = await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals('ki_volnay_grape'))).getSingle();
      final template = await (db.select(
        db.questionTemplates,
      )..where((t) => t.id.equals(grapeTemplate))).getSingle();
      expect(
        await const MapGrapeFormat().isEligible(
          GeneratorContext(db, today: '2026-10-01', items: [item]),
          item,
          template,
        ),
        isFalse,
      );
      // An expired assertion cannot establish negative grape answers either.
      await db.writeCurriculum(
        () =>
            (db.update(db.relationSetAssertions)..where(
                  (a) =>
                      a.nodeId.equals('n_geo_chablis') &
                      a.relationType.equals('PERMITS_GRAPE'),
                ))
                .write(
                  const RelationSetAssertionsCompanion(
                    validUntil: Value('2026-10-01'),
                  ),
                ),
      );
      final chablis = await (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals('ki_chablis_grape'))).getSingle();
      expect(
        await const MapGrapeFormat().isEligible(
          GeneratorContext(db, today: '2026-10-01', items: [chablis]),
          chablis,
          template,
        ),
        isFalse,
      );
    },
  );
}
