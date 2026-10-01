import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart' show noProviderRetry;
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_evidence.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/time/time_providers.dart';

import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

class _EvidenceSelectGate extends QueryInterceptor {
  bool armed = false, entered = false, failQuery = false;
  final release = Completer<void>();
  int failedSqlQueries = 0;
  int evidenceReads = 0;
  bool executorCloseEntered = false, executorCloseCompleted = false;
  @override
  Future<void> close(QueryExecutor inner) async {
    executorCloseEntered = true;
    await inner.close();
    executorCloseCompleted = true;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final isEvidence =
        statement.contains('user_settings') &&
        args.any(
          (arg) =>
              arg is String &&
              arg.startsWith(CmsRehearsalRepository.attemptPrefix),
        );
    if (isEvidence) evidenceReads++;
    if (isEvidence && armed && !entered) {
      entered = true;
      await release.future;
    }
    if (isEvidence && failQuery) {
      failedSqlQueries++;
      return executor.runSelect(
        'SELECT cms_injected_missing_column FROM user_settings',
        const [],
      );
    }
    return executor.runSelect(statement, args);
  }
}

Future<void> _settle(WidgetTester tester) async {
  // Explicit zero advances due event-loop timers without advancing study time.
  // A duration-less pump only flushes microtasks in the pinned Flutter binding.
  await tester.pump(Duration.zero);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump(Duration.zero);
}

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  for (var i = 0; i < 50 && !ready(); i++) {
    await _settle(tester);
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  testWidgets(
    'live saved evidence exposes loading, actual SQL error and successful-query recovery',
    (tester) async {
      final gate = _EvidenceSelectGate();
      final db = AppDatabase(NativeDatabase.memory().interceptWith(gate));
      final time = TestClock(t0);
      ProviderContainer? container;
      ProviderSubscription<AsyncValue<CmsRehearsalEvidence>>? subscription;
      final states = <AsyncValue<CmsRehearsalEvidence>>[];
      final milestones = <String>[];
      Object? primaryError;
      StackTrace? primaryStack;
      try {
        final seeded = await tester.runAsync(() async {
          await seedCurriculum(db);
          final row = Map<String, dynamic>.from(
            jsonDecode(
              File('assets/study/cms_certified_rehearsal.json')
                  .readAsStringSync(),
            ) as Map,
          );
          for (final q in row['mcqs'] as List<dynamic>) {
            q['itemIds'] = ['ki_chablis_grape'];
          }
          for (final q in row['written'] as List<dynamic>) {
            for (final c in q['criteria'] as List<dynamic>) {
              c['itemIds'] = ['ki_chablis_grape'];
            }
          }
          final repository = CmsRehearsalRepository(
            db,
            bank: CmsRehearsalBank.fromJson(jsonEncode(row)),
            clock: time.clock,
            random: Random(7),
          );
          var attempt = await repository.start(CmsRehearsalSection.service);
          for (final q in attempt.written) {
            attempt = await repository.answerWritten(
              attempt.id,
              q.id,
              'My actual written reasoning and acknowledged limits.',
            );
          }
          attempt = await repository.finish(attempt.id);
          for (final q in attempt.written) {
            attempt = await repository.selfAssess(
              attempt.id,
              q.id,
              {},
              improvement: 'Improve the evidence and guest-specific condition.',
            );
          }
          attempt = await repository.review(attempt.id);
          return attempt.isReviewed;
        });
        expect(seeded, isTrue);
        gate.armed = true;
        container = ProviderContainer(
          retry: noProviderRetry,
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
          ],
        );
        subscription = container.listen(
          cmsRehearsalEvidenceProvider,
          (_, next) => states.add(next),
          fireImmediately: true,
        );
        expect(container.read(cmsRehearsalEvidenceProvider).isLoading, isTrue);
        await _until(
          tester,
          () => gate.entered,
          'the real first saved-evidence SELECT must reach its held read',
        );
        expect(container.read(cmsRehearsalEvidenceProvider).isLoading, isTrue);
        expect(
          states.whereType<AsyncData<CmsRehearsalEvidence>>(),
          isEmpty,
          reason: 'Loading must not fabricate a numeric zero.',
        );
        gate.release.complete();
        await _until(
          tester,
          () => container!.read(cmsRehearsalEvidenceProvider).asData != null,
          'the actual saved reviewed service record must load',
        );
        var live = container.read(cmsRehearsalEvidenceProvider);
        expect(live.asData!.value.serviceReviewed, 1);
        expect(live.asData!.value.unreadableCount, 0);
        milestones.add('saved-count-loaded');

        gate.failQuery = true;
        final write = await tester.runAsync(
          () => db
              .into(db.userSettings)
              .insertOnConflictUpdate(
                UserSetting(
                  name: 'cms_evidence_refresh_probe',
                  value: 'first',
                  updatedAt: time.now,
                ),
              )
              .timeout(const Duration(seconds: 5)),
        );
        expect(write, isNotNull);
        await _until(
          tester,
          () => container!.read(cmsRehearsalEvidenceProvider).hasError,
          'an actual SQLite query failure must surface as AsyncError',
        );
        live = container.read(cmsRehearsalEvidenceProvider);
        expect(live.error, isA<SqliteException>());
        expect(gate.failedSqlQueries, greaterThan(0));
        milestones.add('sql-error-visible');
        final afterError = states.length;
        time.advance(const Duration(minutes: 2));
        await tester.pump(const Duration(minutes: 1));
        await _settle(tester);
        expect(container.read(cmsRehearsalEvidenceProvider).hasError, isTrue);
        expect(
          states.skip(afterError).whereType<AsyncData<CmsRehearsalEvidence>>(),
          isEmpty,
          reason: 'A cached-row timer must not hide the failed query with stale numeric success.',
        );

        milestones.add('cache-timer-preserved-error');
        gate.failQuery = false;
        final retry = await tester.runAsync(
          () => db
              .into(db.userSettings)
              .insertOnConflictUpdate(
                UserSetting(
                  name: 'cms_evidence_refresh_probe',
                  value: 'retry',
                  updatedAt: time.now,
                ),
              )
              .timeout(const Duration(seconds: 5)),
        );
        expect(retry, isNotNull);
        await _until(
          tester,
          () => container!.read(cmsRehearsalEvidenceProvider).asData != null,
          'a successful subsequent query must recover the actual saved count',
        );
        live = container.read(cmsRehearsalEvidenceProvider);
        expect(live.hasError, isFalse);
        expect(live.asData!.value.serviceReviewed, 1);
        final stored = await tester.runAsync(
          () => db.select(db.userSettings).get(),
        );
        expect(stored!.where((r) => r.name.startsWith('exam_pass_')), isEmpty);
        expect(
          await tester.runAsync(() => db.select(db.reviewEvents).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.reviewStates).get()),
          isEmpty,
        );
        milestones.add('body-complete');
      } catch (error, stack) {
        primaryError = error;
        primaryStack = stack;
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        subscription?.close();
        milestones.add('subscription-close-called');
        container?.dispose();
        milestones.add('container-disposed');
        await _settle(tester);
        // The watch and its cancellation originate in FakeAsync. Begin close
        // there too, then pump its stream-close callbacks before awaiting the
        // captured future through the real zone. Preserve the original error.
        Object? cleanupError;
        StackTrace? cleanupStack;
        final closing = db.close().then(
          (_) => true,
          onError: (Object error, StackTrace stack) {
            cleanupError = error;
            cleanupStack = stack;
            return false;
          },
        );
        for (var i = 0; i < 5; i++) {
          await _settle(tester);
        }
        final closed = await tester.runAsync(() async {
          try {
            return await closing.timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException(
                'CMS evidence cleanup milestones: ${milestones.join(' > ')}; evidence reads=${gate.evidenceReads}; executor close entered=${gate.executorCloseEntered}, completed=${gate.executorCloseCompleted}',
                const Duration(seconds: 5),
              ),
            );
          } catch (error, stack) {
            cleanupError = error;
            cleanupStack = stack;
            return false;
          }
        });
        if (primaryError != null) {
          Error.throwWithStackTrace(primaryError, primaryStack!);
        }
        if (cleanupError != null) {
          Error.throwWithStackTrace(cleanupError!, cleanupStack!);
        }
        expect(
          closed,
          isTrue,
          reason: 'Dispose the real DB subscription before bounded real-zone cleanup.',
        );
      }
    },
  );
}
