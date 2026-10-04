import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/features/diploma_tasting/diploma_tasting_flight_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

Future<void> _seedDiploma(AppDatabase db) => db.writeCurriculum(
  () => runSql(db, [
    "INSERT INTO tasting_grids VALUES ('tg_structured', 'WSET_SAT', '1.0', 'Structured tasting')",
    "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', 'tg_structured', 1, 'certification', NULL)",
    "INSERT INTO tasting_grid_attributes VALUES ('tg_structured', 'sweetness', 'Taste', 'Sweetness', 1, 'single', 1), ('tg_structured', 'aromas', 'Smell', 'Aromas', 2, 'multi', 0)",
    "INSERT INTO tasting_grid_values VALUES ('tg_structured', 'sweetness', 'dry', 'Dry', 1, NULL), ('tg_structured', 'sweetness', 'sweet', 'Sweet', 2, NULL), ('tg_structured', 'aromas', 'citrus', 'Citrus', 1, NULL), ('tg_structured', 'aromas', 'bready', 'Bread', 2, NULL)",
  ]),
);

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaTastingFlightRepository repository;
  setUp(() async {
    final previousFatalHitTests = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() {
      WidgetController.hitTestWarningShouldBeFatal = previousFatalHitTests;
    });
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await _seedDiploma(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = DiplomaTastingFlightRepository(
      db,
      bank: DiplomaTastingBank.fromJson(
        File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(81),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showScreen(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaTastingFlightRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(home: screen),
      ),
    );
    await settle(tester);
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder found, {
    double delta = 240,
  }) async {
    if (found.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        found,
        delta,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 20,
      );
    }
    await tester.ensureVisible(found);
    await tester.pumpAndSettle();
    expect(found, findsOneWidget);
    expect(found.hitTestable(), findsOneWidget);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final found = find.byKey(ValueKey(key));
    await reveal(
      tester,
      found,
      delta: key.startsWith('diploma-flight-step-') ? -240 : 240,
    );
    await tester.tap(found.hitTestable());
    await settle(tester);
  }

  testApp(
    'named session exposes six wines and narrow switching reloads exact separate prose',
    (tester) async {
      await showScreen(
        tester,
        const DiplomaTastingFlightScreen(unitId: 'D3_1'),
      );
      expect(find.textContaining('six actual still wines'), findsOneWidget);
      expect(
        find.textContaining('session 1: structure and origin'),
        findsOneWidget,
      );
      await tapKey(tester, 'diploma-flight-start');
      final wineOne = find.byKey(
        const ValueKey('diploma-flight-evidence-0-description'),
      );
      await reveal(tester, wineOne);
      await tester.enterText(wineOne, 'Named wine one exact draft.');
      await tapKey(tester, 'diploma-flight-step-5');
      expect(find.text('Wine 6 of 6'), findsOneWidget);
      final wineSix = find.byKey(
        const ValueKey('diploma-flight-evidence-5-description'),
      );
      await reveal(tester, wineSix);
      await tester.enterText(wineSix, 'Named wine six distinct draft.');
      await tapKey(tester, 'diploma-flight-step-0');
      final saved = (await repository.current('D3_1'))!;
      expect(
        saved.wines[0].evidence['description'],
        'Named wine one exact draft.',
      );
      expect(
        saved.wines[5].evidence['description'],
        'Named wine six distinct draft.',
      );
      expect(saved.wines.every((wine) => !wine.physicallyTasted), isTrue);
      await reveal(tester, wineOne);
      expect(
        tester.widget<TextFormField>(wineOne).initialValue,
        'Named wine one exact draft.',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await showScreen(
        tester,
        const DiplomaTastingFlightScreen(unitId: 'D3_1'),
      );
      expect((await repository.current('D3_1'))!.id, saved.id);
      await reveal(tester, wineOne);
      expect(
        tester.widget<TextFormField>(wineOne).initialValue,
        'Named wine one exact draft.',
      );
      await tapKey(tester, 'diploma-flight-step-5');
      await reveal(tester, wineSix);
      expect(
        tester.widget<TextFormField>(wineSix).initialValue,
        'Named wine six distinct draft.',
      );
      await tapKey(tester, 'diploma-flight-step-6');
      expect(find.text('Complete physical wines: 0 of 6'), findsOneWidget);
      final comparison = find.widgetWithText(
        TextFormField,
        'Six-wine comparison',
      );
      await reveal(tester, comparison);
      expect(comparison, findsOneWidget);
      expect(await repository.current('D3'), isNull);
      expect(await repository.current('D3_2'), isNull);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'second named session keeps its focus and saved wine six is read only',
    (tester) async {
      final flight = await repository.start('D3_2');
      for (var wine = 0; wine < 6; wine++) {
        await repository.acknowledgePhysical(flight.id, wine, true);
        await repository.choose(flight.id, wine, 'sweetness', {'dry'});
        for (final prompt in flight.wines[wine].prompts) {
          await repository.saveEvidence(
            flight.id,
            wine,
            prompt.id,
            'Saved fixture wine ${wine + 1} ${prompt.id}.',
          );
        }
      }
      await repository.saveReflection(flight.id, 'Saved six-wine comparison.');
      await repository.saveSelfReview(
        flight.id,
        'Saved limitations and evidence review.',
      );
      await repository.markSelfReviewed(flight.id);
      final saved = await repository.finish(flight.id);
      await showScreen(
        tester,
        const DiplomaTastingFlightScreen(unitId: 'D3_2'),
      );
      expect(
        find.textContaining('session 2: style and production'),
        findsOneWidget,
      );
      await tapKey(tester, 'diploma-flight-view-${saved.id}');
      expect(find.byType(SavedDiplomaTastingFlightScreen), findsOneWidget);
      await tapKey(tester, 'diploma-flight-saved-wine-5');
      expect(find.text('Wine 6 of 6'), findsOneWidget);
      expect(find.text('Saved fixture wine 6 description.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect((await repository.read(saved.id)).toJson(), saved.toJson());
      expect(await repository.current('D3_2'), isNull);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
