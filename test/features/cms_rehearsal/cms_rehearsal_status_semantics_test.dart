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
}
