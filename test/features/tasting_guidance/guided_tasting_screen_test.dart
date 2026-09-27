import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/backup/user_data_backup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting_providers.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/tasting_guidance/guided_tasting_screen.dart';

import '../../core/tasting_guidance/guided_tasting_fixture.dart';
import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late GuidedTastingRepository repository;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1');
    repository = GuidedTastingRepository(
      db,
      bank: guidedTastingFixtureBank(),
      clock: time.clock,
    );
  });
  tearDown(() => db.close());
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screen(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          guidedTastingRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const GuidedTastingScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      400,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
  }

  testApp(
    'phone setup distinguishes physical observations from original cases',
    (tester) async {
      await screen(tester, scale: 2);
      expect(
        find.textContaining('no automatic correctness score'),
        findsOneWidget,
      );
      await visible(tester, find.text('Observe a physical wine'));
      expect(find.text('Observe a physical wine'), findsOneWidget);
      await visible(tester, find.byKey(const ValueKey('guided-tasting-start')));
      expect(tester.takeException(), isNull);
    },
  );

  testApp('physical observation and evidence save with no objective grade', (
    tester,
  ) async {
    final record = (await tester.runAsync(() => repository.start(1)))!;
    await screen(tester);
    final dry = find.byKey(const ValueKey('guided-observation-sweetness-dry'));
    await visible(tester, dry);
    await tester.tap(dry);
    await settle(tester);
    final field = find.byKey(const ValueKey('guided-evidence-description'));
    await visible(tester, field);
    await tester.enterText(
      field,
      'Dryness is supported by the observed palate.',
    );
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.current()))!
          .evidence['description'],
      'Dryness is supported by the observed palate.',
    );
    final finish = find.byKey(const ValueKey('guided-tasting-finish'));
    await visible(tester, finish);
    await tester.tap(finish);
    await settle(tester);
    await visible(
      tester,
      find.byKey(const ValueKey('guided-tasting-complete')),
    );
    expect(find.byKey(const ValueKey('guided-tasting-feedback')), findsNothing);
    expect(
      (await tester.runAsync(() => repository.read(record.sessionId)))!
          .isFinished,
      isTrue,
    );
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testApp(
    'unreadable guided history is visible beside resumable valid evidence',
    (tester) async {
      final valid = (await tester.runAsync(() => repository.start(1)))!;
      await tester.runAsync(() => repository.leaveCurrent());
      await tester.runAsync(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: '${GuidedTastingRepository.recordPrefix}broken',
                value: '{invalid',
                updatedAt: time.now,
              ),
            ),
      );
      await screen(tester);
      expect(
        find.byKey(const ValueKey('guided-history-warning')),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 saved guided record could not be read'),
        findsOneWidget,
      );
      final tile = find.byKey(ValueKey('guided-history-${valid.sessionId}'));
      await visible(tester, tile);
      await tester.tap(tile);
      await settle(tester);
      expect(
        (await tester.runAsync(() => repository.current()))!.sessionId,
        valid.sessionId,
      );
      expect(
        find.byKey(const ValueKey('guided-history-warning')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'case references and criteria appear only after saved evidence completes',
    (tester) async {
      final record = (await tester.runAsync(
        () => repository.start(1, caseId: 'case_l1'),
      ))!;
      await screen(tester);
      expect(find.text(record.calibration!.feedback), findsNothing);
      expect(find.text(record.calibration!.criteria.first.text), findsNothing);
      await tester.runAsync(() async {
        await repository.choose(record.sessionId, 'sweetness', {'dry'});
        await repository.evidence(
          record.sessionId,
          'description',
          'Supported descriptive evidence.',
        );
      });
      // A fresh route reads the persisted draft rather than retaining stale UI.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await screen(tester);
      final finish = find.byKey(const ValueKey('guided-tasting-finish'));
      await visible(tester, finish);
      await tester.tap(finish);
      await settle(tester);
      await visible(
        tester,
        find.byKey(const ValueKey('guided-tasting-feedback')),
      );
      expect(find.text('Training reference observations'), findsOneWidget);
      expect(find.text(record.calibration!.feedback), findsOneWidget);
      final check = find.text(record.calibration!.criteria.first.text);
      await visible(tester, check);
      await tester.tap(check);
      await settle(tester);
      expect(
        (await tester.runAsync(() => repository.current()))!.selfAssessment,
        {'evidence'},
      );
    },
  );

  testApp(
    'imported invalid calibration reference shows recovery warning and valid feedback',
    (tester) async {
      final valid = (await tester.runAsync(() async {
        Future<GuidedTastingRecord> finishedCase() async {
          final record = await repository.start(1, caseId: 'case_l1');
          await repository.choose(record.sessionId, 'sweetness', {'dry'});
          await repository.evidence(
            record.sessionId,
            'description',
            'Saved evidence from the original training case.',
          );
          final saved = await repository.finish(record.sessionId);
          await repository.leaveCurrent();
          return saved;
        }

        final invalid = await finishedCase();
        final good = await finishedCase();
        final row = invalid.toJson();
        row['calibration']['referenceObservations'][0]['attributeKey'] =
            'missing_attribute';
        await db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name:
                    '${GuidedTastingRepository.recordPrefix}${invalid.sessionId.replaceAll('-', '_')}',
                value: jsonEncode(row),
                updatedAt: time.now,
              ),
            );
        final backup = UserDataBackup(db, clock: time.clock);
        final exported = await backup.exportJson();
        await backup.eraseAll();
        await backup.import(exported);
        return good;
      }))!;
      await screen(tester);
      expect(
        find.byKey(const ValueKey('guided-history-warning')),
        findsOneWidget,
      );
      expect(
        find.textContaining('1 saved guided record could not be read'),
        findsOneWidget,
      );
      final tile = find.byKey(ValueKey('guided-history-${valid.sessionId}'));
      await visible(tester, tile);
      await tester.tap(tile);
      await settle(tester);
      await visible(
        tester,
        find.byKey(const ValueKey('guided-tasting-feedback')),
      );
      expect(find.text('Training reference observations'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
    },
  );
}
