import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
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
      .where((item) => item.id.startsWith('ki_d1method_'))
      .toList();
  const caseSubjects = {
    'qt_d1method_case_white': 'n_d1method_case_white',
    'qt_d1method_case_red': 'n_d1method_case_red',
  };
  const caseRoles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };

  test('source-bounded methods are cited and mapped only to Diploma', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(16));
    final sourceIds = {for (final source in dataset.sourceCitations) source.id};
    for (final item in items) {
      expect(item.domainId, 'winemaking', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final joins = dataset.knowledgeItemCitations
          .where((join) => join.knowledgeItemId == item.id)
          .toList();
      expect(joins, isNotEmpty, reason: item.id);
      for (final join in joins) {
        expect(sourceIds, contains(join.sourceCitationId), reason: item.id);
        expect(join.locator, isNotEmpty, reason: item.id);
      }
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
      expect(mappings.single.importance, 'core', reason: item.id);
      expect(mappings.single.minimumDepth, 3, reason: item.id);
    }
    for (final subject in caseSubjects.values) {
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

  test('cases and choices present cited Diploma decisions', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(db).ingest(dataset);
    final l4Items = {
      for (final card in await StudyPlanner(db).cards('WSET_L4')) card.itemId,
    };
    final l3Items = {
      for (final card in await StudyPlanner(db).cards('WSET_L3')) card.itemId,
    };
    expect(l4Items, containsAll(items.map((item) => item.id)));
    expect(l3Items.intersection(items.map((item) => item.id).toSet()), isEmpty);

    final presenter = ExercisePresenter(db);
    final criteriaTemplate = dataset.questionTemplates.singleWhere(
      (template) => template.id == 'qt_d1method_case_criteria',
    );
    expect(
      CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate),
      caseSubjects.values.toSet(),
    );
    expect(
      CaseCriteriaFormat.datasetProblems(criteriaTemplate, dataset),
      isEmpty,
    );
    for (final entry in caseSubjects.entries) {
      final action = items.singleWhere(
        (item) =>
            item.subjectId == entry.value && item.relationType == 'CASE_ACTION',
      );
      final exercise = await presenter.present(
        action.id,
        entry.key,
        seed: 31,
      ) as ShortAnswerExercise;
      expect(exercise.keyPoints, isNotEmpty);
      expect(
        exercise.keyPoints
            .map((point) => point.itemId)
            .toSet()
            .difference(
              items
                  .where((item) => item.subjectId == entry.value)
                  .map((item) => item.id)
                  .toSet(),
            ),
        isEmpty,
      );
      final matching = await presenter.present(
        action.id,
        'qt_d1method_case_criteria',
        seed: 31,
      ) as CaseCriteriaExercise;
      expect(matching.itemIds, hasLength(4));
      expect(matching.options, hasLength(6));
      expect(
        matching.criteria.map((criterion) => criterion.role).toSet(),
        caseRoles,
      );
      for (final criterion in matching.criteria) {
        expect(criterion.sources, isNotEmpty);
        expect(criterion.sources.first.url, startsWith('https://'));
      }
    }

    const expectedSources = {
      'ki_d1method_hyper': 'src_d1method_awri_hyper',
      'ki_d1method_hyper_risk': 'src_d1method_awri_hyper',
      'ki_d1method_flotation': 'src_d1method_awri_flotation',
      'ki_d1method_flotation_gas': 'src_d1method_awri_flotation',
      'ki_d1method_flash': 'src_d1method_awri_flash_mechanism',
      'ki_d1method_microox': 'src_d1method_oiv_microox',
      'ki_d1method_oak_pieces': 'src_d1method_oiv_oak',
      'ki_d1method_oak_compare': 'src_d1method_oiv_barrel',
    };
    final choiceTemplate = dataset.questionTemplates.singleWhere(
      (template) => template.id == 'qt_d1method_choices',
    );
    final choices =
        (jsonDecode(choiceTemplate.parameters!)
                as Map<String, dynamic>)['item_choices']
            as Map<String, dynamic>;
    final keyRanks = List<int>.filled(4, 0);
    final keyPositions = List<int>.filled(4, 0);
    for (final entry in expectedSources.entries) {
      final choice = await presenter.present(
        entry.key,
        'qt_d1method_choices',
        seed: 31,
      ) as AuthoredChoiceQuestion;
      expect(choice.options, hasLength(4), reason: entry.key);
      expect(choice.sourceCitationId, entry.value, reason: entry.key);
      final data = choices[entry.key] as Map<String, dynamic>;
      final options = (data['options'] as List<dynamic>).cast<String>();
      final index = data['correctIndex'] as int;
      expect(choice.answer.name, options[index], reason: entry.key);
      keyPositions[index]++;
      keyRanks[options
          .where((option) => option.length < options[index].length)
          .length]++;
    }
    expect(keyPositions, [2, 2, 2, 2]);
    expect(keyRanks, [2, 2, 2, 2]);
  });
}
