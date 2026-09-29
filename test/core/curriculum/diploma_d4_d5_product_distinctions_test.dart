import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d4d5_'))
      .toList();
  final itemIds = items.map((item) => item.id).toSet();
  final template = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d4d5_product_choice',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  const d4Principles = {
    'bourgogne_base',
    'saumur_bottle',
    'trento_riserva',
    'sorbara_dry',
    'grasparossa_body',
  };
  const d5Principles = {
    'palo_route',
    'palo_dry',
    'lbv_vintage',
    'colheita_cask',
    'white_port_age',
  };
  final d4Ids = {
    for (final key in d4Principles) 'ki_d4d5_$key',
    for (final role in roles)
      'ki_d4d5_case_italian_list_${role.substring(5).toLowerCase()}',
  };
  final d5Ids = {
    for (final key in d5Principles) 'ki_d4d5_$key',
    for (final role in roles)
      'ki_d4d5_case_port_release_${role.substring(5).toLowerCase()}',
  };

  test('D4/D5 facts are source-linked, unverified and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(18));
    expect(itemIds, {...d4Ids, ...d5Ids});
    final citations = dataset.knowledgeItemCitations
        .map((citation) => citation.knowledgeItemId)
        .toSet();
    for (final item in items) {
      expect(item.domainId, 'winemaking', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(citations, contains(item.id), reason: item.id);
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
      expect(mappings.single.importance, 'core', reason: item.id);
      expect(
        mappings.single.minimumDepth,
        greaterThanOrEqualTo(3),
        reason: item.id,
      );
    }

    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = scope.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d4 = diploma.units.singleWhere((unit) => unit.id == 'D4');
    final d5 = diploma.units.singleWhere((unit) => unit.id == 'D5');
    expect(d4.itemIds.toSet().intersection(itemIds), d4Ids);
    expect(d5.itemIds.toSet().intersection(itemIds), d5Ids);
    expect(d4.regionRoots, contains('n_geo_cremant_de_bourgogne'));
    expect(d4.regionRoots, contains('n_geo_cremant_de_loire'));
    expect(d4.regionRoots, contains('n_geo_saumur'));
    expect(diploma.curriculumComplete, isFalse);
  });

  test('product comparisons are routed to their D4 and D5 objectives', () {
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final objective in scope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    const expected = {
      'wset_l4.sparkling.france': [
        'n_d4d5_principle_bourgogne_base',
        'n_d4d5_principle_saumur_bottle',
      ],
      'wset_l4.sparkling.italy': [
        'n_d4d5_principle_trento_riserva',
        'n_d4d5_principle_sorbara_dry',
        'n_d4d5_principle_grasparossa_body',
        'n_d4d5_case_italian_list',
      ],
      'wset_l4.fortified.sherry': [
        'n_d4d5_principle_palo_route',
        'n_d4d5_principle_palo_dry',
      ],
      'wset_l4.fortified.port': [
        'n_d4d5_principle_lbv_vintage',
        'n_d4d5_principle_colheita_cask',
        'n_d4d5_principle_white_port_age',
        'n_d4d5_case_port_release',
      ],
    };
    for (final entry in expected.entries) {
      expect(
        objectives[entry.key]!.covers!.within,
        containsAll(entry.value),
        reason: entry.key,
      );
    }
  });

  test('ten choices use cited answers without a position or length cue', () {
    expect(template.mode, 'authored_choice');
    expect(choices.keys.toSet(), {
      for (final key in {...d4Principles, ...d5Principles}) 'ki_d4d5_$key',
    });
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final indexCounts = List<int>.filled(4, 0);
    final lengthRanks = List<int>.filled(4, 0);
    for (final entry in choices.entries) {
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List).cast<String>();
      expect(options, hasLength(4), reason: entry.key);
      expect(
        options.map((option) => option.toLowerCase().trim()).toSet(),
        hasLength(4),
        reason: entry.key,
      );
      final correct = choice['correctIndex'] as int;
      expect(correct, inInclusiveRange(0, 3), reason: entry.key);
      indexCounts[correct]++;
      lengthRanks[options
          .where((option) => option.length < options[correct].length)
          .length]++;
      expect(choice['prompt'], isNotEmpty, reason: entry.key);
      expect(choice['explanation'], isNotEmpty, reason: entry.key);
      expect(
        citationPairs.contains((entry.key, choice['sourceCitationId'])),
        isTrue,
        reason: entry.key,
      );
    }
    expect(indexCounts, [3, 3, 2, 2]);
    expect(lengthRanks, [2, 3, 3, 2]);
  });

  test('Italian and Port cases retain complete four-role written rubrics', () {
    final criteriaTemplate = dataset.questionTemplates.singleWhere(
      (template) => template.id == 'qt_d4d5_case_criteria',
    );
    expect(criteriaTemplate.mode, CaseCriteriaFormat.formatId);
    expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), {
      'n_d4d5_case_italian_list',
      'n_d4d5_case_port_release',
    });
    final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
    for (final key in ['italian_list', 'port_release']) {
      final subject = 'n_d4d5_case_$key';
      expect(distractors[subject], hasLength(2));
      for (final distractor in distractors[subject]!) {
        expect(distractor.summary.length, greaterThan(35));
        expect(distractor.explanation!.length, greaterThan(45));
      }
      final caseTemplate = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d4d5_case_$key',
      );
      expect(caseTemplate.mode, 'short_answer');
      final params =
          jsonDecode(caseTemplate.parameters!) as Map<String, dynamic>;
      expect(params['scope_node_ids'], [subject]);
      expect(
        (params['key_points'] as Map<String, dynamic>).keys.toSet(),
        roles,
      );
      final points = items.where((item) => item.subjectId == subject).toList();
      expect(points, hasLength(4));
      expect(points.map((item) => item.relationType).toSet(), roles);
    }
  });

  test(
    'ingestion serves ten choices and two complete interactive cases',
    () async {
      final db = openTestDatabase();
      try {
        final generation = await CurriculumIngester(db).ingest(dataset);
        final questions = await db.select(db.questions).get();
        expect(
          questions.where(
            (question) => question.questionTemplateId == template.id,
          ),
          hasLength(10),
        );
        final pools = await db.select(db.exercisePools).get();
        expect(
          pools.where(
            (pool) => pool.questionTemplateId == 'qt_d4d5_case_criteria',
          ),
          hasLength(2),
        );
        final members = await db.select(db.exercisePoolItems).get();
        for (final key in ['italian_list', 'port_release']) {
          expect(
            pools.where(
              (pool) => pool.questionTemplateId == 'qt_d4d5_case_$key',
            ),
            hasLength(1),
            reason: key,
          );
          final criteriaPool = pools.singleWhere(
            (pool) =>
                pool.questionTemplateId == 'qt_d4d5_case_criteria' &&
                pool.scopeNodeId == 'n_d4d5_case_$key',
          );
          expect(
            members.where((member) => member.exercisePoolId == criteriaPool.id),
            hasLength(4),
            reason: key,
          );
        }
        final exercise = await ExercisePresenter(db).present(
          'ki_d4d5_case_port_release_action',
          'qt_d4d5_case_criteria',
          seed: 7,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds, hasLength(4));
        expect(exercise.options, hasLength(6));
        expect(
          exercise.criteria.map((criterion) => criterion.role).toSet(),
          roles,
        );
        expect(
          exercise.criteria.every((criterion) => criterion.sources.isNotEmpty),
          isTrue,
        );

        const path = 'assets/curriculum/coverage_policy.yaml';
        final report = await CoverageChecker(
          db,
          CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
        ).check('WSET_L4', on: '2026-09-29', skipped: generation.skipped);
        final added = report.items.where((item) => itemIds.contains(item.id));
        expect(added, hasLength(18));
        for (final item in added) {
          expect(item.hasUsefulPractice, isTrue, reason: item.id);
        }
      } finally {
        await db.close();
      }
    },
  );
}
