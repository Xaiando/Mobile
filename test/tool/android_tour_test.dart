import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sommelier/core/database/app_database.dart';

import '../../tool/android_tour/tour.dart';
import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// The Android emulator's screen tour (tool/android_tour) visits each main
/// screen by its route and a few labels. Run here at the default look, it
/// breaks on the next pull request when a screen or a label it needs goes
/// away, instead of at the next emulator run.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp('the tour reaches every main screen at the default look', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();

    final shots = <String>[];
    final report = await walkMainScreens(
      tester,
      looks: const [TourLook('light')],
      shoot: (tester, name) async => shots.add(name),
    );

    expect(report.problems, isEmpty);
    expect(
      shots,
      containsAll([
        'light-home',
        'light-study',
        'light-study-lesson',
        'light-practice',
        'light-practice-card',
        'light-practice-answer',
        'light-tasting',
        'light-tasting-new',
        'light-tasting-grid',
        'light-cellar',
        'light-cellar-new',
        'light-cellar-new-bottom',
        'light-settings',
        'light-settings-data',
        'light-about',
        'light-rehearsal',
        'light-cms-rehearsal',
        'light-tasting-paired',
        'light-tasting-guided',
      ]),
    );
  });

  testWidgets('the tour notices a missing route and a redirect', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/here',
      routes: [
        GoRoute(path: '/here', builder: (context, state) => const Text('here')),
        GoRoute(path: '/old', redirect: (context, state) => '/here'),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(routeProblem(router, '/here'), isNull);

    router.go('/old');
    await tester.pumpAndSettle();
    expect(routeProblem(router, '/old'), contains('the app is at /here'));

    router.go('/gone');
    await tester.pumpAndSettle();
    expect(routeProblem(router, '/gone'), contains('error page'));
  });
}
