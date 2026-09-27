import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/formats/reasoning/reasoning_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/study_session.dart';
import 'package:sommelier/features/practice/formats/option_button.dart';
import 'package:sommelier/features/practice/formats/reasoning_view.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../../support/app_fixture.dart';

const _source = ReasoningSource(
  sourceId: 'src_reasoning_ui_fixture',
  title: 'Primary fixture reference',
  publisher: 'Fixture research body',
  url: 'https://example.com/primary-reference',
  locator: 'Results, page 3',
);
const _support = ReasoningEvidence(
  itemId: 'ki_reasoning_ui_support',
  title: 'The supplied condition',
  statement: 'The premise supplies the condition used by this explanation.',
  sources: [_source],
);
const _middle = ReasoningEvidence(
  itemId: 'ki_reasoning_ui_middle',
  title: 'The supported mechanism',
  statement: 'The stated mechanism connects the condition to its consequence.',
  sources: [_source],
);
const _target = ReasoningEvidence(
  itemId: 'ki_reasoning_ui_target',
  title: 'The supported consequence',
  statement: 'This conclusion follows under the conditions in the premise.',
  sources: [_source],
);
const _contrastEvidence = ReasoningEvidence(
  itemId: 'ki_reasoning_ui_contrast',
  title: 'Evidence explaining a ruled-out choice',
  statement: 'The alternative requires a condition explicitly excluded here.',
  sources: [_source],
);
const _directionEvidence = ReasoningEvidence(
  itemId: 'ki_reasoning_ui_contrast_direction',
  title: 'The direction of the supplied mechanism',
  statement: 'The stated causal direction rules out the reversed effect.',
  sources: [_source],
);
const _correct = QuestionOption(
  'n_reasoning_ui_answer',
  'Supported consequence',
);
const _wrong = QuestionOption('n_reasoning_ui_wrong', 'Excluded consequence');
const _exercise = ReasoningExercise(
  primaryItemId: 'ki_reasoning_ui_target',
  questionTemplateId: 'qt_reasoning_ui_fixture',
  prompt: 'Under these supplied conditions, which consequence is supported?',
  seed: 19,
  premiseNodeId: 'n_reasoning_ui_premise',
  chain: [
    'ki_reasoning_ui_support',
    'ki_reasoning_ui_middle',
    'ki_reasoning_ui_target',
  ],
  options: [
    _wrong,
    _correct,
    QuestionOption('n_reasoning_ui_other', 'Another excluded consequence'),
    QuestionOption('n_reasoning_ui_reverse', 'Reversed consequence'),
  ],
  answer: _correct,
  chainEvidence: [_support, _middle, _target],
  contrasts: [
    ReasoningContrastExplanation(
      option: _wrong,
      statement: 'This choice contradicts the explicitly supplied condition.',
      evidence: [_contrastEvidence],
    ),
    ReasoningContrastExplanation(
      option: QuestionOption('n_reasoning_ui_reverse', 'Reversed consequence'),
      statement: 'This choice reverses the explicitly supplied mechanism.',
      evidence: [_directionEvidence],
    ),
    ReasoningContrastExplanation(
      option: QuestionOption(
        'n_reasoning_ui_other',
        'Another excluded consequence',
      ),
      statement: 'This choice requires a mechanism outside the stated premise.',
      evidence: [_contrastEvidence],
    ),
  ],
);

SessionTurn _turn() {
  final item = KnowledgeItem(
    id: _target.itemId,
    subjectId: 'n_reasoning_ui_mechanism',
    relationType: 'REASONING_UI_CONSEQUENCE',
    objectId: _correct.nodeId,
    domainId: 'winemaking',
    assertionText: _target.statement,
    revision: 1,
    lastVerifiedAt: DateTime.utc(2026, 9, 27),
    verificationStatus: 'unverified',
    isDistinctive: false,
    mcqDisabled: false,
  );
  const format = QuestionFormat(
    questionTemplateId: 'qt_reasoning_ui_fixture',
    direction: 'forward',
    mode: 'reasoning',
    format: ReasoningFormat(),
  );
  return SessionTurn(
    card: StudyCard(
      item: item,
      mapping: EffectiveMapping(
        knowledgeItemId: item.id,
        certificationId: 'WSET_L4',
        importance: 'core',
        minimumDepth: 4,
        chainDepth: 0,
      ),
      formats: const [format],
      state: null,
      retrievability: 0,
      priority: null,
      isStale: false,
    ),
    format: format,
    exercise: _exercise,
    shownAt: DateTime.utc(2026, 9, 27),
  );
}

ReviewResult _result(ItemGrade grade) {
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
      questionTemplateId: _exercise.questionTemplateId,
      reviewedAt: now,
      rating: grade.rating.value,
      seed: _exercise.seed,
      selectedNodeId: grade.selectedNodeId,
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

/// Captures the UI contract. Persistence is tested through the real service
/// in the core reasoning tests, rather than emulated by this view fixture.
class _ViewController extends StudySessionController {
  Object? submitted;
  var continued = false;

  @override
  Future<StudySessionState?> build() async {
    final turn = _turn();
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
    submitted = answer;
    final current = state.value!;
    final results = const ReasoningFormat()
        .grade(_exercise, answer)
        .map(_result)
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
        ReasoningView(current.turn!),
      ],
    );
  }
}

void main() {
  Future<_ViewController> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final controller = _ViewController();
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

  testApp('offers choices without leaking the chain or its sources', (
    tester,
  ) async {
    final controller = await pump(tester);
    expect(find.text(_exercise.prompt), findsOneWidget);
    expect(find.byType(OptionButton), findsNWidgets(4));
    for (final evidence in _exercise.chainEvidence) {
      expect(find.text(evidence.statement), findsNothing);
    }
    expect(find.text(_source.title), findsNothing);
    for (final contrast in _exercise.contrasts) {
      expect(find.text(contrast.statement), findsNothing);
      for (final evidence in contrast.evidence) {
        expect(find.text(evidence.statement), findsNothing);
      }
    }
    expect(find.text('The reasoning chain'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.text('Continue'), findsNothing);

    await tap(tester, find.widgetWithText(OutlinedButton, _correct.name));
    expect(controller.submitted, _correct);
    expect(find.text('Correct: ${_correct.name}'), findsOneWidget);
    expect(
      find.text('All 3 learning points were reviewed as recalled.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_circle), findsWidgets);
  });

  testApp('shows the complete cited chain and explanation-only contrasts', (
    tester,
  ) async {
    await pump(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, _correct.name));
    final chain = find.byKey(ValueKey('reasoning-chain-${_target.itemId}'));
    await tester.ensureVisible(chain);
    await tester.pumpAndSettle();
    for (final evidence in _exercise.chainEvidence) {
      expect(
        find.byKey(ValueKey('reasoning-chain-${evidence.itemId}')),
        findsOneWidget,
      );
    }
    final positions = [
      for (final evidence in _exercise.chainEvidence)
        tester
            .getTopLeft(
              find.byKey(ValueKey('reasoning-chain-${evidence.itemId}')),
            )
            .dy,
    ];
    expect(positions[0], lessThan(positions[1]));
    expect(positions[1], lessThan(positions[2]));
    expect(
      find.descendant(of: chain, matching: find.text(_target.statement)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: chain, matching: find.text(_source.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chain,
        matching: find.text('Fixture research body · Results, page 3'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chain,
        matching: find.widgetWithText(SelectableText, _source.url!),
      ),
      findsOneWidget,
    );
    for (final contrast in _exercise.contrasts) {
      await tester.ensureVisible(find.text(contrast.statement));
      await tester.pumpAndSettle();
      expect(find.text(contrast.statement), findsOneWidget);
    }
    expect(find.text('Explanation only'), findsWidgets);
    for (final contrast in _exercise.contrasts) {
      for (final evidence in contrast.evidence) {
        expect(
          find.byKey(ValueKey('reasoning-chain-${evidence.itemId}')),
          findsNothing,
        );
      }
    }
    for (final option in tester.widgetList<OutlinedButton>(
      find.byType(OutlinedButton),
    )) {
      expect(option.onPressed, isNull);
    }
  });

  testApp('a wrong choice grades only the conclusion and can continue', (
    tester,
  ) async {
    final controller = await pump(tester);
    await tap(tester, find.widgetWithText(OutlinedButton, _wrong.name));
    expect(controller.submitted, _wrong);
    expect(
      find.text('The supported answer is ${_correct.name}'),
      findsOneWidget,
    );
    expect(
      find.text(
        'The final learning point needs another review. '
        'Supporting points were not graded.',
      ),
      findsOneWidget,
    );
    expect(find.text('1. Supporting point · not graded'), findsOneWidget);
    expect(find.text('2. Supporting point · not graded'), findsOneWidget);
    expect(find.text('3. Final learning point'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);

    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    expect(controller.continued, isTrue);
    expect(find.text('Fixture continued'), findsOneWidget);
    expect(find.byType(ReasoningView), findsNothing);
  });

  testApp('choices and long cited feedback are accessible on a narrow screen', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await pump(tester);
      for (final guideline in [
        androidTapTargetGuideline,
        labeledTapTargetGuideline,
        textContrastGuideline,
      ]) {
        await expectLater(tester, meetsGuideline(guideline));
      }
      await tap(tester, find.widgetWithText(OutlinedButton, _wrong.name));
      await tester.ensureVisible(
        find.byKey(ValueKey('reasoning-chain-${_target.itemId}')),
      );
      await tester.pumpAndSettle();
      for (final guideline in [
        androidTapTargetGuideline,
        labeledTapTargetGuideline,
        textContrastGuideline,
      ]) {
        await expectLater(tester, meetsGuideline(guideline));
      }
      expect(tester.takeException(), isNull);
      await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
}
