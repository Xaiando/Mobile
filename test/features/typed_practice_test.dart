import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/features/practice/formats/typed_view.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Typed recall at every depth and in every band, ahead of the other
/// formats, so a new item starts with it.
class _TypedFirst extends TypedFormat {
  const _TypedFirst();

  @override
  int requiredDepth(String direction) => 0;

  @override
  int difficultyRank(String direction) => -2;

  @override
  Set<MemoryBand> preferredBands(String direction) => MemoryBand.values.toSet();
}

/// Backlog Q1: typed recall in a practice session.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  final typedFirst = FormatRegistry(const [
    FlashcardFormat(),
    McqFormat(),
    _TypedFirst(),
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

  /// Answers the cards on screen until a typed one is shown.
  Future<TypedQuestion> nextTypedCard(WidgetTester tester) async {
    for (var i = 0; turn(tester).exercise is! TypedQuestion; i++) {
      expect(i, lessThan(40), reason: 'a typed card in the session');
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
    return turn(tester).exercise as TypedQuestion;
  }

  Future<TypedQuestion> typedCard(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db, overrides: servingOnly(typedFirst));
    await tap(tester, find.text('WSET Level 3'));
    await tester.runAsync(
      () => LearnerProfiles(db).setSessionLimits(sessionSize: 40, newItems: 30),
    );
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));
    return nextTypedCard(tester);
  }

  Future<ReviewEvent> lastEvent(WidgetTester tester) async =>
      (await tester.runAsync(() => db.select(db.reviewEvents).get()))!.last;

  testApp('types the answer and checks it', (tester) async {
    final question = await typedCard(tester);
    expect(find.text('Type the answer'), findsOneWidget, reason: 'badge');
    expect(find.text(question.prompt), findsOneWidget);
    final check = find.widgetWithText(FilledButton, 'Check');
    expect(
      tester.widget<FilledButton>(check).onPressed,
      isNull,
      reason: 'nothing typed yet',
    );

    await tester.enterText(answerField, question.answer.name.toLowerCase());
    await tester.pump();
    await tap(tester, check);
    expect(find.text('Correct: ${question.answer.name}'), findsOneWidget);
    expect(find.textContaining('You typed'), findsNothing);
    final event = await lastEvent(tester);
    expect(event.knowledgeItemId, question.knowledgeItemId);
    expect(event.rating, 3);
    expect(jsonDecode(event.answerPayload!), {
      'typed': question.answer.name.toLowerCase(),
      'matched': question.answer.name,
      'outcome': 'exact',
    });

    // The next typed card starts with an empty field.
    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    final next = await nextTypedCard(tester);
    expect(next, isNot(same(question)));
    expect(tester.widget<TextField>(answerField).controller!.text, isEmpty);
  });

  testApp('a slip of one letter is Hard', (tester) async {
    final question = await typedCard(tester);
    final name = question.answer.name;
    final slip = name.substring(0, 1) + name.substring(2);
    expect(TypedFormat.outcome(question, slip).$1, TypedOutcome.near);

    await tester.enterText(answerField, slip);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Almost: $name. Check the spelling.'), findsOneWidget);
    expect(find.text('You typed: $slip'), findsOneWidget);
    expect((await lastEvent(tester)).rating, 2);
  });

  testApp('a wrong answer shows the right one', (tester) async {
    final question = await typedCard(tester);
    await tester.enterText(answerField, 'Nothing of the sort');
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));
    expect(find.text('The answer is ${question.answer.name}'), findsOneWidget);
    expect(find.text('You typed: Nothing of the sort'), findsOneWidget);
    expect(
      tester.widget<TextField>(answerField).enabled,
      isFalse,
      reason: 'the answer is final',
    );
    expect((await lastEvent(tester)).rating, 1);
  });

  testApp('a typed question meets the accessibility guidelines', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await typedCard(tester);
    await tester.enterText(answerField, 'Something');
    await tester.pumpAndSettle();
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

  testWidgets('the feedback names the answer for each outcome', (tester) async {
    const question = TypedQuestion(
      knowledgeItemId: 'ki_chablis_frost',
      questionTemplateId: 'qt_hazard_fwd_typed',
      direction: 'forward',
      mode: 'typed',
      prompt: 'Which vineyard hazard is a notable risk in Chablis?',
      answer: QuestionOption('n_hazard_spring_frost', 'Spring frost'),
      explanation: 'Chablis has a high risk of spring frost.',
      seed: 1,
      accepted: {'spring frost': 'Spring frost'},
      rivals: {'chalk'},
      typeWords: {'vineyard', 'vineyards', 'hazard', 'hazards'},
    );
    for (final (typed, heading) in [
      ('Spring frost', 'Correct: Spring frost'),
      ('sprng frost', 'Almost: Spring frost. Check the spelling.'),
      ('frost', 'Almost: the full answer is Spring frost.'),
      ('chalk', 'The answer is Spring frost'),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypedFeedback(question, typed: typed)),
        ),
      );
      expect(find.text(heading), findsOneWidget, reason: typed);
      expect(
        find.text('You typed: $typed'),
        typed == 'Spring frost' ? findsNothing : findsOneWidget,
      );
      expect(find.text(question.explanation), findsOneWidget);
    }
  });
}
