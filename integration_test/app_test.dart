// Runs the real app on a device, with its on-device database: it opens,
// installs the bundled curriculum, and a learner picks a track, studies
// a card and starts a tasting. CI runs it on the Windows desktop:
//
//   flutter test integration_test -d windows --dart-define=SOMMELIER_DATABASE=integration
//
// The database name keeps it away from a learner's own data.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/app/learner_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  String describeState<T>(AsyncValue<T> state) => state.when(
    data: (_) => 'data',
    loading: () => 'loading',
    error: (error, _) => 'error: $error',
  );

  String startupSnapshot(WidgetTester tester) {
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
        .where((text) => text.isNotEmpty)
        .take(20)
        .toList();
    final spinners = find.byType(CircularProgressIndicator).evaluate().length;
    var startup = 'app not mounted';
    var settings = 'app not mounted';
    final appFinder = find.byType(SommelierApp);
    if (appFinder.evaluate().isNotEmpty) {
      final container = ProviderScope.containerOf(
        tester.element(appFinder),
        listen: false,
      );
      startup = describeState(container.read(appStartupProvider));
      settings = describeState(container.read(settingsProvider));
    }
    return 'startup=$startup; settings=$settings; spinners=$spinners; '
        'visibleText=$visibleText';
  }

  /// Pumps frames until [found] holds, or fails after [timeout]: startup
  /// opens the database and installs the curriculum in the background.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() found, {
    required String what,
    Duration timeout = const Duration(seconds: 90),
    Duration? diagnosticAt,
  }) async {
    final startedAt = DateTime.now();
    var checkpointLogged = false;
    while (!found()) {
      final elapsed = DateTime.now().difference(startedAt);
      if (!checkpointLogged &&
          diagnosticAt != null &&
          elapsed >= diagnosticAt) {
        debugPrint(
          'STARTUP_CHECKPOINT after $elapsed: ${startupSnapshot(tester)}',
        );
        checkpointLogged = true;
      }
      if (elapsed >= timeout) {
        fail(
          'timed out waiting for $what after $elapsed; '
          '${startupSnapshot(tester)}',
        );
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    if (diagnosticAt != null) {
      debugPrint('STARTUP_READY after ${DateTime.now().difference(startedAt)}');
    }
  }

  testWidgets('starts, installs the curriculum, studies and tastes', (
    tester,
  ) async {
    app.main();

    // A fresh database starts with onboarding: the age confirmation, how
    // the app works, then the track (backlog R1).
    final ofAge = find.text('I am of legal drinking age where I live.');
    await pumpUntil(
      tester,
      () => ofAge.evaluate().isNotEmpty,
      what: 'onboarding',
      timeout: const Duration(seconds: 180),
      diagnosticAt: const Duration(seconds: 90),
    );
    await tester.tap(ofAge);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    final track = find.text('WSET Level 3');
    await pumpUntil(
      tester,
      () => track.evaluate().isNotEmpty,
      what: 'the track picker',
    );
    await tester.tap(track);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start studying'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Practice'));
    await tester.pumpAndSettle();
    // Home's own button is offstage now, so this finds the Practice one.
    final start = find.text('Start session');
    await pumpUntil(
      tester,
      () => start.evaluate().isNotEmpty,
      what: 'the session start',
    );
    await tester.tap(start);

    // A card: a multiple-choice question or a flashcard.
    final flashcard = find.text('Show answer');
    final options = find.byType(OutlinedButton);
    await pumpUntil(
      tester,
      () => flashcard.evaluate().isNotEmpty || options.evaluate().isNotEmpty,
      what: 'the first card',
    );
    if (flashcard.evaluate().isNotEmpty) {
      await tester.tap(flashcard);
    } else {
      await tester.tap(options.first);
    }
    await tester.pumpAndSettle();

    // A tasting on the track's grid saves each answer as it is chosen
    // (backlog T2).
    await tester.tap(find.text('Tasting').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New tasting'));
    await tester.pumpAndSettle();
    final begin = find.text('Start tasting');
    await pumpUntil(
      tester,
      () => begin.evaluate().isNotEmpty,
      what: 'the tasting grids',
    );
    await tester.tap(begin);
    final bright = find.widgetWithText(ChoiceChip, 'Bright');
    await pumpUntil(
      tester,
      () => bright.evaluate().isNotEmpty,
      what: 'the tasting grid',
    );
    await tester.tap(bright);
    await pumpUntil(
      tester,
      () => tester.widget<ChoiceChip>(bright).selected,
      what: 'the saved answer',
    );
    expect(tester.takeException(), isNull);
  });
}
