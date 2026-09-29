import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair.dart';
import 'package:sommelier/core/tasting_pair/tasting_pair_providers.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/tasting_pair/tasting_pair_screen.dart';

import '../../core/tasting_guidance/guided_tasting_fixture.dart';
import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late TastingPairRepository repository;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await seedGuidedTastingGrids(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    repository = TastingPairRepository(
      db,
      guidance: GuidedTastingRepository(
        db,
        bank: guidedTastingFixtureBank(),
        clock: time.clock,
      ),
      clock: time.clock,
      random: Random(8),
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
          tastingPairRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const TastingPairScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> visible(
    WidgetTester tester,
    Finder finder, {
    double direction = 400,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      direction,
      maxScrolls: 60,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  testApp('phone setup clearly explains the shared timer and training limits', (
    tester,
  ) async {
    await screen(tester, scale: 2);
    expect(
      find.textContaining('no automatic wine grade or official pass'),
      findsOneWidget,
    );
    await visible(tester, find.textContaining('Both share 30 minutes'));
    expect(find.textContaining('Both share 30 minutes'), findsOneWidget);
    expect(
      find.textContaining('one white and one red, in either order'),
      findsOneWidget,
    );
    await visible(tester, find.byKey(const ValueKey('tasting-pair-start')));
    expect(tester.takeException(), isNull);
  });

  testApp('wine switching retains each draft and both finish together', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start()))!;
    await screen(tester);
    final dry = find.byKey(
      const ValueKey('tasting-pair-observation-0-sweetness-dry'),
    );
    await visible(tester, dry);
    await tester.tap(dry);
    await settle(tester);
    final quality = find.byKey(
      const ValueKey('tasting-pair-evidence-0-quality'),
    );
    await visible(tester, quality);
    await tester.enterText(quality, 'Evidence saved for the first wine.');
    await settle(tester);
    final wine2 = find.byKey(const ValueKey('tasting-pair-wine-1'));
    await visible(tester, wine2, direction: -400);
    await tester.tap(wine2);
    await settle(tester);
    final offDry = find.byKey(
      const ValueKey('tasting-pair-observation-1-sweetness-off_dry'),
    );
    await visible(tester, offDry);
    await tester.tap(offDry);
    await settle(tester);
    final finish = find.byKey(const ValueKey('tasting-pair-finish'));
    await visible(tester, finish);
    await tester.tap(finish);
    await settle(tester);
    final saved = (await tester.runAsync(() => repository.current()))!;
    expect(saved.isFinished, isTrue);
    expect(saved.wines.first.observations['sweetness'], {'dry'});
    expect(
      saved.wines.first.evidence['quality'],
      'Evidence saved for the first wine.',
    );
    expect(saved.wines.last.observations['sweetness'], {'off_dry'});
    await visible(
      tester,
      find.byKey(const ValueKey('tasting-pair-finished')),
      direction: -400,
    );
    expect(find.text('Pair finished; answers saved.'), findsOneWidget);
    expect(saved.id, attempt.id);
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testApp(
    'unreadable paired history is visible beside an unchanged saved timer',
    (tester) async {
      final valid = (await tester.runAsync(() => repository.start()))!;
      await tester.runAsync(() => repository.resetCurrentPointer());
      await tester.runAsync(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: '${TastingPairRepository.attemptPrefix}broken',
                value: '{invalid',
                updatedAt: time.now,
              ),
            ),
      );
      time.advance(const Duration(minutes: 5));
      await screen(tester);
      final warning = find.byKey(
        const ValueKey('tasting-pair-history-warning'),
      );
      await visible(tester, warning);
      expect(
        find.textContaining('1 saved paired record could not be read'),
        findsOneWidget,
      );
      final tile = find.byKey(ValueKey('tasting-pair-history-${valid.id}'));
      await visible(tester, tile);
      await tester.tap(tile);
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.current()))!;
      expect(saved.id, valid.id);
      expect(saved.deadline, valid.deadline);
      expect(saved.remaining(time.now), const Duration(minutes: 25));
      expect(tester.takeException(), isNull);
    },
  );

  testApp('resumed deadline expires once and exposes incomplete evidence', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start()))!;
    await tester.runAsync(
      () => repository.evidence(
        attempt.id,
        attempt.wines.first.sessionId,
        'quality',
        'Saved before closing.',
      ),
    );
    time.advance(const Duration(minutes: 29));
    await screen(tester, scale: 2);
    expect(find.text('Time remaining: 1:00'), findsOneWidget);
    time.advance(const Duration(minutes: 2));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Time expired; answers saved.'), findsOneWidget);
    expect(find.byKey(const ValueKey('tasting-pair-timer')), findsNothing);
    final saved = (await tester.runAsync(() => repository.current()))!;
    expect(saved.completedAt, attempt.deadline);
    expect(saved.completeWineCount, 0);
    final missing = find.byKey(const ValueKey('tasting-pair-missing-evidence'));
    await visible(tester, missing);
    expect(find.textContaining('Unanswered evidence:'), findsOneWidget);
    final field = find.byKey(const ValueKey('tasting-pair-evidence-0-quality'));
    await visible(tester, field);
    expect(tester.widget<TextField>(field).readOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testApp('saved finished answers remain read only after reopening', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start()))!;
    await tester.runAsync(() async {
      await repository.choose(
        attempt.id,
        attempt.wines.first.sessionId,
        'sweetness',
        {'dry'},
      );
      await repository.finish(attempt.id);
    });
    await screen(tester);
    final dry = find.byKey(
      const ValueKey('tasting-pair-observation-0-sweetness-dry'),
    );
    await visible(tester, dry);
    expect(tester.widget<FilterChip>(dry).onSelected, isNull);
    expect(tester.widget<FilterChip>(dry).selected, isTrue);
    expect(find.byKey(const ValueKey('tasting-pair-finish')), findsNothing);
    await visible(
      tester,
      find.textContaining('This records completeness only.'),
      direction: -400,
    );
    expect(
      find.text(
        '0 of 2 wines have every required observation and evidence prompt. This records completeness only.',
      ),
      findsOneWidget,
    );
  });

  testApp('a rejected late text edit displays the saved evidence snapshot', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start()))!;
    await tester.runAsync(
      () => repository.evidence(
        attempt.id,
        attempt.wines.first.sessionId,
        'quality',
        'Evidence saved within time.',
      ),
    );
    await screen(tester);
    final field = find.byKey(const ValueKey('tasting-pair-evidence-0-quality'));
    await visible(tester, field);
    time.advance(const Duration(minutes: 31));
    await tester.enterText(field, 'This edit is too late.');
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.current()))!.finishReason,
      'expired',
    );
    expect(
      tester.widget<TextField>(field).controller!.text,
      'Evidence saved within time.',
    );
    expect(tester.widget<TextField>(field).readOnly, isTrue);
    expect(find.byKey(const ValueKey('tasting-pair-error')), findsOneWidget);
  });
}
