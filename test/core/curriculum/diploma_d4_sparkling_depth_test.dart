import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d4depth_'))
      .toList();
  final template = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d4depth_regional_choices',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test(
    '24 D4 principles and 16 case points are cited, bounded and unverified',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(items, hasLength(40));
      expect(choices, hasLength(24));
      final ids = items.map((item) => item.id).toSet();
      expect(ids, hasLength(40));
      for (final item in items) {
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        expect(item.domainId, 'winemaking', reason: item.id);
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) => citation.knowledgeItemId == item.id,
          ),
          isTrue,
          reason: item.id,
        );
        final mappings = dataset.certificationKnowledgeMappings.where(
          (mapping) => mapping.knowledgeItemId == item.id,
        );
        expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
          'WSET_L4',
        }, reason: item.id);
        expect(mappings.single.importance, 'core', reason: item.id);
        expect(
          mappings.single.minimumDepth,
          greaterThanOrEqualTo(3),
          reason: item.id,
        );
      }
    },
  );

  test(
    'every authored answer has four distinct options and its own citation',
    () {
      expect(template.mode, 'authored_choice');
      final citationPairs = {
        for (final citation in dataset.knowledgeItemCitations)
          (citation.knowledgeItemId, citation.sourceCitationId),
      };
      for (final entry in choices.entries) {
        final cue = entry.value as Map<String, dynamic>;
        final options = cue['options'] as List<dynamic>;
        expect(options, hasLength(4), reason: entry.key);
        expect(options.toSet(), hasLength(4), reason: entry.key);
        expect(cue['correctIndex'], inInclusiveRange(0, 3), reason: entry.key);
        expect(
          citationPairs.contains((entry.key, cue['sourceCitationId'])),
          isTrue,
          reason: entry.key,
        );
        expect(entry.key, startsWith('ki_d4depth_'));
      }
    },
  );

  test('four written decisions have complete same-premise rubrics', () {
    final nodesById = {
      for (final node in dataset.knowledgeNodes) node.id: node,
    };
    final templates = dataset.questionTemplates
        .where((template) => template.id.startsWith('qt_d4depth_case_'))
        .toList();
    expect(templates, hasLength(4));
    for (final template in templates) {
      expect(template.mode, 'short_answer');
      final params = jsonDecode(template.parameters!) as Map<String, dynamic>;
      final subject =
          (params['scope_node_ids'] as List<dynamic>).single as String;
      final rubric = params['key_points'] as Map<String, dynamic>;
      expect(template.promptTemplate, nodesById[subject]!.name);
      expect(rubric.keys.toSet(), {
        'CASE_ACTION',
        'CASE_REASON',
        'CASE_TRADEOFF',
        'CASE_LIMITATION',
      });
      final points = items.where((item) => item.subjectId == subject).toList();
      expect(points, hasLength(4));
      expect(
        points.map((item) => item.relationType).toSet(),
        rubric.keys.toSet(),
      );
    }
  });

  test(
    'ingestion builds 24 choices and four fixed short-answer pools',
    () async {
      final db = openTestDatabase();
      try {
        await CurriculumIngester(db).ingest(dataset);
        final questions = await db.select(db.questions).get();
        expect(
          questions.where(
            (question) => question.questionTemplateId == template.id,
          ),
          hasLength(24),
        );
        final pools = await db.select(db.exercisePools).get();
        for (final caseTemplate in dataset.questionTemplates.where(
          (template) => template.id.startsWith('qt_d4depth_case_'),
        )) {
          expect(
            pools.where((pool) => pool.questionTemplateId == caseTemplate.id),
            hasLength(1),
            reason: caseTemplate.id,
          );
        }
      } finally {
        await db.close();
      }
    },
  );

  test('new content routes to D4 only and leaves Diploma incomplete', () {
    final progress = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = progress.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final itemIds = items.map((item) => item.id).toSet();
    expect(
      diploma.units.singleWhere((unit) => unit.id == 'D4').itemIds.toSet(),
      containsAll(itemIds),
    );
    for (final unit in diploma.units.where((unit) => unit.id != 'D4')) {
      expect(unit.itemIds.toSet().intersection(itemIds), isEmpty);
    }
    expect(diploma.curriculumComplete, isFalse);

    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    for (final track in scope.tracks.values.where(
      (track) => track.trackId != 'WSET_L4',
    )) {
      for (final objective in track.objectives) {
        expect(
          objective.covers?.within.where((id) => id.startsWith('n_d4depth_')) ??
              const <String>[],
          isEmpty,
          reason: '${track.trackId}: ${objective.id}',
        );
      }
    }
    final objectives = {
      for (final objective in scope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    for (final entry in {
      'wset_l4.sparkling.france': 'n_d4depth_case_champagne_house',
      'wset_l4.sparkling.spain': 'n_d4depth_case_cava_upgrade',
      'wset_l4.sparkling.italy': 'n_d4depth_case_rive_offer',
      'wset_l4.sparkling.britain': 'n_d4depth_case_british_frost',
    }.entries) {
      expect(objectives[entry.key]!.covers!.within, contains(entry.value));
    }
  });
}
