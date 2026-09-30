import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/progress_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_evidence.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight_providers.dart';
import 'package:sommelier/core/progress/progress_providers.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/progress/wset_progress_screen.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

class _HeldProgress extends WsetProgressRepository {
  _HeldProgress(super.db, {required super.scope});
  final started = Completer<void>();
  final reads = <Completer<WsetProgressSnapshot>>[];
  @override
  Future<WsetProgressSnapshot> snapshot() {
    final read = Completer<WsetProgressSnapshot>();
    reads.add(read);
    if (!started.isCompleted) started.complete();
    return read.future;
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late WsetScope scope;
  late WsetProgressSnapshot initial;
  late DiplomaTastingFlightRepository flights;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4','WSET',4,'WSET Level 4 Diploma','WSET_L3',NULL,1,'certification',NULL)",
        "INSERT INTO tasting_grids VALUES ('tg_structured','WSET_SAT','1.0','Structured tasting')",
        "INSERT INTO tasting_grid_attributes VALUES ('tg_structured','sweetness','Taste','Sweetness',1,'single',1)",
        "INSERT INTO tasting_grid_values VALUES ('tg_structured','sweetness','dry','Dry',1,NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    scope = WsetScope([
      for (var level = 1; level <= 4; level++)
        WsetLevelScope(
          certificationId: 'WSET_L$level',
          title: 'WSET Level $level',
          curriculumComplete: false,
          gaps: ['More practice needed.'],
          sourceUrl: 'https://www.wsetglobal.com/',
          units: level == 4
              ? [
                  for (var unit = 1; unit <= 6; unit++)
                    WsetUnitScope(
                      id: 'D$unit',
                      title: 'Unit $unit',
                      gap: 'Practice in progress.',
                      domains: const [],
                    ),
                ]
              : [],
        ),
    ]);
    flights = DiplomaTastingFlightRepository(
      db,
      bank: DiplomaTastingBank.fromJson(
        File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(79),
    );
    initial = await WsetProgressRepository(
      db,
      scope: scope,
      clock: time.clock,
    ).snapshot();
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openD3(WidgetTester tester) async {
    final heading = find.text('D3 · Unit 3');
    await tester.scrollUntilVisible(
      heading,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    // Scrolling changes the position before the render tree has repainted.
    // Reveal and settle the actual header before dispatching the pointer event.
    await tester.ensureVisible(heading);
    await settle(tester);
    expect(heading.hitTestable(), findsOneWidget);
    await tester.tap(heading);
    await settle(tester);
  }

  String label(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey('wset_unit_physical_D3')))
      .data!;

  testApp(
    'D3 submitted flight updates independently of a held full read and revokes removed credit',
    (tester) async {
      final flight = (await tester.runAsync(() async {
        final draft = await flights.start('D3');
        for (var wine = 0; wine < 3; wine++) {
          await flights.acknowledgePhysical(draft.id, wine, true);
          await flights.choose(draft.id, wine, 'sweetness', {'dry'});
          for (final prompt in draft.wines[wine].prompts) {
            await flights.saveEvidence(
              draft.id,
              wine,
              prompt.id,
              'My observed wine $wine evidence: ${prompt.id}.',
            );
          }
        }
        await flights.saveReflection(
          draft.id,
          'Wine two had a longer finish; the structure differed across all three.',
        );
        return flights.saveSelfReview(
          draft.id,
          'I need clearer observations before inferring a grape or origin.',
        );
      }))!;
      final held = _HeldProgress(db, scope: scope);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
            appStartupProvider.overrideWith(
              (ref) async => StorageDurability.persistent,
            ),
            wsetScopeProvider.overrideWith((ref) async => scope),
            wsetProgressRepositoryProvider(scope).overrideWithValue(held),
          ],
          child: const MaterialApp(home: WsetProgressScreen()),
        ),
      );
      await tester.runAsync(
        () => held.started.future.timeout(const Duration(seconds: 5)),
      );
      expect(held.started.isCompleted, isTrue);
      held.reads.single.complete(initial);
      await settle(tester);
      await openD3(tester);
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 0.'),
      );
      await tester.pump(const Duration(minutes: 1));
      await settle(tester);
      expect(held.reads, hasLength(2));
      expect(held.reads.last.isCompleted, isFalse);
      time.advance(const Duration(seconds: 1));
      Future<T> save<T>(Future<T> Function() action, String phase) async {
        final value = await tester.runAsync(
          () => action().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('Timed out during $phase.'),
          ),
        );
        expect(value, isNotNull, reason: phase);
        await settle(tester);
        if (value == null) throw StateError('No result during $phase.');
        return value;
      }

      await save(
        () => flights.markSelfReviewed(flight.id),
        'explicit D3 review',
      );
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 0.'),
      );
      final submitted = await save(
        () => flights.finish(flight.id),
        'submit D3 flight',
      );
      expect(submitted.isSubmitted, isTrue);
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 1.'),
      );
      expect(held.reads.last.isCompleted, isFalse);
      expect(initial.levels.last.units[2].physicalFlights, 0);
      expect(initial.levels.last.appLevelComplete, isFalse);
      expect(initial.levels.last.examPassed, isFalse);
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewStates).get()),
        isEmpty,
      );
      final savedSettings = await tester.runAsync(
        () => db.select(db.userSettings).get(),
      );
      expect(
        savedSettings!.where((row) => row.name.startsWith('exam_pass_')),
        isEmpty,
      );

      const futureId = '11111111-1111-4111-8111-111111111111';
      const corruptId = '22222222-2222-4222-8222-222222222222';
      final futureAt = time.now.add(const Duration(minutes: 2));
      final future = submitted.toJson()..['id'] = futureId;
      for (final name in [
        'startedAt',
        'updatedAt',
        'completedAt',
        'selfReviewedAt',
      ]) {
        future[name] = futureAt.toIso8601String();
      }
      await save(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: DiplomaTastingFlightRepository.keyFor(futureId),
                value: jsonEncode(future),
                updatedAt: time.now,
              ),
            ),
        'future imported flight',
      );
      await save(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: DiplomaTastingFlightRepository.keyFor(corruptId),
                value: '{"broken":',
                updatedAt: time.now,
              ),
            ),
        'corrupt imported flight',
      );
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 1.'),
      );
      expect(
        label(tester),
        contains('2 saved tasting records could not be read'),
      );
      time.advance(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 1));
      await settle(tester);
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 2.'),
      );
      expect(
        label(tester),
        contains('1 saved tasting record could not be read'),
      );
      expect(held.reads.last.isCompleted, isFalse);
      await save(
        () =>
            (db.delete(db.userSettings)..where(
                  (row) => row.name.isIn([
                    DiplomaTastingFlightRepository.keyFor(submitted.id),
                    DiplomaTastingFlightRepository.keyFor(futureId),
                  ]),
                ))
                .go(),
        'delete submitted D3 flights',
      );
      expect(
        label(tester),
        startsWith('Three-wine physical practices recorded: 0.'),
      );
      expect(held.reads, hasLength(2));
      expect(held.reads.last.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      held.reads.last.complete(initial);
      await settle(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(held.reads, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'saved tasting read errors never substitute a numeric participation count',
    (tester) async {
      final evidence = StreamController<DiplomaTastingEvidence>();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              clockProvider.overrideWithValue(time.clock),
              wsetProgressProvider.overrideWith((ref) => Stream.value(initial)),
              diplomaTastingEvidenceProvider.overrideWith(
                (ref) => evidence.stream,
              ),
            ],
            child: const MaterialApp(home: WsetProgressScreen()),
          ),
        );
        await settle(tester);
        await openD3(tester);
        expect(label(tester), 'Reading saved tasting participation…');
        evidence.add(const DiplomaTastingEvidence(d3Flights: 1));
        await settle(tester);
        expect(
          label(tester),
          startsWith('Three-wine physical practices recorded: 1.'),
        );
        evidence.addError(StateError('Saved flight read failed.'));
        await settle(tester);
        expect(
          label(tester),
          'Saved tasting participation could not be read. Reopen progress to retry.',
        );
        expect(label(tester), isNot(contains('recorded: 0')));
        expect(label(tester), isNot(contains('recorded: 1')));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        await settle(tester);
        final closing = evidence.close();
        final closed = await tester.runAsync(
          () => closing.timeout(const Duration(seconds: 5)).then((_) => true),
        );
        expect(closed, isTrue);
      }
    },
  );
}
