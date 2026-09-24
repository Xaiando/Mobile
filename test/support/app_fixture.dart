import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';

/// A widget test of the whole app.
///
/// Screens follow the database through Drift stream queries. When the app
/// unmounts, Riverpod cancels them and Drift closes each one on a zero-delay
/// timer; the test unmounts the app and runs those timers before it ends,
/// even when it fails.
void testApp(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (tester) async {
    try {
      await body(tester);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    }
  });
}

/// Pumps the app on [db] and waits until it settles.
Future<void> pumpApp(
  WidgetTester tester,
  AppDatabase db, {
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
