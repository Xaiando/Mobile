import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, TransactionExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart' show noProviderRetry;
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

/// Holds the first actual prose snapshot INSERT inside answer()'s transaction.
/// Later observations count actual committed snapshots, not callbacks, timer
/// ticks, repository mocks, or native worker request/response messages.
class _FirstProseInsertGate extends QueryInterceptor {
  String? targetKey;
  bool everyWriteInTransaction = true;
  bool _targetTransaction = false;
  int committedSnapshots = 0;
  final requestedSnapshots = <Map<String, String>>[];
  final entered = Completer<void>();
  final release = Completer<void>();
  final firstSettled = Completer<void>();

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (targetKey != null &&
        statement.contains('user_settings') &&
        args.contains(targetKey)) {
      everyWriteInTransaction =
          everyWriteInTransaction && executor is TransactionExecutor;
      _targetTransaction = true;
      final raw = args.whereType<String>().firstWhere(
        (value) => value.startsWith('{'),
      );
      final row = jsonDecode(raw) as Map<String, dynamic>;
      requestedSnapshots.add(Map<String, String>.from(row['prose'] as Map));
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    }
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (_targetTransaction) {
      _targetTransaction = false;
      committedSnapshots++;
      if (!firstSettled.isCompleted) firstSettled.complete();
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    if (_targetTransaction) {
      _targetTransaction = false;
      if (!firstSettled.isCompleted) firstSettled.complete();
    }
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaWrittenRepository repository;
  late _FirstProseInsertGate gate;

  setUp(() async {
    gate = _FirstProseInsertGate();
    db = AppDatabase(NativeDatabase.memory().interceptWith(gate));
    time = TestClock(t0);
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = DiplomaWrittenRepository(
      db,
      bank: DiplomaWrittenBank.fromJson(
        File('assets/study/diploma_written_practice.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(83),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready,
    String phase,
  ) async {
    final bound = Stopwatch()..start();
    while (!ready() && bound.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(ready(), isTrue, reason: 'Prose coalescing phase: $phase');
  }

  testApp(
    'Back saves latest three responses without committing superseded queued prose',
    (tester) async {
      final original = (await tester.runAsync(
        () => repository.start('D4').timeout(const Duration(seconds: 5)),
      ))!;
      expect(original.questions, hasLength(3));
      final questions = original.questions;
      final latest = <String, String>{
        questions[0].id:
            'Latest Champagne response: name the supplied stock constraint and '
            'compare the conditional production routes.',
        questions[1].id:
            'Latest Italian response: the actual product version matters.\n'
            'Compare acidity, méthode and the supplied buyer assumptions.',
        questions[2].id:
            'Latest Australian response: site and supply risk remain conditional; '
            'do not promise quality or a premium price.',
      };
      Finder field(String questionId) =>
          find.byKey(ValueKey('diploma-written-prose-$questionId'));
      String visibleValue(String questionId) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(questionId),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      tester.view.physicalSize = const Size(1100, 4500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
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
        () => questions.every((q) => field(q.id).evaluate().isNotEmpty),
        'all three actual draft fields loaded',
      );
      await settle(tester);
      for (final question in questions) {
        expect(
          tester.widget<TextFormField>(field(question.id)).enabled,
          isTrue,
        );
        expect(visibleValue(question.id), isEmpty);
      }

      const firstInFlight =
          'First admitted value, already inside its SQL write.';
      gate.targetKey = DiplomaWrittenRepository.keyFor(original.id);
      try {
        await tester.enterText(field(questions[0].id), firstInFlight);
        await pumpUntil(
          tester,
          () => gate.entered.isCompleted,
          'first answer reached the held real transaction INSERT',
        );
        expect(gate.everyWriteInTransaction, isTrue);
        expect(gate.requestedSnapshots, [
          {questions[0].id: firstInFlight},
        ]);
        expect(gate.committedSnapshots, 0);
        expect(gate.release.isCompleted, isFalse);

        // Every enterText dispatches a genuine editable-field change while the
        // first transaction is blocked. Each field receives distinct revisions
        // rather than duplicate callbacks or direct calls to a save method.
        for (var revision = 1; revision <= 12; revision++) {
          for (final question in questions) {
            final text =
                'Superseded revision $revision for ${question.id}: '
                'this intermediate wording must not outlive the latest edit.';
            await tester.enterText(field(question.id), text);
            expect(visibleValue(question.id), text);
          }
        }
        for (final question in questions) {
          await tester.enterText(field(question.id), latest[question.id]!);
          expect(visibleValue(question.id), latest[question.id]);
        }
        expect(gate.requestedSnapshots, hasLength(1));
        expect(gate.committedSnapshots, 0);

        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        expect(
          find.byType(DiplomaWrittenScreen),
          findsOneWidget,
          reason:
              'Back must retain the route while an admitted save is pending',
        );
        expect(find.text('Open D4 writing'), findsNothing);
        for (final question in questions) {
          expect(
            tester.widget<TextFormField>(field(question.id)).enabled,
            isFalse,
          );
          expect(visibleValue(question.id), latest[question.id]);
        }
        expect(gate.release.isCompleted, isFalse);
        expect(gate.firstSettled.isCompleted, isFalse);
      } finally {
        // Always unblock native SQL, including an earlier genuine RED failure,
        // so no pending write strands the real database during test cleanup.
        if (!gate.release.isCompleted) gate.release.complete();
        if (gate.entered.isCompleted) {
          await pumpUntil(
            tester,
            () => gate.firstSettled.isCompleted,
            'held first transaction commits or rolls back',
          );
        }
      }
      await pumpUntil(
        tester,
        () => find.byType(DiplomaWrittenScreen).evaluate().isEmpty,
        'Back drains admitted responses and returns to the previous route',
      );
      await settle(tester);
      expect(find.text('Open D4 writing'), findsOneWidget);
      expect(gate.everyWriteInTransaction, isTrue);

      final saved = (await tester.runAsync(
        () => repository.read(original.id).timeout(const Duration(seconds: 5)),
      ))!;
      expect(saved.prose, latest);
      expect(saved.startedAt, original.startedAt);
      expect(saved.deadline, original.deadline);
      expect(saved.completedAt, isNull);
      expect(saved.finishReason, isNull);
      expect(saved.isFinished, isFalse);
      expect(saved.isReviewed, isFalse);
      expect(saved.reviews, isEmpty);
      final current = (await tester.runAsync(
        () => repository.current('D4').timeout(const Duration(seconds: 5)),
      ))!;
      expect(current.toJson(), saved.toJson());
      expect(
        await tester.runAsync(() => db.select(db.reviewStates).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewEventOptions).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.userProfiles).getSingle()),
        predicate<UserProfile>(
          (profile) => profile.activeCertificationId == 'WSET_L4',
        ),
      );
      expect(tester.takeException(), isNull);
      expect(gate.requestedSnapshots.length, gate.committedSnapshots);
      expect(
        gate.committedSnapshots,
        lessThanOrEqualTo(1 + questions.length),
        reason:
            'one already-running write plus at most one latest pending snapshot '
            'per question; superseded queued text must not require SQL commits',
      );
    },
  );
}
