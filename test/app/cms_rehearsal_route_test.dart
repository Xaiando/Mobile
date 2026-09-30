import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/cms_rehearsal/cms_rehearsal_screen.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/curriculum_fixture.dart';
import '../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalRepository cms;
  late RehearsalRepository wset;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 9, 30, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) => File(path).readAsBytes(),
    ).ensureCurrent(bundledDataset());
    await seedSchedulerConfig(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    wset = RehearsalRepository(
      db,
      bank: RehearsalBank.fromJson(
        File('assets/study/wset_rehearsal.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(73),
    );
    cms = CmsRehearsalRepository(
      db,
      bank: CmsRehearsalBank.fromJson(
        File('assets/study/cms_certified_rehearsal.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(74),
    );
  });
  tearDown(() => db.close());

  testApp(
    'CMS Home action starts independent service practice without replacing WSET draft',
    (tester) async {
      final savedWset = await tester.runAsync(() => wset.start(3));
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpApp(
        tester,
        db,
        overrides: [
          appStartupProvider.overrideWith(
            (ref) async => StorageDurability.persistent,
          ),
          clockProvider.overrideWithValue(time.clock),
          cmsRehearsalRepositoryProvider.overrideWith((ref) async => cms),
        ],
      );
      final tile = find.widgetWithText(ListTile, 'CMS Certified rehearsal');
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CmsRehearsalScreen), findsOneWidget);
      final start = find.byKey(const ValueKey('cms-rehearsal-start-service'));
      await tester.ensureVisible(start);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pumpAndSettle();
      final cmsAttempt = await tester.runAsync(cms.current);
      final wsetAttempt = await tester.runAsync(wset.current);
      final profile = await tester.runAsync(
        () => LearnerProfiles(db).current(),
      );
      expect(cmsAttempt!.section, CmsRehearsalSection.service);
      expect(
        cmsAttempt.deadline.difference(cmsAttempt.startedAt).inSeconds,
        900,
      );
      expect(wsetAttempt!.id, savedWset!.id);
      expect(wsetAttempt.deadline, savedWset.deadline);
      expect(profile!.activeCertificationId, 'WSET_L3');
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
