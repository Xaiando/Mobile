import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_providers.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_providers.dart';
import 'package:sommelier/features/practice/format_views.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';
import '../support/pair_format.dart';

/// Backlog F3: a format added with one registry line per layer runs in a
/// practice session, end to end.
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

  testApp('practises the test-only pair format through its own view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      db,
      overrides: [
        formatRegistryProvider.overrideWithValue(pairFormats),
        formatViewsProvider.overrideWithValue(pairViews),
        curriculumSourceProvider.overrideWithValue(
          () async => datasetOf(datasetWithPairs()),
        ),
      ],
    );
    await tap(tester, find.text('WSET Level 3'));
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    await tap(tester, find.widgetWithText(FilledButton, 'Start session'));

    SessionTurn turn() =>
        ProviderScope.containerOf(tester.element(find.byType(PracticeScreen)))
            .read(studySessionProvider)
            .value!
            .turn!;

    // A new item starts with its easiest format, here the pair; an item
    // whose relation type has no pool is answered and passed.
    for (var i = 0; turn().exercise is! PairExercise; i++) {
      expect(i, lessThan(10), reason: 'a pair exercise within ten cards');
      final question = turn().question;
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

    final pair = turn().exercise as PairExercise;
    expect(find.text('Pair'), findsOneWidget, reason: "the format's badge");
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tap(tester, find.text(pair.statements[pair.primaryItemId]!));
    await tap(tester, find.widgetWithText(FilledButton, 'Check'));

    final events = await tester.runAsync(
      () => (db.select(
        db.reviewEvents,
      )..where((e) => e.exerciseId.isNotNull())).get(),
    );
    expect(
      {for (final e in events!) e.knowledgeItemId: e.rating},
      {pair.primaryItemId: 3, pair.coItemId: 1},
    );
    expect(events.map((e) => e.exerciseId).toSet(), hasLength(1));
    final session = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    ).read(studySessionProvider).value!.session;
    expect(session.bonus, 1);

    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    expect(turn().exercise, isNot(same(pair)));
  });
}
