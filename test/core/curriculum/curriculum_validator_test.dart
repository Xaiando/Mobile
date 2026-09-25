import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

/// The rules [data] breaks.
Set<String> brokenRules(Map<String, dynamic> data) => {
  for (final issue in validateDataset(
    CurriculumDataset.parse(datasetText(data)),
  ).errors)
    issue.rule,
};

void main() {
  test('the bundled dataset passes every rule (TASK-010)', () {
    final report = validateDataset(bundledDataset());
    expect(report.errors, isEmpty, reason: report.errors.join('\n'));
    expect(
      report.warnings.map((w) => w.rule),
      containsAll(['uncurated-date', 'structural-relation', 'unverified']),
    );
  });

  test('the minimal fixture is valid', () {
    expect(brokenRules(minimalDataset()), isEmpty);
  });

  group('rejects', () {
    test('a relation to a node that does not exist (§S.1)', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_geo_chablis',
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_nowhere',
        'valid_from': '1900-01-01',
      });
      expect(brokenRules(data), contains('dangling-relation'));
    });

    test('a prerequisite cycle of any length (§S.2)', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_item_prerequisites').add({
        'knowledge_item_id': 'ki_chablis_grape',
        'prerequisite_item_id': 'ki_volnay_grape',
      });
      expect(brokenRules(data), contains('cycle'));
    });

    test('an item that is its own prerequisite (§S.2)', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_item_prerequisites').add({
        'knowledge_item_id': 'ki_chablis_grape',
        'prerequisite_item_id': 'ki_chablis_grape',
      });
      expect(brokenRules(data), contains('self-reference'));
    });

    test('a containment cycle', () {
      final data = minimalDataset();
      rowsOf(data, 'relation_type_signatures').add({
        'relation_type': 'LOCATED_IN',
        'subject_node_type': 'region',
        'object_node_type': 'appellation',
      });
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_geo_burgundy',
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_chablis',
        'valid_from': '1900-01-01',
      });
      expect(brokenRules(data), contains('cycle'));
    });

    test('an item asserting something that is not a relation', () {
      final data = minimalDataset();
      rowOf(data, 'knowledge_items', 'id', 'ki_chablis_grape')['object_id'] =
          'n_grape_pinot_noir';
      expect(brokenRules(data), contains('item-relation'));
    });

    test('a relation between node types its type does not allow', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_grape_chardonnay',
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_burgundy',
        'valid_from': '1900-01-01',
      });
      expect(brokenRules(data), contains('relation-signature'));
    });

    test('two values of a one-valued relation in force at once', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_grape_chardonnay',
        'relation_type': 'HAS_BERRY_COLOUR',
        'object_id': 'n_colour_black',
        'valid_from': '2000-01-01',
      });
      expect(brokenRules(data), contains('cardinality-one'));
    });

    test('a certification chain across organizations or levels', () {
      final data = minimalDataset();
      rowsOf(data, 'certifications').add({
        'id': 'CMS_CERTIFIED',
        'organization': 'CMS',
        'level': 2,
        'display_name': 'CMS Certified',
        'includes_certification_id': 'WSET_L2',
      });
      expect(brokenRules(data), contains('certification-chain'));
    });

    test('an item without a citation', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_item_citations').removeAt(0);
      expect(brokenRules(data), contains('item-citation'));
    });

    test('wine law cited only from a reference work (PR-3)', () {
      final data = minimalDataset();
      rowOf(data, 'source_citations', 'id', 'src_test_law')['kind'] =
          'reference_work';
      expect(brokenRules(data), contains('regulatory-citation'));
    });

    test('an item mapped to no certification', () {
      final data = minimalDataset();
      rowsOf(data, 'certification_knowledge_mappings').removeAt(0);
      expect(brokenRules(data), contains('item-mapping'));
    });

    test('near-duplicate names of one node type', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_nodes').add({
        'id': 'n_geo_chablis_aoc',
        'node_type': 'appellation',
        'name': 'CHABLIS AOC',
      });
      expect(brokenRules(data), contains('name-norm'));
    });

    test('a template placeholder that does not exist', () {
      final data = minimalDataset();
      rowOf(
        data,
        'question_templates',
        'id',
        'qt_principal_grape_fwd_mcq',
      )['prompt_template'] = 'Which grape grows in {subject.region}?';
      expect(brokenRules(data), contains('template-placeholder'));
    });

    test('a relation type with items but no forward template', () {
      final data = minimalDataset();
      rowsOf(data, 'question_templates').clear();
      expect(brokenRules(data), contains('template-coverage'));
    });

    test('duplicate values, bad ID prefixes and unknown references', () {
      final data = minimalDataset();
      rowsOf(data, 'knowledge_nodes').add(_node('geo_x', 'region', 'X'));
      // A key written twice fails parsing; other unique columns are the
      // validator's.
      rowsOf(
        data,
        'curriculum_domains',
      ).add({'id': 'history', 'display_name': 'History', 'position': 1});
      rowOf(data, 'knowledge_items', 'id', 'ki_volnay_grape')['domain_id'] =
          'oenology';
      expect(
        brokenRules(data),
        containsAll(['id-format', 'duplicate-key', 'unknown-reference']),
      );
    });

    test('a quantity node without a value', () {
      final data = minimalDataset();
      rowsOf(data, 'node_types').add({'id': 'quantity', 'label': 'quantity'});
      rowsOf(data, 'knowledge_nodes').add(_node('n_qty_x', 'quantity', 'X'));
      expect(brokenRules(data), contains('quantity'));
    });
  });

  group('schema v2 (F2)', () {
    test('the fixture with one row of each v2 kind is valid', () {
      expect(brokenRules(v2Dataset()), isEmpty);
    });

    test('rejects a symmetric pair stored the wrong way round', () {
      final data = v2Dataset();
      rowOf(data, 'knowledge_relations', 'relation_type', 'BORDERS')
        ..['subject_id'] = 'n_geo_volnay'
        ..['object_id'] = 'n_geo_pommard';
      expect(brokenRules(data), {'symmetric-relation'});
    });

    test('rejects a symmetric relation type allowed one way only', () {
      final data = v2Dataset();
      rowsOf(data, 'relation_type_signatures').add({
        'relation_type': 'BORDERS',
        'subject_node_type': 'appellation',
        'object_node_type': 'region',
      });
      expect(brokenRules(data), {'symmetric-relation'});
    });

    test('rejects a completeness assertion with no members', () {
      final data = v2Dataset();
      rowOf(
        data,
        'relation_set_assertions',
        'node_id',
        'n_geo_chablis',
      )['node_id'] = 'n_geo_burgundy';
      expect(brokenRules(data), containsAll(['assertion-members']));
    });

    test('rejects a complete set without a member on some date it '
        'covers', () {
      Map<String, dynamic> chardonnay(Map<String, dynamic> data) =>
          rowOf(data, 'knowledge_relations', 'object_id', 'n_grape_chardonnay');

      final lapsing = v2Dataset();
      chardonnay(lapsing)['valid_until'] = '2000-01-01';
      final lapsed = validateDataset(datasetOf(lapsing)).errors.single;
      expect(lapsed.rule, 'assertion-members');
      expect(lapsed.message, endsWith('is in force on 2000-01-01'));

      final expired = v2Dataset();
      chardonnay(expired)['valid_until'] = '1930-01-01';
      expect(
        validateDataset(datasetOf(expired)).errors.single.message,
        endsWith('is in force on 1938-01-13'),
        reason: 'the assertion starts after its only member ended',
      );
    });

    test('firstGap finds the first date no period covers', () {
      expect(firstGap('2000-01-01', null, [('1990-01-01', null)]), isNull);
      expect(
        firstGap('2000-01-01', '2010-01-01', [
          ('1999-01-01', '2005-01-01'),
          ('2005-01-01', '2010-01-01'),
        ]),
        isNull,
      );
      expect(
        firstGap('2000-01-01', null, [
          ('2000-01-01', '2005-01-01'),
          ('2006-01-01', null),
        ]),
        '2005-01-01',
      );
      expect(firstGap('2000-01-01', null, const []), '2000-01-01');
    });

    test('rejects a completeness assertion its relation type does not '
        'allow', () {
      final data = v2Dataset();
      rowOf(
        data,
        'relation_set_assertions',
        'node_id',
        'n_geo_chablis',
      )['member_node_type'] = 'berry_colour';
      expect(
        brokenRules(data),
        containsAll(['assertion-signature', 'assertion-members']),
      );
    });

    test('rejects a reverse assertion of a symmetric set', () {
      final data = v2Dataset();
      rowsOf(data, 'relation_set_assertions').add({
        'node_id': 'n_geo_volnay',
        'relation_type': 'BORDERS',
        'direction': 'reverse',
        'member_node_type': 'appellation',
        'valid_from': '1937-01-01',
        'source_citation_id': 'src_test_law',
      });
      expect(brokenRules(data), {'assertion-direction'});
    });

    test('rejects a complete set of wine law cited from a reference work', () {
      final data = v2Dataset();
      rowsOf(data, 'source_citations').add({
        'id': 'src_test_atlas',
        'kind': 'reference_work',
        'title': 'A test atlas',
        'publisher': 'Test publisher',
        'accessed_on': '2026-01-01',
      });
      rowOf(
        data,
        'relation_set_assertions',
        'node_id',
        'n_geo_chablis',
      )['source_citation_id'] = 'src_test_atlas';
      expect(brokenRules(data), {'regulatory-citation'});
    });

    test('rejects a map layer that cites no licensed dataset', () {
      final uncited = v2Dataset();
      rowsOf(uncited, 'map_layer_citations').clear();
      expect(brokenRules(uncited), {'layer-citation'});

      final unlicensed = v2Dataset();
      rowOf(unlicensed, 'source_citations', 'id', 'src_test_boundaries')
        ..remove('license')
        ..['kind'] = 'reference_work';
      expect(brokenRules(unlicensed), {'layer-citation'});
    });

    test('rejects unknown references and cycles in the map data', () {
      final data = v2Dataset();
      rowOf(
        data,
        'map_layers',
        'id',
        'ml_test_appellations',
      )['parent_layer_id'] = 'ml_test_appellations';
      rowOf(
        data,
        'node_geometries',
        'map_layer_id',
        'ml_test_appellations',
      )['knowledge_node_id'] = 'n_geo_nowhere';
      expect(brokenRules(data), containsAll(['cycle', 'unknown-reference']));
    });

    test('rejects a template of a format that does not exist (QF-2)', () {
      final data = v2Dataset();
      rowOf(
        data,
        'question_templates',
        'id',
        'qt_principal_grape_fwd_flashcard',
      )['mode'] = 'multiple_response';
      expect(brokenRules(data), {'template-format'});
    });

    test('rejects a pack with an examining body, and a certification '
        'without a level or including a pack', () {
      final data = v2Dataset();
      rowOf(data, 'certifications', 'id', 'BURGUNDY_PACK')
        ..['level'] = 1
        ..['includes_certification_id'] = 'WSET_L1';
      rowOf(data, 'certifications', 'id', 'WSET_L1').remove('level');
      rowOf(
        data,
        'certifications',
        'id',
        'WSET_L2',
      )['includes_certification_id'] = 'BURGUNDY_PACK';
      final broken = validateDataset(datasetOf(data)).errors;
      expect(
        broken.map((e) => e.message),
        unorderedEquals([
          'pack BURGUNDY_PACK has an organization or a level; a pack has '
              'neither',
          'certification WSET_L1 needs an organization and a level',
          'WSET_L2 includes the pack BURGUNDY_PACK',
        ]),
      );
    });
  });

  test('allows a fact that changes over time without overlap', () {
    final data = minimalDataset();
    rowOf(
      data,
      'knowledge_relations',
      'object_id',
      'n_colour_white',
    )['valid_until'] = '2000-01-01';
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': 'n_grape_chardonnay',
      'relation_type': 'HAS_BERRY_COLOUR',
      'object_id': 'n_colour_black',
      'valid_from': '2000-01-01',
    });
    expect(brokenRules(data), isEmpty);
  });

  test('findCycle returns the path of a cycle', () {
    expect(
      findCycle({
        'a': ['b'],
        'b': ['c'],
        'c': ['a'],
      }),
      ['a', 'b', 'c', 'a'],
    );
    expect(
      findCycle({
        'a': ['b', 'c'],
        'b': ['c'],
      }),
      isNull,
    );
  });
}

Map<String, dynamic> _node(String id, String type, String name) => {
  'id': id,
  'node_type': type,
  'name': name,
};
