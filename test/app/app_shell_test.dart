import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';

import '../support/fixture.dart';

class _OpenFailure implements Exception {
  @override
  String toString() => 'disk unavailable';
}

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> pumpApp(
    WidgetTester tester, {
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        retry: noProviderRetry,
        overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
        child: const SommelierApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Material 3 shell with the five modules', (tester) async {
    await pumpApp(tester);

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

  testWidgets('no notice when the database is durable', (tester) async {
    await pumpApp(tester);
    expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('warns when web storage keeps nothing', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        storageReportProvider.overrideWithValue(
          StorageReport()..durability = StorageDurability.memoryOnly,
        ),
      ],
    );
    expect(find.textContaining('cannot store data'), findsOneWidget);
  });

  testWidgets('warns when web storage is unsafe across tabs', (tester) async {
    await pumpApp(
      tester,
      overrides: [
        storageReportProvider.overrideWithValue(
          StorageReport()..durability = StorageDurability.singleTabOnly,
        ),
      ],
    );
    expect(find.textContaining('one browser tab'), findsOneWidget);
  });

  testWidgets('shows a database failure at once instead of retrying', (
    tester,
  ) async {
    await pumpApp(
      tester,
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
