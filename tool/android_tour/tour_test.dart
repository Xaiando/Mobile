// The Android emulator's host of the screen tour (tool/android_tour/tour.dart).
//
// It starts the real app on a fresh database, goes through onboarding at a
// large text size, then walks the main screens in every look. Each shot is a
// line in logcat, "TOUR_SHOT <name>", that tool/android/screen_tour.sh
// answers with a real screenshot while the app waits.
//
//   bash tool/android/screen_tour.sh build/android-tour
//
// It is a `flutter drive` target, not an integration_test file, so that
// `flutter test integration_test` on Windows does not pick it up.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sommelier/main.dart' as app;

import 'tour.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Tells the host script to take a screenshot, and waits for it.
  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 100));
    debugPrint('TOUR_SHOT $name');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2500)),
    );
  }

  Future<void> waitFor(
    WidgetTester tester,
    Finder finder,
    String what, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final found = await pumpUntilFound(
      tester,
      () => finder.evaluate().isNotEmpty,
      timeout: timeout,
    );
    if (!found) fail('$what did not appear within ${timeout.inSeconds} s');
  }

  testWidgets('every main screen, in light, dark and large text', (
    tester,
  ) async {
    app.main();

    // The first launch installs the curriculum, which takes minutes on an
    // emulator. A shot of the wait shows the notice that explains it.
    final ofAge = find.text('I am of legal drinking age where I live.');
    final startedAt = DateTime.now();
    var shotTheWait = false;
    while (ofAge.evaluate().isEmpty) {
      final waited = DateTime.now().difference(startedAt);
      if (waited > const Duration(minutes: 12)) {
        fail('onboarding did not appear within twelve minutes');
      }
      if (!shotTheWait && waited > const Duration(seconds: 15)) {
        shotTheWait = true;
        await shoot(tester, 'startup');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    debugPrint(
      'TOUR_TIME startup ${DateTime.now().difference(startedAt).inMilliseconds}',
    );

    // Onboarding, at the largest text size a phone's own slider reaches.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    await settle(tester);
    await shoot(tester, 'onboarding-1-age');
    await tester.tap(ofAge);
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await waitFor(tester, find.text('How it works'), 'the How it works step');
    await settle(tester);
    await shoot(tester, 'onboarding-2-how');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    final track = find.text('WSET Level 3');
    await waitFor(tester, track, 'the track picker');
    await settle(tester);
    await shoot(tester, 'onboarding-3-track');
    await tester.tap(track);
    await settle(tester);
    final start = find.widgetWithText(FilledButton, 'Start studying');
    await waitFor(tester, start, 'Start studying');
    await pumpUntilFound(
      tester,
      () => tester.widget<FilledButton>(start).onPressed != null,
    );
    await shoot(tester, 'onboarding-4-start');
    await tester.tap(start);
    await settle(tester);
    tester.platformDispatcher.clearTextScaleFactorTestValue();

    final navigation = find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    );
    await waitFor(tester, navigation, 'the main navigation');

    final report = await walkMainScreens(
      tester,
      looks: tourLooks,
      shoot: shoot,
    );
    for (final MapEntry(:key, :value) in report.timings.entries) {
      debugPrint('TOUR_TIME $key $value');
    }
    for (final problem in report.problems) {
      debugPrint('TOUR_PROBLEM $problem');
    }
    debugPrint(
      'TOUR_DONE ${report.shots.length} shots, '
      '${report.problems.length} problems',
    );
    expect(
      report.problems,
      isEmpty,
      reason: 'The tour found problems:\n${report.problems.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 45)));
}
