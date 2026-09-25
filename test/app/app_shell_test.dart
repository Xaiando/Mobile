import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';

import '../support/app_fixture.dart';
import '../support/curriculum_fixture.dart';
import '../support/fixture.dart';

class _OpenFailure implements Exception {
  @override
  String toString() => 'disk unavailable';
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  testApp('Material 3 shell with the five modules', (tester) async {
    await pumpApp(tester, db);

    expect(
      Theme.of(tester.element(find.byType(NavigationBar))).useMaterial3,
      isTrue,
    );
    for (final label in ['Home', 'Study', 'Practice', 'Tasting', 'Cellar']) {
      expect(find.widgetWithText(NavigationDestination, label), findsOneWidget);
    }
    expect(find.textContaining('study dashboard'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Tasting'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tasting practice'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Cellar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('wine journal'), findsOneWidget);
  });

  testApp('hydrates the bundled curriculum on first launch', (tester) async {
    await pumpApp(tester, db);
    final release = await tester.runAsync(
      () => db.select(db.curriculumReleases).getSingle(),
    );
    final nodes = await tester.runAsync(
      () => db.select(db.knowledgeNodes).get(),
    );
    final bundled = bundledDataset();
    expect(release!.version, bundled.version);
    // The checksum covers every file, so each include reached the app bundle.
    expect(release.checksum, bundled.checksum);
    expect(nodes!.length, greaterThanOrEqualTo(50));
  });

  testApp('no notice when the database is durable', (tester) async {
    await pumpApp(tester, db);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testApp('warns when web storage keeps nothing', (tester) async {
    await pumpApp(
      tester,
      db,
      overrides: [
        storageReportProvider.overrideWithValue(
          StorageReport()..durability = StorageDurability.memoryOnly,
        ),
      ],
    );
    expect(find.textContaining('cannot store data'), findsOneWidget);
  });

  testApp('warns when web storage is unsafe across tabs', (tester) async {
    await pumpApp(
      tester,
      db,
      overrides: [
        storageReportProvider.overrideWithValue(
          StorageReport()..durability = StorageDurability.singleTabOnly,
        ),
      ],
    );
    expect(find.textContaining('one browser tab'), findsOneWidget);
  });

  testApp('shows a database failure at once instead of retrying', (
    tester,
  ) async {
    await pumpApp(
      tester,
      db,
      overrides: [
        appStartupProvider.overrideWith((ref) async => throw _OpenFailure()),
      ],
    );
    expect(
      find.textContaining('could not be opened: disk unavailable'),
      findsOneWidget,
    );
  });
}
