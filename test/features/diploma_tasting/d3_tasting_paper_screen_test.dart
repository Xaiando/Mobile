import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/diploma_tasting/d3_tasting_paper.dart';
import 'package:sommelier/core/diploma_tasting/d3_tasting_paper_providers.dart';
import 'package:sommelier/core/diploma_tasting/diploma_tasting_flight.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/time/time_providers.dart';
import 'package:sommelier/features/diploma_tasting/d3_tasting_paper_screen.dart';

import '../../support/app_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

DiplomaTastingBank _bank() => DiplomaTastingBank.fromJson(
  File('assets/study/diploma_tasting_flights.json').readAsStringSync(),
);

class _HeldAnswerRepository extends D3TastingPaperRepository {
  _HeldAnswerRepository(super.db, TestClock time)
    : super(bank: _bank(), clock: time.clock, random: Random(31));
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<D3TastingPaper> answer(
    String id,
    int index,
    String prompt,
    String text,
  ) async {
    if (prompt == 'description' && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return super.answer(id, index, prompt, text);
  }
}

class _FailAnswerRepository extends D3TastingPaperRepository {
  _FailAnswerRepository(super.db, TestClock time)
    : super(bank: _bank(), clock: time.clock, random: Random(32));
  bool failed = false;
  @override
  Future<D3TastingPaper> answer(
    String id,
    int index,
    String prompt,
    String text,
  ) async {
    if (!failed) {
      failed = true;
      throw StateError('Simulated actual save failure');
    }
    return super.answer(id, index, prompt, text);
  }
}

class _FailCurrentTwiceRepository extends D3TastingPaperRepository {
  _FailCurrentTwiceRepository(super.db, TestClock time)
    : super(bank: _bank(), clock: time.clock, random: Random(33));
  int failures = 2;
  @override
  Future<D3TastingPaper?> current() async {
    if (failures > 0) {
      failures--;
      throw StateError('Simulated pointer read failure');
    }
    return super.current();
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late D3TastingPaperRepository repository;
  setUp(() async {
    db = openTestDatabase();
    time = TestClock(t0);
    await seedCurriculum(db);
    await db.writeCurriculum(
      () => runSql(db, [
        "INSERT INTO tasting_grids VALUES ('tg_structured', 'WSET_SAT', '1.0', 'Structured tasting')",
        "INSERT INTO certifications VALUES ('WSET_L4', 'WSET', 4, 'WSET Level 4', 'WSET_L3', 'tg_structured', 1, 'certification', NULL)",
        "INSERT INTO tasting_grid_attributes VALUES ('tg_structured', 'sweetness', 'Taste', 'Sweetness', 1, 'single', 1), ('tg_structured', 'aromas', 'Smell', 'Aromas', 2, 'multi', 0)",
        "INSERT INTO tasting_grid_values VALUES ('tg_structured', 'sweetness', 'dry', 'Dry', 1, NULL), ('tg_structured', 'sweetness', 'sweet', 'Sweet', 2, NULL), ('tg_structured', 'aromas', 'citrus', 'Citrus', 1, NULL)",
      ]),
    );
    await LearnerProfiles(db, clock: time.clock).selectTrack('WSET_L4');
    repository = D3TastingPaperRepository(
      db,
      bank: _bank(),
      clock: time.clock,
      random: Random(30),
    );
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String value) => find.byKey(ValueKey(value));
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          d3TastingPaperRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          clockProvider.overrideWithValue(time.clock),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute<void>(
                    builder: (_) => const D3TastingPaperScreen(),
                  ),
                ),
                child: const Text('Open timed paper'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open timed paper'));
    await settle(tester);
  }

  Future<String> start(WidgetTester tester, {bool mixed = false}) async {
    await tester.tap(
      key(mixed ? 'd3-paper-start-mixed' : 'd3-paper-start-grouped'),
    );
    await settle(tester);
    final paper = await tester.runAsync(() => repository.current());
    return paper!.id;
  }

  testApp(
    'six wine navigation preserves owned controllers and real saved answers',
    (tester) async {
      await show(tester);
      final id = await start(tester);
      for (var index = 0; index < 6; index++) {
        await tester.tap(key('d3-paper-nav-$index'));
        await settle(tester);
        await tester.enterText(
          key('d3-paper-evidence-$index-description'),
          'Actual Wine ${index + 1} observation.',
        );
        await settle(tester);
      }
      await tester.tap(key('d3-paper-nav-0'));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(key('d3-paper-evidence-0-description'))
            .controller!
            .text,
        'Actual Wine 1 observation.',
      );
      final saved = await tester.runAsync(() => repository.read(id));
      expect(
        saved!.wines.map((w) => w.evidence['description']).toList(),
        List.generate(6, (index) => 'Actual Wine ${index + 1} observation.'),
      );
      await tester.tap(key('d3-paper-back'));
      await settle(tester);
      await tester.tap(find.text('Open timed paper'));
      await settle(tester);
      expect(
        tester
            .widget<TextField>(key('d3-paper-evidence-0-description'))
            .controller!
            .text,
        'Actual Wine 1 observation.',
      );
    },
  );

  testApp('Back waits for an actual pending SQL answer before popping', (
    tester,
  ) async {
    final held = _HeldAnswerRepository(db, time);
    addTearDown(() {
      if (!held.release.isCompleted) held.release.complete();
    });
    repository = held;
    await show(tester);
    final id = await start(tester);
    await tester.enterText(
      key('d3-paper-evidence-0-description'),
      'Durable before Back.',
    );
    await tester.runAsync(() => held.entered.future);
    await tester.tap(key('d3-paper-back'));
    await tester.pump();
    expect(find.byType(D3TastingPaperScreen), findsOneWidget);
    held.release.complete();
    await settle(tester);
    expect(find.byType(D3TastingPaperScreen), findsNothing);
    final saved = await tester.runAsync(() => repository.read(id));
    expect(saved!.wines.first.evidence['description'], 'Durable before Back.');
  });

  testApp('failed save blocks Back until explicit durable reload', (
    tester,
  ) async {
    repository = _FailAnswerRepository(db, time);
    await show(tester);
    final id = await start(tester);
    await tester.enterText(
      key('d3-paper-evidence-0-description'),
      'Rejected draft.',
    );
    await settle(tester);
    expect(key('d3-paper-save-error'), findsOneWidget);
    await tester.tap(key('d3-paper-back'));
    await tester.pump();
    expect(find.byType(D3TastingPaperScreen), findsOneWidget);
    await tester.tap(key('d3-paper-reload'));
    await settle(tester);
    expect(
      tester
          .widget<TextField>(key('d3-paper-evidence-0-description'))
          .controller!
          .text,
      isEmpty,
    );
    final saved = await tester.runAsync(() => repository.read(id));
    expect(saved!.wines.first.evidence['description'], isNull);
    await tester.tap(key('d3-paper-back'));
    await settle(tester);
    expect(find.byType(D3TastingPaperScreen), findsNothing);
  });

  testApp(
    'absolute expiry rejects held late text and hydrates read-only durable answers',
    (tester) async {
      final held = _HeldAnswerRepository(db, time);
      addTearDown(() {
        if (!held.release.isCompleted) held.release.complete();
      });
      repository = held;
      await show(tester);
      final id = await start(tester, mixed: true);
      await tester.enterText(
        key('d3-paper-evidence-0-description'),
        'Too late to commit.',
      );
      await tester.runAsync(() => held.entered.future);
      time.advance(const Duration(minutes: 90, seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      held.release.complete();
      await settle(tester);
      final saved = await tester.runAsync(() => repository.read(id));
      expect(saved!.finishReason, 'expired');
      expect(saved.wines.first.evidence['description'], isNull);
      final field = tester.widget<TextField>(
        key('d3-paper-evidence-0-description'),
      );
      expect(field.enabled, isFalse);
      expect(field.controller!.text, isEmpty);
      await tester.tap(key('d3-paper-nav-comparison'));
      await settle(tester);
      expect(
        tester.widget<TextButton>(key('d3-paper-save-review')).onPressed,
        isNull,
      );
      expect(find.textContaining('incomplete paper'), findsOneWidget);
    },
  );

  testApp(
    'incomplete and abandoned papers retain history without self-review participation',
    (tester) async {
      await show(tester);
      final id = await start(tester);
      await tester.tap(key('d3-paper-abandon'));
      await settle(tester);
      final saved = await tester.runAsync(() => repository.read(id));
      expect(saved!.isAbandoned, isTrue);
      expect(saved.isReviewed, isFalse);
      expect(
        tester.widget<TextButton>(key('d3-paper-save-review')).onPressed,
        isNull,
      );
      expect(find.textContaining('no participation credit'), findsOneWidget);
    },
  );

  testApp(
    'inner prose scroll and caret preserve focus while outer user scroll unfocuses',
    (tester) async {
      await show(tester);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pump();
      await start(tester);
      final field = key('d3-paper-evidence-0-description');
      await tester.ensureVisible(field);
      await tester.enterText(
        field,
        List.generate(80, (index) => 'Observed line $index.').join('\n'),
      );
      await settle(tester);
      await tester.tap(field);
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus!;
      expect(focused.hasFocus, isTrue);
      await tester.drag(field, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focused));
      final controller = tester.widget<TextField>(field).controller!;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focused));
      final outer = tester.state<ScrollableState>(
        find
            .descendant(
              of: key('d3-paper-outer-scroll'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(outer.position.maxScrollExtent, greaterThan(0));
      await tester.dragFrom(const Offset(8, 350), const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(focused.hasFocus, isFalse);
    },
  );

  testApp(
    'completed six actual wines require a separate saved post-paper review',
    (tester) async {
      final ready = await repository.start(D3TastingPaperKind.mixed);
      for (var index = 0; index < 6; index++) {
        await repository.markTasted(ready.id, index, true);
        await repository.observation(ready.id, index, 'sweetness', {'dry'});
        for (final prompt in ready.wines[index].prompts) {
          await repository.answer(
            ready.id,
            index,
            prompt.id,
            'Actual wine $index ${prompt.id} evidence.',
          );
        }
      }
      await repository.comparison(
        ready.id,
        0,
        'Six actual wines compared with cautious alternatives.',
      );
      await show(tester);
      await tester.tap(key('d3-paper-end'));
      await settle(tester);
      var saved = await tester.runAsync(() => repository.read(ready.id));
      expect(saved!.readyToReview, isTrue);
      expect(saved.isReviewed, isFalse);
      await tester.ensureVisible(key('d3-paper-review'));
      await tester.enterText(
        key('d3-paper-review'),
        'I will check my least secure origin inference with qualified feedback.',
      );
      await tester.ensureVisible(key('d3-paper-save-review'));
      await tester.tap(key('d3-paper-save-review'));
      await settle(tester);
      saved = await tester.runAsync(() => repository.read(ready.id));
      expect(saved!.isReviewed, isTrue);
      expect(
        saved.selfReview,
        'I will check my least secure origin inference with qualified feedback.',
      );
      expect(find.textContaining('no assessed score or pass'), findsOneWidget);
    },
  );

  testApp(
    'reload that fails again preserves the current-pointer error and recovery action',
    (tester) async {
      repository = _FailCurrentTwiceRepository(db, time);
      final paper = await repository.start(D3TastingPaperKind.grouped);
      await show(tester);
      expect(
        find.textContaining('current paper pointer could not be read'),
        findsOneWidget,
      );
      await tester.tap(key('d3-paper-reload'));
      await settle(tester);
      expect(
        find.textContaining('current paper pointer could not be read'),
        findsOneWidget,
      );
      expect(key('d3-paper-reset-pointer'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(key('d3-paper-start-grouped')).onPressed,
        isNull,
      );
      await tester.tap(key('d3-paper-reload'));
      await settle(tester);
      expect(key('d3-paper-save-error'), findsNothing);
      expect(key('d3-paper-evidence-0-description'), findsOneWidget);
      final durable = await tester.runAsync(() => repository.read(paper.id));
      expect(durable!.isFinished, isFalse);
    },
  );

  testApp(
    'initial current-pointer expiry refreshes saved history to ended View state',
    (tester) async {
      final paper = await repository.start(D3TastingPaperKind.mixed);
      time.advance(const Duration(minutes: 91));
      await show(tester);
      expect(find.text('Resume'), findsNothing);
      expect(find.text('View'), findsOneWidget);
      expect(find.textContaining('expired'), findsOneWidget);
      final durable = await tester.runAsync(() => repository.read(paper.id));
      expect(durable!.finishReason, 'expired');
      expect(key('d3-paper-start-grouped'), findsOneWidget);
    },
  );
}
