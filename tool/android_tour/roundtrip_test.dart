// The Android emulator's host of the backup round trip
// (tool/android_tour/roundtrip.dart).
//
// It starts the real app on a fresh database with the platform's file dialog
// replaced by memory, goes through onboarding, and runs the walk. What it
// found is a line in logcat, "ROUNDTRIP_PROBLEM <text>", that
// tool/android/data_roundtrip.sh collects.
//
//   bash tool/android/data_roundtrip.sh build/android-roundtrip
//
// It is a `flutter drive` target, not an integration_test file, so that
// `flutter test integration_test` on Windows does not pick it up.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/core/database/database_connection.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/features/settings/your_data.dart';

import 'roundtrip.dart';
import 'tour.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('a backup restores the journal, and a bad file is refused', (
    tester,
  ) async {
    final files = MemoryBackupFiles();
    final storage = StorageReport();
    final database = openAppDatabase(
      onWebStorage: (durability) => storage.durability = durability,
    );
    await tester.pumpWidget(
      ProviderScope(
        retry: noProviderRetry,
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          storageReportProvider.overrideWithValue(storage),
          backupFilesProvider.overrideWithValue(files),
        ],
        child: const SommelierApp(),
      ),
    );

    // The first launch installs the curriculum, which takes minutes on an
    // emulator; then onboarding, as for a new learner.
    final ofAge = find.text('I am of legal drinking age where I live.');
    await waitFor(
      tester,
      ofAge,
      'onboarding',
      timeout: const Duration(minutes: 12),
    );
    await tester.tap(ofAge);
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await waitFor(tester, find.text('How it works'), 'the How it works step');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    final track = find.text('WSET Level 3');
    await waitFor(tester, track, 'the track picker');
    await settle(tester);
    await tester.tap(track);
    await settle(tester);
    final start = find.widgetWithText(FilledButton, 'Start studying');
    await waitFor(tester, start, 'Start studying');
    await pumpUntilFound(
      tester,
      () => tester.widget<FilledButton>(start).onPressed != null,
    );
    await tester.tap(start);
    await settle(tester);
    final navigation = find.byWidgetPredicate(
      (widget) => widget is NavigationBar || widget is NavigationRail,
    );
    await waitFor(tester, navigation, 'the main navigation');

    final problems = await roundTripYourData(tester, files);
    for (final problem in problems) {
      debugPrint('ROUNDTRIP_PROBLEM $problem');
    }
    debugPrint('ROUNDTRIP_DONE ${problems.length} problems');
    expect(
      problems,
      isEmpty,
      reason: 'The round trip found problems:\n${problems.join('\n')}',
    );
  }, timeout: const Timeout(Duration(minutes: 30)));
}
