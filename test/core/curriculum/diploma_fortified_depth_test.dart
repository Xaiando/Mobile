import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d5f_'))
      .toList();
  final itemIds = items.map((item) => item.id).toSet();
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5f_authored_choice',
  );
  final choices =
      (jsonDecode(choiceTemplate.parameters!)
              as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;
  const caseKeys = ['port_offer', 'sherry_vos_stock', 'fortified_list'];
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };

  test('D5 facts are cited, review-pending and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(28));
    expect(
      items.where((item) => item.relationType == 'PRINCIPLE_EXPLANATION'),
      hasLength(16),
    );
    expect(
      items.where((item) => roles.contains(item.relationType)),
      hasLength(12),
    );
    for (final item in items) {
      expect(item.domainId, 'winemaking', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .map((mapping) => mapping.certificationId)
            .toSet(),
        {'WSET_L4'},
        reason: item.id,
      );
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isTrue,
        reason: item.id,
      );
    }
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = scope.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d5 = diploma.units.singleWhere((unit) => unit.id == 'D5');
    expect(d5.itemIds.toSet(), containsAll(itemIds));
    expect(diploma.curriculumComplete, isFalse);
  });

  test('all five D5 regional selectors include new teaching decisions', () {
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final objective in scope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    const subjects = {
      'wset_l4.fortified.port': 'n_d5f_principle_port_beneficio',
      'wset_l4.fortified.sherry': 'n_d5f_principle_sherry_vos',
      'wset_l4.fortified.madeira': 'n_d5f_principle_madeira_categories',
      'wset_l4.fortified.france': 'n_d5f_principle_vdn_banyuls_labour',
      'wset_l4.fortified.australia': 'n_d5f_principle_ruth_tiers',
    };
    for (final entry in subjects.entries) {
      expect(
        objectives[entry.key]!.covers!.within,
        contains(entry.value),
        reason: entry.key,
      );
    }
    for (final id in [
      'wset_l4.fortified.madeira',
      'wset_l4.fortified.france',
      'wset_l4.fortified.australia',
    ]) {
      expect(
        objectives[id]!.covers!.within,
        contains('n_d5f_case_fortified_list'),
      );
    }
  });

  test(
    'choice keys are distinct and balanced; cases have four points each',
    () {
      expect(choiceTemplate.mode, 'authored_choice');
      expect(choices.keys.toSet(), {
        for (final item in items)
          if (item.relationType == 'PRINCIPLE_EXPLANATION') item.id,
      });
      final indexCounts = List<int>.filled(4, 0);
      for (final entry in choices.entries) {
        final choice = entry.value as Map<String, dynamic>;
        final options = (choice['options'] as List).cast<String>();
        expect(options, hasLength(4), reason: entry.key);
        expect(
          options.map((text) => text.toLowerCase().trim()).toSet(),
          hasLength(4),
          reason: entry.key,
        );
        expect(choice['prompt'], isNotEmpty, reason: entry.key);
        expect(choice['explanation'], isNotEmpty, reason: entry.key);
        indexCounts[choice['correctIndex'] as int]++;
      }
      expect(indexCounts, [4, 4, 4, 4]);

      for (final key in caseKeys) {
        final subject = 'n_d5f_case_$key';
        final template = dataset.questionTemplates.singleWhere(
          (template) => template.id == 'qt_d5f_case_$key',
        );
        expect(template.mode, 'short_answer');
        expect(ShortAnswerFormat.scopeNodeIdsOf(template), [subject]);
        expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(), roles);
        expect(
          items
              .where((item) => item.subjectId == subject)
              .map((item) => item.relationType)
              .toSet(),
          roles,
        );
      }
      expect(
        dataset.questionTemplates
            .singleWhere(
              (template) => template.id == 'qt_d5f_case_sherry_vos_stock',
            )
            .promptTemplate,
        contains('1,500 L'),
      );
    },
  );

  test(
    'new choices and case pools are generated and served only at Level 4',
    () async {
      final db = openTestDatabase();
      try {
        await CurriculumIngester(db).ingest(dataset);
        final questions = await db.customSelect('''
        SELECT q.knowledge_item_id FROM questions q
        WHERE q.question_template_id = 'qt_d5f_authored_choice'
      ''').get();
        expect(
          questions.map((row) => row.read<String>('knowledge_item_id')).toSet(),
          choices.keys.toSet(),
        );
        for (final id in choices.keys) {
          final presented = await QuestionPresenter(db).questionsFor(id);
          expect(
            presented.map((question) => question.questionTemplateId),
            contains('qt_d5f_authored_choice'),
            reason: id,
          );
        }
        final pools = await db.select(db.exercisePools).get();
        final poolItems = await db.select(db.exercisePoolItems).get();
        for (final key in caseKeys) {
          final pool = pools.singleWhere(
            (row) => row.questionTemplateId == 'qt_d5f_case_$key',
          );
          expect(pool.scopeNodeId, 'n_d5f_case_$key');
          expect(
            poolItems
                .where((row) => row.exercisePoolId == pool.id)
                .map((row) => row.knowledgeItemId)
                .toSet(),
            items
                .where((item) => item.subjectId == pool.scopeNodeId)
                .map((item) => item.id)
                .toSet(),
          );
        }
        final planner = StudyPlanner(db);
        final diplomaCards = {
          for (final card in await planner.cards('WSET_L4')) card.itemId: card,
        };
        final l3Ids = {
          for (final card in await planner.cards('WSET_L3')) card.itemId,
        };
        final cmsIds = {
          for (final card in await planner.cards('CMS_CERTIFIED')) card.itemId,
        };
        expect(diplomaCards.keys.toSet(), containsAll(itemIds));
        expect(l3Ids.intersection(itemIds), isEmpty);
        expect(cmsIds.intersection(itemIds), isEmpty);
        for (final id in choices.keys) {
          expect(
            diplomaCards[id]!.formats.map((format) => format.mode),
            contains('authored_choice'),
            reason: id,
          );
        }
      } finally {
        await db.close();
      }
    },
  );
}
