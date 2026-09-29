import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/progress_state.dart';
import 'package:sommelier/app/startup.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/database/storage_durability.dart';
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
    'empty level shows missing material, zero progress and no completion claim',
    (tester) async {
      await screen(tester);
      expect(find.text('WSET Level 1'), findsOneWidget);
      expect(
        find.textContaining('Study material not yet available.'),
        findsOneWidget,
      );
      expect(find.text('App study milestone complete'), findsNothing);
      expect(find.textContaining('100%'), findsNothing);
      expect(find.text('Full level coverage incomplete'), findsWidgets);
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
    }
    expect(find.text('App study milestone complete'), findsNothing);
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
}
