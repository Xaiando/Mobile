import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/rehearsal/rehearsal_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/rehearsal/rehearsal_screen.dart';

import '../../core/rehearsal/rehearsal_fixture.dart';
import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late RehearsalRepository repository;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE certifications SET is_selectable=1 WHERE id IN ('WSET_L1','WSET_L2')",
        "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L1','ki_chablis_grape','core',1,NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1');
    repository = RehearsalRepository(
      db,
      bank: rehearsalFixtureBank(),
      clock: time.clock,
      random: Random(5),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screen(
    WidgetTester tester, {
    double scale = 1,
    int? initialLevel,
  }) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          rehearsalRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: RehearsalScreen(initialLevel: initialLevel),
        ),
      ),
    );
    await settle(tester);
  }

  testApp('phone setup clearly labels original timed practice', (tester) async {
    await screen(tester, scale: 2);
    expect(
      find.textContaining('not official examination questions'),
      findsOneWidget,
    );
    expect(find.text('30 questions · 45 minutes'), findsOneWidget);
    expect(find.byKey(const ValueKey('rehearsal-start')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('unreadable history is visible while a readable draft can resume', (
    tester,
  ) async {
    final valid = (await tester.runAsync(() => repository.start(1)))!;
    await tester.runAsync(() => repository.resetCurrentPointer());
    await tester.runAsync(
      () => db
          .into(db.userSettings)
          .insertOnConflictUpdate(
            UserSetting(
              name: '${RehearsalRepository.attemptPrefix}broken',
              value: '{invalid',
              updatedAt: time.now,
            ),
          ),
    );
    await screen(tester);
    expect(
      find.byKey(const ValueKey('rehearsal-history-warning')),
      findsOneWidget,
    );
    expect(
      find.textContaining('1 saved practice record could not be read'),
      findsOneWidget,
    );
    final tile = find.byKey(ValueKey('rehearsal-history-${valid.id}'));
    await tester.scrollUntilVisible(tile, 400, maxScrolls: 30);
    await tester.tap(tile);
    await settle(tester);
    expect((await tester.runAsync(() => repository.current()))!.id, valid.id);
    expect(
      find.byKey(const ValueKey('rehearsal-history-warning')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testApp('a progress link opens the requested level before starting', (
    tester,
  ) async {
    await screen(tester, initialLevel: 2);
    expect(find.text('50 questions · 60 minutes'), findsOneWidget);
    expect(find.text('Start Level 2 practice'), findsOneWidget);
    expect((await tester.runAsync(() => repository.current())), isNull);
  });

  testApp(
    'a saved written response can honestly record zero supported criteria',
    (tester) async {
      await tester.runAsync(
        () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
      );
      final attempt = (await tester.runAsync(() => repository.start(3)))!;
      final question = attempt.written.first;
      await tester.runAsync(
        () => repository.answerWritten(
          attempt.id,
          question.id,
          'My original response does not yet explain the required mechanism.',
        ),
      );
      await tester.runAsync(() => repository.finish(attempt.id));
      await screen(tester);
      final reviewed = find.byKey(
        ValueKey('rehearsal-reviewed-${question.id}'),
      );
      await tester.scrollUntilVisible(
        reviewed,
        600,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 100,
      );
      await tester.tap(reviewed);
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.current()))!;
      expect(saved.selfAssessment.containsKey(question.id), isTrue);
      expect(saved.selfAssessment[question.id], isEmpty);
      expect(saved.prose[question.id], contains('My original response'));
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testApp('feedback is deferred until completion and answers persist', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start(1)))!;
    await screen(tester);
    final question = attempt.mcqs.first;
    expect(find.text(question.explanation), findsNothing);
    expect(find.byKey(const ValueKey('rehearsal-score')), findsNothing);
    final answer = question.options.singleWhere(
      (o) => o.id == question.correctOptionId,
    );
    await tester.tap(find.text(answer.text));
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.current()))!.answers[question.id],
      question.correctOptionId,
    );
    final finish = find.byKey(const ValueKey('rehearsal-finish'));
    await tester.scrollUntilVisible(finish, 600, maxScrolls: 100);
    await tester.tap(finish);
    await settle(tester);
    expect(find.byKey(const ValueKey('rehearsal-timer')), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rehearsal-score')),
      -600,
      maxScrolls: 100,
    );
    expect(find.text('Original practice: 1 of 30 correct'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(question.explanation),
      300,
      maxScrolls: 20,
    );
    expect(find.text(question.explanation), findsOneWidget);
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testApp('a resumed attempt keeps its deadline and expires on screen', (
    tester,
  ) async {
    await tester.runAsync(() => repository.start(1));
    time.advance(const Duration(minutes: 44));
    await screen(tester);
    expect(find.text('Time remaining: 1:00'), findsOneWidget);
    time.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Original practice: 0 of 30 correct'), findsOneWidget);
    expect(
      (await tester.runAsync(() => repository.current()))!.finishReason,
      'expired',
    );
    expect(find.byKey(const ValueKey('rehearsal-timer')), findsNothing);
  });

  testApp('written text is saved while criteria remain hidden until finish', (
    tester,
  ) async {
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
    );
    final attempt = (await tester.runAsync(() => repository.start(3)))!;
    await screen(tester);
    final question = attempt.written.first;
    final field = find.byKey(ValueKey('rehearsal-written-${question.id}'));
    await tester.scrollUntilVisible(field, 600, maxScrolls: 100);
    expect(find.text(question.criteria.first.text), findsNothing);
    await tester.enterText(
      field,
      'An evidence-based explanation saved as a draft.',
    );
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.current()))!.prose[question.id],
      'An evidence-based explanation saved as a draft.',
    );
    expect(tester.takeException(), isNull);
  });

  testApp('opening history persists the selected draft across screen restart', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start(1)))!;
    await tester.runAsync(() => repository.resetCurrentPointer());
    time.advance(const Duration(minutes: 10));
    await screen(tester);
    await tester.tap(find.byKey(ValueKey('rehearsal-history-${attempt.id}')));
    await settle(tester);
    expect(find.text('Time remaining: 35:00'), findsOneWidget);
    expect((await tester.runAsync(() => repository.current()))!.id, attempt.id);
    await tester.pumpWidget(const SizedBox.shrink());
    await screen(tester);
    expect(find.text('Time remaining: 35:00'), findsOneWidget);
    expect(find.byKey(const ValueKey('rehearsal-start')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testApp('finished history exit preserves a draft selected by another caller', (
    tester,
  ) async {
    final finished = (await tester.runAsync(() => repository.start(1)))!;
    await tester.runAsync(() => repository.finish(finished.id));
    await tester.runAsync(() => repository.leaveFinished(finished.id));
    await screen(tester);
    // The visible history was loaded before another caller selected its draft.
    final current = (await tester.runAsync(() => repository.start(1)))!;
    await tester.tap(find.byKey(ValueKey('rehearsal-history-${finished.id}')));
    await settle(tester);
    final leave = find.text('Choose a new practice attempt');
    await tester.scrollUntilVisible(leave, 600, maxScrolls: 100);
    await tester.tap(leave);
    await settle(tester);
    final saved = (await tester.runAsync(() => repository.current()))!;
    expect(saved.id, current.id);
    expect(saved.isFinished, isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rehearsal-timer')),
      -600,
      maxScrolls: 100,
    );
    expect(find.byKey(const ValueKey('rehearsal-timer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('a rejected late written edit restores the saved feedback text', (
    tester,
  ) async {
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
    );
    final attempt = (await tester.runAsync(() => repository.start(3)))!;
    final question = attempt.written.first;
    await tester.runAsync(
      () => repository.answerWritten(
        attempt.id,
        question.id,
        'Saved explanation before the deadline.',
      ),
    );
    await screen(tester);
    final field = find.byKey(ValueKey('rehearsal-written-${question.id}'));
    await tester.scrollUntilVisible(
      field,
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    // Advance the real repository clock without running the UI ticker first.
    time.advance(const Duration(minutes: 121));
    await tester.enterText(
      field,
      'This unsaved late text must not appear in feedback.',
    );
    await settle(tester);
    await tester.scrollUntilVisible(
      field,
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    final rendered = tester.widget<TextField>(field);
    expect(rendered.controller!.text, 'Saved explanation before the deadline.');
    expect(rendered.readOnly, isTrue);
    expect(find.text('Reset saved selection'), findsNothing);
    final saved = (await tester.runAsync(() => repository.current()))!;
    expect(saved.prose[question.id], 'Saved explanation before the deadline.');
    expect(saved.finishReason, 'expired');
    expect(saved.completedAt, attempt.deadline);
    expect(tester.takeException(), isNull);
  });

  testApp('an unanswered written question has disabled evidence claims', (
    tester,
  ) async {
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
    );
    final attempt = (await tester.runAsync(() => repository.start(3)))!;
    await tester.runAsync(() => repository.finish(attempt.id));
    await screen(tester);
    final question = attempt.written.first;
    final criterion = find.widgetWithText(
      CheckboxListTile,
      question.criteria.first.text,
    );
    await tester.scrollUntilVisible(
      criterion,
      600,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 100,
    );
    expect(tester.widget<CheckboxListTile>(criterion).onChanged, isNull);
    expect(
      find.text(
        'No written answer was saved. Review these points without claiming evidence.',
      ),
      findsWidgets,
    );
    expect(
      (await tester.runAsync(() => repository.current()))!.selfAssessment,
      isEmpty,
    );
  });
}
