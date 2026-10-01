import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show CheckedState, PointerDeviceKind;

import 'package:flutter/semantics.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal.dart';
import 'package:sommelier/core/cms_rehearsal/cms_rehearsal_providers.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/cms_rehearsal/cms_rehearsal_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const _deductiveKeys = [
  'clarity',
  'brightness',
  'hue',
  'concentration',
  'rim',
  'fruit_state',
  'fruit',
  'non_fruit',
  'wood',
  'intensity',
  'dryness',
  'body',
  'acid',
  'alcohol',
  'tannin',
  'complexity',
  'finish',
  'climate',
  'style',
  'age',
];

Future<void> _seedCms(AppDatabase db, CmsRehearsalBank bank) async {
  final links = {
    for (final q in bank.mcqs) ...q.itemIds,
    for (final q in bank.written) ...q.itemIds,
  };
  // Synthetic current study facts and vocabulary, not shipped wine claims.
  // Selection, storage and review still use the real database/repository.
  await db.writeCurriculum(
    () => runSql(db, [
      "INSERT INTO tasting_grids VALUES ('tg_deductive', 'CMS_DTM', '1.0', 'Test deductive observations')",
      for (final (index, _) in links.indexed)
        "INSERT INTO knowledge_nodes (id, node_type, name, name_norm) VALUES ('n_cms_widget_$index', 'appellation', 'CMS widget fact $index', 'cms widget fact $index')",
      for (final (index, _) in links.indexed)
        "INSERT INTO knowledge_relations (subject_id, relation_type, object_id, valid_from, valid_until) VALUES ('n_cms_widget_$index', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', '1900-01-01', NULL)",
      for (final (index, id) in links.indexed)
        "INSERT OR IGNORE INTO knowledge_items (id, subject_id, relation_type, object_id, domain_id, assertion_text, last_verified_at) VALUES ('$id', 'n_cms_widget_$index', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay', 'geography', 'Test-only linked study fact.', '2026-01-01T00:00:00.000Z')",
      for (final id in links)
        "INSERT OR IGNORE INTO certification_knowledge_mappings VALUES ('CMS_CERTIFIED', '$id', 'core', 2, NULL)",
      for (final (index, key) in _deductiveKeys.indexed)
        "INSERT INTO tasting_grid_attributes VALUES ('tg_deductive', '$key', 'Test observation', '$key', ${index + 1}, '${key == 'fruit' || key == 'non_fruit' ? 'multi' : 'single'}', ${key == 'fruit' || key == 'non_fruit' ? 0 : 1})",
      for (final key in _deductiveKeys)
        "INSERT INTO tasting_grid_values VALUES ('tg_deductive', '$key', 'observed', 'Observed test value', 1, NULL), ('tg_deductive', '$key', 'alternative', 'Alternative test value', 2, NULL)",
    ]),
  );
}

class _PausedRepository extends CmsRehearsalRepository {
  _PausedRepository(super.db, CmsRehearsalBank bank, TestClock time)
    : super(bank: bank, clock: time.clock, random: Random(41));

  final started = Completer<void>();
  final release = Completer<void>();
  bool pauseNext = true;
  int finishCalls = 0;

  @override
  Future<CmsRehearsalAttempt> answerWritten(
    String id,
    String questionId,
    String text,
  ) async {
    if (pauseNext) {
      pauseNext = false;
      started.complete();
      await release.future;
    }
    return super.answerWritten(id, questionId, text);
  }

  @override
  Future<CmsRehearsalAttempt> finish(String id) {
    finishCalls++;
    return super.finish(id);
  }
}

class _FailOnceRepository extends CmsRehearsalRepository {
  _FailOnceRepository(super.db, CmsRehearsalBank bank, TestClock time)
    : super(bank: bank, clock: time.clock, random: Random(42));

  bool failNext = false;
  int finishCalls = 0;

  @override
  Future<CmsRehearsalAttempt> answerWritten(
    String id,
    String questionId,
    String text,
  ) {
    if (failNext) {
      failNext = false;
      throw StateError('simulated durable write failure');
    }
    return super.answerWritten(id, questionId, text);
  }

  @override
  Future<CmsRehearsalAttempt> finish(String id) {
    finishCalls++;
    return super.finish(id);
  }
}

class _FailOnceCurrentRepository extends CmsRehearsalRepository {
  _FailOnceCurrentRepository(super.db, CmsRehearsalBank bank, TestClock time)
    : super(bank: bank, clock: time.clock, random: Random(43));
  bool failNext = true;
  @override
  Future<CmsRehearsalAttempt?> current() {
    if (failNext) {
      failNext = false;
      throw StateError('database unavailable');
    }
    return super.current();
  }
}

class _PausedObservationRepository extends CmsRehearsalRepository {
  _PausedObservationRepository(super.db, CmsRehearsalBank bank, TestClock time)
    : super(bank: bank, clock: time.clock, random: Random(44));
  final started = Completer<void>();
  final release = Completer<void>();
  bool pauseNext = true;
  @override
  Future<CmsRehearsalAttempt> chooseObservation(
    String id,
    int wineIndex,
    String key,
    Set<String> values,
  ) async {
    if (pauseNext) {
      pauseNext = false;
      started.complete();
      await release.future;
    }
    return super.chooseObservation(id, wineIndex, key, values);
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalBank bank;
  late CmsRehearsalRepository repository;

  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    bank = CmsRehearsalBank.fromJson(
      File('assets/study/cms_certified_rehearsal.json').readAsStringSync(),
    );
    await seedCurriculum(db);
    await _seedCms(db, bank);
    await LearnerProfiles(db, clock: time.clock).selectTrack('CMS_CERTIFIED');
    repository = CmsRehearsalRepository(
      db,
      bank: bank,
      clock: time.clock,
      random: Random(40),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> show(
    WidgetTester tester, {
    String? savedId,
    bool readOnly = false,
    bool withBackRoute = false,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
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
        child: MaterialApp(
          home: withBackRoute
              ? Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CmsRehearsalScreen(
                            savedAttemptId: savedId,
                            readOnly: readOnly,
                          ),
                        ),
                      ),
                      child: const Text('Open CMS practice'),
                    ),
                  ),
                )
              : CmsRehearsalScreen(savedAttemptId: savedId, readOnly: readOnly),
        ),
      ),
    );
    if (withBackRoute) {
      await tester.tap(find.text('Open CMS practice'));
    }
    await settle(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final outer = find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first;
    final state = tester.state<ScrollableState>(outer);
    state.position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      target,
      180,
      scrollable: outer,
      maxScrolls: 100,
    );
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final target = find.byKey(ValueKey(key));
    await reveal(tester, target);
    await tester.tap(target);
    await settle(tester);
  }

  Future<void> enterKey(WidgetTester tester, String key, String text) async {
    final target = find.byKey(ValueKey(key));
    await reveal(tester, target);
    await tester.enterText(target, text);
    await settle(tester);
  }

  String textFor(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byType(EditableText),
        ),
      )
      .controller
      .text;

  Future<CmsRehearsalAttempt> servicePacket(
    String tag, {
    bool reviewed = false,
  }) async {
    final attempt = await repository.start(CmsRehearsalSection.service);
    for (final q in attempt.written) {
      await repository.answerWritten(
        attempt.id,
        q.id,
        '$tag exact response for ${q.id}.',
      );
    }
    var saved = await repository.finish(attempt.id);
    if (reviewed) {
      for (final q in attempt.written) {
        saved = await repository.selfAssess(
          attempt.id,
          q.id,
          {},
          improvement: '$tag exact improvement for ${q.id}.',
        );
      }
      saved = await repository.review(attempt.id);
    }
    return saved;
  }

  Future<void> expectNoStudyCredit(WidgetTester tester) async {
    expect(
      await tester.runAsync(() => db.select(db.reviewStates).get()),
      isEmpty,
    );
    expect(
      await tester.runAsync(() => db.select(db.reviewEvents).get()),
      isEmpty,
    );
    final rows = await tester.runAsync(() => db.select(db.userSettings).get());
    expect(
      rows!.where(
        (r) =>
            RegExp(r'official|exam_pass|qualification_completed')
                .hasMatch(r.name),
      ),
      isEmpty,
    );
  }

  for (final wheel in [true, false]) {
    testApp(
      'user ${wheel ? 'wheel' : 'drag'} dismisses CMS editing without losing answers',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          final attempt = (await tester.runAsync(() async {
            final draft = await repository.start(CmsRehearsalSection.service);
            for (final question in draft.written) {
              await repository.answerWritten(
                draft.id,
                question.id,
                'Stored sibling response for ${question.id}.',
              );
            }
            return repository.read(draft.id);
          }))!;
          await show(tester);
          tester.view.physicalSize = const Size(320, 780);
          await tester.pumpAndSettle();
          final question = attempt.written.first;
          final key = 'cms-rehearsal-written-${question.id}';
          const edited = 'An exact response survives scrolling and re-entry.';
          await enterKey(tester, key, edited);
          final field = find.byKey(ValueKey(key));
          final editable = tester.widget<EditableText>(
            find.descendant(of: field, matching: find.byType(EditableText)),
          );
          expect(editable.focusNode.hasFocus, isTrue);
          final list = find.byType(ListView).first;
          final outer = find
              .descendant(of: list, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(outer).position;
          final before = position.pixels;
          expect(
            before,
            greaterThan(0),
            reason: 'the edited field is below the top',
          );
          final body = tester.getRect(list);
          final gutter = Offset(body.left + 8, body.center.dy);
          if (wheel) {
            final pointer = TestPointer(401, PointerDeviceKind.mouse);
            await tester.sendEventToBinding(pointer.hover(gutter));
            await tester.sendEventToBinding(
              pointer.scroll(const Offset(0, -100000)),
            );
            await tester.sendEventToBinding(pointer.removePointer());
          } else {
            await tester.dragFrom(gutter, const Offset(0, 180));
          }
          await settle(tester);
          expect(
            editable.focusNode.hasFocus,
            isFalse,
            reason: 'user scrolling must close editing before offscreen inputs return',
          );
          expect(position.pixels, lessThan(before));
          final expected = {...attempt.prose, question.id: edited};
          final stored = (await tester.runAsync(
            () => repository.read(attempt.id),
          ))!;
          expect(stored.prose, expected);
          expect(stored.startedAt, attempt.startedAt);
          expect(stored.deadline, attempt.deadline);
          expect(stored.isFinished, isFalse);
          expect(stored.isReviewed, isFalse);

          await reveal(tester, field);
          expect(textFor(tester, key), edited);
          // Deliberate deletion after refocusing remains a valid saved edit.
          await enterKey(tester, key, '');
          final cleared = (await tester.runAsync(
            () => repository.read(attempt.id),
          ))!;
          expect(cleared.prose, {...expected, question.id: ''});
          expect(cleared.deadline, attempt.deadline);
          await expectNoStudyCredit(tester);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testApp('all three original app presets show explicit study limitations', (
    tester,
  ) async {
    await show(tester);
    expect(
      find.textContaining('not official exam allocations'),
      findsOneWidget,
    );
    for (final section in CmsRehearsalSection.values) {
      await reveal(
        tester,
        find.byKey(ValueKey('cms-rehearsal-start-${section.id}')),
      );
      expect(find.text('Start ${section.id} practice'), findsOneWidget);
      expect(
        find.text(
          'App-authored ${section.durationSeconds ~/ 60}-minute practice',
        ),
        findsOneWidget,
      );
    }
    await tapKey(tester, 'cms-rehearsal-start-service');
    final current = (await tester.runAsync(repository.current))!;
    expect(current.section, CmsRehearsalSection.service);
    expect(current.preset.durationSeconds, 900);
    expect(current.written.length, 3);
    await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-timer')));
    expect(find.text('Time remaining: 15:00'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('cms-rehearsal-start-theory')),
      findsNothing,
      reason: 'a current draft must be resumed or explicitly discarded',
    );
    expect(current.isReviewed, isFalse);
    await expectNoStudyCredit(tester);
    expect(tester.takeException(), isNull);
  });

  testApp(
    'finish drains serialized response saves and disables late draft inputs',
    (tester) async {
      final paused = _PausedRepository(db, bank, time);
      repository = paused;
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      await show(tester);
      final firstKey = 'cms-rehearsal-written-${attempt.written.first.id}';
      await reveal(tester, find.byKey(ValueKey(firstKey)));
      await tester.enterText(
        find.byKey(ValueKey(firstKey)),
        'First queued exact explanation.',
      );
      await tester.runAsync(
        () => paused.started.future.timeout(const Duration(seconds: 2)),
      );
      final secondKey = 'cms-rehearsal-written-${attempt.written[1].id}';
      await reveal(tester, find.byKey(ValueKey(secondKey)));
      await tester.enterText(
        find.byKey(ValueKey(secondKey)),
        'Second queued exact explanation.',
      );
      final finish = find.byKey(const ValueKey('cms-rehearsal-finish'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pump();
      expect(paused.finishCalls, 0);
      expect(tester.widget<FilledButton>(finish).onPressed, isNull);
      await reveal(tester, find.byKey(ValueKey(secondKey)));
      expect(
        tester.widget<TextFormField>(find.byKey(ValueKey(secondKey))).enabled,
        isFalse,
      );
      paused.release.complete();
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.read(attempt.id)))!;
      expect(saved.isFinished, isTrue);
      expect(
        saved.prose[attempt.written.first.id],
        'First queued exact explanation.',
      );
      expect(
        saved.prose[attempt.written[1].id],
        'Second queued exact explanation.',
      );
      expect(
        saved.isReviewed,
        isFalse,
        reason: 'third response and self-review are incomplete',
      );
      expect(paused.finishCalls, 1);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'a failed autosave blocks finish and Back until same-ID reload restores saved prose',
    (tester) async {
      final failing = _FailOnceRepository(db, bank, time);
      repository = failing;
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      final question = attempt.written.first;
      await tester.runAsync(
        () => repository.answerWritten(
          attempt.id,
          question.id,
          'Previously durable prose.',
        ),
      );
      failing.failNext = true;
      await show(tester, withBackRoute: true);
      final key = 'cms-rehearsal-written-${question.id}';
      await enterKey(tester, key, 'Unsaved replacement that must not finish.');
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-error')));
      expect(
        find.textContaining('simulated durable write failure'),
        findsOneWidget,
      );
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-finish')));
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('cms-rehearsal-finish')),
            )
            .onPressed,
        isNull,
      );
      await tester.pageBack();
      await settle(tester);
      expect(find.byType(CmsRehearsalScreen), findsOneWidget);
      expect(failing.finishCalls, 0);
      final beforeReload = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(beforeReload.isFinished, isFalse);
      expect(beforeReload.prose[question.id], 'Previously durable prose.');
      await tapKey(tester, 'cms-rehearsal-reload');
      await reveal(tester, find.byKey(ValueKey(key)));
      expect(
        textFor(tester, key),
        'Previously durable prose.',
        reason: 'explicit reload must reseed controllers even for the same draft ID',
      );
      expect((await tester.runAsync(repository.current))!.id, attempt.id);
      await enterKey(tester, key, 'New durable prose after reload.');
      await tapKey(tester, 'cms-rehearsal-finish');
      expect(
        (await tester.runAsync(() => repository.read(attempt.id)))!
            .prose[question.id],
        'New durable prose after reload.',
      );
      expect(failing.finishCalls, 1);
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'Back waits for an in-flight autosave and leaves the original deadline intact',
    (tester) async {
      final paused = _PausedRepository(db, bank, time);
      repository = paused;
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      await show(tester, withBackRoute: true);
      final key = 'cms-rehearsal-written-${attempt.written.first.id}';
      await reveal(tester, find.byKey(ValueKey(key)));
      await tester.enterText(
        find.byKey(ValueKey(key)),
        'Exact prose saved before leaving.',
      );
      await tester.runAsync(
        () => paused.started.future.timeout(const Duration(seconds: 2)),
      );
      await tester.pageBack();
      await tester.pump();
      expect(find.byType(CmsRehearsalScreen), findsOneWidget);
      paused.release.complete();
      await settle(tester);
      expect(find.byType(CmsRehearsalScreen), findsNothing);
      final saved = (await tester.runAsync(repository.current))!;
      expect(saved.id, attempt.id);
      expect(saved.deadline, attempt.deadline);
      expect(
        saved.prose[attempt.written.first.id],
        'Exact prose saved before leaving.',
      );
      expect(saved.isFinished, isFalse);
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'saving one review retains another unsaved note and requires all improvement-led reviews',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => servicePacket('Review packet'),
      ))!;
      await show(tester, savedId: attempt.id);
      final first = attempt.written[0];
      final second = attempt.written[1];
      final secondKey = 'cms-rehearsal-improvement-${second.id}';
      await enterKey(
        tester,
        secondKey,
        'Unsaved second note retained across first save.',
      );
      await enterKey(
        tester,
        'cms-rehearsal-improvement-${first.id}',
        'First concrete improvement.',
      );
      await tapKey(tester, 'cms-rehearsal-self-review-${first.id}');
      await reveal(tester, find.byKey(ValueKey(secondKey)));
      expect(
        textFor(tester, secondKey),
        'Unsaved second note retained across first save.',
      );
      final partial = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(partial.reviewNotes[first.id], 'First concrete improvement.');
      expect(partial.reviewNotes.containsKey(second.id), isFalse);
      expect(partial.isReviewed, isFalse);
      await tapKey(tester, 'cms-rehearsal-reviewed');
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-error')));
      expect(
        find.textContaining('each improvement-led review first'),
        findsOneWidget,
      );
      expect(
        (await tester.runAsync(() => repository.read(attempt.id)))!.isReviewed,
        isFalse,
      );
      await tapKey(tester, 'cms-rehearsal-self-review-${second.id}');
      final third = attempt.written[2];
      await enterKey(
        tester,
        'cms-rehearsal-improvement-${third.id}',
        'Third concrete improvement.',
      );
      await tapKey(tester, 'cms-rehearsal-self-review-${third.id}');
      await tapKey(tester, 'cms-rehearsal-reviewed');
      final reviewed = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(reviewed.isReviewed, isTrue);
      expect(
        reviewed.selfAssessment.values.every((selected) => selected.isEmpty),
        isTrue,
        reason: 'unchecked criteria plus genuine improvement evidence is honest participation',
      );
      expect(
        reviewed.reviewNotes[second.id],
        'Unsaved second note retained across first save.',
      );
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-status')));
      expect(
        find.text(
          'Self-reviewed participation saved. This is not a grade or pass.',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      for (final q in reviewed.written) {
        await reveal(
          tester,
          find.byKey(ValueKey('cms-rehearsal-improvement-${q.id}')),
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(ValueKey('cms-rehearsal-improvement-${q.id}')),
              )
              .enabled,
          isFalse,
        );
      }
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'read-only finished history preserves exact saved prose, notes and a newer draft pointer',
    (tester) async {
      final saved = (await tester.runAsync(
        () => servicePacket('Archived', reviewed: true),
      ))!;
      time.advance(const Duration(minutes: 1));
      final current = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      await tester.runAsync(
        () => repository.answerWritten(
          current.id,
          current.written.first.id,
          'Newer draft stays current.',
        ),
      );
      await show(tester);
      await tapKey(tester, 'cms-rehearsal-view-${saved.id}');
      expect(
        find.text(
          'Read-only saved snapshot. Viewing this record does not change your current draft.',
        ),
        findsOneWidget,
      );
      for (final q in saved.written) {
        final key = 'cms-rehearsal-written-${q.id}';
        await reveal(tester, find.byKey(ValueKey(key)));
        expect(find.text(q.prompt), findsOneWidget);
        expect(textFor(tester, key), 'Archived exact response for ${q.id}.');
        expect(
          tester.widget<TextFormField>(find.byKey(ValueKey(key))).enabled,
          isFalse,
        );
        final note = 'cms-rehearsal-improvement-${q.id}';
        await reveal(tester, find.byKey(ValueKey(note)));
        expect(
          textFor(tester, note),
          'Archived exact improvement for ${q.id}.',
        );
        expect(
          tester.widget<TextFormField>(find.byKey(ValueKey(note))).enabled,
          isFalse,
        );
      }
      expect(find.byKey(const ValueKey('cms-rehearsal-finish')), findsNothing);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      expect((await tester.runAsync(repository.current))!.id, current.id);
      await tester.pageBack();
      await settle(tester);
      expect((await tester.runAsync(repository.current))!.id, current.id);
      final key = 'cms-rehearsal-written-${current.written.first.id}';
      await reveal(tester, find.byKey(ValueKey(key)));
      expect(textFor(tester, key), 'Newer draft stays current.');
      // A true remount re-reads durable snapshots rather than reusing controllers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await show(tester, savedId: saved.id, readOnly: true);
      for (final q in saved.written) {
        await reveal(
          tester,
          find.byKey(ValueKey('cms-rehearsal-written-${q.id}')),
        );
        expect(
          textFor(tester, 'cms-rehearsal-written-${q.id}'),
          saved.prose[q.id],
        );
        await reveal(
          tester,
          find.byKey(ValueKey('cms-rehearsal-improvement-${q.id}')),
        );
        expect(
          textFor(tester, 'cms-rehearsal-improvement-${q.id}'),
          saved.reviewNotes[q.id],
        );
      }
      expect((await tester.runAsync(repository.current))!.id, current.id);
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'deadline expiry preserves the original snapshot and incomplete history has no review action',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      await tester.runAsync(
        () => repository.answerWritten(
          attempt.id,
          attempt.written.first.id,
          'Saved before absolute expiry.',
        ),
      );
      time.advance(const Duration(minutes: 16));
      await show(tester);
      expect(await tester.runAsync(repository.current), isNull);
      await tapKey(tester, 'cms-rehearsal-view-${attempt.id}');
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-status')));
      expect(find.text('Ended: expired'), findsOneWidget);
      expect(find.byKey(const ValueKey('cms-rehearsal-timer')), findsNothing);
      final expired = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(expired.completedAt, attempt.deadline);
      expect(expired.deadline, attempt.deadline);
      expect(expired.finishReason, 'expired');
      expect(expired.isReviewed, isFalse);
      final key = 'cms-rehearsal-written-${attempt.written.first.id}';
      await reveal(tester, find.byKey(ValueKey(key)));
      expect(textFor(tester, key), 'Saved before absolute expiry.');
      expect(
        tester.widget<TextFormField>(find.byKey(ValueKey(key))).enabled,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'tasting cannot earn reviewed participation from typed evidence without two physical wines',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.tasting),
      ))!;
      await tester.runAsync(() async {
        for (final wine in attempt.wines) {
          for (final attribute in wine.attributes) {
            if (attribute.isRequired) {
              await repository.chooseObservation(
                attempt.id,
                wine.ordinal,
                attribute.key,
                {'observed'},
              );
            }
          }
          for (final prompt in attempt.wineEvidencePrompts) {
            await repository.writeWineEvidence(
              attempt.id,
              wine.ordinal,
              prompt.id,
              'Typed-only Wine ${wine.ordinal + 1}: ${prompt.id}.',
            );
          }
        }
        await repository.answerWritten(
          attempt.id,
          attempt.written.single.id,
          'Typed two-wine comparison.',
        );
      });
      await show(tester);
      await tapKey(tester, 'cms-rehearsal-finish');
      final finished = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(finished.isFinished, isTrue);
      expect(finished.physicalAcknowledged, isFalse);
      expect(
        finished.missingReasons,
        contains('Confirm these observations describe two actual wines.'),
      );
      expect(finished.isReviewed, isFalse);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('cms-rehearsal-incomplete')),
      );
      expect(
        find.text(
          'This packet is incomplete and cannot count as reviewed participation.',
        ),
        findsOneWidget,
      );
      // The mounted evidence watch schedules its database refresh in the
      // widget test's fake zone. Give that callback a real observed completion
      // between transactions instead of chaining real-zone writes behind it.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CmsRehearsalScreen)),
      );
      var evidenceEvents = 0;
      final evidenceSubscription = container.listen(
        cmsRehearsalEvidenceProvider,
        (_, next) {
          if (next.hasValue && !next.isLoading && !next.hasError) {
            evidenceEvents++;
          }
        },
        fireImmediately: true,
      );
      addTearDown(evidenceSubscription.close);

      Future<void> waitForEvidenceAfter(int previous, String phase) async {
        final bound = Stopwatch()..start();
        while (evidenceEvents <= previous &&
            bound.elapsed < const Duration(seconds: 5)) {
          await tester.pump();
          // Yield an event-loop turn for the actual SQLite response, then
          // pump its fake-zone notification; no arbitrary sleep is required.
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(
          evidenceEvents,
          greaterThan(previous),
          reason: 'CMS tasting widget phase: $phase',
        );
        await tester.pump();
        debugPrint('CMS tasting widget phase complete: $phase');
      }

      await waitForEvidenceAfter(0, 'initial evidence ready');
      final beforeAssessment = evidenceEvents;
      final assessed = await tester.runAsync(
        () => repository
            .selfAssess(
              attempt.id,
              attempt.written.single.id,
              {},
              improvement: 'Actual sensory observations are still required.',
            )
            .timeout(const Duration(seconds: 5)),
      );
      expect(assessed, isNotNull);
      await waitForEvidenceAfter(
        beforeAssessment,
        'saved improvement acknowledged by live evidence watch',
      );
      await tester.runAsync(
        () => expectLater(
          repository.review(attempt.id).timeout(const Duration(seconds: 5)),
          throwsStateError,
        ),
      );
      await tester.pump();
      debugPrint(
        'CMS tasting widget phase complete: incomplete physical review rejected',
      );
      expect(
        (await tester.runAsync(() => repository.read(attempt.id)))!.isReviewed,
        isFalse,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'a saved two-wine packet reloads exact observations, evidence and comparison without edits',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.tasting),
      ))!;
      await tester.runAsync(() async {
        await repository.acknowledgePhysical(attempt.id, true);
        for (final wine in attempt.wines) {
          for (final attribute in wine.attributes) {
            await repository.chooseObservation(
              attempt.id,
              wine.ordinal,
              attribute.key,
              attribute.isSingle ? {'observed'} : {'observed', 'alternative'},
            );
          }
          for (final prompt in attempt.wineEvidencePrompts) {
            await repository.writeWineEvidence(
              attempt.id,
              wine.ordinal,
              prompt.id,
              'Saved Wine ${wine.ordinal + 1} exact ${prompt.id} evidence.',
            );
          }
        }
        await repository.answerWritten(
          attempt.id,
          attempt.written.single.id,
          'Exact saved two-wine comparison with uncertainty.',
        );
        await repository.finish(attempt.id);
        await repository.selfAssess(
          attempt.id,
          attempt.written.single.id,
          {},
          improvement: 'Exact saved improvement without an identity authentication claim.',
        );
        await repository.review(attempt.id);
      });
      final snapshot = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      await show(tester, savedId: attempt.id, readOnly: true);
      for (final wine in snapshot.wines) {
        await tapKey(tester, 'cms-rehearsal-wine-${wine.ordinal}');
        final observation = find.byKey(
          ValueKey('cms-rehearsal-observation-${wine.ordinal}-fruit-observed'),
        );
        await reveal(tester, observation);
        expect(tester.widget<FilterChip>(observation).selected, isTrue);
        expect(tester.widget<FilterChip>(observation).onSelected, isNull);
        final alternative = find.byKey(
          ValueKey(
            'cms-rehearsal-observation-${wine.ordinal}-fruit-alternative',
          ),
        );
        expect(tester.widget<FilterChip>(alternative).selected, isTrue);
        for (final prompt in snapshot.wineEvidencePrompts) {
          final key =
              'cms-rehearsal-wine-evidence-${wine.ordinal}-${prompt.id}';
          await reveal(tester, find.byKey(ValueKey(key)));
          expect(
            textFor(tester, key),
            'Saved Wine ${wine.ordinal + 1} exact ${prompt.id} evidence.',
          );
          expect(
            tester.widget<TextFormField>(find.byKey(ValueKey(key))).enabled,
            isFalse,
          );
        }
      }
      final key = 'cms-rehearsal-written-${snapshot.written.single.id}';
      await reveal(tester, find.byKey(ValueKey(key)));
      expect(
        textFor(tester, key),
        'Exact saved two-wine comparison with uncertainty.',
      );
      final note = 'cms-rehearsal-improvement-${snapshot.written.single.id}';
      await reveal(tester, find.byKey(ValueKey(note)));
      expect(
        textFor(tester, note),
        'Exact saved improvement without an identity authentication claim.',
      );
      expect(await tester.runAsync(repository.current), isNull);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-reviewed')),
        findsNothing,
      );
      final reread = (await tester.runAsync(
        () => repository.read(attempt.id),
      ))!;
      expect(
        reread.toJson(),
        snapshot.toJson(),
        reason: 'viewing finished evidence is immutable',
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'unreadable current selection has confirmed pointer-only recovery that retains raw history',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      const raw = '{retained imported bytes that are not valid JSON';
      await tester.runAsync(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: CmsRehearsalRepository.keyFor(attempt.id),
                value: raw,
                updatedAt: time.now,
              ),
            ),
      );
      await show(tester);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-retry-load')),
        findsOneWidget,
      );
      await tapKey(tester, 'cms-rehearsal-release-selection');
      expect(
        find.textContaining('Saved attempt data is retained in history'),
        findsOneWidget,
      );
      await tester.tap(find.text('Release selection'));
      await settle(tester);
      expect(await tester.runAsync(repository.currentPointer), isNull);
      final row = await tester.runAsync(
        () =>
            (db.select(db.userSettings)..where(
                  (r) =>
                      r.name.equals(CmsRehearsalRepository.keyFor(attempt.id)),
                ))
                .getSingle(),
      );
      expect(row!.value, raw);
      await reveal(
        tester,
        find.byKey(const ValueKey('cms-rehearsal-history-warning')),
      );
      expect(find.text('1 saved record(s) could not be read.'), findsOneWidget);
      await tapKey(tester, 'cms-rehearsal-start-service');
      final current = (await tester.runAsync(repository.current))!;
      expect(current.id, isNot(attempt.id));
      expect(
        (await tester.runAsync(
          () =>
              (db.select(db.userSettings)..where(
                    (r) => r.name.equals(
                      CmsRehearsalRepository.keyFor(attempt.id),
                    ),
                  ))
                  .getSingle(),
        ))!.value,
        raw,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'recovery confirmation cannot release a newer valid draft selection',
    (tester) async {
      final old = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      const raw = '{preserve this unreadable previous record';
      await tester.runAsync(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: CmsRehearsalRepository.keyFor(old.id),
                value: raw,
                updatedAt: time.now,
              ),
            ),
      );
      await show(tester);
      await tapKey(tester, 'cms-rehearsal-release-selection');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(CmsRehearsalScreen)),
      );
      var evidenceEvents = 0;
      final evidenceSubscription = container.listen(
        cmsRehearsalEvidenceProvider,
        (_, next) {
          if (next.hasValue && !next.isLoading && !next.hasError) {
            evidenceEvents++;
          }
        },
        fireImmediately: true,
      );
      addTearDown(evidenceSubscription.close);

      Future<void> waitForEvidenceAfter(int previous, String phase) async {
        final bound = Stopwatch()..start();
        while (evidenceEvents <= previous &&
            bound.elapsed < const Duration(seconds: 5)) {
          await tester.pump(Duration.zero);
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        }
        expect(
          evidenceEvents,
          greaterThan(previous),
          reason: 'CMS recovery race phase: $phase',
        );
        await tester.pump(Duration.zero);
        debugPrint('CMS recovery race phase complete: $phase');
      }

      await waitForEvidenceAfter(0, 'initial successful live evidence ready');
      final beforeDelete = evidenceEvents;
      final deleted = await tester.runAsync(
        () =>
            (db.delete(db.userSettings)..where(
                  (r) => r.name.equals(CmsRehearsalRepository.currentKey),
                ))
                .go()
                .timeout(
                  const Duration(seconds: 5),
                  onTimeout: () => throw TimeoutException(
                    'CMS recovery race phase: delete previous selection',
                  ),
                ),
      );
      expect(deleted, 1);
      await waitForEvidenceAfter(
        beforeDelete,
        'pointer deletion acknowledged by live evidence watch',
      );
      final beforeStart = evidenceEvents;
      final newer = (await tester.runAsync(
        () => repository
            .start(CmsRehearsalSection.service)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException(
                'CMS recovery race phase: start newer valid draft',
              ),
            ),
      ))!;
      await waitForEvidenceAfter(
        beforeStart,
        'new valid draft acknowledged by live evidence watch',
      );
      await tester.tap(find.text('Release selection'));
      await settle(tester);
      expect(await tester.runAsync(repository.currentPointer), newer.id);
      expect((await tester.runAsync(repository.current))!.id, newer.id);
      final oldRow = await tester.runAsync(
        () =>
            (db.select(db.userSettings)..where(
                  (r) => r.name.equals(CmsRehearsalRepository.keyFor(old.id)),
                ))
                .getSingle(),
      );
      expect(oldRow!.value, raw);
      await tapKey(tester, 'cms-rehearsal-retry-load');
      expect((await tester.runAsync(repository.current))!.id, newer.id);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-release-selection')),
        findsNothing,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'clock repair refuses to release the same now-readable future draft',
    (tester) async {
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      final futureStart = time.now.add(const Duration(hours: 1));
      final data = {
        ...attempt.toJson(),
        'startedAt': futureStart.toIso8601String(),
        'deadline': futureStart
            .add(const Duration(minutes: 15))
            .toIso8601String(),
      };
      await tester.runAsync(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: CmsRehearsalRepository.keyFor(attempt.id),
                value: jsonEncode(data),
                updatedAt: time.now,
              ),
            ),
      );
      await show(tester);
      await tapKey(tester, 'cms-rehearsal-release-selection');
      time.advance(const Duration(hours: 1, minutes: 5));
      await tester.tap(find.text('Release selection'));
      await settle(tester);
      expect(await tester.runAsync(repository.currentPointer), attempt.id);
      final repaired = (await tester.runAsync(repository.current))!;
      expect(repaired.id, attempt.id);
      expect(repaired.isFinished, isFalse);
      expect(repaired.startedAt, futureStart);
      expect(repaired.deadline, futureStart.add(const Duration(minutes: 15)));
      await tapKey(tester, 'cms-rehearsal-retry-load');
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-timer')));
      expect(find.text('Time remaining: 10:00'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-release-selection')),
        findsNothing,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'generic executor read failure offers Retry without pointer release',
    (tester) async {
      repository = _FailOnceCurrentRepository(db, bank, time);
      final current = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.service),
      ))!;
      await show(tester);
      expect(find.textContaining('database unavailable'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('cms-rehearsal-retry-load')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('cms-rehearsal-release-selection')),
        findsNothing,
      );
      expect(await tester.runAsync(repository.currentPointer), current.id);
      await tapKey(tester, 'cms-rehearsal-retry-load');
      expect((await tester.runAsync(repository.current))!.id, current.id);
      await reveal(tester, find.byKey(const ValueKey('cms-rehearsal-timer')));
      expect(find.text('Time remaining: 15:00'), findsOneWidget);
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'queued multi-select observations retain both choices before Finish drains them',
    (tester) async {
      final paused = _PausedObservationRepository(db, bank, time);
      repository = paused;
      final attempt = (await tester.runAsync(
        () => repository.start(CmsRehearsalSection.tasting),
      ))!;
      await show(tester);
      await tapKey(tester, 'cms-rehearsal-wine-0');
      final observed = find.byKey(
        const ValueKey('cms-rehearsal-observation-0-fruit-observed'),
      );
      await reveal(tester, observed);
      await tester.tap(observed);
      await tester.pump();
      await tester.runAsync(
        () => paused.started.future.timeout(const Duration(seconds: 2)),
      );
      final alternative = find.byKey(
        const ValueKey('cms-rehearsal-observation-0-fruit-alternative'),
      );
      await reveal(tester, alternative);
      await tester.tap(alternative);
      await tester.pump();
      expect(tester.widget<FilterChip>(observed).selected, isTrue);
      expect(tester.widget<FilterChip>(alternative).selected, isTrue);
      final finish = find.byKey(const ValueKey('cms-rehearsal-finish'));
      await reveal(tester, finish);
      await tester.tap(finish);
      await tester.pump();
      expect(
        (await tester.runAsync(() => repository.read(attempt.id)))!.isFinished,
        isFalse,
      );
      paused.release.complete();
      await settle(tester);
      final saved = (await tester.runAsync(() => repository.read(attempt.id)))!;
      expect(saved.isFinished, isTrue);
      expect(saved.wines.first.observations['fruit'], {
        'observed',
        'alternative',
      });
      expect(saved.wines.last.observations, isEmpty);
      expect(saved.isReviewed, isFalse);
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'live participation follows genuine review, corruption, clock rollback and deletion',
    (tester) async {
      await show(tester);
      String count() => tester
          .widget<Text>(
            find.byKey(const ValueKey('cms-rehearsal-count-service')),
          )
          .data!;
      expect(count(), 'Service decisions: 0');

      Future<T> save<T>(Future<T> Function() change, String phase) async {
        final result = await tester.runAsync(
          () => change().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('CMS stream phase: $phase'),
          ),
        );
        await settle(tester);
        return result as T;
      }

      final attempt = await save(
        () => repository.start(CmsRehearsalSection.service),
        'start real service draft',
      );
      for (final q in attempt.written) {
        await save(
          () => repository.answerWritten(
            attempt.id,
            q.id,
            'Live saved response for ${q.id}.',
          ),
          'save response ${q.id}',
        );
      }
      await save(() => repository.finish(attempt.id), 'finish service packet');
      for (final q in attempt.written) {
        await save(
          () => repository.selfAssess(
            attempt.id,
            q.id,
            {},
            improvement: 'Live concrete improvement for ${q.id}.',
          ),
          'self-review ${q.id}',
        );
        expect(
          count(),
          'Service decisions: 0',
          reason:
              'individual notes alone are not complete reviewed participation',
        );
      }
      final reviewed = await save(
        () => repository.review(attempt.id),
        'explicit reviewed participation',
      );
      expect(count(), 'Service decisions: 1');
      final storedJson = jsonEncode(reviewed.toJson());

      await save(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: CmsRehearsalRepository.keyFor(attempt.id),
                value: '{"corrupt":',
                updatedAt: time.now,
              ),
            ),
        'corrupt saved packet',
      );
      expect(count(), 'Service decisions: 0');
      expect(
        find.text(
          '1 saved practice record(s) excluded because they could not be read.',
        ),
        findsOneWidget,
      );

      await save(
        () => db
            .into(db.userSettings)
            .insertOnConflictUpdate(
              UserSetting(
                name: CmsRehearsalRepository.keyFor(attempt.id),
                value: storedJson,
                updatedAt: time.now,
              ),
            ),
        'restore valid packet',
      );
      expect(count(), 'Service decisions: 1');
      expect(
        find.byKey(const ValueKey('cms-rehearsal-count-unreadable')),
        findsNothing,
      );

      time.now = t0.subtract(const Duration(minutes: 1));
      await tester.pump(const Duration(minutes: 1));
      await settle(tester);
      expect(
        count(),
        'Service decisions: 0',
        reason: 'rollback makes the stored submission future-dated until the clock is repaired',
      );
      expect(
        find.text(
          '1 saved practice record(s) excluded because they could not be read.',
        ),
        findsOneWidget,
      );
      time.now = t0;
      await tester.pump(const Duration(minutes: 1));
      await settle(tester);
      expect(count(), 'Service decisions: 1');

      await save(
        () =>
            (db.delete(db.userSettings)..where(
                  (row) => row.name.equals(
                    CmsRehearsalRepository.keyFor(attempt.id),
                  ),
                ))
                .go(),
        'delete reviewed packet',
      );
      expect(count(), 'Service decisions: 0');
      expect(
        find.byKey(const ValueKey('cms-rehearsal-count-unreadable')),
        findsNothing,
      );
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testApp(
    'each CMS written prompt owns its prose and finished self-review semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final attempt = await tester.runAsync(() async {
          final draft = await repository
              .start(CmsRehearsalSection.service)
              .timeout(const Duration(seconds: 5));
          for (final question in draft.written) {
            await repository
                .answerWritten(
                  draft.id,
                  question.id,
                  'Exact semantic response for ${question.id}; different per prompt.',
                )
                .timeout(const Duration(seconds: 5));
          }
          return repository.read(draft.id).timeout(const Duration(seconds: 5));
        });
        final saved = attempt!;
        expect(saved.written, hasLength(3));
        await show(tester);
        // Narrow width exercises real wrapping. This test inspects ownership;
        // the browser gate separately checks a 320 x 780 clipped viewport.
        tester.view.physicalSize = const Size(320, 6000);
        await tester.pumpAndSettle();

        List<SemanticsNode> tree(SemanticsNode root) {
          final nodes = <SemanticsNode>[root];
          root.visitChildren((child) {
            nodes.addAll(tree(child));
            return true;
          });
          return nodes;
        }

        void checkQuestionOwners({required bool finished}) {
          final ownedIds = <Set<int>>[];
          for (final (index, question) in saved.written.indexed) {
            final label = 'Written ${index + 1} ${question.prompt}';
            final boundary = find.bySemanticsLabel(
              RegExp(
                '^${RegExp.escape(label)}'
                r'$',
              ),
            );
            expect(
              boundary,
              findsOneWidget,
              reason: 'one exact context boundary per original prompt',
            );
            final owner = tester.getSemantics(boundary);
            expect(owner.getSemanticsData().label, label);
            final nodes = tree(owner);
            ownedIds.add(nodes.map((node) => node.id).toSet());
            final fields = nodes
                .where(
                  (node) => node.getSemanticsData().flagsCollection.isTextField,
                )
                .toList();
            if (finished) {
              expect(
                fields,
                hasLength(1),
                reason: 'one remaining editable improvement field per prompt',
              );
              final savedProse = nodes
                  .where(
                    (node) =>
                        node.getSemanticsData().label ==
                        'Your explanation\nExact semantic response for '
                            '${question.id}; different per prompt.',
                  )
                  .toList();
              expect(
                savedProse,
                hasLength(1),
                reason: 'one separately owned exact static saved prose leaf',
              );
              expect(
                savedProse.single
                    .getSemanticsData()
                    .flagsCollection
                    .isTextField,
                isFalse,
              );
              expect(tree(savedProse.single), hasLength(1));
              final proseKey = 'cms-rehearsal-written-${question.id}';
              expect(
                textFor(tester, proseKey),
                'Exact semantic response for ${question.id}; different per prompt.',
              );
              expect(
                tester
                    .widget<TextFormField>(find.byKey(ValueKey(proseKey)))
                    .enabled,
                isFalse,
              );
            } else {
              expect(
                fields,
                hasLength(1),
                reason: 'the original draft prose input is unchanged',
              );
              final prose = fields
                  .where(
                    (node) =>
                        node.getSemanticsData().label == 'Your explanation',
                  )
                  .toList();
              expect(prose, hasLength(1));
              expect(
                prose.single.getSemanticsData().value,
                'Exact semantic response for ${question.id}; different per prompt.',
              );
            }
            if (finished) {
              expect(
                fields.where(
                  (node) =>
                      node.getSemanticsData().label ==
                      'What would improve this answer?',
                ),
                hasLength(1),
              );
              for (final criterion in question.criteria) {
                expect(
                  nodes.where(
                    (node) =>
                        node.getSemanticsData().label == criterion.text &&
                        node.getSemanticsData().flagsCollection.isChecked !=
                            CheckedState.none,
                  ),
                  hasLength(1),
                  reason: 'each criterion belongs to its original prompt',
                );
              }
              expect(
                nodes.where(
                  (node) =>
                      node.getSemanticsData().label == 'Save self-review' &&
                      node.getSemanticsData().flagsCollection.isButton,
                ),
                hasLength(1),
              );
            }
          }
          for (var i = 0; i < ownedIds.length; i++) {
            for (var j = i + 1; j < ownedIds.length; j++) {
              expect(
                ownedIds[i].intersection(ownedIds[j]),
                isEmpty,
                reason: "one question must not own another question's controls",
              );
            }
          }
        }

        checkQuestionOwners(finished: false);
        await tapKey(tester, 'cms-rehearsal-finish');
        checkQuestionOwners(finished: true);
        final stored = await tester.runAsync(
          () => repository.read(saved.id).timeout(const Duration(seconds: 5)),
        );
        expect(stored!.prose, saved.prose);
        expect(stored.deadline, saved.deadline);
        expect(stored.startedAt, saved.startedAt);
        expect(stored.isFinished, isTrue);
        expect(stored.isReviewed, isFalse);
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp('two CMS wines own five separate evidence prompt fields each', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      final attempt = await tester.runAsync(() async {
        final draft = await repository
            .start(CmsRehearsalSection.tasting)
            .timeout(const Duration(seconds: 5));
        for (final wine in draft.wines) {
          for (final prompt in draft.wineEvidencePrompts) {
            await repository
                .writeWineEvidence(
                  draft.id,
                  wine.ordinal,
                  prompt.id,
                  'Distinct stored wine ${wine.ordinal + 1} ${prompt.id} evidence marker.',
                )
                .timeout(const Duration(seconds: 5));
          }
        }
        return repository.read(draft.id).timeout(const Duration(seconds: 5));
      });
      final saved = attempt!;
      expect(saved.wines, hasLength(2));
      expect(saved.wineEvidencePrompts, hasLength(5));
      expect(saved.physicalAcknowledged, isFalse);
      await show(tester);
      tester.view.physicalSize = const Size(320, 6000);
      await tester.pumpAndSettle();

      List<SemanticsNode> tree(SemanticsNode root) {
        final nodes = <SemanticsNode>[root];
        root.visitChildren((child) {
          nodes.addAll(tree(child));
          return true;
        });
        return nodes;
      }

      final wineIds = <Set<int>>[];
      final allPromptIds = <Set<int>>[];
      final actualWineLabels = <String>{};
      for (final wine in saved.wines) {
        final wineLabel = 'Wine ${wine.ordinal + 1} of 2';
        final boundary = find.bySemanticsLabel(
          RegExp(
            '^${RegExp.escape(wineLabel)}'
            r'$',
          ),
        );
        expect(
          boundary,
          findsOneWidget,
          reason: 'one exact wine context owns five supplied prompt fields',
        );
        final owner = tester.getSemantics(boundary);
        actualWineLabels.add(owner.getSemanticsData().label);
        final nodes = tree(owner);
        wineIds.add(nodes.map((node) => node.id).toSet());
        final fields = nodes
            .where(
              (node) => node.getSemanticsData().flagsCollection.isTextField,
            )
            .toList();
        expect(fields, hasLength(5));
        for (final prompt in saved.wineEvidencePrompts) {
          final promptOwners = nodes
              .where((node) => node.getSemanticsData().label == prompt.prompt)
              .toList();
          expect(
            promptOwners,
            hasLength(1),
            reason: 'prompt identity must belong to this wine only',
          );
          final promptNodes = tree(promptOwners.single);
          allPromptIds.add(promptNodes.map((node) => node.id).toSet());
          final evidence = promptNodes
              .where(
                (node) => node.getSemanticsData().flagsCollection.isTextField,
              )
              .toList();
          expect(evidence, hasLength(1));
          expect(
            evidence.single.getSemanticsData().label,
            'Your wine evidence',
          );
          expect(
            evidence.single.getSemanticsData().value,
            'Distinct stored wine ${wine.ordinal + 1} ${prompt.id} evidence marker.',
          );
        }
      }
      expect(actualWineLabels, {'Wine 1 of 2', 'Wine 2 of 2'});
      expect(wineIds[0].intersection(wineIds[1]), isEmpty);
      expect(allPromptIds, hasLength(10));
      for (var i = 0; i < allPromptIds.length; i++) {
        for (var j = i + 1; j < allPromptIds.length; j++) {
          expect(
            allPromptIds[i].intersection(allPromptIds[j]),
            isEmpty,
            reason: 'one prompt cannot own another prompt or wine field',
          );
        }
      }
      final stored = await tester.runAsync(
        () => repository.read(saved.id).timeout(const Duration(seconds: 5)),
      );
      expect(stored!.deadline, saved.deadline);
      expect(stored.physicalAcknowledged, isFalse);
      expect(stored.isFinished, isFalse);
      expect(stored.isReviewed, isFalse);
      for (final wine in saved.wines) {
        expect(stored.wines[wine.ordinal].evidence, wine.evidence);
      }
      await expectNoStudyCredit(tester);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  List<SemanticsNode> savedValueTree(SemanticsNode root) {
    final nodes = <SemanticsNode>[root];
    root.visitChildren((child) {
      nodes.addAll(savedValueTree(child));
      return true;
    });
    return nodes;
  }

  Set<int> expectOwnedSavedValue(
    WidgetTester tester, {
    required String ownerLabel,
    required String purpose,
    required String value,
    required String fieldKey,
  }) {
    final boundary = find.bySemanticsLabel(
      RegExp(
        '^${RegExp.escape(ownerLabel)}'
        r'$',
      ),
    );
    expect(boundary, findsOneWidget);
    final owner = tester.getSemantics(boundary);
    expect(
      owner.getSemanticsData().label,
      ownerLabel,
      reason: 'saved prose must not be merged into its prompt identity',
    );
    final nodes = savedValueTree(owner);
    final leaves = nodes
        .where((node) => node.getSemanticsData().label == '$purpose\n$value')
        .toList();
    expect(
      leaves,
      hasLength(1),
      reason:
          'exact evidence must remain accessible without an editing connection',
    );
    expect(
      leaves.single.getSemanticsData().flagsCollection.isTextField,
      isFalse,
    );
    expect(
      savedValueTree(leaves.single),
      hasLength(1),
      reason: 'the original disabled child must not duplicate saved semantics',
    );
    final field = find.descendant(
      of: boundary,
      matching: find.byKey(ValueKey(fieldKey)),
    );
    expect(field, findsOneWidget);
    expect(tester.widget<TextFormField>(field).enabled, isFalse);
    expect(
      textFor(tester, fieldKey),
      value,
      reason: 'the visual controller/key remains the exact saved response',
    );
    return nodes.map((node) => node.id).toSet();
  }

  void expectDisjointSavedOwners(List<Set<int>> owners) {
    for (var i = 0; i < owners.length; i++) {
      for (var j = i + 1; j < owners.length; j++) {
        expect(
          owners[i].intersection(owners[j]),
          isEmpty,
          reason: 'saved values cannot belong to another prompt or wine',
        );
      }
    }
  }

  testApp(
    'finished service keeps three exact static saved prose leaves and editable review fields',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final saved = (await tester.runAsync(
          () => servicePacket('Finished static'),
        ))!;
        expect(saved.isFinished, isTrue);
        expect(saved.isReviewed, isFalse);
        await show(tester, savedId: saved.id);
        tester.view.physicalSize = const Size(320, 6000);
        await tester.pumpAndSettle();
        final owners = <Set<int>>[];
        for (final (index, q) in saved.written.indexed) {
          final label = 'Written ${index + 1} ${q.prompt}';
          owners.add(
            expectOwnedSavedValue(
              tester,
              ownerLabel: label,
              purpose: 'Your explanation',
              value: saved.prose[q.id]!,
              fieldKey: 'cms-rehearsal-written-${q.id}',
            ),
          );
          final boundary = find.bySemanticsLabel(
            RegExp(
              '^${RegExp.escape(label)}'
              r'$',
            ),
          );
          final fields = savedValueTree(tester.getSemantics(boundary))
              .where(
                (node) => node.getSemanticsData().flagsCollection.isTextField,
              )
              .toList();
          expect(fields, hasLength(1));
          expect(
            fields.single.getSemanticsData().label,
            'What would improve this answer?',
          );
          final improvement = find.byKey(
            ValueKey('cms-rehearsal-improvement-${q.id}'),
          );
          expect(tester.widget<TextFormField>(improvement).enabled, isTrue);
        }
        expectDisjointSavedOwners(owners);
        final stored = (await tester.runAsync(
          () => repository.read(saved.id),
        ))!;
        expect(stored.prose, saved.prose);
        expect(stored.startedAt, saved.startedAt);
        expect(stored.deadline, saved.deadline);
        expect(stored.isReviewed, isFalse);
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp(
    'reviewed service history exposes exact owned prose and notes without stealing a newer draft',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final saved = (await tester.runAsync(
          () => servicePacket('Reviewed static', reviewed: true),
        ))!;
        final newer = (await tester.runAsync(() async {
          final draft = await repository.start(CmsRehearsalSection.service);
          return repository.answerWritten(
            draft.id,
            draft.written.first.id,
            'Distinct newer current response that must survive saved-history viewing.',
          );
        }))!;
        await show(tester, savedId: saved.id, readOnly: true);
        tester.view.physicalSize = const Size(320, 6000);
        await tester.pumpAndSettle();
        final owners = <Set<int>>[];
        for (final (index, q) in saved.written.indexed) {
          final label = 'Written ${index + 1} ${q.prompt}';
          owners.add(
            expectOwnedSavedValue(
              tester,
              ownerLabel: label,
              purpose: 'Your explanation',
              value: saved.prose[q.id]!,
              fieldKey: 'cms-rehearsal-written-${q.id}',
            ),
          );
          expectOwnedSavedValue(
            tester,
            ownerLabel: label,
            purpose: 'What would improve this answer?',
            value: saved.reviewNotes[q.id]!,
            fieldKey: 'cms-rehearsal-improvement-${q.id}',
          );
          final boundary = find.bySemanticsLabel(
            RegExp(
              '^${RegExp.escape(label)}'
              r'$',
            ),
          );
          expect(
            savedValueTree(tester.getSemantics(boundary)).where(
              (node) => node.getSemanticsData().flagsCollection.isTextField,
            ),
            isEmpty,
            reason: 'immutable history exposes no editable semantic input',
          );
        }
        expectDisjointSavedOwners(owners);
        final current = (await tester.runAsync(repository.current))!;
        expect(current.id, newer.id);
        expect(current.startedAt, newer.startedAt);
        expect(current.deadline, newer.deadline);
        expect(current.prose, newer.prose);
        final reread = (await tester.runAsync(
          () => repository.read(saved.id),
        ))!;
        expect(reread.toJson(), saved.toJson());
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp(
    'incomplete finished history retains legitimate empty responses and empty notes',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final saved = (await tester.runAsync(() async {
          final draft = await repository.start(CmsRehearsalSection.service);
          await repository.answerWritten(
            draft.id,
            draft.written.first.id,
            'Only this original response was saved.',
          );
          return repository.finish(draft.id);
        }))!;
        expect(saved.prose, hasLength(1));
        expect(saved.isComplete, isFalse);
        await show(tester, savedId: saved.id, readOnly: true);
        tester.view.physicalSize = const Size(320, 6000);
        await tester.pumpAndSettle();
        for (final (index, q) in saved.written.indexed) {
          final label = 'Written ${index + 1} ${q.prompt}';
          expectOwnedSavedValue(
            tester,
            ownerLabel: label,
            purpose: 'Your explanation',
            value: saved.prose[q.id] ?? '',
            fieldKey: 'cms-rehearsal-written-${q.id}',
          );
          expectOwnedSavedValue(
            tester,
            ownerLabel: label,
            purpose: 'What would improve this answer?',
            value: '',
            fieldKey: 'cms-rehearsal-improvement-${q.id}',
          );
        }
        final stored = (await tester.runAsync(
          () => repository.read(saved.id),
        ))!;
        expect(
          stored.toJson(),
          saved.toJson(),
          reason:
              'rendering empties must not create/fill missing saved responses',
        );
        expect(stored.isReviewed, isFalse);
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp(
    'saved two-wine history exposes all ten separate exact evidence leaves without physical credit',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final saved = (await tester.runAsync(() async {
          final draft = await repository.start(CmsRehearsalSection.tasting);
          for (final wine in draft.wines) {
            for (final prompt in draft.wineEvidencePrompts) {
              await repository.writeWineEvidence(
                draft.id,
                wine.ordinal,
                prompt.id,
                'Saved synthetic evidence for wine ${wine.ordinal + 1} / ${prompt.id}; no sensory claim.',
              );
            }
          }
          return repository.finish(draft.id);
        }))!;
        final newer = (await tester.runAsync(
          () => repository.start(CmsRehearsalSection.service),
        ))!;
        await show(tester, savedId: saved.id, readOnly: true);
        tester.view.physicalSize = const Size(320, 10000);
        await tester.pumpAndSettle();
        final wineOwners = <Set<int>>[];
        final promptOwners = <Set<int>>[];
        for (final wine in saved.wines) {
          final label = 'Wine ${wine.ordinal + 1} of 2';
          final boundary = find.bySemanticsLabel(
            RegExp(
              '^${RegExp.escape(label)}'
              r'$',
            ),
          );
          expect(boundary, findsOneWidget);
          final owner = tester.getSemantics(boundary);
          expect(owner.getSemanticsData().label, label);
          wineOwners.add(savedValueTree(owner).map((node) => node.id).toSet());
          for (final prompt in saved.wineEvidencePrompts) {
            final nodes = savedValueTree(owner);
            final promptRoots = nodes
                .where((node) => node.getSemanticsData().label == prompt.prompt)
                .toList();
            expect(promptRoots, hasLength(1));
            final promptNodes = savedValueTree(promptRoots.single);
            promptOwners.add(promptNodes.map((node) => node.id).toSet());
            final expected = wine.evidence[prompt.id]!;
            final leaves = promptNodes
                .where(
                  (node) =>
                      node.getSemanticsData().label ==
                      'Your wine evidence\n$expected',
                )
                .toList();
            expect(leaves, hasLength(1));
            expect(savedValueTree(leaves.single), hasLength(1));
            expect(
              promptNodes.where(
                (node) => node.getSemanticsData().flagsCollection.isTextField,
              ),
              isEmpty,
            );
            final fieldKey =
                'cms-rehearsal-wine-evidence-${wine.ordinal}-${prompt.id}';
            expect(textFor(tester, fieldKey), expected);
            expect(
              tester
                  .widget<TextFormField>(find.byKey(ValueKey(fieldKey)))
                  .enabled,
              isFalse,
            );
          }
        }
        expect(wineOwners, hasLength(2));
        expect(promptOwners, hasLength(10));
        expectDisjointSavedOwners(wineOwners);
        expectDisjointSavedOwners(promptOwners);
        final current = (await tester.runAsync(repository.current))!;
        expect(current.id, newer.id);
        expect(current.deadline, newer.deadline);
        final stored = (await tester.runAsync(
          () => repository.read(saved.id),
        ))!;
        expect(stored.toJson(), saved.toJson());
        expect(stored.physicalAcknowledged, isFalse);
        expect(stored.isReviewed, isFalse);
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testApp(
    'review becoming immutable exposes durable notes rather than unsaved local text',
    (tester) async {
      final semantics = tester.ensureSemantics();
      const savedProse =
          'Évidence enregistrée — Château.\nSecond exact line; retain final spaces.  ';
      const savedNote =
          'Améliorer avec un exemple précis.\nSaved second line; retain final spaces.  ';
      const unsavedNote =
          'Unsaved local edit that must never be presented as the saved reviewed note.';
      try {
        final saved = (await tester.runAsync(() async {
          final draft = await repository.start(CmsRehearsalSection.service);
          for (final q in draft.written) {
            await repository.answerWritten(
              draft.id,
              q.id,
              q.id == draft.written.first.id
                  ? savedProse
                  : 'Saved response for ${q.id}.',
            );
          }
          var ended = await repository.finish(draft.id);
          for (final q in draft.written) {
            ended = await repository.selfAssess(
              draft.id,
              q.id,
              {},
              improvement: q.id == draft.written.first.id
                  ? savedNote
                  : 'Saved improvement for ${q.id}.',
            );
          }
          return ended;
        }))!;
        final first = saved.written.first;
        expect(saved.isReviewed, isFalse);
        expect(saved.reviewNotes[first.id], savedNote);
        await show(tester, savedId: saved.id);
        tester.view.physicalSize = const Size(320, 6000);
        await tester.pumpAndSettle();
        await enterKey(
          tester,
          'cms-rehearsal-improvement-${first.id}',
          unsavedNote,
        );
        expect(
          textFor(tester, 'cms-rehearsal-improvement-${first.id}'),
          unsavedNote,
        );
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(ValueKey('cms-rehearsal-improvement-${first.id}')),
              )
              .enabled,
          isTrue,
        );
        await tapKey(tester, 'cms-rehearsal-reviewed');
        final stored = (await tester.runAsync(
          () => repository.read(saved.id),
        ))!;
        expect(stored.isReviewed, isTrue);
        expect(stored.prose, saved.prose);
        expect(
          stored.reviewNotes,
          saved.reviewNotes,
          reason: 'review marks existing saved reflection, not the local unsaved edit',
        );
        expect(stored.startedAt, saved.startedAt);
        expect(stored.deadline, saved.deadline);
        expect(
          find.byKey(const ValueKey('cms-rehearsal-reviewed')),
          findsNothing,
        );
        final owners = <Set<int>>[];
        for (final (index, q) in stored.written.indexed) {
          final label = 'Written ${index + 1} ${q.prompt}';
          owners.add(
            expectOwnedSavedValue(
              tester,
              ownerLabel: label,
              purpose: 'Your explanation',
              value: stored.prose[q.id]!,
              fieldKey: 'cms-rehearsal-written-${q.id}',
            ),
          );
          expectOwnedSavedValue(
            tester,
            ownerLabel: label,
            purpose: 'What would improve this answer?',
            value: stored.reviewNotes[q.id]!,
            fieldKey: 'cms-rehearsal-improvement-${q.id}',
          );
          final boundary = find.bySemanticsLabel(
            RegExp(
              '^${RegExp.escape(label)}'
              r'$',
            ),
          );
          final nodes = savedValueTree(tester.getSemantics(boundary));
          expect(
            nodes.where(
              (node) => node.getSemanticsData().flagsCollection.isTextField,
            ),
            isEmpty,
          );
          expect(
            nodes.where(
              (node) => node.getSemanticsData().label.contains(unsavedNote),
            ),
            isEmpty,
          );
        }
        expectDisjointSavedOwners(owners);
        await expectNoStudyCredit(tester);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
