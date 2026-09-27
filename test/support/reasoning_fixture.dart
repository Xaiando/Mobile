import 'package:drift/drift.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/database/app_database.dart';

import 'curriculum_fixture.dart';

const reasoningTwoTemplateId = 'qt_reason_two';
const reasoningThreeTemplateId = 'qt_reason_three';
const reasoningTwoTargetId = 'ki_reason_two_2';
const reasoningThreeTargetId = 'ki_reason_three_3';
const reasoningTwoChain = ['ki_reason_two_1', 'ki_reason_two_2'];
const reasoningThreeChain = [
  'ki_reason_three_1',
  'ki_reason_three_2',
  'ki_reason_three_3',
];
const reasoningSupportIds = [
  'ki_reason_two_1',
  'ki_reason_three_1',
  'ki_reason_three_2',
];
const reasoningFixtureDate = '2026-01-01';

/// Synthetic mechanisms and citations for engine tests, never bundled facts.
Map<String, dynamic> reasoningDatasetMap() {
  final data = copyOf(minimalDataset());
  rowsOf(data, 'certifications').add({
    'id': 'WSET_L4',
    'organization': 'WSET',
    'level': 4,
    'display_name': 'WSET Level 4 fixture',
    'is_selectable': true,
  });
  rowsOf(
    data,
    'node_types',
  ).add({'id': 'causal_state', 'label': 'causal test state'});
  for (final type in ['CAUSES_STATE', 'LEADS_TO', 'CONTRADICTS']) {
    rowsOf(data, 'relation_types').add({
      'id': type,
      'label': type.toLowerCase(),
      'reverse_label': 'reverse ${type.toLowerCase()}',
      'cardinality': 'many',
      'default_domain_id': 'viticulture',
    });
    rowsOf(data, 'relation_type_signatures').add({
      'relation_type': type,
      'subject_node_type': 'causal_state',
      'object_node_type': 'causal_state',
    });
    rowsOf(data, 'question_templates').add({
      'id': 'qt_reason_${type.toLowerCase()}_flashcard',
      'relation_type': type,
      'direction': 'forward',
      'mode': 'flashcard',
      'prompt_template': 'What follows from {subject.name}?',
    });
  }
  rowsOf(data, 'source_citations').add({
    'id': 'src_reason_fixture',
    'kind': 'reference_work',
    'title': 'Synthetic mechanism source',
    'publisher': 'Fixture publisher',
    'url': 'https://example.invalid/reasoning-fixture',
    'accessed_on': reasoningFixtureDate,
  });
  for (final (suffix, length) in [('two', 2), ('three', 3)]) {
    final start = 'n_reason_${suffix}_0',
        target = 'ki_reason_${suffix}_$length';
    for (var index = 0; index <= length; index++) {
      rowsOf(data, 'knowledge_nodes').add({
        'id': 'n_reason_${suffix}_$index',
        'node_type': 'causal_state',
        'name': index == 0
            ? '$suffix supplied starting conditions'
            : '$suffix consequence $index',
      });
    }
    void edge(
      String id,
      String subject,
      String type,
      String object,
      String assertion, {
      int? depth,
    }) {
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': subject,
        'relation_type': type,
        'object_id': object,
        'valid_from': '2020-01-01',
      });
      rowsOf(data, 'knowledge_items').add({
        'id': id,
        'subject_id': subject,
        'relation_type': type,
        'object_id': object,
        'domain_id': 'viticulture',
        'assertion_text': assertion,
        'mcq_disabled': true,
        'last_verified_at': '2026-01-01T00:00:00.000Z',
      });
      rowsOf(data, 'knowledge_item_citations').add({
        'knowledge_item_id': id,
        'source_citation_id': 'src_reason_fixture',
        'locator': 'Fixture paragraph $id',
      });
      if (depth != null) {
        rowsOf(data, 'certification_knowledge_mappings').add({
          'certification_id': 'WSET_L4',
          'knowledge_item_id': id,
          'importance': 'core',
          'minimum_depth': depth,
        });
      }
    }

    for (var index = 1; index <= length; index++) {
      edge(
        'ki_reason_${suffix}_$index',
        'n_reason_${suffix}_${index - 1}',
        index == 1 ? 'CAUSES_STATE' : 'LEADS_TO',
        'n_reason_${suffix}_$index',
        '$suffix step $index is supported under the supplied conditions.',
        depth: index == length ? 4 : 3,
      );
    }
    final contrasts = <Map<String, dynamic>>[];
    for (var wrong = 1; wrong <= 3; wrong++) {
      final node = 'n_reason_${suffix}_wrong_$wrong',
          evidence = 'ki_reason_${suffix}_contrast_$wrong';
      rowsOf(data, 'knowledge_nodes').add({
        'id': node,
        'node_type': 'causal_state',
        'name': '$suffix contradictory alternative $wrong',
      });
      edge(
        evidence,
        start,
        'CONTRADICTS',
        node,
        'Under $suffix supplied conditions, alternative $wrong is contradicted.',
      );
      rowsOf(data, 'certification_knowledge_mappings').add({
        'certification_id': 'WSET_L4',
        'knowledge_item_id': evidence,
        'importance': 'secondary',
        'minimum_depth': 2,
      });
      contrasts.add({
        'option_node_id': node,
        'evidence_item_ids': [evidence],
        'explanation':
            'Alternative $wrong contradicts the stated $suffix conditions.',
      });
    }
    rowsOf(data, 'question_templates').add({
      'id': 'qt_reason_$suffix',
      'relation_type': 'LEADS_TO',
      'direction': 'forward',
      'mode': 'reasoning',
      'variant': suffix,
      'prompt_template': 'Given {subject.name}, which conclusion follows?',
      'parameters': {
        'path_relation_types': [
          'CAUSES_STATE',
          for (var i = 1; i < length; i++) 'LEADS_TO',
        ],
        'scope_node_ids': [start],
        'contrasts': {
          target: {start: contrasts},
        },
      },
    });
  }
  return data;
}

CurriculumDataset reasoningDataset() => datasetOf(reasoningDatasetMap());

/// Presenters/planners require each supporting assessed item to be studied.
Future<void> studyReasoningSupports(
  AppDatabase db, {
  Iterable<String> itemIds = reasoningSupportIds,
}) async {
  for (final id in itemIds) {
    await db
        .into(db.reviewStates)
        .insertOnConflictUpdate(
          ReviewStatesCompanion.insert(
            knowledgeItemId: id,
            state: 2,
            stability: 30,
            difficulty: 5,
            due: DateTime.utc(2026, 1, 3),
            lastReview: DateTime.utc(2026, 1, 1),
            reps: 1,
            step: const Value(null),
          ),
        );
  }
}
