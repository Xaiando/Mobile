import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_pair/map_pair_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late ExercisePresenter presenter;
  late Set<String> activePairNodes;
  late String retiredPairNode;
  const day = '2026-10-01';
  const pairTemplate = 'qt_located_in_fwd_local_midnight_map_pair';
  const plantingItem = 'ki_nz_2025_marlborough_top_sauvignon_blanc';
  const plantingSubject = 'n_stat_nz_top_two_planted_2025_marlborough';
  const nzAreas = {
    'n_geo_marlborough',
    'n_geo_central_otago',
    'n_geo_hawkes_bay',
    'n_geo_gisborne',
    'n_geo_nelson',
    'n_geo_wairarapa',
  };
  // In Oslo this is still September 30 in UTC. UTC CI also exercises the
  // same calendar-date contract; the test does not depend on a fixed offset.
  final localMidnight = DateTime(2026, 10, 1, 0, 30);
  final time = Clock.fixed(localMidnight.toUtc());

  setUpAll(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    final data = copyOf(bundledDatasetMap());
    rowsOf(data, 'question_templates').add({
      'id': pairTemplate,
      'relation_type': 'LOCATED_IN',
      'direction': 'forward',
      'mode': 'map_pair',
      'variant': 'local_midnight',
      'prompt_template': 'Find the requested places.',
      'parameters': {'min_places': 2, 'max_places': 2},
    });
    await CurriculumIngester(
      db,
      clock: time,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(datasetOf(data));
    presenter = ExercisePresenter(db, clock: time);

    final frame = await GeometryRepository(db)
        .frameOf('n_geo_chablis', on: day);
    expect(frame, isNotNull);
    final candidateIds = frame!.candidates.map((node) => node.id).toSet()
      ..remove('n_geo_chablis');
    final locationItems = await db.select(db.knowledgeItems).get();
    final peerNodes =
        locationItems
            .where(
              (item) =>
                  item.relationType == 'LOCATED_IN' &&
                  candidateIds.contains(item.subjectId),
            )
            .map((item) => item.subjectId)
            .toSet()
            .toList()
          ..sort();
    expect(peerNodes.length, greaterThanOrEqualTo(4));
    retiredPairNode = peerNodes.first;
    activePairNodes = peerNodes.skip(1).toSet();

    await db.writeCurriculum(() async {
      // These controlled ranking records and their complete-set assertions
      // become usable on the local date, including their structural area links.
      await db.customStatement(
        'UPDATE knowledge_relations SET valid_from=? '
        "WHERE relation_type IN ('TOP_PLANTED_GRAPE','STATISTIC_IN_AREA') "
        "AND subject_id LIKE 'n_stat_nz_top_two_planted_2025_%'",
        [day],
      );
      await db.customStatement(
        'UPDATE relation_set_assertions SET valid_from=? '
        "WHERE relation_type='TOP_PLANTED_GRAPE' "
        "AND node_id LIKE 'n_stat_nz_top_two_planted_2025_%'",
        [day],
      );
      await db.customStatement(
        'INSERT INTO knowledge_relations '
        '(subject_id,relation_type,object_id,valid_from,valid_until) '
        "VALUES (?,'TOP_PLANTED_GRAPE','n_grape_merlot','2026-02-26',?)",
        [plantingSubject, day],
      );

      // Keep the primary location unchanged. Every co-item in its original
      // frame starts today, except one retired location from yesterday.
      for (final nodeId in candidateIds) {
        await db.customStatement(
          nodeId == retiredPairNode
              ? 'UPDATE knowledge_relations SET valid_until=? '
                    "WHERE subject_id=? AND relation_type='LOCATED_IN' "
                    'AND valid_from<=? AND (valid_until IS NULL OR valid_until>?)'
              : 'UPDATE knowledge_relations SET valid_from=? '
                    "WHERE subject_id=? AND relation_type='LOCATED_IN' "
                    'AND valid_from<=? AND (valid_until IS NULL OR valid_until>?)',
          [day, nodeId, day, day],
        );
      }
    });
  });

  test(
    'planting maps use newly active local-date complete sets and area links',
    () async {
      expect(localToday(time), day);
      final map = await presenter.present(
        plantingItem,
        'qt_top_planted_grape_fwd_map_grape',
        seed: 0,
      ) as MapExercise;
      expect(map.candidateIds, unorderedEquals(nzAreas));
      expect(map.correctNodeIds, contains('n_geo_marlborough'));
      expect(map.prompt, contains('2025'));
      expect(map.prompt, isNot(contains('Merlot')));
    },
  );

  test('typed planting ranks accept today’s starts and reject yesterday’s retired value', () async {
    final question = await presenter.present(
      plantingItem,
      'qt_top_planted_grape_fwd_typed',
      seed: 1,
    );
    const typed = TypedFormat();
    expect(
      typed.grade(question, 'Sauvignon Blanc').single.rating,
      fsrs.Rating.good,
    );
    expect(typed.grade(question, 'Pinot Noir').single.rating, fsrs.Rating.good);
    expect(typed.grade(question, 'Merlot').single.rating, fsrs.Rating.again);
  });

  test(
    'multi-place maps choose today’s location peers and omit retired peers',
    () async {
      for (var seed = 0; seed < 4; seed++) {
        final pair = await presenter.present(
          'ki_chablis_location',
          pairTemplate,
          seed: seed,
        ) as MapPairExercise;
        expect(pair.places, hasLength(2));
        expect(pair.places.first.nodeId, 'n_geo_chablis');
        expect(activePairNodes, contains(pair.places.last.nodeId));
        expect(
          pair.places.map((place) => place.nodeId),
          isNot(contains(retiredPairNode)),
        );
      }
    },
  );

  test(
    'typed berry colour switches at local midnight on its correction date',
    () async {
      final correctionTime = Clock.fixed(DateTime(2026, 9, 26, 0, 30).toUtc());
      final question = await ExercisePresenter(db, clock: correctionTime)
          .present(
            'ki_berry_pinot_gris_grey',
            'qt_berry_colour_fwd_typed',
            seed: 1,
          );
      const typed = TypedFormat();
      expect(localToday(correctionTime), '2026-09-26');
      expect(typed.grade(question, 'Grey').single.rating, fsrs.Rating.good);
      expect(typed.grade(question, 'Gray').single.rating, fsrs.Rating.good);
      expect(typed.grade(question, 'White').single.rating, fsrs.Rating.again);
    },
  );
}
