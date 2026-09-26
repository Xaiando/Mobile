import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/web_mercator.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_identify/map_identify_format.dart';
import 'package:sommelier/core/questions/formats/map_locate/map_locate_format.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/features/map/map_canvas.dart';
import 'package:sommelier/features/map/map_presentation.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Map locate, ahead of the text formats, so a new drawn item starts on
/// the map.
class _LocateFirst extends MapLocateFormat {
  const _LocateFirst();

  @override
  int difficultyRank(String direction) => -2;
}

/// Map identify, ahead of everything.
class _IdentifyFirst extends MapIdentifyFormat {
  const _IdentifyFirst();

  @override
  int difficultyRank(String direction) => -3;
}

/// Backlog G4: map questions in a practice session.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  SessionTurn turn(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(PracticeScreen)))
          .read(studySessionProvider)
          .value!
          .turn!;

  /// Starts a session with [first] as the easiest format, then answers
  /// text cards until a map card is shown.
  Future<MapExercise> mapCard(
    WidgetTester tester,
    FormatRegistry formats, {
    Future<void> Function()? beforeStart,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db, overrides: servingOnly(formats));
    await tap(tester, find.text('WSET Level 3'));
    // Every item in one session, so the drawn areas come up.
    await tester.runAsync(
      () =>
          LearnerProfiles(db).setSessionLimits(sessionSize: 100, newItems: 60),
    );
    if (beforeStart != null) await tester.runAsync(beforeStart);
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));
    for (var i = 0; turn(tester).exercise is! MapExercise; i++) {
      expect(i, lessThan(80), reason: 'a map card in the session');
      final question = turn(tester).question;
      if (question.isMultipleChoice) {
        await tap(
          tester,
          find.widgetWithText(OutlinedButton, question.answer.name),
        );
        await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
      } else {
        await tap(tester, find.text('Show answer'));
        await tap(tester, find.widgetWithText(FilledButton, 'Good'));
      }
    }
    // The layers load in the background: wait for the map, or its notice.
    for (
      var i = 0;
      find.byType(MapCanvas).evaluate().isEmpty &&
          find.textContaining('cannot draw').evaluate().isEmpty;
      i++
    ) {
      expect(i, lessThan(50), reason: 'the map loads');
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pumpAndSettle();
    }
    return turn(tester).exercise as MapExercise;
  }

  /// Where [exercise]'s area is on screen: its label point.
  Offset areaOnScreen(WidgetTester tester, MapExercise exercise) {
    final geometry = exercise.frame.candidates
        .firstWhere((c) => c.id == exercise.nodeId)
        .geometry;
    final view = tester.state<MapCanvasState>(find.byType(MapCanvas)).debugView;
    final world = WebMercator.project(
      LonLat(geometry.labelLon, geometry.labelLat),
    );
    return tester.getTopLeft(find.byType(MapCanvas)) +
        Offset(view.screenX(world.x), view.screenY(world.y));
  }

  Future<ReviewEvent> lastEvent(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.reviewEvents).get()))!.last;

  final locateFirst = FormatRegistry(const [
    FlashcardFormat(),
    McqFormat(),
    _LocateFirst(),
    MapIdentifyFormat(),
  ]);

  testApp('finds an area by tapping it on the map', (tester) async {
    final exercise = await mapCard(tester, locateFirst);
    expect(find.text('Find it on the map'), findsOneWidget, reason: 'badge');
    expect(
      tester.widget<MapCanvas>(find.byType(MapCanvas)).mode,
      MapLabelMode.labelled,
      reason: 'a new item is asked on a labelled map',
    );

    await tester.tapAt(areaOnScreen(tester, exercise));
    await tester.pumpAndSettle();
    expect(find.text('Correct: ${exercise.nodeName}'), findsOneWidget);
    final event = await lastEvent(tester);
    expect(event.knowledgeItemId, exercise.primaryItemId);
    expect(event.rating, 3);
    final payload = jsonDecode(event.answerPayload!) as Map<String, Object?>;
    expect(payload['node'], exercise.nodeId);
    expect(payload['tap'], isA<List<Object?>>());
    expect(payload['frame'], exercise.frame.parent.id);

    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    expect(turn(tester).exercise, isNot(same(exercise)));
  });

  testApp('answers from a list, the accessible mode (GEO-13)', (tester) async {
    final exercise = await mapCard(tester, locateFirst);
    await tap(tester, find.text('Answer from a list'));
    final wrong = exercise.names.entries.firstWhere(
      (e) => e.key != exercise.nodeId,
    );
    await tap(tester, find.widgetWithText(OutlinedButton, wrong.value));
    expect(
      find.text('That is ${wrong.value}. ${exercise.nodeName} is marked.'),
      findsOneWidget,
    );
    final event = await lastEvent(tester);
    expect(event.rating, 1);
    expect(event.selectedNodeId, wrong.key);
    expect(jsonDecode(event.answerPayload!), containsPair('list', true));
  });

  testApp('a map question meets the accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await mapCard(tester, locateFirst);
    await tap(tester, find.text('Answer from a list'));
    for (final guideline in [
      androidTapTargetGuideline,
      labeledTapTargetGuideline,
      textContrastGuideline,
    ]) {
      await expectLater(
        tester,
        meetsGuideline(guideline),
        reason: guideline.description,
      );
    }
    semantics.dispose();
  });

  testApp('answers from the list when this app cannot draw the map '
      '(GEO-30)', (tester) async {
    // As after a downgrade: the database holds a newer appellation layer.
    final exercise = await mapCard(
      tester,
      locateFirst,
      beforeStart: () => db.writeCurriculum(
        () =>
            (db.update(db.mapLayers)
                  ..where((l) => l.id.equals('ml_fr_appellations')))
                .write(MapLayersCompanion(assetSha256: Value('0' * 64))),
      ),
    );
    expect(find.textContaining('cannot draw this map'), findsOneWidget);
    expect(find.byType(MapCanvas), findsNothing);
    await tap(tester, find.text('Answer from a list'));
    await tap(tester, find.widgetWithText(OutlinedButton, exercise.nodeName));
    expect(find.text('Correct: ${exercise.nodeName}'), findsOneWidget);
  });

  testApp('names a highlighted area', (tester) async {
    final exercise = await mapCard(
      tester,
      FormatRegistry(const [
        FlashcardFormat(),
        McqFormat(),
        MapLocateFormat(),
        _IdentifyFirst(),
      ]),
    );
    expect(find.text('Name it on the map'), findsOneWidget, reason: 'badge');
    final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
    expect(canvas.highlights, {exercise.nodeId: MapHighlight.focus});
    expect(canvas.mode, MapLabelMode.outline, reason: 'labels would name it');
    expect(find.byType(OutlinedButton), findsNWidgets(4));

    await tap(tester, find.widgetWithText(OutlinedButton, exercise.nodeName));
    expect(find.text('Correct: ${exercise.nodeName}'), findsOneWidget);
    final event = await lastEvent(tester);
    expect(event.rating, 3);
    expect(event.selectedNodeId, exercise.nodeId);
  });

  testApp('draws each difficulty mode (GEO-8)', (tester) async {
    final exercise = await mapCard(tester, locateFirst);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    );
    final controller = container.read(studySessionProvider.notifier);
    for (final mode in MapMode.values) {
      final current = container.read(studySessionProvider).value!;
      controller.state = AsyncData(
        StudySessionState(
          session: current.session,
          turn: SessionTurn(
            card: current.turn!.card,
            format: current.turn!.format,
            exercise: exercise.inMode(mode),
            shownAt: current.turn!.shownAt,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final canvas = tester.widget<MapCanvas>(find.byType(MapCanvas));
      expect(canvas.mode.name, mode.name);
      expect(canvas.candidates, exercise.candidateIds);
      expect(tester.takeException(), isNull, reason: mode.name);
    }
  });
}
