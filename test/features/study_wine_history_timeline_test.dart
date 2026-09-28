import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp('wine history opens on CMS and Diploma but not WSET Levels 1–3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);

    Future<void> selectTrack(String id) async {
      await tester.runAsync(() => LearnerProfiles(db).selectTrack(id));
      await tester.pumpAndSettle();
    }

    await selectTrack('WSET_L1');
    await tester.tap(find.widgetWithText(NavigationDestination, 'Study'));
    await tester.pumpAndSettle();

    for (final id in ['WSET_L1', 'WSET_L2', 'WSET_L3']) {
      await selectTrack(id);
      expect(
        find.byKey(const ValueKey('study-wine-history-open')),
        findsNothing,
        reason: id,
      );
    }

    for (final id in ['WSET_L4', 'CMS_CERTIFIED']) {
      await selectTrack(id);
      final open = find.byKey(const ValueKey('study-wine-history-open'));
      expect(open, findsOneWidget, reason: id);
      final originalCount = tester
          .widget<Text>(find.byKey(const ValueKey('study-result-count')))
          .data;

      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('study-wine-history-timeline')),
        findsOneWidget,
      );
      final early = find.byKey(const ValueKey('study-history-early-evidence'));
      final roman = find.byKey(const ValueKey('study-history-roman'));
      expect(early, findsOneWidget);
      expect(roman, findsOneWidget);
      expect(
        tester.getTopLeft(early).dy,
        lessThan(tester.getTopLeft(roman).dy),
      );

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('study-result-count')))
            .data,
        originalCount,
      );
    }
  });
}
