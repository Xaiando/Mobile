import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/diploma_written/diploma_written_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/diploma_written/diploma_written_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  late AppDatabase db;
  late TestClock time;
  late DiplomaWrittenRepository repository;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = DiplomaWrittenRepository(
      db,
      bank: DiplomaWrittenBank.fromJson(
        File('assets/study/diploma_written_practice.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(19),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, String unitId) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          diplomaWrittenRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(home: DiplomaWrittenScreen(unitId: unitId)),
      ),
    );
    await settle(tester);
  }

  testApp('D1 writing saves prose and hides criteria until writing ends', (
    tester,
  ) async {
    await show(tester, 'D1');
    expect(
      find.textContaining('Original 90-minute writing practice'),
      findsOneWidget,
    );
    expect(
      find.textContaining('not official examination questions or marks'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('diploma-written-start')));
    await settle(tester);
    final attempt = (await tester.runAsync(() => repository.current('D1')))!;
    expect(find.text('Time remaining: 90:00'), findsOneWidget);
    expect(
      find.byKey(
        ValueKey('diploma-written-prose-${attempt.questions.first.id}'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'diploma-written-criterion-${attempt.questions.first.id}-${attempt.questions.first.criteria.first.id}',
        ),
      ),
      findsNothing,
    );
    await tester.enterText(
      find.byKey(
        ValueKey('diploma-written-prose-${attempt.questions.first.id}'),
      ),
      'The cooler site may slow ripening; water supply still matters.',
    );
    await settle(tester);
    expect(
      (await tester.runAsync(() => repository.read(attempt.id)))!
          .prose[attempt.questions.first.id],
      contains('cooler site'),
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('diploma-written-finish')),
    );
    await tester.tap(find.byKey(const ValueKey('diploma-written-finish')));
    await settle(tester);
    expect(
      find.textContaining('Writing ended. Compare each saved answer'),
      findsOneWidget,
    );
    expect(
      find.byKey(
        ValueKey(
          'diploma-written-criterion-${attempt.questions.first.id}-${attempt.questions.first.criteria.first.id}',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('not a score or model answer'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testApp('D2 shows one-hour preset and saves an explicit self-review', (
    tester,
  ) async {
    final attempt = (await tester.runAsync(() => repository.start('D2')))!;
    await tester.runAsync(
      () => repository.answer(
        attempt.id,
        attempt.questions.first.id,
        'A response on cost, currency and commercial risks.',
      ),
    );
    await show(tester, 'D2');
    expect(find.text('Time remaining: 60:00'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('diploma-written-finish')),
    );
    await tester.tap(find.byKey(const ValueKey('diploma-written-finish')));
    await settle(tester);
    final q = attempt.questions.first;
    final criterion = find.byKey(
      ValueKey('diploma-written-criterion-${q.id}-${q.criteria.first.id}'),
    );
    await tester.ensureVisible(criterion);
    await tester.tap(criterion);
    await tester.enterText(
      find.byKey(ValueKey('diploma-written-improvement-${q.id}')),
      'I would add a specific contract assumption.',
    );
    await tester.ensureVisible(
      find.byKey(ValueKey('diploma-written-review-${q.id}')),
    );
    await tester.tap(find.byKey(ValueKey('diploma-written-review-${q.id}')));
    await settle(tester);
    final saved = (await tester.runAsync(() => repository.read(attempt.id)))!;
    expect(saved.reviews[q.id]!.selectedCriteria, {q.criteria.first.id});
    expect(saved.reviews[q.id]!.improvement, contains('contract assumption'));
    expect(
      saved.isReviewed,
      isFalse,
      reason: 'the other two responses were blank',
    );
    expect(
      find.textContaining('not a grade or pass'),
      findsNothing,
      reason: 'partial work must not display the all-reviewed completion copy',
    );
    expect(tester.takeException(), isNull);
  });

  testApp('a new attempt does not inherit an earlier written response', (
    tester,
  ) async {
    await show(tester, 'D1');
    await tester.tap(find.byKey(const ValueKey('diploma-written-start')));
    await settle(tester);
    final first = (await tester.runAsync(() => repository.current('D1')))!;
    final proseKey = ValueKey('diploma-written-prose-${first.questions.first.id}');
    await tester.enterText(find.byKey(proseKey), 'Earlier private response');
    await settle(tester);
    await tester.ensureVisible(find.byKey(const ValueKey('diploma-written-finish')));
    await tester.tap(find.byKey(const ValueKey('diploma-written-finish')));
    await settle(tester);
    await tester.ensureVisible(find.text('Choose another attempt'));
    await tester.tap(find.text('Choose another attempt'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('diploma-written-start')));
    await settle(tester);
    final second = (await tester.runAsync(() => repository.current('D1')))!;
    expect(second.id, isNot(first.id));
    expect(second.prose, isEmpty);
    expect(tester.widget<TextFormField>(find.byKey(proseKey)).initialValue, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
