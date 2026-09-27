import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/formats/numeric/numeric_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/study_session.dart';
import 'package:sommelier/features/practice/formats/numeric_view.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../../support/app_fixture.dart';

NumericQuestion _question({
  double minimum = 20,
  double? maximum,
  String canonicalUnit = '°C',
  String displayUnit = '°C',
  String relationType = 'TYPICAL_TEMPERATURE',
  double tolerance = 0,
}) => NumericQuestion(
  knowledgeItemId: 'ki_numeric_ui_fixture',
  questionTemplateId: 'qt_numeric_ui_fixture',
  prompt: 'What quantity is stated in this cited example?',
  answer: const QuestionOption('n_numeric_ui_target', 'Hidden quantity target'),
  explanation:
      'The cited example supplies this quantity under its stated conditions.',
  seed: 29,
  relationType: relationType,
  canonicalMinimum: minimum,
  canonicalMaximum: maximum,
  canonicalUnit: canonicalUnit,
  displayUnit: displayUnit,
  tolerance: tolerance,
);

SessionTurn _turn(NumericQuestion question) {
  final item = KnowledgeItem(
    id: question.knowledgeItemId,
    subjectId: 'n_numeric_ui_subject',
    relationType: question.relationType,
    objectId: question.answer.nodeId,
    domainId: 'winemaking',
    assertionText: question.explanation,
    revision: 1,
    lastVerifiedAt: DateTime.utc(2026, 9, 27),
    verificationStatus: 'unverified',
    isDistinctive: false,
    mcqDisabled: true,
  );
  const format = QuestionFormat(
    questionTemplateId: 'qt_numeric_ui_fixture',
    direction: 'forward',
    mode: 'numeric',
    format: NumericFormat(),
  );
  return SessionTurn(
    card: StudyCard(
      item: item,
      mapping: EffectiveMapping(
        knowledgeItemId: item.id,
        certificationId: 'WSET_L4',
        importance: 'core',
        minimumDepth: 3,
        chainDepth: 0,
      ),
      formats: const [format],
      state: null,
      retrievability: 0,
      priority: null,
      isStale: false,
    ),
    format: format,
    exercise: question,
    shownAt: DateTime.utc(2026, 9, 27),
  );
}

ReviewResult _result(NumericQuestion question, ItemGrade grade) {
  final now = DateTime.utc(2026, 9, 27);
  final after = ReviewState(
    knowledgeItemId: grade.itemId,
    state: 2,
    stability: 10,
    difficulty: 5,
    due: now.add(const Duration(days: 1)),
    lastReview: now,
    reps: 1,
    lapses: 0,
  );
  return ReviewResult(
    event: ReviewEvent(
      id: 'fixture-${grade.itemId}',
      knowledgeItemId: grade.itemId,
      questionTemplateId: question.questionTemplateId,
      reviewedAt: now,
      rating: grade.rating.value,
      seed: question.seed,
      schedulerConfigVersion: 1,
      stateAfter: after.state,
      stabilityAfter: after.stability,
      difficultyAfter: after.difficulty,
      dueAfter: after.due,
    ),
    before: null,
    after: after,
  );
}

/// Captures view submissions; core tests cover real review persistence.
/// Deliberately has no duplicate-submit guard, so the view's guard is tested.
class _ViewController extends StudySessionController {
  _ViewController(this.question, {this.submissionGate});

  final NumericQuestion question;
  final Completer<void>? submissionGate;
  final submitted = <NumericAnswer>[];
  var continued = false;

  @override
  Future<StudySessionState?> build() async {
    final turn = _turn(question);
    return StudySessionState(
      session: StudySession(
        StudyPlan(
          certificationId: 'WSET_L4',
          cards: [turn.card],
          dueCount: 0,
          newAvailable: 1,
        ),
      ),
      turn: turn,
    );
  }

  @override
  Future<void> submit(Object answer) async {
    submitted.add(answer as NumericAnswer);
    await submissionGate?.future;
    final current = state.value!;
    final results = const NumericFormat()
        .grade(question, answer)
        .map((grade) => _result(question, grade))
        .toList();
    state = AsyncData(
      StudySessionState(
        session: current.session,
        turn: current.turn!.copyWith(
          answer: answer,
          results: results,
          revealed: true,
        ),
      ),
    );
  }

  @override
  Future<void> next() async {
    continued = true;
    state = AsyncData(
      StudySessionState(session: state.value!.session, turn: null),
    );
  }
}

class _ViewHarness extends ConsumerWidget {
  const _ViewHarness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(studySessionProvider).value;
    if (current == null) return const SizedBox.shrink();
    if (current.turn == null) return const Text('Fixture continued');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(current.turn!.exercise.prompt),
        const SizedBox(height: 16),
        NumericView(current.turn!),
      ],
    );
  }
}

void main() {
  Future<_ViewController> pump(
    WidgetTester tester,
    NumericQuestion question, {
    Completer<void>? submissionGate,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = _ViewController(
      question,
      submissionGate: submissionGate,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studySessionProvider.overrideWith(() => controller)],
        child: const MaterialApp(home: Scaffold(body: _ViewHarness())),
      ),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testApp(
    'shows the preferred unit and single input without leaking a target',
    (tester) async {
      final question = _question(displayUnit: '°F');
      final controller = await pump(tester, question);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.suffixText, '°F');
      expect(
        field.keyboardType,
        const TextInputType.numberWithOptions(decimal: true, signed: true),
      );
      expect(field.textInputAction, TextInputAction.done);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text(question.displayAnswer), findsNothing);
      expect(find.text(question.answer.name), findsNothing);
      expect(find.text(question.explanation), findsNothing);
      expect(find.byType(NumericFeedback), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check'))
            .onPressed,
        isNull,
      );
      expect(controller.submitted, isEmpty);
    },
  );

  testApp('invalid text never submits or reveals feedback', (tester) async {
    final question = _question();
    final controller = await pump(tester, question);
    for (final text in ['twenty', '1,000', '20 C rubbish', 'NaN', 'Infinity']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      await tap(tester, find.widgetWithText(FilledButton, 'Check'));
      expect(
        find.text('Enter a valid number using a decimal point.'),
        findsOneWidget,
      );
      expect(controller.submitted, isEmpty);
      expect(find.byType(NumericFeedback), findsNothing);
      expect(find.text('Continue'), findsNothing);
      expect(find.text(question.explanation), findsNothing);
    }
  });

  testApp(
    'keyboard and repeated check submit once, then show grade and continue',
    (tester) async {
      final question = _question(displayUnit: '°F');
      final gate = Completer<void>();
      final controller = await pump(tester, question, submissionGate: gate);
      await tester.enterText(find.byType(TextField), '68');
      await tester.pump();
      final checkAgain = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check'))
          .onPressed!;
      final submitAgain = tester
          .widget<TextField>(find.byType(TextField))
          .onSubmitted!;
      await tester.testTextInput.receiveAction(TextInputAction.done);
      checkAgain();
      await tester.pump();
      expect(controller.submitted, hasLength(1));
      expect(controller.submitted.single.minimum, 68);
      expect(controller.submitted.single.unit, '°F');
      expect(controller.submitted.single.isInterval, isFalse);
      expect(find.text('Checking…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.byType(NumericFeedback), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Correct'), findsOneWidget);
      expect(find.text('Target: ${question.displayAnswer}'), findsOneWidget);
      expect(find.text('You entered: 68 °F'), findsOneWidget);
      expect(find.text('Review grade: Good'), findsOneWidget);
      expect(find.text(question.explanation), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      submitAgain('68');
      checkAgain();
      await tester.pump();
      expect(controller.submitted, hasLength(1));
      await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
      expect(controller.continued, isTrue);
      expect(find.text('Fixture continued'), findsOneWidget);
    },
  );

  testApp('a genuine range has explicit controls and rejects reversed bounds', (
    tester,
  ) async {
    final question = _question(minimum: 18, maximum: 22);
    final controller = await pump(tester, question);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Target range: ${question.displayAnswer}'), findsNothing);
    await tap(tester, find.byType(SwitchListTile));
    expect(find.byType(TextField), findsNWidgets(2));
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.decoration!.suffixText, '°C');
    }
    await tester.enterText(find.byType(TextField).at(0), '22');
    await tester.enterText(find.byType(TextField).at(1), '18');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));
    expect(
      find.text('The lower value must not exceed the upper value.'),
      findsOneWidget,
    );
    expect(controller.submitted, isEmpty);
    await tester.enterText(find.byType(TextField).at(0), '18');
    await tester.enterText(find.byType(TextField).at(1), '22');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));
    expect(controller.submitted, hasLength(1));
    expect(controller.submitted.single.isInterval, isTrue);
    expect(controller.submitted.single.minimum, 18);
    expect(controller.submitted.single.maximum, 22);
    expect(find.text('Correct'), findsOneWidget);
    expect(
      find.text('Target range: ${question.displayAnswer}'),
      findsOneWidget,
    );
    expect(find.text('Review grade: Good'), findsOneWidget);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      isNull,
    );
    for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
      expect(field.enabled, isFalse);
    }
  });

  testApp('a legal minimum never offers or accepts a range input', (
    tester,
  ) async {
    final question = _question(
      minimum: 12,
      maximum: 24,
      canonicalUnit: 'year',
      displayUnit: 'year',
      relationType: 'MIN_AGEING',
    );
    final controller = await pump(tester, question);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '12 to 24');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));
    expect(find.text('Enter one number for this question.'), findsOneWidget);
    expect(controller.submitted, isEmpty);
    expect(find.byType(NumericFeedback), findsNothing);
    await tester.enterText(find.byType(TextField), '12');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));
    expect(find.text('Target: ${question.displayAnswer}'), findsOneWidget);
    expect(find.text('Correct'), findsOneWidget);
  });

  testApp('feedback handles raw text and invalid nonfinite answers safely', (
    tester,
  ) async {
    final question = _question();
    for (final (answer, heading, entered, grade)
        in <(Object, String, String, String)>[
          ('20', 'Correct', '20 °C', 'Good'),
          ('Infinity', 'Not correct', 'Invalid numeric input', 'Again'),
          (
            const NumericAnswer.scalar(double.infinity, unit: '°C'),
            'Not correct',
            'Invalid numeric input',
            'Again',
          ),
        ]) {
      final results = const NumericFormat()
          .grade(question, answer)
          .map((itemGrade) => _result(question, itemGrade))
          .toList();
      final turn = _turn(question).copyWith(answer: answer, results: results);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: NumericFeedback(turn))),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(heading), findsOneWidget);
      expect(find.text('You entered: $entered'), findsOneWidget);
      expect(find.text('Review grade: $grade'), findsOneWidget);
      expect(find.text('Target: ${question.displayAnswer}'), findsOneWidget);
      expect(find.text(question.explanation), findsOneWidget);
    }
  });

  for (final (typed, heading, grade) in [
    ('20.5', 'Close', 'Hard'),
    ('30', 'Not correct', 'Again'),
  ]) {
    testApp('shows $heading numeric feedback with its review grade', (
      tester,
    ) async {
      final question = _question(tolerance: 1);
      final controller = await pump(tester, question);
      await tester.enterText(find.byType(TextField), typed);
      await tester.pump();
      await tap(tester, find.widgetWithText(FilledButton, 'Check'));
      expect(controller.submitted, hasLength(1));
      expect(find.text(heading), findsOneWidget);
      expect(find.text('Review grade: $grade'), findsOneWidget);
      expect(find.text('Target: ${question.displayAnswer}'), findsOneWidget);
      expect(find.text(question.explanation), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });
  }
}
