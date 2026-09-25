// Runs the real app on a device, with its on-device database: it opens,
// installs the bundled curriculum, and a learner picks a track and studies
// a card. CI runs it on the Windows desktop:
//
//   flutter test integration_test -d windows --dart-define=SOMMELIER_DATABASE=integration
//
// The database name keeps it away from a learner's own data.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sommelier/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps frames until [found] holds, or fails after [timeout]: startup
  /// opens the database and installs the curriculum in the background.
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() found, {
    required String what,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final end = DateTime.now().add(timeout);
    while (!found()) {
      if (DateTime.now().isAfter(end)) fail('timed out waiting for $what');
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('starts, installs the curriculum and studies a card', (
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
    expect(tester.takeException(), isNull);
  });
}
