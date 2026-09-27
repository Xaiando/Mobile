import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

const cueId = 'qt_test_point_cue';
const pointId = 'ki_test_cooling_point';

Map<String, dynamic> cueReferenceFixture() {
  final data = copyOf(minimalDataset());
  rowsOf(
    data,
    'node_types',
  ).add({'id': 'learning_point', 'label': 'learning point'});
  rowsOf(data, 'relation_types').add({
    'id': 'PRINCIPLE_EXPLANATION',
    'label': 'explains',
    'reverse_label': 'is explained by',
    'cardinality': 'many',
    'default_domain_id': 'geography',
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'subject_node_type': 'appellation',
    'object_node_type': 'learning_point',
  });
  rowsOf(data, 'knowledge_nodes').add({
    'id': 'n_test_cooling_point',
    'node_type': 'learning_point',
    'name': 'Cooling can slow sugar accumulation',
  });
  rowsOf(data, 'knowledge_relations').add({
    'subject_id': 'n_geo_chablis',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_cooling_point',
    'valid_from': '1900-01-01',
  });
  rowsOf(data, 'knowledge_items').add({
    'id': pointId,
    'subject_id': 'n_geo_chablis',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_cooling_point',
    'domain_id': 'geography',
    'assertion_text':
        'Cooling can slow sugar accumulation in this supplied comparison.',
    'last_verified_at': '2026-01-01T00:00:00.000Z',
    'mcq_disabled': true,
  });
  rowsOf(
    data,
    'knowledge_item_citations',
  ).add({'knowledge_item_id': pointId, 'source_citation_id': 'src_test_law'});
  rowsOf(data, 'certification_knowledge_mappings').add({
    'certification_id': 'WSET_L2',
    'knowledge_item_id': pointId,
    'importance': 'core',
    'minimum_depth': 2,
  });
  rowsOf(data, 'question_templates').add({
    'id': cueId,
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'direction': 'forward',
    'mode': 'typed',
    'variant': 'point_scoped_cue',
    'prompt_template': '{subject.name}',
    'parameters': {
      'item_cues': {
        pointId: {
          'prompt':
              'What happens to sugar accumulation under the stated cooling?',
          'acceptedAnswers': ['slower sugar accumulation'],
        },
      },
    },
  });
  return data;
}

List<ValidationIssue> cueErrors(Map<String, dynamic> data) =>
    validateDataset(datasetOf(data)).errors
        .where((issue) => issue.rule == 'template-parameters')
        .toList();

void replaceCueTarget(Map<String, dynamic> data, String id) {
  final template = rowOf(data, 'question_templates', 'id', cueId);
  final parameters = template['parameters'] as Map<String, dynamic>;
  final cues = parameters['item_cues'] as Map<String, dynamic>;
  final cue = cues.remove(pointId);
  cues[id] = cue;
}

void main() {
  test('a real eligible point cue has no validation errors', () {
    final report = validateDataset(datasetOf(cueReferenceFixture()));
    expect(report.errors, isEmpty, reason: report.errors.join('\n'));
  });

  test('unknown cue item is rejected and located on its authored template', () {
    final data = cueReferenceFixture();
    replaceCueTarget(data, 'ki_missing_point');
    final issues = cueErrors(data);
    expect(
      issues.map((issue) => issue.message),
      contains(
        '$cueId: item_cues names ki_missing_point, which is no knowledge item',
      ),
    );
    expect(issues.single.row?.section, 'question_templates');
  });

  test('an existing legal grape fact cannot masquerade as a principle target', () {
    final data = cueReferenceFixture();
    replaceCueTarget(data, 'ki_chablis_grape');
    expect(
      cueErrors(data).map((issue) => issue.message),
      contains(
        '$cueId: item_cues names ki_chablis_grape, which is not an eligible forward PRINCIPLE_EXPLANATION item',
      ),
    );
  });

  test('cue targets must match an allowed subject-answer signature', () {
    final data = cueReferenceFixture();
    rowOf(data, 'knowledge_nodes', 'id', 'n_test_cooling_point')['node_type'] =
        'grape';
    expect(
      cueErrors(data).map((issue) => issue.message),
      contains(
        '$cueId: item_cues names $pointId, whose appellation -> grape signature is not allowed',
      ),
    );
    expect(
      validateDataset(datasetOf(data)).errors.map((issue) => issue.rule),
      contains('relation-signature'),
      reason: 'the underlying graph remains invalid too',
    );
  });

  test('missing cue endpoint and supporting relation are explicit errors', () {
    final missingNode = cueReferenceFixture();
    rowOf(missingNode, 'knowledge_items', 'id', pointId)['object_id'] =
        'n_missing';
    expect(
      cueErrors(missingNode).map((issue) => issue.message),
      contains(
        '$cueId: item_cues names $pointId with a missing subject or answer node',
      ),
    );
    final missingRelation = cueReferenceFixture();
    rowsOf(missingRelation, 'knowledge_relations').removeWhere(
      (row) =>
          (row as Map<String, dynamic>)['relation_type'] ==
          'PRINCIPLE_EXPLANATION',
    );
    expect(
      cueErrors(missingRelation).map((issue) => issue.message),
      contains(
        '$cueId: item_cues names $pointId, which has no supporting relation',
      ),
    );
  });

  test('reverse cues fail eligibility rather than bypassing the forward target rule', () {
    final data = cueReferenceFixture();
    rowOf(data, 'question_templates', 'id', cueId)['direction'] = 'reverse';
    expect(
      cueErrors(data).map((issue) => issue.message),
      contains('$cueId: item_cues need forward PRINCIPLE_EXPLANATION'),
    );
  });

  test('retired supporting relations remain valid references for preserved history', () {
    final data = cueReferenceFixture();
    final relation = rowsOf(data, 'knowledge_relations')
        .cast<Map<String, dynamic>>()
        .singleWhere((row) => row['relation_type'] == 'PRINCIPLE_EXPLANATION');
    relation['valid_until'] = '2026-01-01';
    expect(
      cueErrors(data),
      isEmpty,
      reason: 'currentness is a separate generation/presentation gate, not an unknown reference',
    );
  });
}
