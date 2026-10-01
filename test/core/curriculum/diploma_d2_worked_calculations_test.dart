import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/app/app.dart' show noProviderRetry;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_format.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/numeric/numeric_format.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/study_session.dart';
import 'package:sommelier/features/practice/formats/numeric_view.dart';
import 'package:sommelier/features/practice/study_session_controller.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _answers = {
  'ki_d2_calc_unit_contribution': (8.0, 'EUR', 'src_biz_sba_planning'),
  'ki_d2_calc_breakeven_bottles': (1251.0, 'bottles', 'src_biz_sba_planning'),
  'ki_d2_calc_fx_receipt': (7500.0, 'EUR', 'src_biz_ita_fx'),
  'ki_d2_calc_fx_receipt_reduction': (500.0, 'EUR', 'src_biz_ita_fx'),
  'ki_d2_calc_landed_cost_per_bottle': (13.0, 'EUR', 'src_d2_ita_landed_cost'),
  'ki_d2_calc_cash_gap_days': (35.0, 'days', 'src_biz_au_cashflow'),
};
const _cms = {
  'ki_cms_calc_full_pours',
  'ki_cms_calc_event_bottles',
  'ki_cms_calc_gross_profit',
  'ki_cms_calc_gross_margin',
  'ki_cms_calc_markup',
  'ki_cms_calc_target_price',
};
const _numeric = 'qt_cms_calculated_value_fwd_numeric';
const _flashcard = 'qt_cms_calculated_value_fwd_flashcard';
const _primaryUrls = {
  'src_biz_sba_planning': 'https://www.sba.gov/counseling/plan-your-business/',
  'src_biz_ita_fx': 'https://www.trade.gov/foreign-exchange-risk',
  'src_d2_ita_landed_cost':
      'https://www.trade.gov/determine-total-export-price',
  'src_biz_au_cashflow':
      'https://business.gov.au/guide/guide-to-managing-cash-flow',
};

class _NumericHarness extends ConsumerWidget {
  const _NumericHarness();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(studySessionProvider).value;
    if (state?.turn == null) return const SizedBox.shrink();
    return ListView(
      children: [Text(state!.turn!.exercise.prompt), NumericView(state.turn!)],
    );
  }
}

class _D2ViewController extends StudySessionController {
  _D2ViewController(this.initial, this.reviews);
  final SessionTurn initial;
  final ReviewService reviews;
  bool get answered => state.value?.turn?.isAnswered ?? false;
  @override
  Future<StudySessionState?> build() async => StudySessionState(
    session: StudySession(
      StudyPlan(
        certificationId: 'WSET_L4',
        cards: [initial.card],
        dueCount: 0,
        newAvailable: 1,
      ),
    ),
    turn: initial,
  );
  @override
  Future<void> submit(Object answer) async {
    final before = state.value!;
    final results = await reviews.recordExercise(
      initial.exercise,
      const NumericFormat().grade(initial.exercise, answer),
    );
    state = AsyncData(
      StudySessionState(
        session: before.session,
        turn: before.turn!.copyWith(
          answer: answer,
          results: results,
          revealed: true,
        ),
      ),
    );
  }

  @override
  Future<void> next() async {}
}

void main() {
  final dataset = bundledDataset();
  final items = {for (final i in dataset.knowledgeItems) i.id: i};
  final clock = Clock.fixed(dataset.publishedAt);
  late AppDatabase db;
  late StudyPlanner planner;
  late ExercisePresenter presenter;
  setUpAll(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: clock,
      assets: (p) async => File(p).readAsBytesSync(),
    ).ingest(dataset);
    planner = StudyPlanner(db, clock: clock);
    presenter = ExercisePresenter(db, clock: clock);
  });
  tearDownAll(() => db.close());
  Future<NumericQuestion> present(String id) async => await presenter.present(
    id,
    _numeric,
    seed: 41,
    certificationId: 'WSET_L4',
  ) as NumericQuestion;

  test('six exact original Diploma items retain primary sources and Level4-only boundaries', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final d2 = dataset.knowledgeItems.where(
      (i) => i.id.startsWith('ki_d2_calc_'),
    );
    expect(d2.map((i) => i.id).toSet(), _answers.keys.toSet());
    expect(
      dataset.knowledgeItems
          .where((i) => i.relationType == 'CALCULATED_VALUE')
          .map((i) => i.id)
          .toSet(),
      {..._cms, ..._answers.keys},
    );
    final quantities = {
      for (final q in dataset.quantityValues) q.knowledgeNodeId: q,
    };
    for (final entry in _answers.entries) {
      final item = items[entry.key]!;
      expect(item.domainId, 'business');
      expect(item.relationType, 'CALCULATED_VALUE');
      expect(item.verificationStatus, 'unverified');
      expect(item.mcqDisabled, isTrue);
      final mappings = dataset.certificationKnowledgeMappings.where(
        (m) => m.knowledgeItemId == item.id,
      );
      expect(mappings, hasLength(1));
      expect(
        (
          mappings.single.certificationId,
          mappings.single.importance,
          mappings.single.minimumDepth,
        ),
        ('WSET_L4', 'core', 2),
      );
      final q = quantities[item.objectId]!;
      expect(
        (q.minimum, q.maximum, q.unit),
        (entry.value.$1, entry.value.$1, entry.value.$2),
      );
      expect(q.minimum.isFinite && q.minimum > 0, isTrue);
      final current = dataset.knowledgeRelations.where(
        (r) =>
            r.subjectId == item.subjectId &&
            r.relationType == 'CALCULATED_VALUE',
      );
      expect(current, hasLength(1));
      expect(current.single.objectId, item.objectId);
      expect(current.single.validFrom, '2026-09-30');
      final citations = dataset.knowledgeItemCitations.where(
        (c) => c.knowledgeItemId == item.id,
      );
      expect(citations, hasLength(1));
      expect(citations.single.sourceCitationId, entry.value.$3);
      expect(citations.single.locator, contains('original fictional'));
      final source = dataset.sourceCitations.singleWhere(
        (s) => s.id == entry.value.$3,
      );
      expect(source.url, _primaryUrls[entry.value.$3]);
      expect(
        dataset.sourceCitations.where((s) => s.url == source.url),
        hasLength(1),
      );
      final subject = dataset.knowledgeNodes.singleWhere(
        (n) => n.id == item.subjectId,
      );
      expect(subject.nodeType, 'worked_example');
      expect(subject.name.toLowerCase(), contains('fictional'));
    }
    final l4 = dataset.certificationKnowledgeMappings
        .where((m) => m.certificationId == 'WSET_L4')
        .map((m) => m.knowledgeItemId)
        .toSet();
    final prerequisites = dataset.knowledgeItemPrerequisites.where(
      (r) => _answers.containsKey(r.knowledgeItemId),
    );
    expect(prerequisites, hasLength(13));
    expect(
      prerequisites.map((r) => r.prerequisiteItemId).toSet().difference(l4),
      isEmpty,
    );
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = scope.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    expect(diploma.curriculumComplete, isFalse);
    expect(
      diploma.units
          .where((unit) => unit.domains.contains('business'))
          .map((unit) => unit.id),
      ['D2'],
    );
    expect(
      diploma.units.expand((unit) => unit.itemIds).where(_answers.containsKey),
      isEmpty,
      reason: 'These nonregional subjects use the existing D2 business-domain assignment.',
    );
    final template = dataset.questionTemplates.singleWhere(
      (t) => t.id == _numeric,
    );
    final parameters = jsonDecode(template.parameters!) as Map<String, dynamic>;
    expect(
      (template.mode, template.direction, template.promptTemplate),
      ('numeric', 'forward', '{subject.name}'),
    );
    expect(
      (parameters['scope_node_ids'] as List<dynamic>).cast<String>().toSet(),
      {
        for (final id in {..._cms, ..._answers.keys}) items[id]!.subjectId,
      },
    );
    expect(
      dataset.questionTemplates.where(
        (row) =>
            row.relationType == 'CALCULATED_VALUE' &&
            row.direction == 'forward' &&
            row.mode == 'numeric',
      ),
      hasLength(1),
      reason: 'The published relation/direction/format/language signature remains unique.',
    );
    expect(parameters['exact_tolerance'], 0);
    expect(parameters['tolerance'], 0);
    final existing = dataset.questionTemplates.singleWhere(
      (t) => t.id == _flashcard,
    );
    expect(
      existing.parameters,
      isNull,
      reason: 'Preserve the existing unscoped flashcard and its CMS cohort.',
    );
  });

  test('integer cents and rational thresholds independently distinguish six numerical targets', () {
    const revenueCents = 2400;
    const variableCents = 1300 + 200 + 100;
    const contributionCents = revenueCents - variableCents;
    expect(
      contributionCents ~/ 100,
      _answers['ki_d2_calc_unit_contribution']!.$1,
    );
    const fixedCents = 10001 * 100;
    final wholeBottles =
        (fixedCents + contributionCents - 1) ~/ contributionCents;
    expect(wholeBottles, _answers['ki_d2_calc_breakeven_bottles']!.$1);
    expect(1250 * contributionCents < fixedCents, isTrue);
    expect(1251 * contributionCents >= fixedCents, isTrue);
    expect(wholeBottles <= 1500, isTrue);
    const usdInvoice = 10000;
    const comparisonCents = usdInvoice * 80;
    const settlementCents = usdInvoice * 75;
    expect(settlementCents ~/ 100, _answers['ki_d2_calc_fx_receipt']!.$1);
    expect(
      (comparisonCents - settlementCents) ~/ 100,
      _answers['ki_d2_calc_fx_receipt_reduction']!.$1,
    );
    expect((comparisonCents - settlementCents) % 100, 0);
    const landedCents = (9000 + 1000 + 500 + 500 + 2000) * 100;
    expect(
      landedCents ~/ 1000 ~/ 100,
      _answers['ki_d2_calc_landed_cost_per_bottle']!.$1,
    );
    expect(47 - 12, _answers['ki_d2_calc_cash_gap_days']!.$1);
    expect(47 - 12 + 1, isNot(_answers['ki_d2_calc_cash_gap_days']!.$1));
  });

  test('actual D2 planner delivers exactly both supported formats with strict amount/unit grading', () async {
    final cards = {for (final c in await planner.cards('WSET_L4')) c.itemId: c};
    const format = NumericFormat();
    for (final entry in _answers.entries) {
      final card = cards[entry.key]!;
      expect(
        card.formats.map((f) => f.questionTemplateId),
        unorderedEquals([_numeric, _flashcard]),
      );
      final q = await present(entry.key);
      expect(q.prompt, isNot(card.item.assertionText));
      expect(
        q.prompt,
        dataset.knowledgeNodes
            .singleWhere((n) => n.id == card.item.subjectId)
            .name,
      );
      expect(
        (
          q.canonicalMinimum,
          q.canonicalMaximum,
          q.canonicalUnit,
          q.exactTolerance,
          q.tolerance,
        ),
        (entry.value.$1, entry.value.$1, entry.value.$2, 0.0, 0.0),
      );
      expect(q.allowsInterval, isFalse);
      expect(q.isLegalMinimum, isFalse);
      for (final answer in [
        entry.value.$1.toString(),
        '${entry.value.$1} ${entry.value.$2}',
      ]) {
        final grades = format.grade(q, answer);
        expect(grades, hasLength(1));
        expect(
          (grades.single.itemId, grades.single.rating),
          (entry.key, fsrs.Rating.good),
        );
      }
      for (final answer in <Object>[
        (entry.value.$1 - 1).toString(),
        (entry.value.$1 + 1).toString(),
        (entry.value.$1 + 0.0001).toString(),
        '${entry.value.$1} kg',
        'NaN',
        'Infinity',
        '1e-9999',
        NumericAnswer.interval(
          entry.value.$1,
          entry.value.$1 + 1,
          unit: entry.value.$2,
        ),
      ]) {
        final grades = format.grade(q, answer);
        expect(grades, hasLength(1));
        expect(
          (grades.single.itemId, grades.single.rating),
          (entry.key, fsrs.Rating.again),
          reason: '${entry.key} rejects $answer',
        );
      }
    }
    for (final pair in const [
      ('ki_d2_calc_unit_contribution', '16 EUR'),
      ('ki_d2_calc_breakeven_bottles', '1250 bottles'),
      ('ki_d2_calc_breakeven_bottles', '1250.125 bottles'),
      ('ki_d2_calc_fx_receipt', '7500 USD'),
      ('ki_d2_calc_fx_receipt', '7500 eur'),
      ('ki_d2_calc_fx_receipt', 'EUR 7500'),
      ('ki_d2_calc_fx_receipt', '7,500'),
      ('ki_d2_calc_fx_receipt', '10000 * 0.75'),
      ('ki_d2_calc_fx_receipt_reduction', '7500 EUR'),
      ('ki_d2_calc_fx_receipt_reduction', '500 USD'),
      ('ki_d2_calc_landed_cost_per_bottle', '13000 EUR'),
      ('ki_d2_calc_cash_gap_days', '36 days'),
      ('ki_d2_calc_cash_gap_days', '47 days'),
    ]) {
      expect(
        format.grade(await present(pair.$1), pair.$2).single.rating,
        fsrs.Rating.again,
        reason: '${pair.$1} rejects ${pair.$2}',
      );
    }
    for (final track in [
      'WSET_L1',
      'WSET_L2',
      'WSET_L3',
      'CMS_INTRODUCTORY',
      'CMS_CERTIFIED',
    ]) {
      expect(
        (await planner.cards(track))
            .where((c) => _answers.containsKey(c.itemId)),
        isEmpty,
        reason: track,
      );
    }
    final cms = (await planner.cards('CMS_CERTIFIED'))
        .where((c) => _cms.contains(c.itemId));
    expect(cms.map((c) => c.itemId).toSet(), _cms);
    for (final card in cms) {
      expect(
        card.formats.map((f) => f.questionTemplateId),
        unorderedEquals(['qt_cms_calculated_value_fwd_numeric', _flashcard]),
      );
    }
    final policyPath = 'assets/curriculum/coverage_policy.yaml';
    final report =
        await CoverageChecker(
          db,
          CoveragePolicy.parse(
            File(policyPath).readAsStringSync(),
            path: policyPath,
          ),
        ).check(
          'WSET_L4',
          on: dataset.publishedAt.toIso8601String().substring(0, 10),
        );
    final delivered = report.items.where(
      (r) => _answers.containsKey(r.item.id),
    );
    expect(delivered, hasLength(6));
    expect(delivered.where((r) => !r.hasUsefulPractice), isEmpty);
  });

  test('competing objects and missing metadata never choose an arbitrary new D2 target', () async {
    final item = items['ki_d2_calc_unit_contribution']!;
    final template = dataset.questionTemplates.singleWhere(
      (t) => t.id == _numeric,
    );
    final day = dataset.publishedAt.toIso8601String().substring(0, 10);
    final context = GeneratorContext(db, today: day, items: [item]);
    const format = NumericFormat();
    expect(await format.isEligible(context, item, template), isTrue);
    await db.writeCurriculum(
      () => db.customStatement(
        "INSERT INTO knowledge_relations VALUES ('n_d2_calc_unit_contribution','CALCULATED_VALUE','n_qty_d2_calc_cash_gap_days','2026-09-30',NULL)",
      ),
    );
    try {
      expect(await format.isEligible(context, item, template), isFalse);
      await expectLater(present(item.id), throwsStateError);
    } finally {
      await db.writeCurriculum(
        () => db.customStatement(
          "DELETE FROM knowledge_relations WHERE subject_id='n_d2_calc_unit_contribution' AND object_id='n_qty_d2_calc_cash_gap_days'",
        ),
      );
    }
    await db.writeCurriculum(
      () => db.customStatement(
        "DELETE FROM quantity_values WHERE knowledge_node_id='n_qty_d2_calc_unit_contribution'",
      ),
    );
    try {
      expect(await format.isEligible(context, item, template), isFalse);
      await expectLater(present(item.id), throwsStateError);
    } finally {
      await db.writeCurriculum(
        () => db.customStatement(
          "INSERT INTO quantity_values (knowledge_node_id,minimum,maximum,unit) VALUES ('n_qty_d2_calc_unit_contribution',8,8,'EUR')",
        ),
      );
    }
    expect((await present(item.id)).canonicalMinimum, 8);
  });

  testWidgets(
    'actual numeric learner view hides the result until graded and writes only fact memory',
    (tester) async {
      final q = (await tester.runAsync(
        () => present('ki_d2_calc_fx_receipt_reduction'),
      ))!;
      final card = (await tester.runAsync(() => planner.cards('WSET_L4')))!
          .singleWhere((c) => c.itemId == q.knowledgeItemId);
      final format = card.formats.singleWhere(
        (f) => f.questionTemplateId == _numeric,
      );
      final turn = SessionTurn(
        card: card,
        format: format,
        exercise: q,
        shownAt: clock.now(),
      );
      await tester.runAsync(
        () => LearnerProfiles(db, clock: clock).selectTrack('WSET_L4'),
      );
      final before = (await tester.runAsync(
        () => db.select(db.userSettings).get(),
      ))!;
      final controller = _D2ViewController(
        turn,
        ReviewService(db, clock: clock, random: Random(41)),
      );
      await tester.pumpWidget(
        ProviderScope(
          retry: noProviderRetry,
          overrides: [studySessionProvider.overrideWith(() => controller)],
          child: const MaterialApp(home: Scaffold(body: _NumericHarness())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(q.prompt), findsOneWidget);
      expect(find.text(q.explanation), findsNothing);
      expect(find.text('Target: ${q.displayAnswer}'), findsNothing);
      expect(find.text('Review grade: Good'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.enterText(find.byType(TextField), '500 EUR');
      final check = find.widgetWithText(FilledButton, 'Check');
      debugPrint(
        'D2 numeric Check enabled before controller frame: '
        '${tester.widget<FilledButton>(check).onPressed != null}',
      );
      // The text-controller listener rebuilds button eligibility on a frame.
      await tester.pump(Duration.zero);
      await tester.ensureVisible(check);
      await tester.pump(Duration.zero);
      expect(
        tester.widget<FilledButton>(check).onPressed,
        isNotNull,
        reason: 'Check must be visibly enabled before the learner submits.',
      );
      await tester.tap(check);
      for (var i = 0; i < 50 && !controller.answered; i++) {
        await tester.pump(Duration.zero);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(controller.answered, isTrue);
      expect(find.text('Target: 500 EUR'), findsOneWidget);
      expect(find.text(q.explanation), findsOneWidget);
      expect(find.text('Review grade: Good'), findsOneWidget);
      final events = (await tester.runAsync(
        () => db.select(db.reviewEvents).get(),
      ))!;
      expect(events, hasLength(1));
      expect(
        (
          events.single.knowledgeItemId,
          events.single.questionTemplateId,
          events.single.rating,
        ),
        (q.knowledgeItemId, _numeric, fsrs.Rating.good.value),
      );
      final memory = (await tester.runAsync(
        () => db.select(db.reviewStates).get(),
      ))!;
      expect(memory, hasLength(1));
      expect(memory.single.knowledgeItemId, q.knowledgeItemId);
      expect(memory.single.reps, 1);
      final after = (await tester.runAsync(
        () => db.select(db.userSettings).get(),
      ))!;
      expect(
        {for (final r in after) r.name: r.value},
        {for (final r in before) r.name: r.value},
        reason: 'Numerical fact review must not write qualification or rehearsal settings.',
      );
      final profile = (await tester.runAsync(
        () => db.select(db.userProfiles).getSingle(),
      ))!;
      expect(profile.activeCertificationId, 'WSET_L4');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(Duration.zero);
    },
  );
}
