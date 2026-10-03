import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/features/settings/your_data.dart';

import '../../tool/android_tour/roundtrip.dart';
import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// The backup round trip that the Android emulator runs
/// (tool/android_tour/roundtrip.dart): a wine and its photo are saved,
/// exported, lost, imported back, and a file that is not a backup changes
/// nothing. Run here on the desktop test runner, it breaks on the next pull
/// request when a screen or label it uses goes away, instead of at the next
/// emulator run.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp(
    'a backup restores the wine and its photo, and a bad file is refused',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final files = MemoryBackupFiles();
      await pumpApp(
        tester,
        db,
        overrides: [backupFilesProvider.overrideWithValue(files)],
      );

      final problems = await roundTripYourData(tester, files);

      expect(problems, isEmpty);
      expect(files.saves, 1);
      expect(files.opens, 2);
    },
  );
}
