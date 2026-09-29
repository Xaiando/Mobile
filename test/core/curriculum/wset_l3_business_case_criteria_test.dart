import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/generated_coverage_formats.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l3_business_case_criteria_19',
  );
  final scope = CaseCriteriaFormat.scopeNodeIdsOf(template);
  final distractors = CaseCriteriaFormat.distractorsOf(template);
  late AppDatabase db;
  late TrackCoverage report;
  late TestClock time;

  setUpAll(() async {
    time = TestClock(DateTime.utc(2026, 9, 29, 15, 30));
    db = openTestDatabase();
    final generation = await CurriculumIngester(
      db,
      clock: time.clock,
    ).ingest(dataset);
    const path = 'assets/curriculum/coverage_policy.yaml';
    report = await CoverageChecker(
      db,
      CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
    ).check('WSET_L3', on: '2026-09-29', skipped: generation.skipped);
  });

  tearDownAll(() async => db.close());

  test('19 scoped cases retain four cited, expert-unverified roles', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(scope, hasLength(19));
    expect(distractors.keys.toSet(), scope);
    expect(template.mode, CaseCriteriaFormat.formatId);
    final items = dataset.knowledgeItems;
    final citations = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    final links = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    final businessIds = <String>{};
    for (final subject in scope) {
      expect(distractors[subject], hasLength(2));
      for (final wrong in distractors[subject]!) {
        expect(wrong.summary.length, greaterThan(35));
        expect(wrong.explanation!.length, greaterThan(45));
      }
      final roles = [
        for (final item in items)
          if (item.subjectId == subject &&
              caseCriterionRoles.contains(item.relationType))
            item,
      ];
      expect(roles, hasLength(4), reason: subject);
      expect(
        roles.map((item) => item.relationType).toSet(),
        caseCriterionRoles.toSet(),
        reason: subject,
      );
      for (final item in roles) {
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(citations, contains(item.id), reason: item.id);
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (row) =>
              row.certificationId == 'WSET_L3' &&
              row.knowledgeItemId == item.id,
        );
        expect(mapping.importance, 'core', reason: item.id);
        expect(mapping.minimumDepth, 2, reason: item.id);
        if (item.domainId == 'business') businessIds.add(item.id);
      }
    }
    expect(businessIds, hasLength(39));
    for (final citation in dataset.knowledgeItemCitations) {
      if (!businessIds.contains(citation.knowledgeItemId)) continue;
      final uri = Uri.parse(links[citation.sourceCitationId]!);
      expect(uri.scheme, 'https', reason: citation.knowledgeItemId);
      expect(uri.host, isNotEmpty, reason: citation.knowledgeItemId);
    }
  });

  test('19 complete pools serve the 39 business assertions', () async {
    final pools = (await db.select(db.exercisePools).get())
        .where((pool) => pool.questionTemplateId == template.id)
        .toList();
    expect(pools, hasLength(19));
    expect(pools.map((pool) => pool.scopeNodeId).toSet(), scope);
    final members = await db.select(db.exercisePoolItems).get();
    for (final pool in pools) {
      expect(
        members.where((member) => member.exercisePoolId == pool.id),
        hasLength(4),
        reason: pool.scopeNodeId,
      );
    }
    final caseItems = report.items.where(
      (item) =>
          item.item.domainId == 'business' &&
          caseCriterionRoles.contains(item.item.relationType),
    );
    expect(caseItems, hasLength(39));
    for (final item in caseItems) {
      expect(item.isCore, isTrue, reason: item.id);
      expect(item.servedFormats, contains('short_answer'), reason: item.id);
      expect(item.servedFormats, contains('case_criteria'), reason: item.id);
      expect(item.hasUsefulPractice, isTrue, reason: item.id);
    }
    final business = report.domains.singleWhere((d) => d.id == 'business');
    expect(business.counts[CoverageMetric.coreUsefulPractice], 99);
    expect(business.counts[CoverageMetric.core], 99);
    expect(business.counts[CoverageMetric.structured], 39);
  });

  test('whole-case matching grades each role independently', () async {
    const id = 'ki_reg_isi_case_etna_price_tradeoff';
    final exercise = await ExercisePresenter(
      db,
      clock: time.clock,
    ).present(id, template.id, seed: 7) as CaseCriteriaExercise;
    expect(exercise.primaryItemId, id);
    expect(exercise.prompt, contains('Etna producer'));
    expect(exercise.itemIds, hasLength(4));
    expect(exercise.options, hasLength(6));
    expect(
      exercise.options.where((option) => option.explanation != null),
      hasLength(2),
    );
    expect(
      exercise.criteria.map((c) => c.role).toSet(),
      caseCriterionRoles.toSet(),
    );
    for (final criterion in exercise.criteria) {
      expect(criterion.summary, isNotEmpty);
      expect(criterion.assertion, isNotEmpty);
      expect(criterion.sources, isNotEmpty);
      expect(criterion.sources.first.url, startsWith('https://'));
    }
    final byRole = {for (final c in exercise.criteria) c.role: c.itemId};
    const format = CaseCriteriaFormat();
    final correct = format.grade(exercise, CaseCriteriaResponse(byRole));
    expect(correct, hasLength(4));
    expect(correct.every((grade) => grade.rating == fsrs.Rating.good), isTrue);

    final swapped = {
      ...byRole,
      'CASE_TRADEOFF': byRole['CASE_LIMITATION']!,
      'CASE_LIMITATION': byRole['CASE_TRADEOFF']!,
    };
    final grades = format.grade(exercise, CaseCriteriaResponse(swapped));
    final byId = {for (final grade in grades) grade.itemId: grade.rating};
    expect(byId[byRole['CASE_ACTION']], fsrs.Rating.good);
    expect(byId[byRole['CASE_REASON']], fsrs.Rating.good);
    expect(byId[byRole['CASE_TRADEOFF']], fsrs.Rating.again);
    expect(byId[byRole['CASE_LIMITATION']], fsrs.Rating.again);
    final falseOption = exercise.options.singleWhere(
      (option) =>
          option.explanation != null &&
          option.summary.contains('terrace expense'),
    );
    final withFalseClaim = {...byRole, 'CASE_TRADEOFF': falseOption.id};
    final falseGrades = format.grade(
      exercise,
      CaseCriteriaResponse(withFalseClaim),
    );
    expect(
      falseGrades
          .singleWhere((grade) => grade.itemId == byRole['CASE_TRADEOFF'])
          .rating,
      fsrs.Rating.again,
    );
    expect(
      () => format.grade(
        exercise,
        CaseCriteriaResponse({
          ...byRole,
          'CASE_LIMITATION': byRole['CASE_TRADEOFF']!,
        }),
      ),
      throwsArgumentError,
      reason: 'one response cannot earn credit for two roles',
    );
  });

  test('a track cannot present a case without its complete rubric', () async {
    const id = 'ki_reg_isi_case_etna_price_tradeoff';
    final planner = StudyPlanner(db, clock: time.clock);
    final before = (await planner.cards('WSET_L3'))
        .singleWhere((card) => card.itemId == id);
    expect(
      before.formats.map((format) => format.mode),
      isNot(contains('case_criteria')),
      reason: 'three unseen co-items should not bypass the new-item budget',
    );
    final reviews = ReviewService(db, clock: time.clock);
    for (final (coItem, question) in [
      ('ki_reg_isi_case_etna_price_action', 'qt_case_action_flashcard'),
      ('ki_reg_isi_case_etna_price_reason', 'qt_case_reason_flashcard'),
      ('ki_reg_isi_case_etna_price_limitation', 'qt_case_limitation_flashcard'),
    ]) {
      await reviews.record(
        knowledgeItemId: coItem,
        questionTemplateId: question,
        rating: fsrs.Rating.good,
      );
    }
    final l3 = await planner.cards('WSET_L3');
    final card = l3.singleWhere((card) => card.itemId == id);
    expect(
      card.formats.map((format) => format.mode),
      contains('case_criteria'),
    );
    final presented = await ExercisePresenter(
      db,
      clock: time.clock,
    ).present(id, template.id, seed: 7, certificationId: 'WSET_L3');
    expect(presented, isA<CaseCriteriaExercise>());
    await expectLater(
      ExercisePresenter(
        db,
        clock: time.clock,
      ).present(id, template.id, seed: 7, certificationId: 'WSET_L2'),
      throwsArgumentError,
    );
  });

  test('coverage excludes a pool if even one criterion is unmapped', () async {
    final mappings = await StudyPlanner(
      db,
      clock: time.clock,
    ).effectiveMappings('WSET_L3');
    final partial = {...mappings}
      ..remove('ki_reg_isi_case_etna_price_limitation');
    final generated = await GeneratedCoverageFormats.read(db, on: '2026-09-29');
    for (final id in [
      'ki_reg_isi_case_etna_price_action',
      'ki_reg_isi_case_etna_price_reason',
      'ki_reg_isi_case_etna_price_tradeoff',
    ]) {
      final formats = generated.forMappedItems(partial)[id]!;
      expect(
        formats.map((format) => format.mode),
        isNot(contains('case_criteria')),
        reason: id,
      );
    }
  });
}
