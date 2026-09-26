import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Short answers at every depth and in every band, ahead of the other
/// formats, so a new item in a pool starts with one.
class _ShortAnswerFirst extends ShortAnswerFormat {
  const _ShortAnswerFirst();

  @override
  int requiredDepth(String direction) => 0;

  @override
  int difficultyRank(String direction) => -3;

  @override
  Set<MemoryBand> preferredBands(String direction) => MemoryBand.values.toSet();
}

/// Backlog Q1: short written answers in a practice session (QF-14).
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  final shortAnswerFirst = FormatRegistry(const [
    FlashcardFormat(),
    McqFormat(),
    _ShortAnswerFirst(),
  ]);
  final answerField = find.widgetWithText(TextField, 'Your answer');

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

  /// Starts a session and answers cards until a short answer is shown.
  Future<ShortAnswerExercise> shortAnswer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db, overrides: servingOnly(shortAnswerFirst));
    await tap(tester, find.text('WSET Level 3'));
    await tester.runAsync(
      () => LearnerProfiles(db).setSessionLimits(sessionSize: 40, newItems: 30),
    );
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));
    for (var i = 0; turn(tester).exercise is! ShortAnswerExercise; i++) {
      expect(i, lessThan(40), reason: 'a short answer in the session');
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
    return turn(tester).exercise as ShortAnswerExercise;
  }

  Future<List<ReviewEvent>> events(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.reviewEvents).get()))!;

  testApp('writes an answer, then ticks the key points it covered', (
    tester,
  ) async {
    final exercise = await shortAnswer(tester);
    expect(find.text('Short answer'), findsOneWidget, reason: 'badge');
    expect(find.text(exercise.prompt), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing, reason: 'not yet');

    const written = 'Its soils, and the grape it is made from.';
    await tester.enterText(answerField, written);
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Check the key points'),
    );
    expect(answerField, findsNothing, reason: 'the answer is final');
    expect(find.text(written), findsOneWidget);
    expect(
      find.text('Tick the key points your answer covered.'),
      findsOneWidget,
    );
    final points = exercise.keyPoints;
    expect(find.byType(CheckboxListTile), findsNWidgets(points.length));

    final ticked = points.first;
    await tap(tester, find.widgetWithText(CheckboxListTile, ticked.title));
    await tap(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(
      find.text('You covered 1 of ${points.length} key points.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.byIcon(Icons.cancel_outlined),
      findsNWidgets(points.length - 1),
    );

    final logged = await events(tester);
    expect(logged, hasLength(points.length));
    expect({for (final e in logged) e.exerciseId}, hasLength(1));
    expect(
      {for (final e in logged) e.knowledgeItemId: e.rating},
      {
        for (final point in points)
          point.itemId: point.itemId == ticked.itemId ? 3 : 1,
      },
    );
    final primary = logged.singleWhere(
      (e) => e.knowledgeItemId == exercise.primaryItemId,
    );
    expect(jsonDecode(primary.answerPayload!), containsPair('text', written));

    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    expect(turn(tester).exercise, isNot(same(exercise)));
  });

  testApp('checks an empty answer: every point is Again', (tester) async {
    final exercise = await shortAnswer(tester);
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Check the key points'),
    );
    expect(find.text('You wrote nothing.'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Done'));
    expect(
      find.text('You covered 0 of ${exercise.keyPoints.length} key points.'),
      findsOneWidget,
    );
    expect((await events(tester)).map((e) => e.rating), everyElement(1));
  });

  testApp('a short answer meets the accessibility guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    await shortAnswer(tester);
    Future<void> check() async {
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
    }

    await check();
    await tester.enterText(answerField, 'Something.');
    await tap(
      tester,
      find.widgetWithText(FilledButton, 'Check the key points'),
    );
    await check();
    await tap(tester, find.widgetWithText(FilledButton, 'Done'));
    await check();
    semantics.dispose();
  });
}
