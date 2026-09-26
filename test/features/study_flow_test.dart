import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> launch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      db,
      overrides: [
        clockProvider.overrideWithValue(
          Clock.fixed(DateTime.utc(2026, 10, 1, 9)),
        ),
        studyRandomProvider.overrideWithValue(Random(1)),
      ],
    );
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<T> query<T>(WidgetTester tester, Future<T> Function() body) async =>
      (await tester.runAsync(body)) as T;

  /// Answers the card on screen correctly.
  Future<void> answerCorrectly(WidgetTester tester) async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    );
    final turn = container.read(studySessionProvider).value!.turn!;
    final question = turn.question;
    if (turn.exercise is TypedQuestion) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Your answer'),
        question.answer.name,
      );
      await tap(tester, find.widgetWithText(FilledButton, 'Check'));
      expect(find.text('Correct: ${question.answer.name}'), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    } else if (question.isMultipleChoice) {
      await tap(
        tester,
        find.widgetWithText(OutlinedButton, question.answer.name),
      );
      expect(find.text('Correct: ${question.answer.name}'), findsOneWidget);
      expect(find.text(question.explanation), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Continue'));
    } else {
      await tap(tester, find.text('Show answer'));
      expect(find.text(question.explanation), findsOneWidget);
      await tap(tester, find.widgetWithText(FilledButton, 'Good'));
    }
  }

  testApp('first launch asks for a certification track', (tester) async {
    await launch(tester);
    expect(find.text('Choose your certification track'), findsOneWidget);
    expect(find.text('WSET Level 3'), findsOneWidget);
    expect(find.text('CMS Certified Sommelier'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);

    await tap(tester, find.text('WSET Level 3'));
    final profile = await query(
      tester,
      () => db.select(db.userProfiles).getSingle(),
    );
    expect(profile.activeCertificationId, 'WSET_L3');
    expect(find.text('Due now'), findsOneWidget);
    expect(find.text('New available'), findsOneWidget);
    expect(find.text('Retention (30 days)'), findsOneWidget);
    expect(
      find.widgetWithText(FloatingActionButton, 'Start session'),
      findsOneWidget,
    );
  });

  testApp('a session from Home: answers grade items and advance the queue '
      '(TASK-006, TASK-007)', (tester) async {
    await launch(tester);
    await tap(tester, find.text('WSET Level 3'));
    await tap(
      tester,
      find.widgetWithText(FloatingActionButton, 'Start session'),
    );

    // The Practice tab shows the first card: a new item.
    expect(find.byType(PracticeScreen), findsOneWidget);
    expect(find.text('New'), findsOneWidget);
    expect(find.text('Unverified'), findsOneWidget);

    await answerCorrectly(tester);
    final events = await query(tester, () => db.select(db.reviewEvents).get());
    expect(events, hasLength(1));
    expect(events.single.rating, 3);
    expect(
      await query(tester, () => db.select(db.reviewStates).get()),
      hasLength(1),
    );

    // New items take two correct answers (learning steps, FS-11): the
    // session ends after ten.
    var answers = 1;
    while (find.textContaining('Session complete').evaluate().isEmpty) {
      await answerCorrectly(tester);
      answers++;
      expect(answers, lessThanOrEqualTo(10));
    }
    expect(answers, 10);
    expect(
      find.text('Session complete: 10 of 10 answers correct across 5 items.'),
      findsOneWidget,
    );
    final states = await query(tester, () => db.select(db.reviewStates).get());
    expect(states, hasLength(5));
    expect(states.map((s) => s.state), everyElement(2));

    await tap(tester, find.text('Done'));
    await tap(tester, find.widgetWithText(NavigationDestination, 'Home'));
    expect(find.textContaining('5 of '), findsOneWidget);
  });

  testApp('a wrong MCQ answer shows the right one', (tester) async {
    await launch(tester);
    await tap(tester, find.text('WSET Level 3'));
    await tap(
      tester,
      find.widgetWithText(FloatingActionButton, 'Start session'),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    );
    final question = container.read(studySessionProvider).value!.turn!.question;
    expect(question.isMultipleChoice, isTrue, reason: 'easiest format first');
    final wrong = question.options.firstWhere((o) => o != question.answer);
    await tap(tester, find.widgetWithText(OutlinedButton, wrong.name));
    expect(find.text('The answer is ${question.answer.name}'), findsOneWidget);
    // The outcome is marked by icons, not by colour alone.
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, question.answer.name),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(OutlinedButton, wrong.name),
        matching: find.byIcon(Icons.cancel),
      ),
      findsOneWidget,
    );
    final event = await query(
      tester,
      () => db.select(db.reviewEvents).getSingle(),
    );
    expect(event.rating, 1);
    expect(event.selectedNodeId, wrong.nodeId);
  });

  testApp('Practice without a track offers the track picker', (tester) async {
    await launch(tester);
    await tap(tester, find.widgetWithText(NavigationDestination, 'Practice'));
    expect(
      find.text('Choose the certification you are studying for.'),
      findsOneWidget,
    );
    await tap(tester, find.text('CMS Certified Sommelier'));
    expect(
      find.textContaining('CMS Certified Sommelier: 0 due'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Start session'), findsOneWidget);
  });

  testApp('Study lists the track by topic, with badges and sources', (
    tester,
  ) async {
    await launch(tester);
    await tap(tester, find.text('WSET Level 3'));
    await tap(tester, find.widgetWithText(NavigationDestination, 'Study'));

    expect(find.textContaining('Geography ·'), findsOneWidget);
    expect(find.byTooltip('Unverified'), findsWidgets);
    expect(find.textContaining('Core · New'), findsWidgets);

    final chablis = await query(
      tester,
      () => (db.select(
        db.knowledgeItems,
      )..where((i) => i.id.equals('ki_chablis_grape'))).getSingle(),
    );
    await tap(tester, find.text(chablis.assertionText));
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Not studied yet.'), findsOneWidget);
    final source = await query(
      tester,
      () => db
          .customSelect(
            'SELECT s.title FROM knowledge_item_citations c '
            'JOIN source_citations s ON s.id = c.source_citation_id '
            "WHERE c.knowledge_item_id = 'ki_chablis_grape'",
          )
          .getSingle(),
    );
    expect(find.text(source.read<String>('title')), findsOneWidget);
  });
}
