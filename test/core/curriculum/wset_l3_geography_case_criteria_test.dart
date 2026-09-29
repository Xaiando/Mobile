import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l3_geography_case_criteria_5',
  );
  final scope = CaseCriteriaFormat.scopeNodeIdsOf(template);
  final distractors = CaseCriteriaFormat.distractorsOf(template);
  final businessScope = CaseCriteriaFormat.scopeNodeIdsOf(
    dataset.questionTemplates.singleWhere(
      (row) => row.id == 'qt_wset_l3_business_case_criteria_19',
    ),
  );
  late AppDatabase db;
  late TrackCoverage report;

  setUpAll(() async {
    db = openTestDatabase();
    final generation = await CurriculumIngester(
      db,
      clock: TestClock(DateTime.utc(2026, 9, 29, 16)).clock,
    ).ingest(dataset);
    const path = 'assets/curriculum/coverage_policy.yaml';
    report = await CoverageChecker(
      db,
      CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
    ).check('WSET_L3', on: '2026-09-29', skipped: generation.skipped);
  });

  tearDownAll(() async => db.close());

  test('five disjoint regional cases retain four source-linked roles', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(scope, hasLength(5));
    expect(scope.toSet().intersection(businessScope), isEmpty);
    expect(distractors.keys.toSet(), scope);
    final cited = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    final links = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    var geographyCount = 0;
    for (final subject in scope) {
      expect(distractors[subject], hasLength(2));
      for (final wrong in distractors[subject]!) {
        expect(wrong.summary.length, greaterThan(35));
        expect(wrong.explanation!.length, greaterThan(45));
      }
      final roles = [
        for (final item in dataset.knowledgeItems)
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
        expect(cited, contains(item.id), reason: item.id);
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (row) =>
              row.certificationId == 'WSET_L3' &&
              row.knowledgeItemId == item.id,
        );
        expect(mapping.importance, 'core', reason: item.id);
        expect(mapping.minimumDepth, 2, reason: item.id);
        final citations = dataset.knowledgeItemCitations.where(
          (row) => row.knowledgeItemId == item.id,
        );
        for (final citation in citations) {
          final uri = Uri.parse(links[citation.sourceCitationId]!);
          expect(uri.scheme, 'https', reason: item.id);
          expect(uri.host, isNotEmpty, reason: item.id);
        }
        if (item.domainId == 'geography') geographyCount++;
      }
    }
    expect(geographyCount, 15);
  });

  test('five complete pools serve every Level 3 regional case role', () async {
    final pools = (await db.select(db.exercisePools).get())
        .where((pool) => pool.questionTemplateId == template.id)
        .toList();
    expect(pools, hasLength(5));
    expect(pools.map((pool) => pool.scopeNodeId).toSet(), scope);
    final members = await db.select(db.exercisePoolItems).get();
    for (final pool in pools) {
      expect(
        members.where((member) => member.exercisePoolId == pool.id),
        hasLength(4),
        reason: pool.scopeNodeId,
      );
    }
    final cases = report.items.where(
      (row) =>
          row.item.domainId == 'geography' &&
          caseCriterionRoles.contains(row.item.relationType) &&
          row.isCore,
    );
    expect(cases, hasLength(32));
    for (final row in cases) {
      expect(row.servedFormats, contains('short_answer'), reason: row.id);
      expect(row.servedFormats, contains('case_criteria'), reason: row.id);
      expect(row.hasUsefulPractice, isTrue, reason: row.id);
    }
  });

  test(
    'Riesling case grades all four roles and rejects a false criterion',
    () async {
      const id = 'ki_reg_de_case_riesling_sweetness_evidence_action';
      final exercise = await ExercisePresenter(
        db,
      ).present(id, template.id, seed: 9) as CaseCriteriaExercise;
      expect(exercise.prompt, contains('Mosel Riesling'));
      expect(exercise.itemIds, hasLength(4));
      expect(exercise.options, hasLength(6));
      expect(
        exercise.options.where((option) => option.explanation != null),
        hasLength(2),
      );
      for (final criterion in exercise.criteria) {
        expect(criterion.sources, isNotEmpty);
        expect(criterion.sources.first.url, startsWith('https://'));
      }
      final byRole = {for (final c in exercise.criteria) c.role: c.itemId};
      const format = CaseCriteriaFormat();
      expect(
        format
            .grade(exercise, CaseCriteriaResponse(byRole))
            .every((grade) => grade.rating == fsrs.Rating.good),
        isTrue,
      );
      final falseOption = exercise.options.singleWhere(
        (option) => option.summary.contains('supplier\'s regional shorthand'),
      );
      final withFalse = {...byRole, 'CASE_REASON': falseOption.id};
      expect(
        format
            .grade(exercise, CaseCriteriaResponse(withFalse))
            .singleWhere((grade) => grade.itemId == byRole['CASE_REASON'])
            .rating,
        fsrs.Rating.again,
      );
    },
  );
}
