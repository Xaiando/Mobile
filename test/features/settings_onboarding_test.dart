import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/settings/user_settings.dart';
import 'package:sommelier/core/study/learner_profile.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = openTestDatabase());
  tearDown(() => db.close());

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testApp('onboarding confirms the age, explains, picks a track, and is '
      'shown once', (tester) async {
    phone(tester);
    await pumpApp(tester, db, onboarded: false);
    expect(find.text('Welcome to Sommelier Study Companion'), findsOneWidget);

    final next = find.widgetWithText(FilledButton, 'Continue');
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tap(tester, find.text('I am of legal drinking age where I live.'));
    await tap(tester, next);
    expect(find.text('How it works'), findsOneWidget);
    await tap(tester, find.widgetWithText(FilledButton, 'Continue'));

    final start = find.widgetWithText(FilledButton, 'Start studying');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);
    await tap(tester, find.text('WSET Level 3'));
    await tap(tester, start);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Due now'), findsOneWidget);

    final settings = await tester.runAsync(() => LearnerSettings(db).current());
    expect(settings!.isOnboarded, isTrue);
  });

  testApp('settings change the session limits and the appearance', (
    tester,
  ) async {
    phone(tester);
    await pumpApp(tester, db);
    await tap(tester, find.text('WSET Level 3'));
    await tap(tester, find.byTooltip('Settings'));
    expect(find.text('Settings'), findsOneWidget);

    await tap(tester, find.text('15'));
    await tap(tester, find.text('25').last);
    await tap(tester, find.text('Dark'));
    final profile = await tester.runAsync(() => LearnerProfiles(db).current());
    expect(profile!.sessionSize, 25);
    final settings = await tester.runAsync(() => LearnerSettings(db).current());
    expect(settings!.appearance, AppearanceMode.dark);
    expect(
      Theme.of(tester.element(find.text('Settings'))).brightness,
      Brightness.dark,
    );
  });

  testApp('About credits every source of the curriculum', (tester) async {
    // Tall enough for the whole list to be built at once.
    tester.view.physicalSize = const Size(1080, 30000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    await tap(tester, find.byTooltip('Settings'));
    await tap(tester, find.text('About, sources and licences'));
    final sources = await tester.runAsync(
      () => db.select(db.sourceCitations).get(),
    );
    expect(sources, isNotEmpty);
    for (final source in sources!) {
      expect(find.text(source.title), findsOneWidget, reason: source.id);
    }
    expect(find.text('Open-source licences'), findsOneWidget);

    // Back goes to Settings, then to where Settings was opened from.
    await tap(tester, find.byType(BackButton));
    expect(find.text('About, sources and licences'), findsOneWidget);
    await tap(tester, find.byType(BackButton));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Settings'), findsNothing);
  });

  testApp('a wide window puts the modules beside a navigation rail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tap(tester, find.text('Cellar'));
    expect(find.text('Your wine journal'), findsOneWidget);
  });
}
