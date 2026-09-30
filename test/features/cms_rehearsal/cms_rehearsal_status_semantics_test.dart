import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/cms_rehearsal/cms_rehearsal_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const _ended =
    'Practice ended. Review your saved evidence and explain what to improve.';

Future<void> _until(
  WidgetTester tester,
  bool Function() ready,
  String reason,
) async {
  final clock = (await tester.runAsync(() async => Stopwatch()..start()))!;
  while (!ready() && clock.elapsed < const Duration(seconds: 12)) {
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(Duration.zero);
  }
  expect(ready(), isTrue, reason: reason);
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalRepository repository;
  late CmsRehearsalAttempt attempt;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(DateTime.utc(2026, 9, 30, 9));
    await CurriculumIngester(
      db,
      clock: time.clock,
      assets: (path) => File(path).readAsBytes(),
    ).ensureCurrent(bundledDataset());
    await seedSchedulerConfig(db);
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L3');
    repository = CmsRehearsalRepository(
      db,
      bank: CmsRehearsalBank.fromJson(
        File('assets/study/cms_certified_rehearsal.json').readAsStringSync(),
      ),
      clock: time.clock,
      random: Random(201),
    );
    final draft = await repository.start(CmsRehearsalSection.service);
    for (final question in draft.written) {
      await repository.answerWritten(
        draft.id,
        question.id,
        'Exact original service response for ${question.id}.',
      );
    }
    attempt = await repository.read(draft.id);
  });
  tearDown(() => db.close());

  testApp(
    'a genuinely submitted CMS service packet exposes its exact ended status separately',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              clockProvider.overrideWithValue(time.clock),
              cmsRehearsalRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
            ],
            child: const MaterialApp(home: CmsRehearsalScreen()),
          ),
        );
        final finish = find.byKey(const ValueKey('cms-rehearsal-finish'));
        await _until(
          tester,
          () =>
              finish.evaluate().length == 1 &&
              tester.widget<FilledButton>(finish).onPressed != null,
          'the actual saved service packet must finish loading',
        );
        expect(attempt.written, hasLength(3));
        final deepest = find.byKey(
          ValueKey('cms-rehearsal-written-${attempt.written.last.id}'),
        );
        await tester.ensureVisible(deepest);
        await tester.pump();
        await tester.tap(deepest);
        await tester.pump();
        final deepestEditable = tester.widget<EditableText>(
          find.descendant(of: deepest, matching: find.byType(EditableText)),
        );
        expect(deepestEditable.focusNode.hasFocus, isTrue);
        expect(
          deepestEditable.controller.text,
          attempt.prose[attempt.written.last.id],
        );
        // No forced blur or replacement click; activate the actual End button.
        await tester.ensureVisible(finish);
        await tester.pump();
        expect(finish.hitTestable(), findsOneWidget);
        expect(deepestEditable.focusNode.hasFocus, isTrue);
        await tester.tap(finish);
        final status = find.byKey(const ValueKey('cms-rehearsal-status'));
        await _until(
          tester,
          () =>
              status.evaluate().length == 1 &&
              tester.widget<Text>(status).data == _ended,
          'the real finish operation must paint the unchanged submitted status',
        );
        await tester.ensureVisible(status);
        await tester.pump();
        expect(status.hitTestable(), findsOneWidget);
        expect(find.text(_ended), findsOneWidget);
        expect(find.text('Ended: submitted'), findsOneWidget);
        final saved = (await tester.runAsync(
          () => repository.read(attempt.id).timeout(const Duration(seconds: 5)),
        ))!;
        expect(saved.isFinished, isTrue);
        expect(saved.isComplete, isTrue);
        expect(saved.finishReason, 'submitted');
        expect(saved.isReviewed, isFalse);
        expect(saved.prose, attempt.prose);
        expect(saved.startedAt, attempt.startedAt);
        expect(saved.deadline, attempt.deadline);
        expect(await tester.runAsync(repository.current), isNull);
        final profile = await tester.runAsync(
          () => LearnerProfiles(db).current(),
        );
        expect(profile!.activeCertificationId, 'WSET_L3');
        expect(
          await tester.runAsync(() => db.select(db.reviewEvents).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.reviewStates).get()),
          isEmpty,
        );
        expect(tester.takeException(), isNull);

        // Text is painted and stored, but a merged packet label is not a
        // separately discoverable screen-reader status announcement.
        final exactStatus = find.semantics.byPredicate(
          (node) => node.getSemanticsData().label == _ended,
        );
        expect(
          exactStatus.evaluate(),
          hasLength(1),
          reason: 'the exact ended status needs its own public semantics node',
        );
        expect(
          tester.getSemantics(status).getSemanticsData().label,
          _ended,
          reason: 'the status Text must belong to its own semantic boundary',
        );
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp(
    'an actually ended incomplete CMS two-wine packet exposes its exact warning separately',
    (tester) async {
      const incomplete =
          'This packet is incomplete and cannot count as reviewed participation.';
      final semantics = tester.ensureSemantics();
      try {
        // The shared fixture's service packet is retained as abandoned
        // history; use a genuine fresh two-wine draft for this warning case.
        final tasting = (await tester.runAsync(() async {
          await repository.discardCurrent(expectedId: attempt.id);
          final draft = await repository.start(CmsRehearsalSection.tasting);
          for (final q in draft.written) {
            await repository.answerWritten(
              draft.id,
              q.id,
              'Original synthetic comparison for ${q.id}; '
              'typed evidence does not establish physical tasting.',
            );
          }
          for (final wine in draft.wines) {
            for (final prompt in draft.wineEvidencePrompts) {
              await repository.writeWineEvidence(
                draft.id,
                wine.ordinal,
                prompt.id,
                'Saved synthetic wine ${wine.ordinal + 1} evidence for '
                '${prompt.id}; no physical wine was tasted.',
              );
            }
          }
          return repository.read(draft.id);
        }))!;
        expect(tasting.section, CmsRehearsalSection.tasting);
        expect(tasting.wines, hasLength(2));
        expect(tasting.wineEvidencePrompts, hasLength(5));
        expect(tasting.physicalAcknowledged, isFalse);
        expect(tasting.isComplete, isFalse);
        for (final wine in tasting.wines) {
          expect(wine.evidence, hasLength(5));
          expect(wine.observations, isEmpty);
        }

        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              clockProvider.overrideWithValue(time.clock),
              cmsRehearsalRepositoryProvider.overrideWith(
                (ref) async => repository,
              ),
            ],
            child: const MaterialApp(home: CmsRehearsalScreen()),
          ),
        );
        final finish = find.byKey(const ValueKey('cms-rehearsal-finish'));
        await _until(
          tester,
          () =>
              finish.evaluate().length == 1 &&
              tester.widget<FilledButton>(finish).onPressed != null,
          'the genuine incomplete two-wine draft must load before End',
        );
        await tester.ensureVisible(finish);
        await tester.pump();
        expect(finish.hitTestable(), findsOneWidget);
        await tester.tap(finish);

        final warning = find.byKey(const ValueKey('cms-rehearsal-incomplete'));
        await _until(
          tester,
          () =>
              warning.evaluate().length == 1 &&
              tester.widget<Text>(warning).data == incomplete,
          'actual End must paint the unchanged incomplete-packet warning',
        );
        final saved = (await tester.runAsync(
          () => repository.read(tasting.id).timeout(const Duration(seconds: 5)),
        ))!;
        expect(saved.id, tasting.id);
        expect(saved.isFinished, isTrue);
        expect(saved.finishReason, 'submitted');
        expect(saved.isComplete, isFalse);
        expect(saved.physicalAcknowledged, isFalse);
        expect(saved.isReviewed, isFalse);
        expect(saved.reviewedAt, isNull);
        expect(saved.missingReasons, [
          'Confirm these observations describe two actual wines.',
          'Complete Wine 1 observations and evidence.',
          'Complete Wine 2 observations and evidence.',
        ]);
        expect(saved.prose, tasting.prose);
        expect(
          saved.wines.map((wine) => wine.toJson()).toList(),
          tasting.wines.map((wine) => wine.toJson()).toList(),
          reason: 'finish preserves both original wine snapshots and evidence',
        );
        expect(saved.startedAt, tasting.startedAt);
        expect(saved.deadline, tasting.deadline);
        expect(await tester.runAsync(repository.current), isNull);
        expect(
          find.byKey(const ValueKey('cms-rehearsal-reviewed')),
          findsNothing,
          reason: 'the incomplete packet cannot expose participation review',
        );
        final profile = await tester.runAsync(
          () => LearnerProfiles(db).current(),
        );
        expect(profile!.activeCertificationId, 'WSET_L3');
        expect(
          await tester.runAsync(() => db.select(db.reviewEvents).get()),
          isEmpty,
        );
        expect(
          await tester.runAsync(() => db.select(db.reviewStates).get()),
          isEmpty,
        );
        final rows = (await tester.runAsync(
          () => db.select(db.userSettings).get(),
        ))!;
        expect(
          rows.where(
            (row) =>
                RegExp(r'official|exam_pass|qualification_completed')
                    .hasMatch(row.name),
          ),
          isEmpty,
        );
        final tastingCount = find.byKey(
          const ValueKey('cms-rehearsal-count-tasting'),
        );
        final viewport = find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Viewport),
        );
        expect(viewport, findsOneWidget);
        final outer = find.ancestor(
          of: viewport,
          matching: find.byType(Scrollable),
        );
        expect(outer, findsOneWidget);
        tester.state<ScrollableState>(outer).position.jumpTo(0);
        await tester.pump();
        await _until(
          tester,
          () =>
              tastingCount.evaluate().length == 1 &&
              tester.widget<Text>(tastingCount).data == 'Two-wine tasting: 0',
          'a submitted incomplete packet earns no tasting participation',
        );
        await tester.ensureVisible(warning);
        await tester.pump();
        expect(warning.hitTestable(), findsOneWidget);
        expect(find.text(incomplete), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Stored/painted incompleteness is established first; an aggregate
        // header containing this sentence is not its own discoverable leaf.
        final exactWarning = find.semantics.byPredicate(
          (node) => node.getSemanticsData().label == incomplete,
        );
        expect(
          exactWarning.evaluate(),
          hasLength(1),
          reason: 'the exact incomplete warning needs its own semantics node',
        );
        expect(
          tester.getSemantics(warning).getSemanticsData().label,
          incomplete,
          reason: 'the warning Text must belong to its own semantic boundary',
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
