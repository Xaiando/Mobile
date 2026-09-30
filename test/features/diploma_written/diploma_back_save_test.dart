import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/diploma_written/diploma_written_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/diploma_written/diploma_written_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

/// Holds only the last UI response before its real repository transaction.
/// The other responses and the released response use the actual database.
class _HeldLastAnswerRepository extends DiplomaWrittenRepository {
  _HeldLastAnswerRepository(super.db, DiplomaWrittenBank bank, TestClock time)
    : super(bank: bank, clock: time.clock, random: Random(47));

  String? heldQuestionId;
  final heldStarted = Completer<void>();
  final release = Completer<void>();
  final heldCommitted = Completer<void>();
  final committedProse = <String, String>{};

  @override
  Future<DiplomaWrittenAttempt> answer(
    String id,
    String questionId,
    String text,
  ) async {
    final held = questionId == heldQuestionId && !heldStarted.isCompleted;
    if (held) {
      heldStarted.complete();
      await release.future;
    }
    final saved = await super.answer(id, questionId, text);
    committedProse[questionId] = saved.prose[questionId]!;
    if (held) heldCommitted.complete();
    return saved;
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late _HeldLastAnswerRepository repository;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = _HeldLastAnswerRepository(
      db,
      DiplomaWrittenBank.fromJson(
        File('assets/study/diploma_written_practice.json').readAsStringSync(),
      ),
      time,
    );
  });
  tearDown(() => db.close());

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready,
    String phase,
  ) async {
    final bound = Stopwatch()..start();
    while (!ready() && bound.elapsed < const Duration(seconds: 5)) {
      // Advance a render frame, including PopScope/endOfFrame, then yield an
      // event-loop turn for the real SQLite operation. Neither is a sleep.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    }
    expect(ready(), isTrue, reason: 'Written Back phase: $phase');
    debugPrint('Written Back phase complete: $phase');
  }

  testApp(
    'D4 Back holds the route and all mutations until the last real save drains',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start('D4').timeout(const Duration(seconds: 5)),
      ))!;
      expect(attempt.questions, hasLength(3));
      final originalDeadline = attempt.deadline;
      final expectedProse = {
        for (final (index, question) in attempt.questions.indexed)
          question.id:
              'Distinct D4 response ${index + 1}: '
              'supplied production assumptions affect style and cost; '
              'this original response remains private study evidence.',
      };
      repository.heldQuestionId = attempt.questions.last.id;
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
            diplomaWrittenRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const DiplomaWrittenScreen(unitId: 'D4'),
                    ),
                  ),
                  child: const Text('Open D4 writing'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open D4 writing'));
      await pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('diploma-written-timer'))
            .evaluate()
            .isNotEmpty,
        'saved D4 draft loaded on a real Navigator route',
      );
      // Complete each earlier UI write before submitting the held third write.
      for (final question in attempt.questions.take(2)) {
        final field = find.byKey(
          ValueKey('diploma-written-prose-${question.id}'),
        );
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, expectedProse[question.id]!);
        await pumpUntil(
          tester,
          () =>
              repository.committedProse[question.id] ==
              expectedProse[question.id],
          'exact response ${question.id} committed before the held save',
        );
      }

      var queuedLast = false;
      var backRequested = false;
      try {
        final last = find.byKey(
          ValueKey('diploma-written-prose-${attempt.questions.last.id}'),
        );
        await tester.ensureVisible(last);
        await tester.pumpAndSettle();
        await tester.enterText(last, expectedProse[attempt.questions.last.id]!);
        queuedLast = true;
        await tester.pump(Duration.zero);
        await tester.runAsync(
          () =>
              repository.heldStarted.future.timeout(const Duration(seconds: 5)),
        );
        expect(repository.heldStarted.isCompleted, isTrue);
        expect(repository.heldCommitted.isCompleted, isFalse);
        expect(repository.committedProse, hasLength(2));
        expect(find.byType(BackButton), findsOneWidget);
        backRequested = true;
        await tester.tap(find.byType(BackButton));
        await tester.pump(Duration.zero);

        expect(find.byType(DiplomaWrittenScreen), findsOneWidget);
        expect(find.text('Open D4 writing'), findsNothing);
        expect(repository.heldCommitted.isCompleted, isFalse);
        for (final question in attempt.questions) {
          expect(
            tester
                .widget<TextFormField>(
                  find.byKey(ValueKey('diploma-written-prose-${question.id}')),
                )
                .enabled,
            isFalse,
            reason: 'a new prose edit must not enter the queue while leaving',
          );
        }
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('diploma-written-finish')),
              )
              .onPressed,
          isNull,
          reason: 'End writing must not race a pending Back/save drain',
        );
        expect(
          tester
              .widget<TextButton>(
                find.widgetWithText(TextButton, 'Abandon this attempt'),
              )
              .onPressed,
          isNull,
          reason: 'Abandon must not race a pending Back/save drain',
        );
      } finally {
        // This cleanup also runs on the expected baseline enabled-action
        // failure, so the held write cannot strand SQLite or test teardown.
        if (!repository.release.isCompleted) repository.release.complete();
        if (queuedLast) {
          await pumpUntil(
            tester,
            () => repository.heldCommitted.isCompleted,
            'released last answer really committed',
          );
        }
        if (backRequested) {
          await pumpUntil(
            tester,
            () => find.byType(DiplomaWrittenScreen).evaluate().isEmpty,
            'queue drain followed by actual PopScope frame and route pop',
          );
        }
        await tester.pump(Duration.zero);
      }

      expect(find.byType(DiplomaWrittenScreen), findsNothing);
      expect(find.text('Open D4 writing'), findsOneWidget);
      final saved = (await tester.runAsync(
        () => repository.current('D4').timeout(const Duration(seconds: 5)),
      ))!;
      expect(saved.id, attempt.id);
      expect(saved.prose, expectedProse);
      expect(saved.deadline, originalDeadline);
      expect(saved.startedAt, attempt.startedAt);
      expect(
        saved.questions.map((q) => q.toJson()).toList(),
        attempt.questions.map((q) => q.toJson()).toList(),
      );
      expect(saved.isFinished, isFalse);
      expect(saved.isReviewed, isFalse);
      expect(saved.reviews, isEmpty);
      expect(
        await tester.runAsync(() => db.select(db.reviewStates).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
