import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart' show noProviderRetry;
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/database/database_providers.dart';
import 'package:sommelier/core/diploma_written/diploma_written.dart';
import 'package:sommelier/core/diploma_written/diploma_written_providers.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

import 'package:sommelier/features/diploma_written/diploma_written_screen.dart';

/// Records genuine UI callbacks, then commits through the real repository.
/// Held variants defer actual repository writes; no build-test dependency.
class _LoggingWrittenRepository extends DiplomaWrittenRepository {
  _LoggingWrittenRepository(
    super.db, {
    required super.bank,
    required super.clock,
  }) : super(random: Random(83));

  final calls = <Map<String, Object?>>[];

  @override
  Future<DiplomaWrittenAttempt> answer(
    String id,
    String questionId,
    String text,
  ) async {
    calls.add({'questionId': questionId, 'text': text});
    debugPrint(
      'USER_SCROLL_ANSWER_RECEIVED ${jsonEncode({'questionId': questionId, 'length': text.length})}',
    );
    final changed = await super.answer(id, questionId, text);
    debugPrint(
      'USER_SCROLL_ANSWER_COMMITTED ${jsonEncode({'questionId': questionId, 'length': changed.prose[questionId]?.length})}',
    );
    return changed;
  }
}

/// Holds a real middle-answer write to expose lazy recreation while storage
/// still has the old snapshot. The released path always calls super.answer.
class _HeldMiddleWrittenRepository extends _LoggingWrittenRepository {
  _HeldMiddleWrittenRepository(
    super.db, {
    required super.bank,
    required super.clock,
    required this.heldQuestionId,
    this.holdSecond = false,
    this.armed = true,
  });
  final String heldQuestionId;
  final bool holdSecond;
  bool armed;
  final entered = Completer<void>();
  final release = Completer<void>();
  // Settle on success or rejection: cleanup must not strand a write.
  final committed = Completer<void>();
  final secondEntered = Completer<void>();
  final secondRelease = Completer<void>();
  final secondCommitted = Completer<void>();
  final errors = <Object>[];
  @override
  Future<DiplomaWrittenAttempt> answer(
    String id,
    String questionId,
    String text,
  ) async {
    final first = armed && questionId == heldQuestionId && !entered.isCompleted;
    final second =
        armed &&
        holdSecond &&
        questionId == heldQuestionId &&
        entered.isCompleted &&
        !secondEntered.isCompleted;
    if (first) {
      entered.complete();
      await release.future;
    }
    if (second) {
      secondEntered.complete();
      await secondRelease.future;
    }
    try {
      return await super.answer(id, questionId, text);
    } catch (error) {
      errors.add(error);
      rethrow;
    } finally {
      if (first && !committed.isCompleted) committed.complete();
      if (second && !secondCommitted.isCompleted) secondCommitted.complete();
    }
  }

  Future<void> releaseAll(WidgetTester tester) async {
    if (!release.isCompleted) release.complete();
    if (!secondRelease.isCompleted) secondRelease.complete();
    if (entered.isCompleted) {
      await tester.runAsync(
        () => committed.future.timeout(const Duration(seconds: 5)),
      );
    }
    if (secondEntered.isCompleted) {
      await tester.runAsync(
        () => secondCommitted.future.timeout(const Duration(seconds: 5)),
      );
    }
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late _LoggingWrittenRepository repository;
  late DiplomaWrittenAttempt original;
  final notifications = <(int, ScrollDirection)>[];
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    notifications.clear();
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', NULL, 1, 'certification', NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    final raw = jsonDecode(
      File('assets/study/diploma_written_practice.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final france = (raw['variants'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (v) =>
              (v['questions'] as List).first['id'] ==
              'd3_candidate_burgundy_lots',
        );
    raw['units'] = [
      for (final unit in raw['units'] as List)
        if (unit['unitId'] == 'D3') france else unit,
    ];
    raw['variants'] = <Object>[];
    repository = _LoggingWrittenRepository(
      db,
      bank: DiplomaWrittenBank.fromJson(jsonEncode(raw)),
      clock: time.clock,
    );
    original = await repository.start('D3');
  });
  tearDown(() => db.close());
  Finder field(String id) => find.byKey(ValueKey('diploma-written-prose-$id'));
  Finder editable(String id) =>
      find.descendant(of: field(id), matching: find.byType(EditableText));
  String controllerText(WidgetTester tester, String id) =>
      tester.widget<EditableText>(editable(id)).controller.text;
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String phase,
  ) async {
    final bound = Stopwatch()..start();
    while (!ready() && bound.elapsed < const Duration(seconds: 5)) {
      await settle(tester);
    }
    expect(ready(), isTrue, reason: phase);
  }

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        retry: noProviderRetry,
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          clockProvider.overrideWithValue(time.clock),
          diplomaWrittenRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            bottomNavigationBar: const SizedBox(
              height: 80,
              child: ColoredBox(color: Colors.black),
            ),
            body: NotificationListener<UserScrollNotification>(
              onNotification: (n) {
                notifications.add((n.depth, n.direction));
                return false;
              },
              child: const DiplomaWrittenScreen(unitId: 'D3'),
            ),
          ),
        ),
      ),
    );
    await until(
      tester,
      () => find
          .byKey(const ValueKey('diploma-written-timer'))
          .evaluate()
          .isNotEmpty,
      'actual saved D3 draft loaded',
    );
  }

  Future<void> reveal(WidgetTester tester, String id) async {
    final outer = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    outer.jumpTo(0);
    await tester.pump();
    for (var step = 0; field(id).evaluate().isEmpty && step < 80; step++) {
      outer.jumpTo(
        (outer.pixels + 160).clamp(
          outer.minScrollExtent,
          outer.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    expect(field(id), findsOneWidget);
    await tester.ensureVisible(editable(id));
    await settle(tester);
  }

  Future<void> saved(WidgetTester tester, String id, String value) async {
    await until(
      tester,
      () => repository.calls.any(
        (entry) => entry['questionId'] == id && entry['text'] == value,
      ),
      'real answer callback $id',
    );
    final bound = Stopwatch()..start();
    DiplomaWrittenAttempt? snapshot;
    while (bound.elapsed < const Duration(seconds: 5)) {
      await settle(tester);
      snapshot = await tester.runAsync(() => repository.read(original.id));
      if (snapshot?.prose[id] == value) break;
    }
    expect(snapshot?.prose[id], value, reason: 'real SQLite prose $id');
  }

  Future<void> scrollAwayAndBack(WidgetTester tester, String id) async {
    // Trusted test gestures target the outer 16px gutter, never editable text.
    for (var n = 0; n < 5; n++) {
      await tester.dragFrom(const Offset(8, 390), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    expect(
      field(id),
      findsNothing,
      reason: 'long middle field genuinely left lazy viewport/cache',
    );
    var found = false;
    for (var n = 0; n < 12; n++) {
      await tester.dragFrom(const Offset(8, 390), const Offset(0, 450));
      await tester.pumpAndSettle();
      if (editable(id).evaluate().isNotEmpty) {
        final r = tester.getRect(editable(id));
        if (r.bottom > 56 && r.top < 700) {
          found = true;
          break;
        }
      }
    }
    expect(
      found,
      isTrue,
      reason: 'same middle field returned through real gutter gestures',
    );
    await tester.ensureVisible(editable(id));
    await settle(tester);
  }

  testApp(
    'outer user drag ends focus before disposal, preserves all prose and accepts intentional clear',
    (tester) async {
      await mount(tester);
      final expected = {
        for (final q in original.questions)
          q.id:
              'Scroll regression ${q.id}: compare original site, cellar, quality and route evidence; this deliberately distinct draft remains ungraded local practice.',
      };
      for (final q in original.questions) {
        await reveal(tester, q.id);
        await tester.enterText(field(q.id), expected[q.id]!);
        await saved(tester, q.id, expected[q.id]!);
      }
      final id = original.questions[1].id;
      await reveal(tester, id);
      await tester.tap(editable(id));
      await settle(tester);
      final focus = tester.widget<EditableText>(editable(id)).focusNode;
      expect(focus.hasFocus, isTrue);
      await tester.dragFrom(const Offset(8, 390), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(
        focus.hasFocus,
        isFalse,
        reason: 'depth0 genuine scroll ends editing before lazy recreation',
      );
      expect(
        notifications.any((n) => n.$1 == 0 && n.$2 != ScrollDirection.idle),
        isTrue,
      );
      await reveal(tester, id);
      await scrollAwayAndBack(tester, id);
      expect(controllerText(tester, id), expected[id]);
      expect(
        (await tester.runAsync(() => repository.read(original.id)))!.prose,
        expected,
      );
      await tester.enterText(field(id), '');
      await saved(tester, id, '');
      await scrollAwayAndBack(tester, id);
      expect(controllerText(tester, id), isEmpty);
      final cleared = (await tester.runAsync(
        () => repository.read(original.id),
      ))!;
      expect(cleared.prose[id], isEmpty);
      for (final q in original.questions.where((q) => q.id != id)) {
        expect(cleared.prose[q.id], expected[q.id]);
      }
    },
  );
  testApp(
    'inner multiline user scroll and programmatic caret reveal preserve writing focus',
    (tester) async {
      await mount(tester);
      final id = original.questions[1].id;
      await reveal(tester, id);
      final prose = List.generate(
        100,
        (i) => 'Line $i: independent prose observation.',
      ).join('\n');
      await tester.enterText(field(id), prose);
      await saved(tester, id, prose);
      await tester.ensureVisible(editable(id));
      await settle(tester);
      final focus = tester.widget<EditableText>(editable(id)).focusNode;
      expect(focus.hasFocus, isTrue);
      notifications.clear();
      final r = tester.getRect(editable(id));
      await tester.dragFrom(
        Offset(r.center.dx, r.bottom - 24),
        const Offset(0, 100),
      );
      await tester.pumpAndSettle();
      expect(
        notifications.any((n) => n.$1 > 0 && n.$2 != ScrollDirection.idle),
        isTrue,
        reason: 'actual inner editable scroll delivered',
      );
      expect(
        focus.hasFocus,
        isTrue,
        reason: 'nested multiline scrolling must not end editing',
      );
      await tester.ensureVisible(editable(id));
      await settle(tester);
      expect(
        focus.hasFocus,
        isTrue,
        reason: 'programmatic reveal must not end editing',
      );
      expect(controllerText(tester, id), prose);
      expect(
        (await tester.runAsync(() => repository.read(original.id)))!.prose[id],
        prose,
      );
      // Actual outer wheel follows the pinned pointerScroll notification path.
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(8, 390),
          scrollDelta: Offset(0, 120),
        ),
      );
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isFalse, reason: 'outer wheel ends writing focus');
      expect(
        (await tester.runAsync(() => repository.read(original.id)))!.prose[id],
        prose,
      );
    },
  );
  testApp(
    'pending middle prose survives user-scroll recreation before real save releases',
    (tester) async {
      final id = original.questions[1].id;
      final held = _HeldMiddleWrittenRepository(
        db,
        bank: repository.bank,
        clock: time.clock,
        heldQuestionId: id,
      );
      repository = held;
      const latest =
          'Latest admitted middle response: this draft must remain visible through genuine scrolling while its real storage write is still pending.';
      try {
        await mount(tester);
        await reveal(tester, id);
        await tester.enterText(field(id), latest);
        await until(
          tester,
          () => held.entered.isCompleted,
          'middle real answer admitted and held',
        );
        expect(held.release.isCompleted, isFalse);
        expect(controllerText(tester, id), latest);
        await scrollAwayAndBack(tester, id);
        expect(
          controllerText(tester, id),
          latest,
          reason: 'recreated field must show latest admitted prose before storage completion',
        );
        held.release.complete();
        await until(
          tester,
          () => held.committed.isCompleted,
          'held real answer committed',
        );
        await saved(tester, id, latest);
        expect(
          controllerText(tester, id),
          latest,
          reason:
              'real save completion must not leave a stale visible controller',
        );
        await tester.enterText(field(id), '');
        await saved(tester, id, '');
        await scrollAwayAndBack(tester, id);
        expect(controllerText(tester, id), isEmpty);
        expect(
          (await tester.runAsync(() => repository.read(original.id)))!
              .prose[id],
          isEmpty,
        );
      } finally {
        if (!held.release.isCompleted) held.release.complete();
        if (held.entered.isCompleted) {
          await tester.runAsync(
            () => held.committed.future.timeout(const Duration(seconds: 5)),
          );
        }
      }
    },
  );
  for (final newer in [
    'A newer admitted response must survive an older real ACK.',
    '',
  ]) {
    testApp(
      'newer ${newer.isEmpty ? 'intentional clear' : 'prose'} survives older ACK and lazy recreation',
      (tester) async {
        final id = original.questions[1].id;
        final held = _HeldMiddleWrittenRepository(
          db,
          bank: repository.bank,
          clock: time.clock,
          heldQuestionId: id,
          holdSecond: true,
        );
        repository = held;
        const first =
            'The older real write is intentionally held while a newer draft is admitted.';
        try {
          await mount(tester);
          await reveal(tester, id);
          await tester.enterText(field(id), first);
          await until(
            tester,
            () => held.entered.isCompleted,
            'first answer held',
          );
          await tester.enterText(field(id), newer);
          await scrollAwayAndBack(tester, id);
          expect(
            controllerText(tester, id),
            newer,
            reason: 'latest draft before first ACK',
          );
          held.release.complete();
          await until(
            tester,
            () => held.secondEntered.isCompleted,
            'newer real answer held',
          );
          expect(held.secondRelease.isCompleted, isFalse);
          expect(
            (await tester.runAsync(() => repository.read(original.id)))!
                .prose[id],
            first,
            reason: 'older ACK actually committed to SQLite',
          );
          await scrollAwayAndBack(tester, id);
          expect(
            controllerText(tester, id),
            newer,
            reason: 'older ACK must not hydrate over latest draft',
          );
          held.secondRelease.complete();
          await until(
            tester,
            () => held.secondCommitted.isCompleted,
            'newer answer settled',
          );
          await saved(tester, id, newer);
          await scrollAwayAndBack(tester, id);
          expect(controllerText(tester, id), newer);
          expect(
            (await tester.runAsync(() => repository.read(original.id)))!
                .prose[id],
            newer,
          );
          expect(held.errors, isEmpty);
        } finally {
          await held.releaseAll(tester);
        }
      },
    );
  }
  testApp(
    'held answer rejected at deadline restores only durable read-only prose',
    (tester) async {
      final id = original.questions[1].id;
      final held = _HeldMiddleWrittenRepository(
        db,
        bank: repository.bank,
        clock: time.clock,
        heldQuestionId: id,
        armed: false,
      );
      repository = held;
      const durable =
          'This admitted response was genuinely saved before the writing deadline.';
      const rejected =
          'This later response is admitted in the UI but its held repository call crosses the deadline.';
      try {
        await mount(tester);
        await reveal(tester, id);
        await tester.enterText(field(id), durable);
        await saved(tester, id, durable);
        held.armed = true;
        await tester.enterText(field(id), rejected);
        await until(
          tester,
          () => held.entered.isCompleted,
          'late real answer held',
        );
        await scrollAwayAndBack(tester, id);
        expect(
          controllerText(tester, id),
          rejected,
          reason: 'still running admitted draft',
        );
        time.advance(const Duration(hours: 2));
        await tester.pump(const Duration(seconds: 1));
        held.release.complete();
        await until(
          tester,
          () => held.committed.isCompleted,
          'real answer expired and rejected',
        );
        await until(
          tester,
          () =>
              editable(id).evaluate().isNotEmpty &&
              tester.widget<EditableText>(editable(id)).readOnly,
          'tick reads committed expiry and remounts finished field',
        );
        await reveal(tester, id);
        expect(held.errors, hasLength(1));
        expect(held.errors.single, isA<StateError>());
        expect(
          held.errors.single.toString(),
          contains('writing time has ended'),
        );
        final expired = (await tester.runAsync(
          () => repository.read(original.id),
        ))!;
        expect(expired.isFinished, isTrue);
        expect(expired.finishReason, 'expired');
        expect(expired.prose[id], durable);
        expect(expired.reviews, isEmpty);
        expect(expired.isReviewed, isFalse);
        expect(
          controllerText(tester, id),
          durable,
          reason: 'unaccepted late draft must not appear durable',
        );
        expect(tester.widget<EditableText>(editable(id)).readOnly, isTrue);
        // The saved-failure banner is a lazy header: genuinely reveal it.
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await settle(tester);
        expect(
          find.text(
            'Your latest response could not be saved. Reload the saved draft before continuing.',
          ),
          findsOneWidget,
        );
        expect(find.text('Reload saved draft'), findsOneWidget);
      } finally {
        await held.releaseAll(tester);
      }
    },
  );
}
