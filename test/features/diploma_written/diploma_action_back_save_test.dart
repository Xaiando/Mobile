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

/// Hold the real snapshot INSERT after review() has loaded/validated its record
/// inside its own transaction. Released success uses the original native SQL;
/// the failure branch executes invalid SQL and exercises actual rollback.
class _ReviewInsertGate extends QueryInterceptor {
  String? targetKey;
  bool failReleasedWrite = false;
  bool enteredInTransaction = false;
  bool _heldTransaction = false;
  int failedNativeStatements = 0;
  final entered = Completer<void>();
  final release = Completer<void>();
  final settled = Completer<void>();

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (targetKey != null &&
        !entered.isCompleted &&
        statement.contains('user_settings') &&
        args.contains(targetKey)) {
      enteredInTransaction = executor is TransactionExecutor;
      _heldTransaction = true;
      entered.complete();
      await release.future;
      if (failReleasedWrite) {
        failedNativeStatements++;
        // The invalid column is intentionally absent from the canonical schema.
        // A real SQLite error must roll back the pending review transaction.
        return executor.runUpdate(
          'UPDATE user_settings SET missing_diploma_review_column = ? '
          'WHERE name = ?',
          ['must fail', targetKey],
        );
      }
    }
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (_heldTransaction) {
      _heldTransaction = false;
      if (!settled.isCompleted) settled.complete();
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    if (_heldTransaction) {
      _heldTransaction = false;
      if (!settled.isCompleted) settled.complete();
    }
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaWrittenRepository repository;
  late _ReviewInsertGate gate;

  setUp(() async {
    gate = _ReviewInsertGate();
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
      random: Random(71),
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
    expect(ready(), isTrue, reason: 'Written action Back phase: $phase');
  }

  Future<void> bring(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await settle(tester);
  }

  Future<void> materializeListTop(
    WidgetTester tester,
    Finder saveControl,
  ) async {
    expect(saveControl, findsOneWidget);
    expect(
      find.ancestor(of: saveControl, matching: find.byType(ListView)),
      findsOneWidget,
    );
    // The keyed Save button is outside every editable field's nested scrollable.
    // Its nearest Scrollable therefore owns the actual practice ListView.
    final list = Scrollable.of(tester.element(saveControl));
    final bound = Stopwatch()..start();
    list.position.jumpTo(list.position.minScrollExtent);
    await settle(tester);
    var stableFrames = 0;
    // A newly inserted error row can trigger a later lazy-layout scroll
    // correction. Re-jump after that correction and require the exact minimum
    // through two further frames; neither a near-zero offset nor an absent
    // offscreen error counts as a successful observation.
    while (stableFrames < 2 && bound.elapsed < const Duration(seconds: 5)) {
      if (list.position.pixels != list.position.minScrollExtent) {
        list.position.jumpTo(list.position.minScrollExtent);
        stableFrames = 0;
      }
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
      await tester.pump(Duration.zero);
      if (list.position.pixels == list.position.minScrollExtent) {
        stableFrames++;
      } else {
        stableFrames = 0;
      }
    }
    expect(
      stableFrames,
      2,
      reason:
          'practice ListView must reach its exact minimum within five seconds',
    );
    expect(list.position.pixels, list.position.minScrollExtent);
  }

  for (final failWrite in [false, true]) {
    testApp(
      failWrite
          ? 'Back retains a pending real self-review save, shows rollback, and permits an exact retry'
          : 'Back retains a pending real self-review save until it commits without replacing the newer draft',
      (tester) async {
        final original = (await tester.runAsync(
          () => (() async {
            final started = await repository.start('D4');
            for (final (index, question) in started.questions.indexed) {
              await repository.answer(
                started.id,
                question.id,
                'Original saved D4 prose ${index + 1}: supplied production '
                'and commercial assumptions require bounded comparisons.',
              );
            }
            await repository.finish(started.id);
            final question = started.questions.first;
            return repository.review(
              started.id,
              question.id,
              {question.criteria.first.id},
              'Earlier saved reflection that must survive a failed replacement.',
            );
          })().timeout(const Duration(seconds: 5)),
        ))!;
        expect(original.isFinished, isTrue);
        expect(original.isReviewed, isFalse);
        final originalBytes = (await tester.runAsync(() async {
          final row =
              await (db.select(db.userSettings)..where(
                    (row) => row.name.equals(
                      DiplomaWrittenRepository.keyFor(original.id),
                    ),
                  ))
                  .getSingle();
          return row.value;
        }))!;
        final newer = (await tester.runAsync(
          () => (() async {
            final started = await repository.start('D4');
            return repository.answer(
              started.id,
              started.questions.first.id,
              'Newer active draft keeps its own exact private prose.',
            );
          })().timeout(const Duration(seconds: 5)),
        ))!;

        tester.view.physicalSize = const Size(1100, 2400);
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
                        builder: (_) =>
                            const DiplomaWrittenScreen(unitId: 'D4'),
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
        final history = find.byKey(
          ValueKey('diploma-written-history-${original.id}'),
        );
        await pumpUntil(
          tester,
          () => history.evaluate().isNotEmpty,
          'actual newer draft and saved history loaded',
        );
        await bring(tester, history);
        await tester.tap(history);
        final selectedAttempt = find.byKey(
          ValueKey('${original.id}-${original.questions.first.id}'),
        );
        await pumpUntil(
          tester,
          () => selectedAttempt.evaluate().isNotEmpty,
          'finished attempt selected from its real saved history row',
        );
        await settle(tester);
        final question = original.questions.first;
        expect(question.criteria.length, greaterThanOrEqualTo(3));
        final note = find.byKey(
          ValueKey('diploma-written-improvement-${question.id}'),
        );
        Finder criterion(int index) => find.byKey(
          ValueKey(
            'diploma-written-criterion-${question.id}-${question.criteria[index].id}',
          ),
        );
        final save = find.byKey(
          ValueKey('diploma-written-review-${question.id}'),
        );
        const latestNote =
            'My latest reflection needs a named stock assumption and a '
            'comparison with the supplied product method.';
        final latestCriteria = {
          question.criteria[1].id,
          question.criteria[2].id,
        };
        for (final index in [0, 1, 2]) {
          await bring(tester, criterion(index));
          await tester.tap(criterion(index));
          await settle(tester);
          expect(
            tester.widget<CheckboxListTile>(criterion(index)).value,
            index != 0,
            reason: 'verify actual latest review selection before Save',
          );
        }
        await bring(tester, note);
        await tester.enterText(note, latestNote);
        await settle(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: note, matching: find.byType(EditableText)),
              )
              .controller
              .text,
          latestNote,
        );
        await bring(tester, save);
        gate.targetKey = DiplomaWrittenRepository.keyFor(original.id);
        gate.failReleasedWrite = failWrite;
        var reviewRequested = false;
        try {
          await tester.tap(save);
          reviewRequested = true;
          await pumpUntil(
            tester,
            () => gate.entered.isCompleted,
            'real review transaction reached its held snapshot INSERT',
          );
          expect(gate.enteredInTransaction, isTrue);
          expect(gate.settled.isCompleted, isFalse);
          expect(gate.release.isCompleted, isFalse);
          expect(tester.widget<TextButton>(save).onPressed, isNull);
          expect(tester.widget<TextFormField>(note).enabled, isFalse);
          expect(find.byType(BackButton), findsOneWidget);
          await tester.tap(find.byType(BackButton));
          // Allow both PopScope/endOfFrame and the route animation to execute;
          // checking only the immediate first frame could conceal an early pop.
          await settle(tester);
          expect(
            find.byType(DiplomaWrittenScreen),
            findsOneWidget,
            reason:
                'Back must retain the route while the real review SQL is held',
          );
          expect(find.text('Open D4 writing'), findsNothing);
          expect(gate.settled.isCompleted, isFalse);
          expect(gate.release.isCompleted, isFalse);
        } finally {
          // Always release even on the genuine RED early-pop assertion, so the
          // pending native transaction cannot strand the database or teardown.
          if (!gate.release.isCompleted) gate.release.complete();
          if (reviewRequested && gate.entered.isCompleted) {
            await pumpUntil(
              tester,
              () => gate.settled.isCompleted,
              'held review transaction committed or rolled back',
            );
            await settle(tester);
          }
        }

        expect(find.byType(DiplomaWrittenScreen), findsOneWidget);
        await pumpUntil(
          tester,
          () =>
              save.evaluate().isNotEmpty &&
              tester.widget<TextButton>(save).onPressed != null,
          'selected review action becomes available after transaction result',
        );
        await bring(tester, note);
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: note, matching: find.byType(EditableText)),
              )
              .controller
              .text,
          latestNote,
          reason: 'held action must not replace unsaved review text',
        );
        for (final index in [0, 1, 2]) {
          expect(
            tester.widget<CheckboxListTile>(criterion(index)).value,
            index != 0,
          );
        }
        if (failWrite) {
          expect(gate.failedNativeStatements, 1);
          final error = find.byKey(const ValueKey('diploma-written-error'));
          await materializeListTop(tester, save);
          expect(error, findsOneWidget);
          await bring(tester, error);
          expect(
            find.textContaining('missing_diploma_review_column'),
            findsOneWidget,
          );
          final unchangedBytes = (await tester.runAsync(() async {
            final row =
                await (db.select(db.userSettings)..where(
                      (row) => row.name.equals(
                        DiplomaWrittenRepository.keyFor(original.id),
                      ),
                    ))
                    .getSingle();
            return row.value;
          }))!;
          expect(
            unchangedBytes,
            originalBytes,
            reason: 'real failed SQL rolls back review bytes',
          );
          expect(jsonDecode(unchangedBytes), original.toJson());
          await bring(tester, save);
          expect(tester.widget<TextButton>(save).onPressed, isNotNull);
          await tester.tap(save);
          await tester.pump(Duration.zero);
          await pumpUntil(
            tester,
            () =>
                save.evaluate().isNotEmpty &&
                tester.widget<TextButton>(save).onPressed != null,
            'retry action settles using the same selected criteria and latest note',
          );
          await settle(tester);
          await materializeListTop(tester, save);
          expect(
            error,
            findsNothing,
            reason:
                'successful retry clears the error after its row is in view',
          );
          expect(gate.failedNativeStatements, 1);
        } else {
          expect(gate.failedNativeStatements, 0);
        }
        final saved = (await tester.runAsync(
          () =>
              repository.read(original.id).timeout(const Duration(seconds: 5)),
        ))!;
        expect(saved.prose, original.prose);
        expect(saved.deadline, original.deadline);
        expect(saved.startedAt, original.startedAt);
        expect(saved.completedAt, original.completedAt);
        expect(saved.finishReason, original.finishReason);
        expect(saved.reviews[question.id]!.selectedCriteria, latestCriteria);
        expect(saved.reviews[question.id]!.improvement, latestNote);
        expect(saved.reviews, hasLength(1));
        expect(saved.isReviewed, isFalse);
        final active = (await tester.runAsync(
          () => repository.current('D4').timeout(const Duration(seconds: 5)),
        ))!;
        expect(
          active.toJson(),
          newer.toJson(),
          reason: 'finished review does not steal the newer draft',
        );
        expect(
          await tester.runAsync(() => db.select(db.reviewStates).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.reviewEvents).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.userProfiles).getSingle()),
          predicate<UserProfile>(
            (profile) => profile.activeCertificationId == 'WSET_L4',
          ),
        );
        await tester.tap(find.byType(BackButton));
        await pumpUntil(
          tester,
          () => find.byType(DiplomaWrittenScreen).evaluate().isEmpty,
          'Back after completed save returns to the prior route',
        );
        expect(find.text('Open D4 writing'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
