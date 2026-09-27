import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

Map<String, dynamic> scopedFixture({Object? scope = const ['n_geo_chablis']}) {
  final data = copyOf(minimalDataset());
  for (final place in ['chablis', 'volnay']) {
    final id = 'ki_${place}_location';
    rowsOf(data, 'knowledge_items').add({
      'id': id,
      'subject_id': 'n_geo_$place',
      'relation_type': 'LOCATED_IN',
      'object_id': 'n_geo_burgundy',
      'domain_id': 'geography',
      'assertion_text': 'This test appellation lies in Burgundy.',
      'last_verified_at': '2026-01-01T00:00:00.000Z',
    });
    rowsOf(
      data,
      'knowledge_item_citations',
    ).add({'knowledge_item_id': id, 'source_citation_id': 'src_test_law'});
    rowsOf(data, 'certification_knowledge_mappings').add({
      'knowledge_item_id': id,
      'certification_id': 'WSET_L2',
      'importance': 'core',
      'minimum_depth': 2,
    });
  }
  for (final (id, scopeIds) in [('qt_scoped', scope), ('qt_unscoped', null)]) {
    rowsOf(data, 'question_templates').add({
      'id': id,
      'relation_type': 'LOCATED_IN',
      'direction': 'forward',
      'mode': 'short_answer',
      'variant': id,
      'prompt_template': 'Explain the grapes and location of {subject.name}.',
      'parameters': {
        'key_points': {
          'LOCATED_IN': 'Location',
          'PERMITS_PRINCIPAL_GRAPE': 'Grape',
        },
        if (id == 'qt_scoped') 'scope_node_ids': scopeIds,
      },
    });
  }
  return data;
}

void main() {
  test(
    'a case prompt cannot generate pools for other matching subjects',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await CurriculumIngester(db).ingest(datasetOf(scopedFixture()));
      final pools = await db.select(db.exercisePools).get();
      expect(
        pools
            .where((p) => p.questionTemplateId == 'qt_scoped')
            .map((p) => p.scopeNodeId),
        ['n_geo_chablis'],
      );
      expect(
        pools
            .where((p) => p.questionTemplateId == 'qt_unscoped')
            .map((p) => p.scopeNodeId),
        unorderedEquals(['n_geo_chablis', 'n_geo_volnay']),
        reason: 'general profiles retain their existing unscoped behaviour',
      );
    },
  );

  test(
    'malformed and empty scopes cannot silently create unrestricted cases',
    () {
      for (final scope in [
        null,
        'n_geo_chablis',
        <String>[],
        [''],
        [7],
        ['n_geo_chablis', 'n_geo_chablis'],
      ]) {
        final errors = validateDataset(datasetOf(scopedFixture(scope: scope)))
            .errors;
        expect(
          errors
              .where((e) => e.rule == 'template-parameters')
              .map((e) => e.message),
          contains(
            'qt_scoped: scope_node_ids must be a nonempty list of unique node IDs',
          ),
          reason: 'invalid scope: $scope',
        );
      }
    },
  );

  test('a scope must refer to an authored node', () {
    final errors = validateDataset(
      datasetOf(scopedFixture(scope: ['n_missing'])),
    ).errors;
    expect(
      errors
          .where((e) => e.rule == 'template-parameters')
          .map((e) => e.message),
      contains('qt_scoped: scope_node_ids names n_missing, which is no node'),
    );
  });

  test('a fixed scenario cannot be shared across multiple scoped subjects', () {
    final data = scopedFixture(scope: ['n_geo_chablis', 'n_geo_volnay']);
    final template = rowOf(data, 'question_templates', 'id', 'qt_scoped');
    expect(
      validateDataset(datasetOf(data)).errors,
      isEmpty,
      reason: 'the original prompt names its subject',
    );
    template['prompt_template'] =
        'A Chablis producer proposes an action. Explain it.';
    expect(
      validateDataset(datasetOf(data)).errors.map((e) => e.message),
      contains(
        'qt_scoped: a fixed short-answer prompt needs exactly one scope_node_id; multiple subjects need {subject.name}',
      ),
    );
    (template['parameters'] as Map<String, dynamic>)['scope_node_ids'] = [
      'n_geo_chablis',
    ];
    expect(validateDataset(datasetOf(data)).errors, isEmpty);
    (template['parameters'] as Map<String, dynamic>).remove('scope_node_ids');
    expect(
      validateDataset(datasetOf(data)).errors.map((e) => e.message),
      contains(
        'qt_scoped: a fixed short-answer prompt needs exactly one scope_node_id; multiple subjects need {subject.name}',
      ),
      reason:
          'a fixed scenario must not silently become an unrestricted profile',
    );
  });
}
