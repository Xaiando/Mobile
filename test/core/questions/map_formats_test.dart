import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/hit_test.dart';
import 'package:sommelier/core/geography/topojson.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_identify/map_identify_format.dart';
import 'package:sommelier/core/questions/formats/map_locate/map_locate_format.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// Backlog G4: finding and naming an area on the map.
void main() {
  late AppDatabase db;
  late TestClock time;
  late GenerationReport generated;
  late ExercisePresenter presenter;
  late ReviewService reviews;
  final appellations = GeoLayer.fromTopology(
    Topology.parse(
      File('assets/geography/fr_appellations.topo.json').readAsStringSync(),
    ),
    id: 'ml_fr_appellations',
  );

  const locate = 'qt_located_in_fwd_map_locate';
  const identify = 'qt_located_in_fwd_map_identify';

  setUp(() async {
    time = TestClock(DateTime.utc(2026, 10, 1, 9));
    db = openTestDatabase();
    generated = await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    presenter = ExercisePresenter(db, clock: time.clock);
    reviews = ReviewService(
      db,
      clock: time.clock,
      schedulerFactory: unfuzzedScheduler,
      random: Random(5),
    );
  });
  tearDown(() => db.close());

  Future<MapExercise> present(String itemId, String template) async =>
      await presenter.present(itemId, template, seed: 3) as MapExercise;

  /// A tap at [at], hit-tested against [exercise]'s candidates on a view
  /// where the frame is about 400 pixels wide.
  MapTap tapAt(MapExercise exercise, LonLat at) {
    final frame = exercise.frame.box;
    final shapes = [
      for (final id in exercise.candidateIds) ?appellations.shapeFor(id),
    ];
    final pixelsPerWorld = 400 / ((frame.maxLon - frame.minLon) / 360);
    return MapTap(
      position: at,
      hits: const MapHitTester().hitTest(
        shapes,
        WebMercator.project(at),
        pixelsPerWorld,
      ),
      zoom: 6,
      visibleBounds: GeoBounds(
        minLon: frame.minLon,
        minLat: frame.minLat,
        maxLon: frame.maxLon,
        maxLat: frame.maxLat,
      ),
    );
  }

  LonLat labelOf(MapExercise exercise, String nodeId) {
    final g = exercise.frame.candidates
        .firstWhere((c) => c.id == nodeId)
        .geometry;
    return LonLat(g.labelLon, g.labelLat);
  }

  test('only areas drawn and framed are asked on the map', () async {
    final map = await (db.select(
      db.questions,
    )..where((q) => q.questionTemplateId.equals(locate))).get();
    expect(map, hasLength(18), reason: 'every drawn location item');
    expect([
      for (final q in map) q.knowledgeItemId,
    ], containsAll(['ki_chablis_location', 'ki_burgundy_location']));
    expect(
      [
        for (final s in generated.skipped)
          if (s.templateId == locate) (s.itemId, s.reason),
      ],
      contains(('ki_barolo_location', SkipReason.notEligible)),
      reason: 'Barolo is not drawn yet',
    );
  });

  test('frames the question and names its candidates', () async {
    final chablis = await present('ki_chablis_location', locate);
    expect(chablis.prompt, 'Find Chablis on the map.');
    expect(chablis.nodeId, 'n_geo_chablis');
    expect(chablis.frame.parent.id, 'n_geo_france');
    expect(chablis.candidateIds, contains('n_geo_volnay'));
    expect(chablis.names['n_geo_chablis'], 'Chablis');
    expect(chablis.options, isEmpty);
    expect(chablis.mode, MapMode.labelled, reason: 'a new item');
  });

  test('a tap inside the area is right; one on another area or outside '
      'every area is wrong', () async {
    final chablis = await present('ki_chablis_location', locate);
    const format = MapLocateFormat();

    final inside = tapAt(chablis, labelOf(chablis, 'n_geo_chablis'));
    expect(inside.hit?.key, 'n_geo_chablis');
    final right = format.grade(chablis, MapLocateAnswer.fromTap(inside)).single;
    expect(right.rating, fsrs.Rating.good);
    expect(right.selectedNodeId, 'n_geo_chablis');
    expect(right.payload, containsPair('tap', isA<List<Object?>>()));
    expect(right.payload, containsPair('frame', 'n_geo_france'));

    final volnay = tapAt(chablis, labelOf(chablis, 'n_geo_volnay'));
    final wrong = format.grade(chablis, MapLocateAnswer.fromTap(volnay)).single;
    expect(wrong.rating, fsrs.Rating.again);
    expect(wrong.selectedNodeId, 'n_geo_volnay');

    // Bordeaux: no candidate there.
    final outside = tapAt(chablis, const LonLat(-0.58, 44.84));
    expect(outside.hit, isNull);
    final missed = format
        .grade(chablis, MapLocateAnswer.fromTap(outside))
        .single;
    expect(missed.rating, fsrs.Rating.again);
    expect(missed.selectedNodeId, isNull);
    expect(missed.payload, containsPair('node', null));

    final listed = format
        .grade(chablis, const MapLocateAnswer.fromList('n_geo_chablis'))
        .single;
    expect(listed.rating, fsrs.Rating.good);
    expect(listed.payload, containsPair('list', true));
    expect(
      () => format.grade(chablis, const MapLocateAnswer.fromList('n_x')),
      throwsArgumentError,
    );
  });

  test('a tap near an area selects it, and any correct node counts', () async {
    final chablis = await present('ki_chablis_location', locate);
    final shape = appellations.shapeFor('n_geo_chablis')!;
    final near = MapTap(
      position: const LonLat(4.1, 47.8),
      hits: [MapHit(shape: shape, kind: HitKind.near, distance: 6)],
      zoom: 7,
      visibleBounds: GeoBounds(minLon: 3, minLat: 47, maxLon: 5, maxLat: 48),
    );
    const format = MapLocateFormat();
    expect(
      format.grade(chablis, MapLocateAnswer.fromTap(near)).single.rating,
      fsrs.Rating.good,
    );

    final either = MapExercise(
      formatId: chablis.formatId,
      primaryItemId: chablis.primaryItemId,
      questionTemplateId: chablis.questionTemplateId,
      prompt: chablis.prompt,
      seed: chablis.seed,
      nodeId: chablis.nodeId,
      nodeName: chablis.nodeName,
      explanation: chablis.explanation,
      frame: chablis.frame,
      zoomedOut: chablis.zoomedOut,
      mode: chablis.mode,
      names: chablis.names,
      correct: {'n_geo_chablis', 'n_geo_volnay'},
    );
    expect(
      format
          .grade(either, const MapLocateAnswer.fromList('n_geo_volnay'))
          .single
          .rating,
      fsrs.Rating.good,
    );
  });

  test(
    'naming offers four candidates of the frame, fixed by the seed',
    () async {
      final chablis = await present('ki_chablis_location', identify);
      expect(chablis.prompt, 'Name the highlighted area.');
      expect(chablis.options, hasLength(4));
      expect({for (final o in chablis.options) o.nodeId}, hasLength(4));
      expect(
        chablis.options,
        contains(const QuestionOption('n_geo_chablis', 'Chablis')),
      );
      expect(
        chablis.candidateIds,
        containsAll(chablis.options.map((o) => o.nodeId)),
      );
      expect(
        (await present('ki_chablis_location', identify)).options,
        chablis.options,
        reason: 'the same seed, the same options (QG-7)',
      );
      expect(chablis.mode, MapMode.outline, reason: 'labels would name it');

      const format = MapIdentifyFormat();
      final answer = chablis.options.firstWhere(
        (o) => o.nodeId == 'n_geo_chablis',
      );
      final right = format.grade(chablis, answer).single;
      expect(right.rating, fsrs.Rating.good);
      expect(right.optionNodeIds, [for (final o in chablis.options) o.nodeId]);
      final other = chablis.options.firstWhere((o) => o != answer);
      expect(format.grade(chablis, other).single.rating, fsrs.Rating.again);
    },
  );

  test("the mode follows the item's memory until the ladder (GEO-8)", () {
    ReviewState state(double stability, {int? step}) => ReviewState(
      knowledgeItemId: 'ki',
      state: step == null ? 2 : 1,
      step: step,
      stability: stability,
      difficulty: 5,
      due: DateTime.utc(2026, 10, 2),
      lastReview: DateTime.utc(2026, 10, 1),
      reps: 1,
      lapses: 0,
    );
    expect(mapModeFor(null), MapMode.labelled);
    expect(mapModeFor(state(1, step: 0)), MapMode.labelled);
    expect(mapModeFor(state(3)), MapMode.outline);
    expect(mapModeFor(state(12)), MapMode.minimal);
    expect(mapModeFor(state(45)), MapMode.blank);
    expect(
      const MapIdentifyFormat().modeFor(MapMode.labelled),
      MapMode.outline,
    );
  });

  test('GEO-1: finding Chablis, naming it and the text question practise '
      'one item', () async {
    const item = 'ki_chablis_location';
    final found = await present(item, locate);
    await reviews.recordExercise(
      found,
      presenter.grade(found, const MapLocateAnswer.fromList('n_geo_chablis')),
    );
    time.advance(const Duration(minutes: 20));
    final named = await present(item, identify);
    await reviews.recordExercise(
      named,
      presenter.grade(
        named,
        named.options.firstWhere((o) => o.nodeId == 'n_geo_chablis'),
      ),
    );
    time.advance(const Duration(minutes: 20));
    final text = await presenter.present(
      item,
      'qt_located_in_fwd_mcq',
      seed: 1,
    ) as PresentedQuestion;
    expect(text.prompt, 'In which region is Chablis located?');
    await reviews.recordExercise(text, presenter.grade(text, text.answer));

    final events = await db.select(db.reviewEvents).get();
    expect(
      [for (final e in events) (e.knowledgeItemId, e.questionTemplateId)],
      [(item, locate), (item, identify), (item, 'qt_located_in_fwd_mcq')],
    );
    final state = await (db.select(
      db.reviewStates,
    )..where((s) => s.knowledgeItemId.equals(item))).getSingle();
    expect(state.reps, 3, reason: 'one memory for the fact (FS-2)');
  });
}
