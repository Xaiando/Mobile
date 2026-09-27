import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/study/study_screen.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  const grape = 'The permitted principal variety makes white wine in Chablis.';
  const soil = 'Chablis vineyards include Kimméridgian marl.';

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "UPDATE knowledge_items SET assertion_text='$grape' WHERE id='ki_chablis_grape'",
        "UPDATE knowledge_items SET assertion_text='$soil' WHERE id='ki_chablis_soil'",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> screen(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          appStartupProvider.overrideWith(
            (ref) async => StorageDurability.persistent,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const StudyScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byKey(const ValueKey('study-search')), text);
    await settle(tester);
  }

  testApp(
    'search matches assertions, node names, synonyms and folded accents',
    (tester) async {
      await screen(tester);
      expect(find.text('2 of 2 facts'), findsOneWidget);
      await search(tester, 'CHARDONNAY');
      expect(find.text(grape), findsOneWidget);
      expect(find.text(soil), findsNothing);
      await search(tester, 'beaunois');
      expect(find.text(grape), findsOneWidget);
      expect(find.text('1 of 2 facts'), findsOneWidget);
      await search(tester, 'kimmeridgian');
      expect(find.text(soil), findsOneWidget);
      expect(find.text(grape), findsNothing);
      await search(tester, 'viticulture');
      expect(find.text(soil), findsOneWidget);
      await search(tester, 'white chablis');
      expect(find.text(grape), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testApp('topic focus combines with search and reset restores all cards', (
    tester,
  ) async {
    await screen(tester);
    await tester.tap(find.byKey(const ValueKey('study-topic-all')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Viticulture').last);
    await tester.pumpAndSettle();
    expect(find.text(grape), findsNothing);
    expect(find.text(soil), findsOneWidget);
    await search(tester, 'chardonnay');
    expect(find.text('No facts match these filters.'), findsOneWidget);
    expect(find.text('0 of 2 facts'), findsOneWidget);
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 facts'), findsOneWidget);
    expect(find.text(grape), findsOneWidget);
    expect(find.text(soil), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('study-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testApp('search never exposes an unmapped fact and follows track switching', (
    tester,
  ) async {
    await screen(tester);
    await search(tester, 'Barolo');
    expect(find.text('No facts match these filters.'), findsOneWidget);
    expect(find.textContaining('38 months'), findsNothing);
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('CMS_CERTIFIED'),
    );
    await settle(tester);
    expect(find.text('1 of 1 facts'), findsOneWidget);
    expect(find.text(grape), findsOneWidget);
    expect(find.text(soil), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('study-search')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testApp('filtered details retain badges, memory and original citations', (
    tester,
  ) async {
    await screen(tester);
    await search(tester, 'beaunois');
    expect(find.byTooltip('Unverified'), findsOneWidget);
    expect(find.text('Core · New'), findsOneWidget);
    await tester.tap(find.text(grape));
    await settle(tester);
    expect(find.text('Sources'), findsOneWidget);
    expect(find.text('Not studied yet.'), findsOneWidget);
    expect(
      find.text(
        "Cahier des charges de l'appellation d'origine contrôlée « Chablis »",
      ),
      findsOneWidget,
    );
  });

  testApp('search and empty feedback fit a phone with larger text', (
    tester,
  ) async {
    await screen(tester, scale: 2);
    await search(tester, 'no matching example');
    expect(find.text('No facts match these filters.'), findsOneWidget);
    expect(find.text('Reset filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
