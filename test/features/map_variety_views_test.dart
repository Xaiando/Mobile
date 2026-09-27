import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart' hide MapLayer;
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/geometry_repository.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_pair/map_pair_format.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/features/map/map_canvas.dart';
import 'package:sommelier/features/map/map_presentation.dart';
import 'package:sommelier/features/practice/formats/map_grape_view.dart';
import 'package:sommelier/features/practice/formats/map_pair_view.dart';
import 'package:sommelier/features/practice/formats/map_question.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/geography_fixture.dart';

class _CaptureController extends StudySessionController {
  Object? submitted;

  @override
  Future<void> submit(Object answer) async => submitted = answer;
}

void main() {
  final fixture = FixtureLayers();
  final names = {
    'n_fx_north': 'North Hills',
    'n_fx_south': 'South Plain',
    'n_fx_village': 'Fixture Village',
  };

  MappedNode mapped(
    String id,
    String name,
    String layer,
    double lon,
    double lat,
  ) => MappedNode(
    KnowledgeNode(
      id: id,
      nodeType: 'appellation',
      name: name,
      nameNorm: name.toLowerCase(),
    ),
    NodeGeometry(
      knowledgeNodeId: id,
      mapLayerId: layer,
      featureKey: id,
      minLon: lon - 0.1,
      minLat: lat - 0.1,
      maxLon: lon + 0.1,
      maxLat: lat + 0.1,
      labelLon: lon,
      labelLat: lat,
    ),
  );
  final frame = MapFrame(
    parent: mapped('n_fx_region', 'Fixture Region', 'ml_fx_regions', 4.2, 47.5),
    box: const GeoBox(2.8, 46.3, 5.7, 48.7),
    candidates: [
      mapped('n_fx_north', 'North Hills', 'ml_fx_areas', 3.2, 48.2),
      mapped('n_fx_south', 'South Plain', 'ml_fx_areas', 3.5, 47),
      mapped('n_fx_village', 'Fixture Village', 'ml_fx_places', 5.2, 46.6),
    ],
  );

  MapExercise map(String format, {Set<String>? correct}) => MapExercise(
    formatId: format,
    primaryItemId: 'ki_north_location',
    questionTemplateId: 'qt_test',
    prompt: 'Find the places.',
    seed: 3,
    nodeId: 'n_fx_north',
    nodeName: 'North Hills',
    explanation: 'Both mapped areas permit this fixture grape.',
    frame: frame,
    zoomedOut: null,
    mode: MapMode.outline,
    names: names,
    correct: correct,
  );

  final pair = MapPairExercise(
    map: map('map_pair'),
    places: const [
      MapPlace(
        itemId: 'ki_north_location',
        nodeId: 'n_fx_north',
        name: 'North Hills',
        explanation: 'North Hills is in Fixture Region.',
      ),
      MapPlace(
        itemId: 'ki_village_location',
        nodeId: 'n_fx_village',
        name: 'Fixture Village',
        explanation: 'Fixture Village is in Fixture Region.',
      ),
    ],
    prompt: 'Find North Hills and Fixture Village.',
  );

  SessionTurn turn(Exercise exercise, {Object? answer, bool answered = false}) {
    final item = KnowledgeItem(
      id: exercise.primaryItemId,
      subjectId: 'n_fx_north',
      relationType: 'LOCATED_IN',
      objectId: 'n_fx_region',
      domainId: 'geography',
      assertionText: 'North Hills is in Fixture Region.',
      revision: 1,
      lastVerifiedAt: DateTime.utc(2026),
      verificationStatus: 'unverified',
      isDistinctive: false,
      mcqDisabled: false,
    );
    final format = QuestionFormat(
      questionTemplateId: exercise.questionTemplateId,
      direction: 'forward',
      mode: exercise.formatId,
    );
    return SessionTurn(
      card: StudyCard(
        item: item,
        mapping: EffectiveMapping(
          knowledgeItemId: item.id,
          certificationId: 'WSET_L3',
          importance: 'core',
          minimumDepth: 2,
          chainDepth: 0,
        ),
        formats: [format],
        state: null,
        retrievability: 0,
        priority: null,
        isStale: false,
      ),
      format: format,
      exercise: exercise,
      shownAt: DateTime.utc(2026),
      answer: answer,
      results: answered ? [] : null,
    );
  }

  Future<_CaptureController> pump(
    WidgetTester tester,
    SessionTurn current, {
    bool missing = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = _CaptureController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          studySessionProvider.overrideWith(() => controller),
          mapLayersProvider.overrideWith(
            (ref) async => missing
                ? []
                : [
                    MapLayer(fixture.regions),
                    MapLayer(fixture.areas),
                    MapLayer(fixture.places),
                  ],
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: current.exercise is MapPairExercise
                  ? MapPairView(current)
                  : MapGrapeView(current),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Offset point(WidgetTester tester, LonLat at) {
    final view = tester.state<MapCanvasState>(find.byType(MapCanvas)).debugView;
    final projected = WebMercator.project(at);
    return tester.getTopLeft(find.byType(MapCanvas)) +
        Offset(view.screenX(projected.x), view.screenY(projected.y));
  }

  testWidgets(
    'multi-place map stores point taps and requires every selection before submit',
    (tester) async {
      final controller = await pump(tester, turn(pair));
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check 2 locations'),
            )
            .onPressed,
        isNull,
      );
      await tester.tapAt(point(tester, const LonLat(3.2, 48.2)));
      await tester.pumpAndSettle();
      expect(find.text('Selecting: Fixture Village'), findsOneWidget);
      expect(controller.submitted, isNull);
      await tester.tapAt(point(tester, const LonLat(5.2, 46.6)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Check 2 locations'),
            )
            .onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.text('Check 2 locations'));
      await tester.tap(find.text('Check 2 locations'));
      await tester.pumpAndSettle();
      final answer = controller.submitted as MapPairAnswer;
      expect(answer.selections['ki_north_location']!.nodeId, 'n_fx_north');
      expect(answer.selections['ki_village_location']!.nodeId, 'n_fx_village');
      expect(answer.selections['ki_village_location']!.position, isNotNull);
    },
  );

  testWidgets(
    'accessible multi-place selections can be revised when maps are missing',
    (tester) async {
      final controller = await pump(tester, turn(pair), missing: true);
      expect(find.textContaining('cannot draw this map'), findsOneWidget);
      await tester.ensureVisible(find.text('Answer from a list'));
      await tester.tap(find.text('Answer from a list'));
      await tester.pumpAndSettle();
      for (final name in ['South Plain', 'Fixture Village']) {
        final button = find.widgetWithText(OutlinedButton, name);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      final target = find.widgetWithText(ListTile, 'North Hills');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      final revised = find.widgetWithText(OutlinedButton, 'North Hills');
      await tester.ensureVisible(revised);
      await tester.tap(revised);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Check 2 locations'));
      await tester.tap(find.text('Check 2 locations'));
      await tester.pumpAndSettle();
      final answer = controller.submitted as MapPairAnswer;
      expect(answer.selections['ki_north_location']!.nodeId, 'n_fx_north');
      expect(
        answer.selections.values.map((a) => a.fromList),
        everyElement(isTrue),
      );
    },
  );

  testWidgets(
    'grape feedback names the accepted alternative and marks every correct place',
    (tester) async {
      final exercise = map(
        'map_grape',
        correct: {'n_fx_north', 'n_fx_village'},
      );
      await pump(
        tester,
        turn(
          exercise,
          answer: const MapLocateAnswer.fromList('n_fx_village'),
          answered: true,
        ),
      );
      expect(find.text('Correct: Fixture Village'), findsOneWidget);
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      expect(canvas.highlights, {
        'n_fx_north': MapHighlight.correct,
        'n_fx_village': MapHighlight.correct,
      });
      expect(find.text('Continue'), findsOneWidget);
    },
  );

  testWidgets(
    'a grape tap outside represented targets leaves the question unanswered',
    (tester) async {
      final exercise = map('map_grape', correct: {'n_fx_north'});
      final controller = await pump(tester, turn(exercise));
      await tester.tapAt(point(tester, const LonLat(4.3, 47.6)));
      await tester.pumpAndSettle();
      expect(controller.submitted, isNull);
      expect(
        find.text('Select one of the marked study locations.'),
        findsOneWidget,
      );
    },
  );
}
