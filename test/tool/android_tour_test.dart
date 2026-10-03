import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/app/router.dart';
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

  /// A window of the Galaxy Z Fold 6's, or the phone the test began in.
  void showShape(WidgetTester tester, String shape, Size phone, double ratio) {
    if (shape == 'phone') {
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = ratio;
    } else {
      tester.view.physicalSize = foldWindowSizes[shape]!;
      tester.view.devicePixelRatio = foldDevicePixelRatio;
    }
  }

  testApp('the resize walk keeps a typed producer through every Fold shape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();

    final shots = <String>[];
    final report = await walkWindowShapes(
      tester,
      resize: (tester, shape) async =>
          showShape(tester, shape, const Size(1080, 2340), 3),
      shoot: (tester, name) async => shots.add(name),
      layoutProblems: false,
    );

    expect(report.problems, isEmpty);
    expect(shots, [
      for (final shape in resizeWalkShapes) 'resize-$shape-editor',
    ]);
    // The Fold's windows in logical pixels, and the walk's way back.
    expect(report.windows, [
      startsWith('fold-open 707x823 dp'),
      startsWith('fold-cover 369x905 dp'),
      startsWith('fold-open-wide 823x707 dp'),
      startsWith('fold-split 354x823 dp'),
      startsWith('phone 360x780 dp'),
    ]);
  });

  testApp('the resize walk notices a form that a resize lost', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();

    final report = await walkWindowShapes(
      tester,
      shapes: const ['fold-open', 'fold-cover'],
      resize: (tester, shape) async {
        showShape(tester, shape, const Size(1080, 2340), 3);
        if (shape == 'fold-open') {
          // What a restart of the screen would do to an unsaved form.
          ProviderScope.containerOf(
            tester.element(find.byType(SommelierApp)),
            listen: false,
          ).read(routerProvider).go('/home');
        }
      },
      shoot: (tester, name) async {},
      layoutProblems: false,
    );

    expect(
      report.problems,
      contains(
        'resize fold-open: asked for /cellar/new but the app is at /home',
      ),
    );
    expect(
      report.problems,
      contains(
        'resize fold-open: the producer typed before the resize is gone',
      ),
    );
  });

  testApp('the resize walk reports a window that never changed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();

    final report = await walkWindowShapes(
      tester,
      shapes: const ['fold-open'],
      resize: (tester, shape) async =>
          throw StateError('the window did not change for $shape within 40 s'),
      shoot: (tester, name) async {},
      layoutProblems: false,
    );

    expect(report.problems, [
      'resize fold-open: Bad state: the window did not change for fold-open '
          'within 40 s',
    ]);
    expect(report.windows, isEmpty);
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
