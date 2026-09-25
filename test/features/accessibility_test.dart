import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

/// Backlog R1: every screen meets Flutter's accessibility guidelines for
/// tap-target size, labelled controls and text contrast, in light and dark.
void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  Future<void> meetsGuidelines(WidgetTester tester, String screen) async {
    for (final guideline in [
      androidTapTargetGuideline,
      labeledTapTargetGuideline,
      textContrastGuideline,
    ]) {
      await expectLater(
        tester,
        meetsGuideline(guideline),
        reason: '$screen: ${guideline.description}',
      );
    }
  }

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testApp('the tabs meet the guidelines${dark ? ' in dark mode' : ''}', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = dark
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester, db);

      await meetsGuidelines(tester, 'Home before a track');
      await tester.tap(find.text('WSET Level 3'));
      await tester.pumpAndSettle();
      for (final label in ['Home', 'Study', 'Practice', 'Tasting', 'Cellar']) {
        await tab(tester, label);
        await meetsGuidelines(tester, label);
      }
      await tab(tester, 'Cellar');
      await tester.tap(find.text('Log a wine'));
      await tester.pumpAndSettle();
      await meetsGuidelines(tester, 'the journal editor');
      semantics.dispose();
    });
  }

  testApp('onboarding and settings meet the guidelines', (tester) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db, onboarded: false);
    await meetsGuidelines(tester, 'onboarding');

    await tester.tap(find.text('I am of legal drinking age where I live.'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WSET Level 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start studying'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await meetsGuidelines(tester, 'settings');
    semantics.dispose();
  });
}
