import 'dart:async';
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

class _PausedReflectionRepository extends DiplomaTastingFlightRepository {
  _PausedReflectionRepository(super.db, TestClock time)
    : super(
        bank: DiplomaTastingBank.fromJson(
          File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
        ),
        clock: time.clock,
        random: Random(9),
      );

  final reflectionStarted = Completer<void>();
  final releaseReflection = Completer<void>();
  int abandonCalls = 0;

  @override
  Future<DiplomaTastingFlight> saveReflection(String id, String text) async {
    if (!reflectionStarted.isCompleted) reflectionStarted.complete();
    await releaseReflection.future;
    return super.saveReflection(id, text);
  }

  @override
  Future<DiplomaTastingFlight> abandon(String id) {
    abandonCalls++;
    return super.abandon(id);
  }
}

class _PausedFinishRepository extends DiplomaTastingFlightRepository {
  _PausedFinishRepository(super.db, TestClock time)
    : super(
        bank: DiplomaTastingBank.fromJson(
          File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
        ),
        clock: time.clock,
        random: Random(9),
      );

  final finishStarted = Completer<void>();
  final releaseFinish = Completer<void>();

  @override
  Future<DiplomaTastingFlight> finish(String id) async {
    finishStarted.complete();
    await releaseFinish.future;
    return super.finish(id);
  }
}

class _FailOnceEvidenceRepository extends DiplomaTastingFlightRepository {
  _FailOnceEvidenceRepository(super.db, TestClock time)
    : super(
        bank: DiplomaTastingBank.fromJson(
          File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
        ),
        clock: time.clock,
        random: Random(10),
      );

  bool failed = false;

  @override
  Future<DiplomaTastingFlight> saveEvidence(
    String id,
    int wineIndex,
    String promptId,
    String text,
  ) async {
    if (promptId == 'description' && !failed) {
      failed = true;
      throw StateError('simulated write failure');
    }
    return super.saveEvidence(id, wineIndex, promptId, text);
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaTastingFlightRepository repository;

  setUp(() async {
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
      random: Random(9),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> showScreen(WidgetTester tester, String unitId) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaTastingFlightRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(home: DiplomaTastingFlightScreen(unitId: unitId)),
      ),
    );
    await settle(tester);
  }

  testApp('D4 setup asks for three real wines without promising a grade', (
    tester,
  ) async {
    await showScreen(tester, 'D4');
    expect(find.textContaining('three actual sparkling wines'), findsOneWidget);
    expect(find.textContaining('private practice evidence'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diploma-flight-start')));
    await settle(tester);
    expect(find.text('Wine 1 of 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('diploma-flight-step-2')), findsOneWidget);
    expect(find.textContaining('imagined wine does not count'), findsOneWidget);
    expect(
      (await tester.runAsync(() => repository.current('D4')))!.wines,
      hasLength(3),
    );
    expect(tester.takeException(), isNull);
  });

  testApp('switching wines retains physically tasted observations and prose', (
    tester,
  ) async {
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    await showScreen(tester, 'D4');
    await tester.tap(find.byKey(const ValueKey('diploma-flight-physical-0')));
    await settle(tester);
    await tester.tap(find.text('Taste'));
    await settle(tester);
    await tester.tap(
      find.byKey(const ValueKey('diploma-flight-observation-0-sweetness-dry')),
    );
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-evidence-0-description')),
      'Fine bubbles and citrus observed.',
    );
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-1')));
    await settle(tester);
    final saved = (await tester.runAsync(() => repository.read(started.id)))!;
    expect(saved.wines[0].physicallyTasted, isTrue);
    expect(saved.wines[0].observations['sweetness'], {'dry'});
    expect(saved.wines[0].evidence['description'], contains('Fine bubbles'));
    expect(saved.wines[1].evidence, isEmpty);
    expect(find.text('Wine 2 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testApp('comparison and self-review record participation only', (
    tester,
  ) async {
    final started = (await tester.runAsync(() => repository.start('D5')))!;
    await tester.runAsync(() async {
      for (var index = 0; index < 3; index++) {
        await repository.acknowledgePhysical(started.id, index, true);
        await repository.choose(started.id, index, 'sweetness', {'dry'});
        for (final prompt in started.wines[index].prompts) {
          await repository.saveEvidence(
            started.id,
            index,
            prompt.id,
            'Observed ${prompt.id} for wine ${index + 1}.',
          );
        }
      }
    });
    await showScreen(tester, 'D5');
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-3')));
    await settle(tester);
    expect(find.text('Complete physical wines: 3 of 3'), findsOneWidget);
    expect(
      find.textContaining('not a tasting score or exam result'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-comparison')),
      'Wine one had more finish than wine two or three.',
    );
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-self-review')),
      'The alcohol impression may have changed my quality judgement.',
    );
    await tester.tap(
      find.byKey(const ValueKey('diploma-flight-mark-reviewed')),
    );
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.read(started.id)))!
          .selfReviewedAt,
      isNotNull,
    );
    await tester.tap(find.byKey(const ValueKey('diploma-flight-finish')));
    await settle(tester);
    expect(find.textContaining('Physical practice recorded'), findsWidgets);
    expect(
      (await tester.runAsync(() => repository.read(started.id)))!.isSubmitted,
      isTrue,
    );
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testApp('finish freezes prose and rejects a callback after tail capture', (
    tester,
  ) async {
    final paused = _PausedFinishRepository(db, time);
    repository = paused;
    final started = (await tester.runAsync(() => repository.start('D5')))!;
    await tester.runAsync(() async {
      for (var index = 0; index < 3; index++) {
        await repository.acknowledgePhysical(started.id, index, true);
        await repository.choose(started.id, index, 'sweetness', {'dry'});
        for (final prompt in started.wines[index].prompts) {
          await repository.saveEvidence(
            started.id,
            index,
            prompt.id,
            'Observed ${prompt.id} for wine ${index + 1}.',
          );
        }
      }
      await repository.saveReflection(started.id, 'Original comparison.');
      await repository.saveSelfReview(started.id, 'Original self-review.');
      await repository.markSelfReviewed(started.id);
    });
    await showScreen(tester, 'D5');
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-3')));
    await settle(tester);

    final comparison = find.byKey(const ValueKey('diploma-flight-comparison'));
    final selfReview = find.byKey(const ValueKey('diploma-flight-self-review'));
    final lateChange = tester.widget<TextFormField>(selfReview).onChanged!;
    await tester.tap(find.byKey(const ValueKey('diploma-flight-finish')));
    await tester.runAsync(
      () => paused.finishStarted.future.timeout(const Duration(seconds: 5)),
    );
    await tester.pump();
    expect(tester.widget<TextFormField>(comparison).enabled, isFalse);
    expect(tester.widget<TextFormField>(selfReview).enabled, isFalse);
    lateChange('Late change after finish began.');

    paused.releaseFinish.complete();
    await settle(tester);
    final saved = (await tester.runAsync(() => repository.read(started.id)))!;
    expect(saved.isSubmitted, isTrue);
    expect(saved.selfReview, 'Original self-review.');
    expect(find.textContaining('could not be saved'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testApp('back navigation waits for the final prose autosave', (tester) async {
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaTastingFlightRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const DiplomaTastingFlightScreen(unitId: 'D4'),
                    ),
                  ),
                  child: const Text('Open practice'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open practice'));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-evidence-0-description')),
      'The final typed observation is saved before leaving.',
    );
    await tester.pageBack();
    await settle(tester);
    expect(find.text('Open practice'), findsOneWidget);
    expect(
      (await tester.runAsync(() => repository.read(started.id)))!
          .wines[0]
          .evidence['description'],
      'The final typed observation is saved before leaving.',
    );
    expect(tester.takeException(), isNull);
  });

  testApp('a second flight action is blocked while autosave is pending', (
    tester,
  ) async {
    final paused = _PausedReflectionRepository(db, time);
    repository = paused;
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    await showScreen(tester, 'D4');
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-3')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-comparison')),
      'Comparison still being saved.',
    );
    await tester.pump();
    await tester.runAsync(
      () => paused.reflectionStarted.future.timeout(const Duration(seconds: 5)),
    );

    await tester.tap(find.byKey(const ValueKey('diploma-flight-finish')));
    await tester.pump();
    await tester.tap(find.text('Abandon this flight'));
    expect(paused.abandonCalls, 0);

    paused.releaseReflection.complete();
    await settle(tester);
    expect(paused.abandonCalls, 0);
    expect(
      (await tester.runAsync(() => repository.current('D4')))!.id,
      started.id,
    );
    expect(tester.takeException(), isNull);
  });

  testApp('a failed autosave stays visible after another field saves', (
    tester,
  ) async {
    final failing = _FailOnceEvidenceRepository(db, time);
    repository = failing;
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    await showScreen(tester, 'D4');

    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-evidence-0-description')),
      'Unsaved description',
    );
    await settle(tester);
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(
      find.text('Reload saved draft (discard unsaved edits)'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-evidence-0-quality')),
      'Saved quality evidence',
    );
    await settle(tester);
    expect(find.textContaining('could not be saved'), findsOneWidget);
    expect(
      find.text('Reload saved draft (discard unsaved edits)'),
      findsOneWidget,
    );
    final saved = (await tester.runAsync(() => repository.read(started.id)))!;
    expect(saved.wines[0].evidence['description'], isNull);
    expect(saved.wines[0].evidence['quality'], 'Saved quality evidence');

    await tester.tap(find.text('Reload saved draft (discard unsaved edits)'));
    await settle(tester);
    expect(find.text('Unsaved description'), findsNothing);
    expect(find.text('Saved quality evidence'), findsOneWidget);
    expect(
      find.text('Reload saved draft (discard unsaved edits)'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testApp('repeated back presses wait for autosave and pop only once', (
    tester,
  ) async {
    final paused = _PausedReflectionRepository(db, time);
    repository = paused;
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          diplomaTastingFlightRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          const DiplomaTastingFlightScreen(unitId: 'D4'),
                    ),
                  ),
                  child: const Text('Open practice'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open practice'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-3')));
    await settle(tester);
    await tester.enterText(
      find.byKey(const ValueKey('diploma-flight-comparison')),
      'Saved before one pop.',
    );
    await tester.pump();
    await tester.runAsync(
      () => paused.reflectionStarted.future.timeout(const Duration(seconds: 5)),
    );

    final comparison = find.byKey(const ValueKey('diploma-flight-comparison'));
    final lateChange = tester.widget<TextFormField>(comparison).onChanged!;
    await tester.pageBack();
    await tester.pump();
    expect(tester.widget<TextFormField>(comparison).enabled, isFalse);
    lateChange('Late change after back began.');
    await tester.pageBack();
    paused.releaseReflection.complete();
    await settle(tester);
    expect(find.text('Open practice'), findsOneWidget);
    expect(find.byType(DiplomaTastingFlightScreen), findsNothing);
    expect(
      (await tester.runAsync(() => repository.read(started.id)))!.reflection,
      'Saved before one pop.',
    );
    expect(tester.takeException(), isNull);
  });
}
