import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d3rt_regional_choice',
  );
  final choices =
      (jsonDecode(choiceTemplate.parameters!)
              as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;
  final caseItems = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d3rt_case_'))
      .toList();

  test('19 regional choices use cited facts in allowed templates', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choiceTemplate.mode, 'authored_choice');
    expect(choices, hasLength(19));
    final cited = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    const dualRoutedFacts = {
      'ki_reg_oa_adelaide_m3_sources',
      'ki_reg_sa_itata_grapes',
    };
    final templatesByItem = <String, List<String>>{};
    for (final template in dataset.questionTemplates.where(
      (template) => template.mode == 'authored_choice',
    )) {
      final parameters =
          jsonDecode(template.parameters!) as Map<String, dynamic>;
      for (final id
          in (parameters['item_choices'] as Map<String, dynamic>).keys) {
        (templatesByItem[id] ??= <String>[]).add(template.id);
      }
    }
    final itemsById = {
      for (final item in dataset.knowledgeItems) item.id: item,
    };
    for (final entry in choices.entries) {
      final id = entry.key;
      final choice = entry.value as Map<String, dynamic>;
      final item = itemsById[id]!;
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      expect(
        templatesByItem[id],
        unorderedEquals({
          'qt_d3rt_regional_choice',
          if (dualRoutedFacts.contains(id))
            'qt_d3_geography_principle_closure_24',
        }),
        reason: 'authored choices use only the allowed templates for $id',
      );
      expect(choice['options'], hasLength(4), reason: id);
      expect(
        (choice['options'] as List<dynamic>).toSet(),
        hasLength(4),
        reason: id,
      );
      expect(choice['correctIndex'], inInclusiveRange(0, 3), reason: id);
      expect(
        cited.contains((id, choice['sourceCitationId'])),
        isTrue,
        reason: id,
      );
      expect(
        dataset.certificationKnowledgeMappings.any(
          (mapping) =>
              mapping.certificationId == 'WSET_L4' &&
              mapping.knowledgeItemId == id &&
              mapping.importance == 'core' &&
              mapping.minimumDepth >= 3,
        ),
        isTrue,
        reason: id,
      );
    }
  });

  test('four written cases have full cited rubrics and exact prompts', () {
    expect(caseItems, hasLength(16));
    final nodesById = {
      for (final node in dataset.knowledgeNodes) node.id: node,
    };
    final caseTemplates = dataset.questionTemplates
        .where((template) => template.id.startsWith('qt_d3rt_case_'))
        .toList();
    expect(caseTemplates, hasLength(4));
    for (final template in caseTemplates) {
      expect(template.mode, 'short_answer');
      final parameters =
          jsonDecode(template.parameters!) as Map<String, dynamic>;
      final subject =
          (parameters['scope_node_ids'] as List<dynamic>).single as String;
      final rubric = parameters['key_points'] as Map<String, dynamic>;
      expect(template.promptTemplate, nodesById[subject]!.name);
      expect(rubric.keys.toSet(), {
        'CASE_ACTION',
        'CASE_REASON',
        'CASE_TRADEOFF',
        'CASE_LIMITATION',
      });
      final points = caseItems
          .where((item) => item.subjectId == subject)
          .toList();
      expect(
        points.map((item) => item.relationType).toSet(),
        rubric.keys.toSet(),
      );
      for (final item in points) {
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) => citation.knowledgeItemId == item.id,
          ),
          isTrue,
        );
        expect(
          dataset.certificationKnowledgeMappings
              .where((mapping) => mapping.knowledgeItemId == item.id)
              .map((mapping) => mapping.certificationId)
              .toSet(),
          {'WSET_L4'},
        );
      }
    }
  });

  test('ingestion generates 19 choices and four written-case pools', () async {
    final db = openTestDatabase();
    try {
      await CurriculumIngester(db).ingest(dataset);
      final questions = await db.select(db.questions).get();
      expect(
        questions
            .where(
              (question) =>
                  question.questionTemplateId == 'qt_d3rt_regional_choice',
            )
            .length,
        19,
      );
      final pools = await db.select(db.exercisePools).get();
      for (final template in dataset.questionTemplates.where(
        (template) => template.id.startsWith('qt_d3rt_case_'),
      )) {
        expect(
          pools.where((pool) => pool.questionTemplateId == template.id),
          hasLength(1),
          reason: template.id,
        );
      }
    } finally {
      await db.close();
    }
  });

  test('new case points route only to D3 and keep Diploma incomplete', () {
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = scope.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d3 = diploma.units.singleWhere((unit) => unit.id == 'D3');
    expect(d3.itemIds.toSet(), containsAll(caseItems.map((item) => item.id)));
    for (final unit in diploma.units.where((unit) => unit.id != 'D3')) {
      expect(
        unit.itemIds.toSet().intersection(
          caseItems.map((item) => item.id).toSet(),
        ),
        isEmpty,
      );
    }
    expect(diploma.curriculumComplete, isFalse);

    final trackScope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final objective in trackScope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    for (final entry in {
      'wset_l4.world.portugal': 'n_d3rt_case_bairrada_rain',
      'wset_l4.world.spain': 'n_d3rt_case_ribeira_offer',
      'wset_l4.world.australia': 'n_d3rt_case_margaret_blend',
      'wset_l4.world.new_zealand': 'n_d3rt_case_otago_frost',
    }.entries) {
      expect(objectives[entry.key]!.covers!.within, contains(entry.value));
      expect(
        objectives['wset_l4.world.comparison']!.covers!.within,
        contains(entry.value),
      );
    }
  });
}
