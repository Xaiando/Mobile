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
    final proseKey = ValueKey(
      'diploma-written-prose-${first.questions.first.id}',
    );
    await tester.enterText(find.byKey(proseKey), 'Earlier private response');
    await settle(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey('diploma-written-finish')),
    );
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
    expect(
      tester.widget<TextFormField>(find.byKey(proseKey)).initialValue,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });
  for (final unitId in ['D4', 'D5']) {
    testApp('$unitId labels the app 45-minute writing timer and saves a response', (
      tester,
    ) async {
      await show(tester, unitId);
      expect(
        find.textContaining(
          'App-authored 45-minute writing-only practice for $unitId',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('not an official split'), findsOneWidget);
      expect(
        find.textContaining('Physical wine flights are separate activities'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('diploma-written-start')));
      await settle(tester);
      final attempt = (await tester.runAsync(
        () => repository.current(unitId),
      ))!;
      expect(find.text('Time remaining: 45:00'), findsOneWidget);
      final question = attempt.questions.first;
      final prose = find.byKey(
        ValueKey('diploma-written-prose-${question.id}'),
      );
      await tester.enterText(prose, 'My private product comparison.');
      await settle(tester);
      expect(
        (await tester.runAsync(() => repository.read(attempt.id)))!
            .prose[question.id],
        'My private product comparison.',
      );
      expect(
        find.byKey(
          ValueKey(
            'diploma-written-criterion-${question.id}-${question.criteria.first.id}',
          ),
        ),
        findsNothing,
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
            'diploma-written-criterion-${question.id}-${question.criteria.first.id}',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testApp(
    'D3 labels its app hour and a remounted draft keeps the saved deadline',
    (tester) async {
      await show(tester, 'D3');
      expect(
        find.textContaining(
          'App-authored 60-minute regional writing practice for D3',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('not an official examination allocation'),
        findsOneWidget,
      );
      expect(
        find.textContaining('not official examination questions or marks'),
        findsOneWidget,
      );
      expect(
        find.textContaining('three-wine tasting in 90 minutes'),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('diploma-written-start')));
      await settle(tester);
      final started = (await tester.runAsync(() => repository.current('D3')))!;
      expect(find.text('Time remaining: 60:00'), findsOneWidget);
      final first = started.questions.first;
      final prose = find.byKey(ValueKey('diploma-written-prose-${first.id}'));
      await tester.ensureVisible(prose);
      await settle(tester);
      await tester.enterText(
        prose,
        'My parcel plan needs a new health check after rain.',
      );
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.read(started.id)))!;
      expect(
        saved.prose[first.id],
        'My parcel plan needs a new health check after rain.',
      );
      expect(
        find.byKey(
          ValueKey(
            'diploma-written-criterion-${first.id}-${first.criteria.first.id}',
          ),
        ),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      time.advance(const Duration(minutes: 10));
      await show(tester, 'D3');
      expect(find.text('Time remaining: 50:00'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(prose).initialValue,
        saved.prose[first.id],
      );
      final reopened = (await tester.runAsync(() => repository.current('D3')))!;
      expect(reopened.toJson(), saved.toJson());
      expect(reopened.deadline, started.deadline);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'D3 saves all three explicit reviews and restores their notes and choices',
    (tester) async {
      final finished = (await tester.runAsync(() async {
        final started = await repository.start('D3');
        for (final question in started.questions) {
          await repository.answer(
            started.id,
            question.id,
            'My saved regional argument for ${question.id}.',
          );
        }
        return repository.finish(started.id);
      }))!;
      await show(tester, 'D3');
      final history = find.byKey(
        ValueKey('diploma-written-history-${finished.id}'),
      );
      await tester.ensureVisible(history);
      await tester.tap(history);
      await settle(tester);

      Future<void> bring(Finder finder) async {
        final scrollable = find.byType(Scrollable).first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await settle(tester);
        await tester.scrollUntilVisible(
          finder,
          300,
          scrollable: scrollable,
          maxScrolls: 35,
        );
        await tester.ensureVisible(finder);
        await settle(tester);
      }

      for (final (index, question) in finished.questions.indexed) {
        final criterion = find.byKey(
          ValueKey(
            'diploma-written-criterion-${question.id}-${question.criteria.first.id}',
          ),
        );
        if (index < 2) {
          await bring(criterion);
          await tester.tap(criterion);
          await settle(tester);
        }
        final note = find.byKey(
          ValueKey('diploma-written-improvement-${question.id}'),
        );
        await bring(note);
        await tester.enterText(
          note,
          'I need a stronger evidence comparison for ${question.id}.',
        );
        await settle(tester);
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(tester);
        final save = find.byKey(
          ValueKey('diploma-written-review-${question.id}'),
        );
        await bring(save);
        await tester.tap(save);
        await settle(tester);
        final actual = (await tester.runAsync(
          () => repository.read(finished.id),
        ))!;
        expect(
          actual.reviews[question.id]!.improvement,
          'I need a stronger evidence comparison for ${question.id}.',
        );
        expect(
          actual.reviews[question.id]!.selectedCriteria,
          index < 2 ? {question.criteria.first.id} : <String>{},
        );
        expect(actual.isReviewed, index == 2);
      }
      final saved = (await tester.runAsync(
        () => repository.read(finished.id),
      ))!;
      expect(saved.isReviewed, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await settle(tester);
      await show(tester, 'D3');
      await tester.ensureVisible(history);
      await tester.tap(history);
      await settle(tester);
      expect(
        find.text(
          'All three responses self-reviewed. This is participation, not a grade or pass.',
        ),
        findsOneWidget,
      );
      for (final (index, question) in finished.questions.indexed) {
        final criterion = find.byKey(
          ValueKey(
            'diploma-written-criterion-${question.id}-${question.criteria.first.id}',
          ),
        );
        await bring(criterion);
        expect(tester.widget<CheckboxListTile>(criterion).value, index < 2);
        final note = find.byKey(
          ValueKey('diploma-written-improvement-${question.id}'),
        );
        await bring(note);
        expect(
          tester.widget<TextFormField>(note).initialValue,
          saved.reviews[question.id]!.improvement,
        );
      }
      expect(
        (await tester.runAsync(() => repository.read(finished.id)))!.toJson(),
        saved.toJson(),
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewEvents).get()),
        isEmpty,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewStates).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'saving one review preserves another response latest unsaved review edits',
    (tester) async {
      final attempt = (await tester.runAsync(() async {
        final started = await repository.start('D4');
        for (final question in started.questions.take(2)) {
          await repository.answer(
            started.id,
            question.id,
            'A saved explanation for ${question.id}.',
          );
        }
        await repository.finish(started.id);
        for (final question in started.questions.take(2)) {
          await repository.review(started.id, question.id, {
            question.criteria.first.id,
          }, 'Initial review for ${question.id}.');
        }
        return started;
      }))!;
      expect(await tester.runAsync(() => repository.current('D4')), isNull);
      await show(tester, 'D4');
      final savedAttempt = find.byKey(
        ValueKey('diploma-written-history-${attempt.id}'),
      );
      await tester.ensureVisible(savedAttempt);
      await tester.tap(savedAttempt);
      await settle(tester);

      final first = attempt.questions[0];
      final second = attempt.questions[1];
      Finder criterion(
        DiplomaWrittenQuestion question,
        int index,
      ) => find.byKey(
        ValueKey(
          'diploma-written-criterion-${question.id}-${question.criteria[index].id}',
        ),
      );
      Finder note(DiplomaWrittenQuestion question) =>
          find.byKey(ValueKey('diploma-written-improvement-${question.id}'));
      Finder save(DiplomaWrittenQuestion question) =>
          find.byKey(ValueKey('diploma-written-review-${question.id}'));

      Future<void> toggleCriterion(
        DiplomaWrittenQuestion question,
        int index,
        bool expected,
      ) async {
        final tile = criterion(question, index);
        await tester.ensureVisible(tile);
        await settle(tester);
        await tester.tap(tile);
        await settle(tester);
        expect(tester.widget<CheckboxListTile>(tile).value, expected);
      }

      // Leave question two's revised note and selections unsaved while
      // explicitly saving a different response in the same selected attempt.
      await toggleCriterion(second, 0, false);
      await toggleCriterion(second, 1, true);
      await tester.ensureVisible(note(second));
      await settle(tester);
      await tester.enterText(
        note(second),
        'My latest second-response improvement needs a tasting comparison.',
      );
      await settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);

      await tester.ensureVisible(note(first));
      await settle(tester);
      await tester.enterText(
        note(first),
        'My revised first-response improvement needs stock evidence.',
      );
      await settle(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(tester);
      await toggleCriterion(first, 2, true);
      expect(
        tester.widget<CheckboxListTile>(criterion(first, 0)).value,
        isTrue,
      );
      expect(
        tester.widget<CheckboxListTile>(criterion(second, 0)).value,
        isFalse,
      );
      expect(
        tester.widget<CheckboxListTile>(criterion(second, 1)).value,
        isTrue,
      );
      await tester.ensureVisible(save(first));
      await settle(tester);
      await tester.tap(save(first));
      await settle(tester);
      final afterFirst = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(
        afterFirst.reviews[first.id]!.improvement,
        'My revised first-response improvement needs stock evidence.',
      );
      expect(afterFirst.reviews[first.id]!.selectedCriteria, {
        first.criteria[0].id,
        first.criteria[2].id,
      });

      await tester.ensureVisible(save(second));
      await settle(tester);
      await tester.tap(save(second));
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.read(attempt.id)))!;
      expect(
        saved.reviews[second.id]!.improvement,
        'My latest second-response improvement needs a tasting comparison.',
      );
      expect(saved.reviews[second.id]!.selectedCriteria, {
        second.criteria[1].id,
      });
      expect(
        saved.reviews[first.id]!.toJson(),
        afterFirst.reviews[first.id]!.toJson(),
      );
      expect(saved.isReviewed, isFalse, reason: 'the third response is blank');
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'a reopened D5 draft keeps its deadline and exposes review after expiry',
    (tester) async {
      final attempt = (await tester.runAsync(() => repository.start('D5')))!;
      final question = attempt.questions.first;
      await tester.runAsync(
        () => repository.answer(
          attempt.id,
          question.id,
          'A saved Port category comparison.',
        ),
      );
      time.advance(const Duration(minutes: 45));
      await show(tester, 'D5');
      expect(
        find.textContaining('Writing ended · review available'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('diploma-written-timer')), findsNothing);
      await tester.ensureVisible(
        find.byKey(ValueKey('diploma-written-history-${attempt.id}')),
      );
      await tester.tap(
        find.byKey(ValueKey('diploma-written-history-${attempt.id}')),
      );
      await settle(tester);
      expect(
        find.textContaining('Writing ended. Compare each saved answer'),
        findsOneWidget,
      );
      final field = tester.widget<TextFormField>(
        find.byKey(ValueKey('diploma-written-prose-${question.id}')),
      );
      expect(field.initialValue, 'A saved Port category comparison.');
      expect(field.enabled, isFalse);
      final saved = (await tester.runAsync(() => repository.read(attempt.id)))!;
      expect(saved.completedAt, attempt.deadline);
      expect(saved.finishReason, 'expired');
      expect(saved.isReviewed, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
