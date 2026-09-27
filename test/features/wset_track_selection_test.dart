import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/home/track_picker.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;

  const tracks = ['WSET_L1', 'WSET_L2', 'WSET_L3', 'WSET_L4', 'CMS_CERTIFIED'];

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE certifications SET is_selectable=1 WHERE id IN ('WSET_L1','WSET_L2')",
        "INSERT INTO certifications VALUES ('WSET_L4','WSET',4,'WSET Level 4 Diploma','WSET_L3',NULL,1,'certification',NULL)",
        "INSERT INTO certification_knowledge_mappings VALUES ('WSET_L1','ki_chablis_grape','core',1,NULL)",
      ]),
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
          appStartupProvider.overrideWith(
            (ref) async => StorageDurability.persistent,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: TrackPicker(),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  testApp('all five tracks wrap on a narrow phone at double text size', (
    tester,
  ) async {
    await screen(tester, scale: 2);
    expect(find.byType(ChoiceChip), findsNWidgets(5));
    for (final track in tracks) {
      final rectangle = tester.getRect(find.byKey(ValueKey('track-$track')));
      expect(rectangle.left, greaterThanOrEqualTo(16));
      expect(rectangle.right, lessThanOrEqualTo(304));
      expect(rectangle.width, greaterThan(0));
    }
    expect(tester.takeException(), isNull);
  });

  testApp(
    'selecting each level preserves item reviews and restricts its queue',
    (tester) async {
      await tester.runAsync(
        () => ReviewService(db, clock: time.clock).record(
          knowledgeItemId: 'ki_chablis_grape',
          questionTemplateId: 'qt_ppg_fwd_mcq',
          rating: fsrs.Rating.good,
        ),
      );
      final originalStates = await tester.runAsync(
        () async => (await db.select(db.reviewStates).get())
            .map((row) => row.toJson())
            .toList(),
      );
      final originalEvents = await tester.runAsync(
        () async => (await db.select(db.reviewEvents).get())
            .map((row) => row.toJson())
            .toList(),
      );
      await screen(tester);
      for (final (index, track) in tracks.indexed) {
        final chip = find.byKey(ValueKey('track-$track'));
        await tester.ensureVisible(chip);
        await tester.tap(chip);
        await settle(tester);
        final profile = await tester.runAsync(
          () => LearnerProfiles(db, clock: time.clock).current(),
        );
        expect(profile!.activeCertificationId, track);
        expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
        final cards = await tester.runAsync(
          () => StudyPlanner(db, clock: time.clock).cards(track),
        );
        expect(cards, hasLength([1, 1, 2, 2, 1][index]));
        expect(
          cards!.any((card) => card.itemId == 'ki_barolo_min_ageing'),
          isFalse,
        );
      }
      final states = await tester.runAsync(
        () => db.select(db.reviewStates).get(),
      );
      final events = await tester.runAsync(
        () => db.select(db.reviewEvents).get(),
      );
      expect(states!.map((row) => row.toJson()).toList(), originalStates);
      expect(events!.map((row) => row.toJson()).toList(), originalEvents);
      expect(tester.takeException(), isNull);
    },
  );

  testApp('tapping the selected chip keeps the active track', (tester) async {
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L1'),
    );
    await screen(tester);
    await tester.tap(find.byKey(const ValueKey('track-WSET_L1')));
    await settle(tester);
    final profile = await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).current(),
    );
    expect(profile!.activeCertificationId, 'WSET_L1');
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('track-WSET_L1')))
          .selected,
      isTrue,
    );
  });
}
