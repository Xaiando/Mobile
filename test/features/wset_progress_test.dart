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
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/diploma_written/diploma_written_evidence.dart';
import 'package:sommelier/core/diploma_written/diploma_written_providers.dart';
import 'package:sommelier/core/progress/progress_providers.dart';
import 'package:sommelier/core/progress/wset_progress.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/progress/wset_requirements.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/question_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/practice/practice_screen.dart';
import 'package:sommelier/features/progress/wset_progress_card.dart';
import 'package:sommelier/features/progress/wset_progress_screen.dart';

import '../support/app_fixture.dart';
import '../support/fixture.dart';
import '../support/study_fixture.dart';

class _ControlledProgressRepository extends WsetProgressRepository {
  _ControlledProgressRepository(super.db, {required super.scope});

  final started = Completer<void>();
  final calculations = <Completer<WsetProgressSnapshot>>[];

  @override
  Future<WsetProgressSnapshot> snapshot() {
    final calculation = Completer<WsetProgressSnapshot>();
    calculations.add(calculation);
    if (!started.isCompleted) {
      started.complete();
    }
    return calculation.future;
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late WsetScope scope;
  late WsetProgressRepository progress;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await seedSchedulerConfig(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4','WSET',4,'WSET Level 4 Diploma','WSET_L3',NULL,1,'certification',NULL)",
      ]),
    );
    scope = WsetScope([
      for (var i = 1; i <= 4; i++)
        WsetLevelScope(
          certificationId: 'WSET_L$i',
          title: i == 4 ? 'WSET Level 4 Diploma' : 'WSET Level $i',
          curriculumComplete: false,
          gaps: ['Expand wine-style comparisons and tasting.'],
          sourceUrl: 'https://www.wsetglobal.com/',
          units: i == 4
              ? [
                  for (var unit = 1; unit <= 6; unit++)
                    WsetUnitScope(
                      id: 'D$unit',
                      title: 'Unit $unit',
                      gap: 'More unit practice needed.',
                      domains: unit == 3
                          ? ['geography']
                          : unit == 1
                          ? ['viticulture']
                          : [],
                    ),
                ]
              : [],
        ),
    ]);
    progress = WsetProgressRepository(db, scope: scope, clock: time.clock);
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> screen(WidgetTester tester, {double textScale = 1}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          wsetScopeProvider.overrideWith((ref) async => scope),
          wsetProgressProvider.overrideWith((ref) => progress.watch()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const WsetProgressScreen(),
        ),
      ),
    );
    await settle(tester);
  }

  testApp(
    'slow initial progress settles and minute refresh retains data without restarting',
    (tester) async {
      final initial = (await tester.runAsync(() => progress.snapshot()))!;
      final controlled = _ControlledProgressRepository(db, scope: scope);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appStartupProvider.overrideWith(
              (ref) async => StorageDurability.persistent,
            ),
            wsetScopeProvider.overrideWith((ref) async => scope),
            wsetProgressRepositoryProvider(scope).overrideWithValue(controlled),
          ],
          child: const MaterialApp(home: Scaffold(body: WsetProgressCard())),
        ),
      );
      await tester.runAsync(() => controlled.started.future);
      await tester.pumpAndSettle();
      expect(find.text('Calculating your progress…'), findsOneWidget);
      expect(controlled.calculations, hasLength(1));

      // No refresh timer exists while the first database snapshot is pending.
      await tester.pump(const Duration(minutes: 2));
      expect(controlled.calculations, hasLength(1));
      controlled.calculations.single.complete(initial);
      await settle(tester);
      expect(find.text('Calculating your progress…'), findsNothing);
      expect(find.textContaining('0/2 studied'), findsWidgets);

      await tester.pump(const Duration(minutes: 1));
      expect(controlled.calculations, hasLength(2));
      await tester.pumpAndSettle();
      expect(find.textContaining('0/2 studied'), findsWidgets);
      expect(find.text('Calculating your progress…'), findsNothing);

      // Further ticks coalesce behind the running refresh, rather than
      // starting parallel queries or replacing its previous visible data.
      await tester.pump(const Duration(minutes: 2));
      expect(controlled.calculations, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      controlled.calculations.last.complete(initial);
      await settle(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(controlled.calculations, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'saved D4 and D5 participation updates while the full snapshot stays pending',
    (tester) async {
      final writing = DiplomaWrittenRepository(
        db,
        bank: DiplomaWrittenBank.fromJson(
          File('assets/study/diploma_written_practice.json').readAsStringSync(),
        ),
        clock: time.clock,
        random: Random(47),
      );
      final attempts = <String, DiplomaWrittenAttempt>{};
      await tester.runAsync(() async {
        await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
        for (final unit in ['D4', 'D5']) {
          final attempt = await writing.start(unit);
          for (final question in attempt.questions) {
            await writing.answer(
              attempt.id,
              question.id,
              'My comparison and supporting evidence for ${question.id}.',
            );
          }
          attempts[unit] = await writing.finish(attempt.id);
        }
      });
      final initial = (await tester.runAsync(() => progress.snapshot()))!;
      final initialDiploma = initial.levels.last;
      expect(
        initialDiploma.units
            .where((unit) => unit.scope.id == 'D4' || unit.scope.id == 'D5')
            .map((unit) => unit.writtenPractices),
        [0, 0],
      );
      final controlled = _ControlledProgressRepository(db, scope: scope);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
            appStartupProvider.overrideWith(
              (ref) async => StorageDurability.persistent,
            ),
            wsetScopeProvider.overrideWith((ref) async => scope),
            wsetProgressRepositoryProvider(scope).overrideWithValue(controlled),
          ],
          child: const MaterialApp(home: WsetProgressScreen()),
        ),
      );
      await tester.runAsync(
        () => controlled.started.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw StateError(
            'Initial controlled progress snapshot did not start.',
          ),
        ),
      );
      expect(controlled.started.isCompleted, isTrue);
      controlled.calculations.single.complete(initial);
      await settle(tester);
      final scrollable = find.byType(Scrollable).first;
      for (final unit in ['D4', 'D5']) {
        await tester.scrollUntilVisible(
          find.text('$unit · Unit ${unit.substring(1)}'),
          300,
          scrollable: scrollable,
        );
        await tap(tester, find.text('$unit · Unit ${unit.substring(1)}'));
      }

      String writtenLabel(String unit) => tester
          .widget<Text>(find.byKey(ValueKey('wset_unit_written_$unit')))
          .data!;
      void expectWritten(String unit, int count) => expect(
        writtenLabel(unit),
        startsWith('Written practices self-reviewed: $count.'),
      );
      expectWritten('D4', 0);
      expectWritten('D5', 0);

      // Hold the actual repository watch's next complete snapshot. Saving
      // reviews must update the independent settings projection before that
      // slow refresh is released; the initial snapshot stays at zero.
      await tester.pump(const Duration(minutes: 1));
      expect(controlled.calculations, hasLength(2));
      expect(controlled.calculations.last.isCompleted, isFalse);
      time.advance(const Duration(seconds: 1));
      Future<T> savedWrite<T>(Future<T> Function() action, String phase) async {
        final saved = await tester.runAsync(
          () => action().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw StateError('Timed out during $phase.'),
          ),
        );
        expect(saved, isNotNull, reason: '$phase must finish.');
        // Drift query listeners were created in the widget's fake zone.
        // Pump their invalidation/read before starting the next real-zone
        // transaction, while the heavyweight snapshot stays unresolved.
        await settle(tester);
        if (saved == null) throw StateError('$phase returned no result.');
        return saved;
      }

      for (final unit in ['D4', 'D5']) {
        final attempt = attempts[unit]!;
        for (final question in attempt.questions) {
          attempts[unit] = await savedWrite(
            () => writing.review(attempt.id, question.id, {
              question.criteria.first.id,
            }, 'I will add a more precise comparison for ${question.id}.'),
            'saving $unit ${question.id} self-review',
          );
        }
        expect(attempts[unit]!.isReviewed, isTrue);
      }
      await settle(tester);
      expectWritten('D4', 1);
      expectWritten('D5', 1);
      expect(controlled.calculations, hasLength(2));
      expect(controlled.calculations.last.isCompleted, isFalse);
      expect(initialDiploma.counts.mastered, 0);
      expect(initialDiploma.examPassed, isFalse);
      expect(initialDiploma.appLevelComplete, isFalse);
      expect(
        find.text('Exam passed · self-reported. Uncheck to remove.'),
        findsNothing,
      );
      expect(find.text('Required study milestone complete'), findsNothing);
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewStates).get()),
        isEmpty,
      );

      // A structurally valid imported attempt remains ineligible until its
      // actual timestamps arrive. A corrupt record also gets no credit.
      const futureId = '11111111-1111-4111-8111-111111111111';
      const corruptId = '22222222-2222-4222-8222-222222222222';
      final futureTime = time.now.add(const Duration(minutes: 2));
      final futureRow = attempts['D4']!.toJson()
        ..['id'] = futureId
        ..['startedAt'] = futureTime.toIso8601String()
        ..['deadline'] = futureTime
            .add(const Duration(seconds: 2700))
            .toIso8601String()
        ..['completedAt'] = futureTime.toIso8601String();
      final futureReviews = futureRow['reviews'] as Map<String, dynamic>;
      for (final review in futureReviews.values) {
        (review as Map<String, dynamic>)['reviewedAt'] = futureTime
            .toIso8601String();
      }
      final futureAttempt = DiplomaWrittenAttempt.fromJson(futureRow);
      expect(futureAttempt.isReviewed, isTrue);
      await savedWrite(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: DiplomaWrittenRepository.keyFor(futureId),
                value: jsonEncode(futureRow),
                updatedAt: time.now,
              ),
            ),
        'inserting future-dated writing evidence',
      );
      await savedWrite(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: DiplomaWrittenRepository.keyFor(corruptId),
                value: '{"broken":',
                updatedAt: time.now,
              ),
            ),
        'inserting corrupt writing evidence',
      );
      await settle(tester);
      expectWritten('D4', 1);
      expectWritten('D5', 1);
      expect(
        writtenLabel('D4'),
        contains('2 saved writing records could not be read'),
      );

      // No setting changes here: the cached-row clock refresh must eventually
      // revalidate the imported record instead of rejecting it forever.
      time.advance(const Duration(minutes: 2));
      await tester.pump(const Duration(minutes: 1));
      await settle(tester);
      expectWritten('D4', 2);
      expectWritten('D5', 1);
      expect(
        writtenLabel('D4'),
        contains('1 saved writing record could not be read'),
      );
      expect(controlled.calculations, hasLength(2));
      expect(controlled.calculations.last.isCompleted, isFalse);

      // The live count also revokes credit when a saved record is removed or
      // becomes unreadable, without relying on the held full snapshot.
      await savedWrite(
        () =>
            (db.delete(db.userSettings)..where(
                  (row) => row.name.isIn([
                    DiplomaWrittenRepository.keyFor(futureId),
                    DiplomaWrittenRepository.keyFor(attempts['D5']!.id),
                  ]),
                ))
                .go(),
        'deleting saved D5 and imported writing evidence',
      );
      await savedWrite(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: DiplomaWrittenRepository.keyFor(attempts['D4']!.id),
                value: '{"broken":',
                updatedAt: time.now,
              ),
            ),
        'corrupting saved D4 writing evidence',
      );
      await settle(tester);
      expectWritten('D4', 0);
      expectWritten('D5', 0);
      expect(
        writtenLabel('D4'),
        contains('2 saved writing records could not be read'),
      );
      expect(controlled.calculations, hasLength(2));
      expect(controlled.calculations.last.isCompleted, isFalse);

      // Dispose both watches before releasing the obsolete heavyweight read.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
      controlled.calculations.last.complete(initial);
      await settle(tester);
      await tester.pump(const Duration(minutes: 2));
      expect(controlled.calculations, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'saved writing loading and read errors do not substitute a numeric count',
    (tester) async {
      final initial = (await tester.runAsync(() => progress.snapshot()))!;
      final evidence = StreamController<DiplomaWrittenEvidence>();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              clockProvider.overrideWithValue(time.clock),
              wsetProgressProvider.overrideWith((ref) => Stream.value(initial)),
              diplomaWrittenEvidenceProvider.overrideWith(
                (ref) => evidence.stream,
              ),
            ],
            child: const MaterialApp(home: WsetProgressScreen()),
          ),
        );
        await settle(tester);
        await tester.scrollUntilVisible(
          find.text('D4 · Unit 4'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tap(tester, find.text('D4 · Unit 4'));
        String label() => tester
            .widget<Text>(find.byKey(const ValueKey('wset_unit_written_D4')))
            .data!;
        expect(label(), 'Reading saved writing participation…');
        evidence.add(const DiplomaWrittenEvidence(d4Reviewed: 1));
        await settle(tester);
        expect(label(), startsWith('Written practices self-reviewed: 1.'));
        evidence.addError(StateError('Saved writing read failed.'));
        await settle(tester);
        expect(
          label(),
          'Saved writing participation could not be read. Reopen progress to retry.',
        );
        expect(label(), isNot(contains('self-reviewed: 0')));
        expect(label(), isNot(contains('self-reviewed: 1')));
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(Duration.zero);
        await settle(tester);
        // Complete the close through the real async zone before the shared
        // widget fixture's next guarded unmount pump.
        final closing = evidence.close();
        final closed = await tester.runAsync(
          () => closing
              .then((_) => true)
              .timeout(
                const Duration(seconds: 5),
                onTimeout: () => throw StateError(
                  'Saved-writing evidence test stream did not close.',
                ),
              ),
        );
        expect(closed, isTrue, reason: 'The test evidence stream must close.');
      }
    },
  );

  testApp(
    'empty level shows missing material, zero progress and no completion claim',
    (tester) async {
      await screen(tester);
      expect(find.text('WSET Level 1'), findsOneWidget);
      expect(
        find.textContaining('Study material not yet available.'),
        findsOneWidget,
      );
      expect(find.text('Required study milestone complete'), findsNothing);
      expect(find.textContaining('100%'), findsNothing);
      expect(find.text('App study scope incomplete'), findsWidgets);
      expect(find.text('App core question coverage'), findsWidgets);
      expect(
        find.textContaining('three dates over seven days'),
        findsOneWidget,
      );
    },
  );

  testApp(
    'exam pass can be recorded and removed without changing app mastery',
    (tester) async {
      await screen(tester);
      final checkbox = find.byType(Checkbox).first;
      await tap(tester, checkbox);
      final passed = await tester.runAsync(() => progress.snapshot());
      expect(passed!.levels.first.examPassed, isTrue);
      expect(passed.levels.first.counts.mastered, 0);
      expect(
        find.text('Exam passed · self-reported. Uncheck to remove.'),
        findsOneWidget,
      );
      await tap(tester, checkbox);
      final cleared = await tester.runAsync(() => progress.snapshot());
      expect(cleared!.levels.first.examPassed, isFalse);
    },
  );

  testApp(
    'progress details fit a narrow phone with large text and expose all six units',
    (tester) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await screen(tester, textScale: 1.7);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('D6 · Unit 6'),
        350,
        scrollable: scrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('D6 · Unit 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(tester, find.text('D6 · Unit 6'));
      expect(find.text('More unit practice needed.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Coverage and remaining topics').last,
        200,
        scrollable: scrollable,
      );
      await tap(tester, find.text('Coverage and remaining topics').last);
      expect(tester.takeException(), isNull);
    },
  );

  testApp('Diploma D4 and D5 show separate physical practice entry points', (
    tester,
  ) async {
    await screen(tester);
    final scrollable = find.byType(Scrollable).first;
    for (final unit in ['D4', 'D5']) {
      await tester.scrollUntilVisible(
        find.text('$unit · Unit ${unit.substring(1)}'),
        300,
        scrollable: scrollable,
      );
      await tap(tester, find.text('$unit · Unit ${unit.substring(1)}'));
      expect(find.byKey(ValueKey('wset_unit_physical_$unit')), findsOneWidget);
      expect(
        find.byKey(ValueKey('wset_unit_physical_open_$unit')),
        findsOneWidget,
      );
      expect(find.byKey(ValueKey('wset_unit_written_$unit')), findsOneWidget);
      expect(
        find.byKey(ValueKey('wset_unit_written_open_$unit')),
        findsOneWidget,
      );
      expect(find.text('Open $unit app 45-minute writing'), findsOneWidget);
      expect(
        find.textContaining('not examiner marks or unit passes'),
        findsWidgets,
      );
    }
    expect(find.text('Required study milestone complete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testApp('Diploma D6 exposes a research workspace without a pass claim', (
    tester,
  ) async {
    await screen(tester);
    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('D6 · Unit 6'),
      300,
      scrollable: scrollable,
    );
    await tap(tester, find.text('D6 · Unit 6'));
    expect(find.byKey(const ValueKey('wset_unit_research_D6')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('wset_unit_research_open_D6')),
      findsOneWidget,
    );
    expect(find.textContaining('no draft saved yet'), findsOneWidget);
    expect(find.text('App study milestone complete'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testApp('Diploma D1 and D2 expose separate formative writing presets', (
    tester,
  ) async {
    await screen(tester);
    final scrollable = find.byType(Scrollable).first;
    for (final unit in ['D1', 'D2']) {
      await tester.scrollUntilVisible(
        find.text('$unit · Unit ${unit.substring(1)}'),
        300,
        scrollable: scrollable,
      );
      await tap(tester, find.text('$unit · Unit ${unit.substring(1)}'));
      expect(find.byKey(ValueKey('wset_unit_written_$unit')), findsOneWidget);
      expect(
        find.byKey(ValueKey('wset_unit_written_open_$unit')),
        findsOneWidget,
      );
      expect(
        find.textContaining('not examiner marks or unit passes'),
        findsWidgets,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testApp(
    'Home opens progress and its study action starts the selected cumulative level',
    (tester) async {
      await tester.runAsync(
        () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
      );
      await pumpApp(
        tester,
        db,
        overrides: [
          appStartupProvider.overrideWith(
            (ref) async => StorageDurability.persistent,
          ),
          clockProvider.overrideWithValue(time.clock),
          wsetScopeProvider.overrideWith((ref) async => scope),
          wsetProgressProvider.overrideWith((ref) => progress.watch()),
          formatRegistryProvider.overrideWithValue(
            FormatRegistry([FlashcardFormat()]),
          ),
        ],
      );
      await settle(tester);
      await tester.scrollUntilVisible(find.text('View WSET progress'), 250);
      await tap(tester, find.text('View WSET progress'));
      expect(find.byType(WsetProgressScreen), findsOneWidget);
      final levelThreeStudy = find.descendant(
        of: find.byKey(const ValueKey('wset_progress_WSET_L3')),
        matching: find.widgetWithText(FilledButton, 'Study WSET Level 3'),
      );
      await tester.scrollUntilVisible(
        levelThreeStudy,
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(tester, levelThreeStudy);
      expect(find.byType(PracticeScreen), findsOneWidget);
      expect(find.byType(WsetProgressScreen), findsNothing);
      final profile = await tester.runAsync(
        () => LearnerProfiles(db).current(),
      );
      expect(profile!.activeCertificationId, 'WSET_L3');
      final question = find.text('What is the characteristic soil of Chablis?');
      expect(question, findsOneWidget);
    },
  );

  testApp('a required topic opens focused practice with shared memory', (
    tester,
  ) async {
    scope = WsetScope([
      for (final level in scope.levels)
        WsetLevelScope(
          certificationId: level.certificationId,
          title: level.title,
          curriculumComplete: false,
          gaps: level.gaps,
          sourceUrl: level.sourceUrl,
          units: level.units,
          requirements: level.certificationId == 'WSET_L3'
              ? [
                  const WsetRequirement(
                    id: 'chablis_environment',
                    title: 'Chablis site study',
                    reviewed: true,
                    dimensions: [
                      WsetEvidenceDimension(
                        kind: 'environment',
                        itemIds: ['ki_chablis_soil'],
                        formats: ['flashcard'],
                      ),
                    ],
                  ),
                ]
              : [],
        ),
    ]);
    progress = WsetProgressRepository(db, scope: scope, clock: time.clock);
    await tester.runAsync(
      () => LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3'),
    );
    await pumpApp(
      tester,
      db,
      overrides: [
        appStartupProvider.overrideWith(
          (ref) async => StorageDurability.persistent,
        ),
        clockProvider.overrideWithValue(time.clock),
        wsetScopeProvider.overrideWith((ref) async => scope),
        wsetProgressProvider.overrideWith((ref) => progress.watch()),
        formatRegistryProvider.overrideWithValue(
          FormatRegistry([FlashcardFormat()]),
        ),
      ],
    );
    await settle(tester);
    await tester.scrollUntilVisible(find.text('View WSET progress'), 250);
    await tap(tester, find.text('View WSET progress'));
    final requirements = find.text('Study requirements · 0/1 mastered');
    await tester.scrollUntilVisible(
      requirements,
      350,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 50,
    );
    await tap(tester, requirements);
    final topic = find.byKey(
      const ValueKey('wset_topic_WSET_L3_chablis_environment'),
    );
    await tester.scrollUntilVisible(
      topic,
      250,
      scrollable: find.byType(Scrollable).last,
    );
    await tap(tester, topic);
    expect(find.byType(PracticeScreen), findsOneWidget);
    expect(
      find.text('What is the characteristic soil of Chablis?'),
      findsOneWidget,
    );
    expect(find.textContaining('principal grape of Chablis'), findsNothing);
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'completed required study still exposes wider core question gaps',
    (tester) async {
      const mastered = ProgressCounts(
        mapped: 1,
        available: 1,
        studied: 1,
        mastered: 1,
        due: 0,
      );
      final snapshot = WsetProgressSnapshot(
        asOf: DateTime.utc(2026, 9, 29),
        levels: const [
          WsetLevelProgress(
            scope: WsetLevelScope(
              certificationId: 'WSET_L2',
              title: 'WSET Level 2',
              curriculumComplete: true,
              gaps: [],
              sourceUrl: 'https://www.wsetglobal.com/',
            ),
            counts: mastered,
            requiredCounts: mastered,
            corePracticeCoverage: CorePracticeCoverage(core: 2, useful: 0),
            selectable: false,
            examPassed: false,
            topics: [],
            nextItems: [],
            units: [],
            unassigned: ProgressCounts(
              mapped: 0,
              available: 0,
              studied: 0,
              mastered: 0,
              due: 0,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            wsetProgressProvider.overrideWith((ref) => Stream.value(snapshot)),
          ],
          child: const MaterialApp(home: WsetProgressScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Required study milestone complete'), findsOneWidget);
      expect(
        find.text('0 of 2 mapped core facts have useful practice.'),
        findsOneWidget,
      );
      expect(
        find.text('2 mapped core facts need more question formats.'),
        findsOneWidget,
      );
      expect(
        find.text('Exam passed · self-reported. Uncheck to remove.'),
        findsNothing,
      );
      expect(find.text('App study milestone complete'), findsNothing);
    },
  );
}
