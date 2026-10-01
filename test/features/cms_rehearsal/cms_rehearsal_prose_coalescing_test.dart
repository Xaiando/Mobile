import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart'
    show ApplyInterceptor, QueryExecutor, QueryInterceptor, TransactionExecutor;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/app/app.dart' show noProviderRetry;
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

/// Holds the first actual prose snapshot INSERT inside answerWritten()'s transaction.
/// Later observations count actual committed snapshots, not callbacks, timer
/// ticks, repository mocks, or native worker request/response messages.
class _FirstProseInsertGate extends QueryInterceptor {
  String? targetKey;
  bool everyWriteInTransaction = true;
  bool _targetTransaction = false;
  int committedSnapshots = 0;
  final requestedSnapshots = <Map<String, String>>[];
  Completer<void> entered = Completer<void>();
  Completer<void> release = Completer<void>();
  Completer<void> firstSettled = Completer<void>();

  void resetGate() {
    entered = Completer<void>();
    release = Completer<void>();
    firstSettled = Completer<void>();
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (targetKey != null &&
        statement.contains('user_settings') &&
        args.contains(targetKey)) {
      everyWriteInTransaction =
          everyWriteInTransaction && executor is TransactionExecutor;
      _targetTransaction = true;
      final raw = args.whereType<String>().firstWhere(
        (value) => value.startsWith('{'),
      );
      final row = jsonDecode(raw) as Map<String, dynamic>;
      if (row.containsKey('prose')) {
        requestedSnapshots.add(Map<String, String>.from(row['prose'] as Map));
      }
      if (!entered.isCompleted) {
        entered.complete();
        await release.future;
      }
    }
    return executor.runInsert(statement, args);
  }

  @override
  Future<void> commitTransaction(TransactionExecutor inner) async {
    await inner.send();
    if (_targetTransaction) {
      _targetTransaction = false;
      committedSnapshots++;
      if (!firstSettled.isCompleted) firstSettled.complete();
    }
  }

  @override
  Future<void> rollbackTransaction(TransactionExecutor inner) async {
    await inner.rollback();
    if (_targetTransaction) {
      _targetTransaction = false;
      if (!firstSettled.isCompleted) firstSettled.complete();
    }
  }
}

void main() {
  late AppDatabase db;
  late TestClock time;
  late CmsRehearsalBank bank;
  late CmsRehearsalRepository repository;
  late _FirstProseInsertGate gate;

  setUp(() async {
    gate = _FirstProseInsertGate();
    db = AppDatabase(NativeDatabase.memory().interceptWith(gate));
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
    await tester.pump(Duration.zero);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() ready,
    String phase,
  ) async {
    final bound = Stopwatch()..start();
    while (!ready() && bound.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
    expect(ready(), isTrue, reason: 'Prose coalescing phase: $phase');
  }

  testApp(
    'Back saves latest three service written responses without committing superseded queued prose',
    (tester) async {
      final original = (await tester.runAsync(
        () => repository
            .start(CmsRehearsalSection.service)
            .timeout(const Duration(seconds: 5)),
      ))!;
      expect(original.written, hasLength(3));
      final questions = original.written;
      final latest = <String, String>{
        questions[0].id:
            'Latest oyster response: consider Muscadet, describe dressing interaction, '
            'and verify bottle conditions before service.',
        questions[1].id:
            'Latest tart response: consider Tawny Port, account for chocolate intensity, '
            'and confirm remaining evidence.',
        questions[2].id:
            'Latest aperitif response: recommend Americano, verify bitterness preference, '
            'and check ingredient restrictions.',
      };
      Finder field(String questionId) =>
          find.byKey(ValueKey('cms-rehearsal-written-$questionId'));
      String visibleValue(String questionId) => tester
          .widget<EditableText>(
            find.descendant(
              of: field(questionId),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;

      tester.view.physicalSize = const Size(1100, 4500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
            cmsRehearsalRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CmsRehearsalScreen(),
                    ),
                  ),
                  child: const Text('Open CMS rehearsal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open CMS rehearsal'));
      await pumpUntil(
        tester,
        () => questions.every((q) => field(q.id).evaluate().isNotEmpty),
        'all three actual draft fields loaded',
      );
      await settle(tester);
      for (final question in questions) {
        expect(
          tester.widget<TextFormField>(field(question.id)).enabled,
          isTrue,
        );
        expect(visibleValue(question.id), isEmpty);
      }

      const firstInFlight =
          'First admitted value, already inside its SQL write.';
      gate.targetKey = CmsRehearsalRepository.keyFor(original.id);
      try {
        await tester.enterText(field(questions[0].id), firstInFlight);
        await pumpUntil(
          tester,
          () => gate.entered.isCompleted,
          'first answer reached the held real transaction INSERT',
        );
        expect(gate.everyWriteInTransaction, isTrue);
        expect(gate.requestedSnapshots, [
          {questions[0].id: firstInFlight},
        ]);
        expect(gate.committedSnapshots, 0);
        expect(gate.release.isCompleted, isFalse);

        // Every enterText dispatches a genuine editable-field change while the
        // first transaction is blocked. Each field receives distinct revisions
        // rather than duplicate callbacks or direct calls to a save method.
        for (var revision = 1; revision <= 12; revision++) {
          for (final question in questions) {
            final text =
                'Superseded revision $revision for ${question.id}: '
                'this intermediate wording must not outlive the latest edit.';
            await tester.enterText(field(question.id), text);
            expect(visibleValue(question.id), text);
          }
        }
        for (final question in questions) {
          await tester.enterText(field(question.id), latest[question.id]!);
          expect(visibleValue(question.id), latest[question.id]);
        }
        expect(gate.requestedSnapshots, hasLength(1));
        expect(gate.committedSnapshots, 0);

        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        expect(
          find.byType(CmsRehearsalScreen),
          findsOneWidget,
          reason:
              'Back must retain the route while an admitted save is pending',
        );
        expect(find.text('Open CMS rehearsal'), findsNothing);
        for (final question in questions) {
          expect(
            tester.widget<TextFormField>(field(question.id)).enabled,
            isFalse,
          );
          expect(visibleValue(question.id), latest[question.id]);
        }
        expect(gate.release.isCompleted, isFalse);
        expect(gate.firstSettled.isCompleted, isFalse);
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        if (gate.entered.isCompleted) {
          await pumpUntil(
            tester,
            () => gate.firstSettled.isCompleted,
            'held first transaction commits or rolls back',
          );
        }
      }
      await pumpUntil(
        tester,
        () => find.byType(CmsRehearsalScreen).evaluate().isEmpty,
        'Back drains admitted responses and returns to the previous route',
      );
      await settle(tester);
      expect(find.text('Open CMS rehearsal'), findsOneWidget);
      expect(gate.everyWriteInTransaction, isTrue);

      final saved = (await tester.runAsync(
        () => repository.read(original.id).timeout(const Duration(seconds: 5)),
      ))!;
      expect(saved.prose, latest);
      expect(saved.startedAt, original.startedAt);
      expect(saved.deadline, original.deadline);
      expect(saved.isFinished, isFalse);
      final current = (await tester.runAsync(
        () => repository.current().timeout(const Duration(seconds: 5)),
      ))!;
      expect(current.toJson(), saved.toJson());
      expect(tester.takeException(), isNull);
      expect(gate.requestedSnapshots.length, gate.committedSnapshots);
      expect(
        gate.committedSnapshots,
        lessThanOrEqualTo(1 + questions.length),
        reason:
            'one already-running write plus at most one latest pending snapshot '
            'per question; superseded queued text must not require SQL commits',
      );
    },
  );

  testApp(
    'Back saves latest wine evidence without committing superseded queued edits',
    (tester) async {
      final original = (await tester.runAsync(
        () => repository
            .start(CmsRehearsalSection.tasting)
            .timeout(const Duration(seconds: 5)),
      ))!;
      expect(original.wines, hasLength(2));
      expect(original.wineEvidencePrompts, isNotEmpty);
      final prompt = original.wineEvidencePrompts.first;
      final wine = original.wines.first;
      const latestEvidence =
          'Latest wine evidence: high natural acid, phenolic grip, pale straw appearance.';

      final evidenceKey =
          'cms-rehearsal-wine-evidence-${wine.ordinal}-${prompt.id}';
      Finder field() => find.byKey(ValueKey(evidenceKey));
      String visibleValue() => tester
          .widget<EditableText>(
            find.descendant(of: field(), matching: find.byType(EditableText)),
          )
          .controller
          .text;

      tester.view.physicalSize = const Size(1100, 4500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            clockProvider.overrideWithValue(time.clock),
            cmsRehearsalRepositoryProvider.overrideWith(
              (ref) async => repository,
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => const CmsRehearsalScreen(),
                    ),
                  ),
                  child: const Text('Open CMS rehearsal'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open CMS rehearsal'));
      await pumpUntil(
        tester,
        () => field().evaluate().isNotEmpty,
        'wine evidence field loaded',
      );
      await settle(tester);
      expect(tester.widget<TextFormField>(field()).enabled, isTrue);
      expect(visibleValue(), isEmpty);

      const firstInFlight = 'First wine evidence in flight.';
      gate.targetKey = CmsRehearsalRepository.keyFor(original.id);
      gate.resetGate();
      final snapshotsBefore = gate.committedSnapshots;

      try {
        await tester.enterText(field(), firstInFlight);
        await pumpUntil(
          tester,
          () => gate.entered.isCompleted,
          'first wine evidence reached transaction INSERT',
        );
        expect(gate.everyWriteInTransaction, isTrue);

        for (var revision = 1; revision <= 12; revision++) {
          final text = 'Superseded wine evidence $revision';
          await tester.enterText(field(), text);
          expect(visibleValue(), text);
        }
        await tester.enterText(field(), latestEvidence);
        expect(visibleValue(), latestEvidence);

        expect(find.byType(BackButton), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await settle(tester);
        expect(find.byType(CmsRehearsalScreen), findsOneWidget);
        expect(tester.widget<TextFormField>(field()).enabled, isFalse);
      } finally {
        if (!gate.release.isCompleted) gate.release.complete();
        if (gate.entered.isCompleted) {
          await pumpUntil(
            tester,
            () => gate.firstSettled.isCompleted,
            'held transaction finishes',
          );
        }
      }
      await pumpUntil(
        tester,
        () => find.byType(CmsRehearsalScreen).evaluate().isEmpty,
        'Back returns to home',
      );
      await settle(tester);
      expect(find.text('Open CMS rehearsal'), findsOneWidget);

      final saved = (await tester.runAsync(
        () => repository.read(original.id).timeout(const Duration(seconds: 5)),
      ))!;
      expect(saved.wines.first.evidence[prompt.id], latestEvidence);
      final committedDuringTest = gate.committedSnapshots - snapshotsBefore;
      expect(
        committedDuringTest,
        lessThanOrEqualTo(2),
        reason:
            'one in-flight write plus at most one latest coalesced edit; '
            'superseded 12 keystrokes must not commit separate transactions',
      );
    },
  );
}
