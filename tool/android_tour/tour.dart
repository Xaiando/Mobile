// A walk through the app's main screens, in the looks a phone can be set to.
//
// A phone's owner can pick a larger text size and dark mode, and a layout that
// fits the default text can overflow at the largest. The walk visits each main
// screen in each look, takes a shot of it, and reports any exception the
// framework raised on the way, a layout overflow above all.
//
// Two hosts run it:
//
// * tool/android_tour/tour_test.dart, on an Android emulator through
//   `flutter drive` (tool/android/screen_tour.sh). A shot there is a line in
//   logcat that the script answers with a real screenshot.
// * test/tool/android_tour_test.dart, on the desktop test runner in the normal
//   suite, so that a renamed button breaks the tour on the next pull request
//   instead of at the next emulator run. Its font is the test font, so only
//   the default look can be trusted there.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/app/router.dart';

/// The text size and brightness the app is shown at.
class TourLook {
  const TourLook(this.name, {this.textScale = 1, this.dark = false});

  final String name;

  /// The system font scale: Samsung's slider goes to about 1.3, and Android's
  /// accessibility settings to 2.
  final double textScale;

  final bool dark;
}

/// The looks the emulator walk visits.
const tourLooks = [
  TourLook('light'),
  TourLook('dark', dark: true),
  TourLook('large', textScale: 1.3),
  TourLook('huge', textScale: 2),
];

/// Shows [name] to whoever takes the shot.
typedef TourShot = Future<void> Function(WidgetTester tester, String name);

/// What a walk found.
class TourReport {
  /// A screen that failed to appear, or an exception raised while it did.
  final problems = <String>[];

  /// Milliseconds from asking for a screen to its settling, by shot name.
  final timings = <String, int>{};

  /// The shots taken, in order.
  final shots = <String>[];
}

/// Pumps frames until [found] holds, or [timeout] passes.
Future<bool> pumpUntilFound(
  WidgetTester tester,
  bool Function() found, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final started = DateTime.now();
  while (!found()) {
    if (DateTime.now().difference(started) >= timeout) return false;
    await tester.pump(const Duration(milliseconds: 200));
  }
  return true;
}

/// Lets the screen settle, without hanging on an animation that never ends.
Future<void> settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 20),
    );
  } on FlutterError catch (error) {
    if (!error.message.contains('pumpAndSettle timed out')) rethrow;
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Visits the main screens in each of [looks] and returns what it found.
///
/// The app is running, with onboarding done and a track chosen. A screen that
/// cannot be reached is a problem in the report; the walk goes on to the next
/// one. With [layoutProblems] false, a layout overflow is not a problem: the
/// desktop test font is wider than any real one.
Future<TourReport> walkMainScreens(
  WidgetTester tester, {
  required List<TourLook> looks,
  required TourShot shoot,
  bool layoutProblems = true,
}) async {
  final report = TourReport();
  for (final look in looks) {
    final walk = _Walk(tester, report, look, shoot, layoutProblems);
    walk.applyLook();
    try {
      await walk.run();
    } finally {
      tester.platformDispatcher
        ..clearTextScaleFactorTestValue()
        ..clearPlatformBrightnessTestValue();
    }
  }
  return report;
}

class _Walk {
  _Walk(this.tester, this.report, this.look, this.shoot, this.layoutProblems);

  final WidgetTester tester;
  final TourReport report;
  final TourLook look;
  final TourShot shoot;
  final bool layoutProblems;

  void applyLook() {
    tester.platformDispatcher
      ..textScaleFactorTestValue = look.textScale
      ..platformBrightnessTestValue = look.dark
          ? Brightness.dark
          : Brightness.light;
  }

  GoRouter get router => ProviderScope.containerOf(
    tester.element(find.byType(SommelierApp)),
    listen: false,
  ).read(routerProvider);

  /// What the framework raised since the last look at it: an overflow is
  /// reported by the framework, not thrown, and the test binding keeps it.
  void collectException(String where) {
    final exception = tester.takeException();
    if (exception == null) return;
    final text = '$exception'.trim();
    if (!layoutProblems && text.contains('overflowed')) return;
    final firstLines = text.split('\n').take(3).join(' ');
    report.problems.add('${look.name} $where: $firstLines');
  }

  Future<void> go(String path, String name) async {
    final timer = Stopwatch()..start();
    router.go(path);
    await settle(tester);
    report.timings['${look.name}-$name'] = timer.elapsedMilliseconds;
  }

  Future<void> capture(String name) async {
    await settle(tester);
    collectException(name);
    report.shots.add('${look.name}-$name');
    await shoot(tester, '${look.name}-$name');
  }

  /// One part of the walk: its failure is a problem, not the end of the walk.
  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
    } on Object catch (error) {
      report.problems.add('${look.name} $name: ${'$error'.split('\n').first}');
    }
    collectException(name);
  }

  Future<void> run() async {
    await step('home', () async {
      await go('/home', 'home');
      await capture('home');
    });
    await step('study', () async {
      await go('/study', 'study');
      await capture('study');
      final lesson = find.byType(ListTile);
      if (lesson.evaluate().isEmpty) {
        throw StateError('Study listed no lessons');
      }
      await tester.tap(lesson.first);
      await settle(tester);
      await capture('study-lesson');
      // The scrim of the bottom sheet closes it.
      await tester.tapAt(const Offset(8, 8));
      await settle(tester);
    });
    await step('practice', () async {
      await go('/practice', 'practice');
      await capture('practice');
      // A session left open by the previous look is still on this tab.
      final startSession = find.widgetWithText(FilledButton, 'Start session');
      if (startSession.evaluate().isNotEmpty) await tester.tap(startSession);
      final flashcard = find.text('Show answer');
      final options = find.byType(OutlinedButton);
      final arrived = await pumpUntilFound(
        tester,
        () => flashcard.evaluate().isNotEmpty || options.evaluate().isNotEmpty,
      );
      if (!arrived) throw StateError('no first card within a minute');
      await capture('practice-card');
      if (flashcard.evaluate().isNotEmpty) {
        await tester.tap(flashcard);
      } else {
        await tester.tap(options.first);
      }
      await settle(tester);
      await capture('practice-answer');
    });
    await step('tasting', () async {
      await go('/tasting', 'tasting');
      await capture('tasting');
      await go('/tasting/new', 'tasting-new');
      await capture('tasting-new');
      final begin = find.text('Start tasting');
      await tester.ensureVisible(begin);
      await tester.pump();
      await tester.tap(begin);
      final grid = find.byType(ChoiceChip);
      final arrived = await pumpUntilFound(
        tester,
        () => grid.evaluate().isNotEmpty,
      );
      if (!arrived) throw StateError('no tasting grid within a minute');
      await capture('tasting-grid');
    });
    await step('cellar', () async {
      await go('/cellar', 'cellar');
      await capture('cellar');
      await go('/cellar/new', 'cellar-new');
      await capture('cellar-new');
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
      await settle(tester);
      await capture('cellar-new-bottom');
    });
    await step('settings', () async {
      await go('/settings', 'settings');
      await capture('settings');
      await tester.scrollUntilVisible(find.text('Erase all data'), 300);
      await settle(tester);
      await capture('settings-data');
    });
    await step('about', () async {
      await go('/settings/about', 'about');
      await capture('about');
    });
    for (final (path, name) in const [
      ('/practice/rehearsal', 'rehearsal'),
      ('/practice/cms-rehearsal', 'cms-rehearsal'),
      ('/tasting/paired', 'tasting-paired'),
      ('/tasting/guided', 'tasting-guided'),
    ]) {
      await step(name, () async {
        await go(path, name);
        await capture(name);
      });
    }
    await step('home again', () => go('/home', 'home-again'));
  }
}
