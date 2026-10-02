import 'dart:async';
import 'dart:convert';
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

class _CountingDraftsRepository extends DiplomaTastingFlightRepository {
  _CountingDraftsRepository(super.db, TestClock time)
    : super(
        bank: DiplomaTastingBank.fromJson(
          File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
        ),
        clock: time.clock,
        random: Random(9),
      );

  final reflectionWrites = <String>[];
  final firstReflectionEntered = Completer<void>();
  final releaseReflection = Completer<void>();

  @override
  Future<DiplomaTastingFlight> saveReflection(String id, String text) async {
    reflectionWrites.add(text);
    if (!firstReflectionEntered.isCompleted) {
      firstReflectionEntered.complete();
      await releaseReflection.future;
    }
    return super.saveReflection(id, text);
  }
}

Future<DiplomaTastingFlight> _savePacket(
  DiplomaTastingFlightRepository repository,
  String unitId,
  String tag,
) async {
  final flight = await repository.start(unitId);
  for (var index = 0; index < 3; index++) {
    await repository.acknowledgePhysical(flight.id, index, true);
    await repository.choose(flight.id, index, 'sweetness', {
      index == 1 ? 'sweet' : 'dry',
    });
    await repository.choose(flight.id, index, 'aromas', {'citrus'});
    for (final prompt in flight.wines[index].prompts) {
      await repository.saveEvidence(
        flight.id,
        index,
        prompt.id,
        '$tag wine ${index + 1}: ${prompt.id}.',
      );
    }
  }
  await repository.saveReflection(
    flight.id,
    '$tag exact three-wine comparison.',
  );
  await repository.saveSelfReview(flight.id, '$tag exact uncertainty review.');
  await repository.markSelfReviewed(flight.id);
  return repository.finish(flight.id);
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

  testApp('rapid keystrokes in flight comparison coalesce on write tail', (
    tester,
  ) async {
    final counting = _CountingDraftsRepository(db, time);
    repository = counting;
    final started = (await tester.runAsync(() => repository.start('D4')))!;
    await showScreen(tester, 'D4');
    await tester.tap(find.byKey(const ValueKey('diploma-flight-step-3')));
    await settle(tester);

    final comparison = find.byKey(const ValueKey('diploma-flight-comparison'));
    final onChanged = tester.widget<TextFormField>(comparison).onChanged!;

    // First keystroke starts the write tail and pauses in saveReflection
    onChanged('T');
    await tester.pump();
    await tester.runAsync(
      () => counting.firstReflectionEntered.future.timeout(
        const Duration(seconds: 5),
      ),
    );

    // Rapidly type more characters while the first save is in flight
    onChanged('Th');
    onChanged('Thr');
    onChanged('Three');
    onChanged('Three-wine comparison final note.');

    // Release first write
    counting.releaseReflection.complete();
    await settle(tester);

    // Intermediate keystrokes are coalesced: only the first and latest save run
    expect(counting.reflectionWrites, [
      'T',
      'Three-wine comparison final note.',
    ]);

    final saved = (await tester.runAsync(() => repository.read(started.id)))!;
    expect(saved.reflection, 'Three-wine comparison final note.');
    expect(tester.takeException(), isNull);
  });
  testApp('D3 setup explicitly requests three real still wines', (
    tester,
  ) async {
    await showScreen(tester, 'D3');
    expect(find.text('D3 Still tasting practice'), findsOneWidget);
    expect(find.textContaining('three actual still wines'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diploma-flight-start')));
    await settle(tester);
    expect(find.text('I physically tasted this still wine'), findsOneWidget);
    expect(find.textContaining('imagined wine does not count'), findsOneWidget);
    final draft = (await tester.runAsync(() => repository.current('D3')))!;
    expect(
      find.byKey(ValueKey('diploma-flight-editor-${draft.id}-0')),
      findsOneWidget,
    );
    expect(draft.wines, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testApp('narrow saved packets reload exact prose without replacing a draft', (
    tester,
  ) async {
    final first = (await tester.runAsync(
      () => _savePacket(repository, 'D3', 'First saved packet'),
    ))!;
    time.advance(const Duration(seconds: 1));
    final second = (await tester.runAsync(
      () => _savePacket(repository, 'D3', 'Second saved packet'),
    ))!;
    final active = (await tester.runAsync(() => repository.start('D3')))!;
    await tester.runAsync(
      () => repository.saveEvidence(
        active.id,
        0,
        'description',
        'Current draft stays distinct.',
      ),
    );
    final activeBefore = (await tester.runAsync(
      () => repository.read(active.id),
    ))!;
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Future<void> mount() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            diplomaTastingFlightRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: const MaterialApp(
            home: DiplomaTastingFlightScreen(unitId: 'D3'),
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> reveal(Finder finder, Type screenType) async {
      final scrollable = find
          .descendant(
            of: find.byType(screenType),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        finder,
        400,
        scrollable: scrollable,
        maxScrolls: 70,
      );
      await tester.ensureVisible(finder);
      await settle(tester);
    }

    Future<void> inspectPacket(DiplomaTastingFlight packet) async {
      final view = find.byKey(ValueKey('diploma-flight-view-${packet.id}'));
      await reveal(view, DiplomaTastingFlightScreen);
      await tester.tap(view);
      await settle(tester);
      expect(
        find.byKey(ValueKey('diploma-flight-saved-${packet.id}')),
        findsOneWidget,
      );
      expect(
        find.text('Recorded physical practice · read-only'),
        findsOneWidget,
      );
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      for (var index = 0; index < 3; index++) {
        final wine = find.byKey(ValueKey('diploma-flight-saved-wine-$index'));
        await reveal(wine, SavedDiplomaTastingFlightScreen);
        await tester.tap(wine);
        await settle(tester);
        expect(
          find.descendant(
            of: wine,
            matching: find.text(
              index == 1 ? 'Sweetness: Sweet' : 'Sweetness: Dry',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: wine, matching: find.text('Aromas: Citrus')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: wine,
            matching: find.text('Physical tasting acknowledged'),
          ),
          findsOneWidget,
        );
        for (final prompt in packet.wines[index].prompts) {
          final prose = find.byKey(
            ValueKey('diploma-flight-saved-evidence-$index-${prompt.id}'),
          );
          await reveal(prose, SavedDiplomaTastingFlightScreen);
          expect(
            tester.widget<Text>(prose).data,
            packet.wines[index].evidence[prompt.id],
          );
        }
      }
      for (final entry in {
        'diploma-flight-saved-comparison': packet.reflection,
        'diploma-flight-saved-self-review': packet.selfReview,
      }.entries) {
        final prose = find.byKey(ValueKey(entry.key));
        await reveal(prose, SavedDiplomaTastingFlightScreen);
        expect(tester.widget<Text>(prose).data, entry.value);
      }
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await settle(tester);
      expect(
        (await tester.runAsync(() => repository.current('D3')))!.toJson(),
        activeBefore.toJson(),
      );
      expect(
        (await tester.runAsync(() => repository.read(packet.id)))!.toJson(),
        packet.toJson(),
      );
    }

    await mount();
    await inspectPacket(first);
    await inspectPacket(second);
    // Unmount every controller/provider and reconstruct the repository before
    // opening the exact same persisted packet again.
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    repository = DiplomaTastingFlightRepository(
      db,
      bank: DiplomaTastingBank.fromJson(
        File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
      ),
      clock: time.clock,
    );
    await mount();
    await inspectPacket(first);
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => db.select(db.reviewStates).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testApp(
    'legacy completed packet uses its own prompt and observation labels',
    (tester) async {
      final legacy = jsonDecode(
        File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      legacy['version'] = '1.0.0';
      legacy['units'] = (legacy['units'] as List)
          .where((row) => row['unitId'] != 'D3')
          .toList();
      (legacy['units'] as List).first['evidencePrompts'][0]['prompt'] =
          'Original legacy sparkling description prompt.';
      final old = DiplomaTastingFlightRepository(
        db,
        bank: DiplomaTastingBank.fromJson(jsonEncode(legacy)),
        clock: time.clock,
      );
      final saved = (await tester.runAsync(
        () => _savePacket(old, 'D4', 'Legacy packet'),
      ))!;
      await tester.runAsync(
        () => db.writeCurriculum(
          () => runSql(db, [
            "UPDATE tasting_grid_attributes SET label = 'Current sweetness label' WHERE tasting_grid_id = 'tg_structured' AND attribute_key = 'sweetness'",
          ]),
        ),
      );
      await showScreen(tester, 'D4');
      final view = find.byKey(ValueKey('diploma-flight-view-${saved.id}'));
      await tester.ensureVisible(view);
      await tester.tap(view);
      await settle(tester);
      expect(find.text('Saved prompt bank: 1.0.0'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('diploma-flight-saved-wine-0')),
      );
      await settle(tester);
      expect(
        find.text('Original legacy sparkling description prompt.'),
        findsOneWidget,
      );
      expect(find.text('Sweetness: Dry'), findsOneWidget);
      expect(find.textContaining('Current sweetness label'), findsNothing);
      expect(find.text('Legacy packet wine 1: description.'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect((await tester.runAsync(() => repository.current('D4'))), isNull);
      expect(
        (await tester.runAsync(() => repository.read(saved.id)))!.toJson(),
        saved.toJson(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testApp('abandoned packet is readable without granting completion', (
    tester,
  ) async {
    final draft = (await tester.runAsync(() => repository.start('D3')))!;
    await tester.runAsync(
      () => repository.saveEvidence(
        draft.id,
        2,
        'description',
        'Partial wine three observation.',
      ),
    );
    final saved = (await tester.runAsync(() => repository.abandon(draft.id)))!;
    await showScreen(tester, 'D3');
    await tester.tap(find.byKey(ValueKey('diploma-flight-view-${saved.id}')));
    await settle(tester);
    expect(find.text('Abandoned flight · read-only'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('diploma-flight-saved-wine-2')));
    await settle(tester);
    expect(find.text('Partial wine three observation.'), findsOneWidget);
    expect(find.text('Physical tasting not acknowledged'), findsOneWidget);
    expect(find.text('No comparison recorded.'), findsOneWidget);
    expect(find.text('No self-review recorded.'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(
      (await tester.runAsync(() => repository.read(saved.id)))!.isSubmitted,
      isFalse,
    );
    expect((await tester.runAsync(() => repository.current('D3'))), isNull);
    expect(tester.takeException(), isNull);
  });
}
