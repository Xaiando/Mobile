import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/features/practice/map_practice_screen.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp('a region starts a map-only session on the selected study track', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(NavigationDestination, 'Practice'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('practice-maps-open')));
    await tester.pumpAndSettle();
    expect(find.byType(MapPracticeScreen), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('map-region-search')),
      'Chablis',
    );
    await tester.pumpAndSettle();
    final region = find.byKey(const ValueKey('map-practice-n_geo_chablis'));
    expect(region, findsOneWidget);
    await tester.ensureVisible(region);
    await tester.tap(region);
    await tester.pumpAndSettle();
    expect(find.byType(PracticeScreen), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PracticeScreen)),
    );
    final turn = container.read(studySessionProvider).value!.turn!;
    expect(turn.exercise.formatId, startsWith('map_'));
    expect(find.textContaining('The session stopped'), findsNothing);
  });
}
