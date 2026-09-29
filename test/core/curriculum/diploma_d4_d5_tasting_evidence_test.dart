import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/study/review_service.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d45taste_'))
      .toList();
  final itemIds = items.map((item) => item.id).toSet();
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const keys = {
    'sparkling_lees',
    'sparkling_quality',
    'sherry_sweetness',
    'port_development',
  };
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  final caseTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d45taste_case_criteria_4',
  );
  Set<String> idsFor(String key) => {
    for (final role in roles)
      'ki_d45taste_${key}_${role.substring(5).toLowerCase()}',
  };

  test('sixteen sensory-reasoning items are cited and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(16));
    expect(itemIds, {for (final key in keys) ...idsFor(key)});
    for (final item in items) {
      expect(item.domainId, 'tasting', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(item.assertionText.trim(), isNotEmpty, reason: item.id);
      expect(nodes[item.subjectId]!.nodeType, 'production_case');
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4');
      expect(mappings.single.importance, 'core');
      expect(mappings.single.minimumDepth, 3);
      final citations = dataset.knowledgeItemCitations
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty, reason: item.id);
        expect(sources[citation.sourceCitationId]!.url, startsWith('https://'));
        expect(
          sources[citation.sourceCitationId]!.url,
          isNot(contains('wset_l4wines_specification')),
          reason: 'the specification supplies scope, not sample evidence',
        );
      }
    }
    for (final key in keys) {
      final caseItems = items.where(
        (item) => item.subjectId == 'n_d45taste_case_$key',
      );
      expect(caseItems, hasLength(4));
      expect(caseItems.map((item) => item.relationType).toSet(), roles);
    }
  });

  test('four distinct hypothetical cases retain complete written rubrics', () {
    expect(CaseCriteriaFormat.scopeNodeIdsOf(caseTemplate), {
      for (final key in keys) 'n_d45taste_case_$key',
    });
    expect(CaseCriteriaFormat.datasetProblems(caseTemplate, dataset), isEmpty);
    final distractors = CaseCriteriaFormat.distractorsOf(caseTemplate);
    final prompts = <String>{};
    for (final key in keys) {
      final subject = 'n_d45taste_case_$key';
      final template = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d45taste_written_$key',
      );
      expect(template.mode, 'short_answer');
      expect(ShortAnswerFormat.scopeNodeIdsOf(template), {subject});
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(), roles);
      expect(template.promptTemplate, nodes[subject]!.name);
      expect(template.promptTemplate, contains('Hypothetical'));
      expect(template.promptTemplate, contains('invented'));
      prompts.add(template.promptTemplate);
      expect(distractors[subject], hasLength(2));
      for (final wrong in distractors[subject]!) {
        expect(wrong.summary.length, greaterThan(35));
        expect(wrong.explanation!.length, greaterThan(45));
      }
    }
    expect(prompts, hasLength(4));
    final byId = {for (final item in items) item.id: item};
    expect(
      byId['ki_d45taste_sparkling_lees_limitation']!.assertionText,
      contains('cannot authenticate Champagne'),
    );
    expect(
      byId['ki_d45taste_sparkling_quality_limitation']!.assertionText,
      contains('sensory accuracy'),
    );
    expect(
      byId['ki_d45taste_sherry_sweetness_reason']!.assertionText,
      contains('without proving that E is Palo Cortado'),
    );
    expect(
      byId['ki_d45taste_port_development_limitation']!.assertionText,
      contains('cannot assign H an exact twenty-year'),
    );
  });

  test(
    'D4 and D5 explicitly select sensory cases without claiming completion',
    () {
      final scope = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      );
      final objectives = {
        for (final objective in scope.tracks['WSET_L4']!.objectives)
          objective.id: objective,
      };
      final progress = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final diploma = progress.levels.singleWhere(
        (level) => level.certificationId == 'WSET_L4',
      );
      expect(diploma.curriculumComplete, isFalse);
      const unitKeys = {
        'D4': {'sparkling_lees', 'sparkling_quality'},
        'D5': {'sherry_sweetness', 'port_development'},
      };
      for (final entry in unitKeys.entries) {
        final objectiveId = entry.key == 'D4'
            ? 'wset_l4.sparkling.tasting'
            : 'wset_l4.fortified.tasting';
        expect(objectives[objectiveId]!.covers!.within, {
          for (final key in entry.value) 'n_d45taste_case_$key',
        });
        expect(objectives[objectiveId]!.covers!.relationTypes, roles);
        final unit = diploma.units.singleWhere((unit) => unit.id == entry.key);
        expect(unit.itemIds.toSet().intersection(itemIds), {
          for (final key in entry.value) ...idsFor(key),
        });
      }
    },
  );

  test(
    'runtime serves and grades four complete original evidence cases',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: clock,
      ).ingest(dataset);
      final cards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('WSET_L4'))
          card.itemId,
      };
      expect(cards, containsAll(itemIds));
      final lowerCards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('WSET_L3'))
          card.itemId,
      };
      expect(lowerCards.intersection(itemIds), isEmpty);
      final cmsCards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('CMS_CERTIFIED'))
          card.itemId,
      };
      expect(cmsCards.intersection(itemIds), isEmpty);
      final pools = await db.select(db.exercisePools).get();
      expect(
        pools.where((pool) => pool.questionTemplateId == caseTemplate.id),
        hasLength(4),
      );
      final presenter = ExercisePresenter(db, clock: clock);
      final reviews = ReviewService(db, clock: clock);
      for (final key in keys) {
        final expectedCaseIds = idsFor(key);
        final id = 'ki_d45taste_${key}_action';
        // A new written rehearsal respects the two-point introduction budget.
        // Studying its individual facts unlocks the complete four-role rubric.
        final introductory = await presenter.present(
          id,
          'qt_d45taste_written_$key',
          seed: 17,
        ) as ShortAnswerExercise;
        expect(introductory.itemIds, hasLength(2));
        expect(introductory.itemIds, contains(id));
        for (final point in items.where(
          (item) => expectedCaseIds.contains(item.id),
        )) {
          final card = dataset.questionTemplates.singleWhere(
            (template) =>
                template.mode == 'flashcard' &&
                template.relationType == point.relationType,
          );
          await reviews.record(
            knowledgeItemId: point.id,
            questionTemplateId: card.id,
            rating: fsrs.Rating.good,
          );
        }
        final written = await presenter.present(
          id,
          'qt_d45taste_written_$key',
          seed: 17,
        ) as ShortAnswerExercise;
        expect(written.itemIds.toSet(), expectedCaseIds);
        expect(written.keyPoints, hasLength(4));
        expect(written.prompt, nodes['n_d45taste_case_$key']!.name);
        final exercise = await presenter.present(
          id,
          caseTemplate.id,
          seed: 17,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds.toSet(), expectedCaseIds);
        expect(exercise.options, hasLength(6));
        expect(exercise.criteria.map((point) => point.role).toSet(), roles);
        expect(
          exercise.criteria.every((point) => point.sources.isNotEmpty),
          isTrue,
        );
        final answer = {
          for (final point in exercise.criteria) point.role: point.itemId,
        };
        final good = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(answer),
        );
        expect(good, hasLength(4));
        expect(good.every((grade) => grade.rating == fsrs.Rating.good), isTrue);
        final wrong = {...answer};
        wrong['CASE_REASON'] = exercise.options
            .firstWhere((option) => !expectedCaseIds.contains(option.id))
            .id;
        final grades = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(wrong),
        );
        expect(
          grades.where((grade) => grade.rating == fsrs.Rating.again),
          hasLength(1),
        );
        expect(
          grades.where((grade) => grade.rating == fsrs.Rating.good),
          hasLength(3),
        );
      }
      const policyPath = 'assets/curriculum/coverage_policy.yaml';
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
            skipped: generation.skipped,
          );
      final measuredItems = report.items.where(
        (row) => itemIds.contains(row.id),
      );
      expect(measuredItems, hasLength(16));
      for (final row in measuredItems) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(row.servedFormats, contains('case_criteria'), reason: row.id);
        expect(row.servedFormats, contains('short_answer'), reason: row.id);
      }
      final scope = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      );
      final measuredObjectives = {
        for (final row in objectiveCoverage(scope.tracks['WSET_L4']!, report))
          row.objective.id: row,
      };
      for (final id in [
        'wset_l4.sparkling.tasting',
        'wset_l4.fortified.tasting',
      ]) {
        expect(measuredObjectives[id]!.status, ObjectiveStatus.represented);
        expect(measuredObjectives[id]!.items, 8);
        expect(measuredObjectives[id]!.usefulPractice, 8);
      }
    },
  );
}
