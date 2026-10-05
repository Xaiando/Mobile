import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/questions/exercise.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/study_explorer.dart';
import 'package:sommelier/core/study/study_explorer_providers.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/features/study/study_explorer_screen.dart';
import 'package:sommelier/app/learner_state.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

class _Explorer extends StudyExplorer {
  _Explorer(super.db);
  @override
  Future<Exercise> present(
    StudyTopic topic,
    StudyCard card,
    QuestionFormat format, {
    required int seed,
  }) async => PresentedQuestion(
    knowledgeItemId: card.itemId,
    questionTemplateId: format.questionTemplateId,
    direction: 'forward',
    mode: 'mcq',
    prompt: 'Which grape is used in Chablis?',
    answer: const QuestionOption('chardonnay', 'Chardonnay'),
    options: const [
      QuestionOption('riesling', 'Riesling'),
      QuestionOption('chardonnay', 'Chardonnay'),
    ],
    explanation: card.item.assertionText,
    seed: seed,
  );
}

void main() {
  late AppDatabase db;
  late StudyCard card;
  late List<StudyTopic> topics;
  setUp(() {
    db = openTestDatabase();
    card = StudyCard(
      item: KnowledgeItem(
        id: 'ki_test',
        subjectId: 'chablis',
        relationType: 'PERMITS_PRINCIPAL_GRAPE',
        objectId: 'chardonnay',
        domainId: 'geography',
        assertionText: 'Chablis is made from Chardonnay.',
        revision: 1,
        isDistinctive: false,
        lastVerifiedAt: t0,
        verificationStatus: 'unverified',
        mcqDisabled: false,
      ),
      mapping: const EffectiveMapping(
        knowledgeItemId: 'ki_test',
        certificationId: 'WSET_L2',
        importance: 'core',
        minimumDepth: 1,
        chainDepth: 0,
      ),
      formats: const [
        QuestionFormat(
          questionTemplateId: 'qt_test',
          direction: 'forward',
          mode: 'mcq',
        ),
      ],
      retrievability: 0,
      state: null,
      priority: null,
      isStale: false,
    );
    topics = [
      StudyTopic(
        id: 'grapes-pinot',
        category: StudyCategory.grapes,
        title: 'Pinot Noir',
        subtitle: 'Core reference',
        aliases: ['Spätburgunder', 'Pinot Nero'],
        trackId: 'WSET_L4',
        cards: [card],
        mapCards: [],
      ),
      StudyTopic(
        id: 'wines-chablis',
        category: StudyCategory.wines,
        title: 'Chablis',
        subtitle: 'WSET Levels 1–2',
        trackId: 'WSET_L2',
        cards: [card],
        mapCards: [],
      ),
      StudyTopic(
        id: 'wines-soave',
        category: StudyCategory.wines,
        title: 'Soave',
        subtitle: 'WSET Levels 1–2',
        trackId: 'WSET_L2',
        cards: [card],
        mapCards: [],
      ),
    ];
  });
  tearDown(() => db.close());

  Future<void> pump(
    WidgetTester tester, {
    String route = '/study/explore',
  }) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: route,
      routes: [
        GoRoute(
          path: '/study/explore',
          builder: (_, state) => const StudyExplorerScreen(),
          routes: [
            GoRoute(
              path: ':category',
              builder: (_, state) => StudyExplorerScreen(
                category: state.pathParameters['category'],
              ),
              routes: [
                GoRoute(
                  path: ':topic',
                  builder: (_, state) => StudyTopicScreen(
                    category: state.pathParameters['category']!,
                    topicId: state.pathParameters['topic']!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          studyTopicsProvider.overrideWith((ref) async => topics),
          studyExplorerProvider.overrideWithValue(_Explorer(db)),
          itemSourcesProvider.overrideWith((ref, id) async => []),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testApp('four entrances, synonym search and back navigation at 320px', (
    tester,
  ) async {
    await pump(tester);
    for (final category in StudyCategory.values) {
      expect(find.byKey(ValueKey('explore-${category.name}')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('explore-grapes')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('explore-search')),
      'spatburgunder',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pinot Noir'));
    await tester.pumpAndSettle();
    expect(
      find.text('Also known as: Spätburgunder, Pinot Nero'),
      findsOneWidget,
    );
    expect(find.text('Chablis is made from Chardonnay.'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Pinot Noir'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('flashcard reveals, quiz grades and no map is explained', (
    tester,
  ) async {
    await pump(tester, route: '/study/explore/wines/wines-chablis');
    await tester.tap(find.text('Flashcards'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('explore-explanation')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('explore-reveal')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('explore-answer')), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-explanation')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('explore-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('explore-explanation')), findsNothing);
    await tester.tap(find.text('Maps'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No exercises of this kind'), findsOneWidget);
    await tester.tap(find.text('Questions'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('explore-option-riesling')));
    await tester.pumpAndSettle();
    expect(find.text('Review the answer'), findsOneWidget);
    expect(find.text('Answer: Chardonnay'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('explore-next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('explore-option-chardonnay')));
    await tester.pumpAndSettle();
    expect(find.text('Correct'), findsOneWidget);
    final router = GoRouter.of(tester.element(find.byType(StudyTopicScreen)));
    router.go('/study/explore/wines/wines-soave');
    await tester.pumpAndSettle();
    expect(find.text('Soave'), findsOneWidget);
    expect(
      DefaultTabController.of(tester.element(find.byType(TabBar))).index,
      0,
    );
    expect(find.byKey(const ValueKey('explore-fact-ki_test')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('unknown links and empty searches are recoverable', (tester) async {
    await pump(tester, route: '/study/explore/wines/unknown');
    expect(
      find.text('This study topic is no longer available.'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('explore-search')),
      'unrelated_9349',
    );
    await tester.pumpAndSettle();
    expect(find.text('No topics match this search.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Chablis'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
