import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d2_'))
      .where(
        (item) => const {
          'paired_shifts',
          'market_stock_context',
          'competitor_baseline',
          'target_sample',
          'marketing_objective',
          'campaign_review',
          'case_supply_and_demand_action',
          'case_supply_and_demand_reason',
          'case_supply_and_demand_tradeoff',
          'case_supply_and_demand_limitation',
          'case_market_launch_action',
          'case_market_launch_reason',
          'case_market_launch_tradeoff',
          'case_market_launch_limitation',
        }.contains(item.id.substring('ki_d2_'.length)),
      )
      .toList();
  final itemIds = items.map((item) => item.id).toSet();
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_wset_d2_market_decisions_choice_6',
  );
  final choiceRows = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
  final caseTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_wset_d2_market_decisions_case_criteria_2',
  );
  const caseSubjects = {
    'n_d2_case_supply_and_demand',
    'n_d2_case_market_launch',
  };
  const caseRoles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };

  test('fourteen D2 decisions are distinct, cited, and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(14));
    expect(itemIds, hasLength(14));
    expect(
      items.where((item) => item.relationType == 'PRINCIPLE_EXPLANATION'),
      hasLength(6),
    );
    for (final item in items) {
      expect(item.domainId, 'business', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(item.assertionText.trim(), isNotEmpty, reason: item.id);
      expect(
        nodes[item.subjectId]!.nodeType,
        caseSubjects.contains(item.subjectId)
            ? 'production_case'
            : 'production_principle',
        reason: item.id,
      );
      final mappings = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
      expect(mappings.single.importance, 'core', reason: item.id);
      expect(mappings.single.minimumDepth, 3, reason: item.id);
      final citations = dataset.knowledgeItemCitations
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty, reason: item.id);
        expect(sources[citation.sourceCitationId]!.url, startsWith('https://'));
      }
    }
    for (final subject in caseSubjects) {
      expect(
        items
            .where((item) => item.subjectId == subject)
            .map((item) => item.relationType)
            .toSet(),
        caseRoles,
        reason: subject,
      );
    }
  });

  test('D2 selectors and study unit expose the new market decisions', () {
    final track = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final marketing = track.tracks['WSET_L4']!.objectives.singleWhere(
      (objective) => objective.id == 'wset_l4.business.marketing',
    );
    expect(
      marketing.covers!.within,
      containsAll({
        'n_d2_competitor_baseline',
        'n_d2_target_sample',
        'n_d2_marketing_objective',
        'n_d2_campaign_review',
        'n_d2_case_market_launch',
      }),
    );
    final progress = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = progress.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d2 = diploma.units.singleWhere((unit) => unit.id == 'D2');
    expect(d2.domains, contains('business'));
    expect(diploma.curriculumComplete, isFalse);
  });

  test('six choices test separate decisions with cited explanations', () {
    expect(choiceRows.keys.toSet(), {
      'ki_d2_paired_shifts',
      'ki_d2_market_stock_context',
      'ki_d2_competitor_baseline',
      'ki_d2_target_sample',
      'ki_d2_marketing_objective',
      'ki_d2_campaign_review',
    });
    final positions = List<int>.filled(4, 0);
    final lengthRanks = List<int>.filled(4, 0);
    for (final entry in choiceRows.entries) {
      final row = entry.value;
      positions[row.correctIndex]++;
      final orderedLengths = row.options.map((option) => option.length).toList()
        ..sort();
      lengthRanks[orderedLengths.indexOf(
        row.options[row.correctIndex].length,
      )]++;
      expect(row.prompt, contains('?'));
      expect(row.options, hasLength(4));
      expect(row.options.map(normalizeName).toSet(), hasLength(4));
      expect(row.explanation.trim(), isNotEmpty);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) =>
              citation.knowledgeItemId == entry.key &&
              citation.sourceCitationId == row.sourceCitationId,
        ),
        isTrue,
        reason: entry.key,
      );
    }
    expect(positions, [2, 2, 1, 1]);
    expect(lengthRanks.every((count) => count >= 1), isTrue);
  });

  test(
    'both cases have complete written rubrics and usable role choices',
    () async {
      final written = dataset.questionTemplates
          .where(
            (template) => {
              'qt_wset_d2_supply_and_demand_case',
              'qt_wset_d2_market_launch_case',
            }.contains(template.id),
          )
          .toList();
      expect(written, hasLength(2));
      for (final template in written) {
        expect(template.mode, 'short_answer');
        expect(
          ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(),
          caseRoles,
        );
        final subject = ShortAnswerFormat.scopeNodeIdsOf(template)!.single;
        expect(caseSubjects, contains(subject));
        expect(template.promptTemplate, nodes[subject]!.name);
        expect(template.promptTemplate, contains('More than one approach'));
      }
      expect(CaseCriteriaFormat.scopeNodeIdsOf(caseTemplate), caseSubjects);
      final distractors = CaseCriteriaFormat.distractorsOf(caseTemplate);
      for (final subject in caseSubjects) {
        expect(distractors[subject], hasLength(2));
        expect(
          distractors[subject]!.every(
            (wrong) =>
                wrong.summary.isNotEmpty && wrong.explanation!.isNotEmpty,
          ),
          isTrue,
        );
      }

      final db = openTestDatabase();
      addTearDown(db.close);
      final generation = await CurriculumIngester(db).ingest(dataset);
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L4')) card.itemId,
      };
      expect(cards, containsAll(itemIds));
      final l3Cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L3')) card.itemId,
      };
      expect(l3Cards.intersection(itemIds), isEmpty);

      final presenter = ExercisePresenter(db);
      for (final entry in choiceRows.entries) {
        final question = await presenter.present(
          entry.key,
          choiceTemplate.id,
          seed: 17,
        ) as AuthoredChoiceQuestion;
        expect(question.prompt, entry.value.prompt, reason: entry.key);
        expect(question.options, hasLength(4), reason: entry.key);
        expect(
          question.answer.name,
          entry.value.options[entry.value.correctIndex],
        );
        expect(question.sourceCitationId, entry.value.sourceCitationId);
      }
      for (final subject in caseSubjects) {
        final id = items
            .singleWhere(
              (item) =>
                  item.subjectId == subject &&
                  item.relationType == 'CASE_ACTION',
            )
            .id;
        final exercise = await presenter.present(
          id,
          caseTemplate.id,
          seed: 17,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds.toSet(), {
          for (final item in items)
            if (item.subjectId == subject) item.id,
        });
        expect(exercise.options, hasLength(6));
        expect(
          exercise.criteria.map((criterion) => criterion.role).toSet(),
          caseRoles,
        );
        final answer = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        final grades = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(answer),
        );
        expect(
          grades.every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
      }
      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final report = await CoverageChecker(
        db,
        CoveragePolicy.parse(
          File(policyPath).readAsStringSync(),
          path: policyPath,
        ),
      ).check('WSET_L4', on: '2026-09-29', skipped: generation.skipped);
      for (final row in report.items.where((row) => itemIds.contains(row.id))) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        if (caseSubjects.contains(row.item.subjectId)) {
          expect(row.servedFormats, contains('case_criteria'), reason: row.id);
        }
      }
    },
  );
}
