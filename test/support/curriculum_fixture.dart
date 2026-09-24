import 'dart:convert';
import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

/// The dataset bundled with the app.
String bundledDataset() => File(curriculumAssetPath).readAsStringSync();

/// A copy of [dataset] as dataset text. YAML is a superset of JSON.
String datasetText(Map<String, dynamic> dataset) => jsonEncode(dataset);

/// A deep copy, for tests that break one rule at a time.
Map<String, dynamic> copyOf(Map<String, dynamic> dataset) =>
    jsonDecode(jsonEncode(dataset)) as Map<String, dynamic>;

/// The rows of [section] in [dataset], for adding or changing rows.
List<dynamic> rowsOf(Map<String, dynamic> dataset, String section) =>
    dataset[section] as List<dynamic>;

/// The first row of [section] whose [key] equals [value].
Map<String, dynamic> rowOf(
  Map<String, dynamic> dataset,
  String section,
  String key,
  String value,
) => rowsOf(
  dataset,
  section,
).cast<Map<String, dynamic>>().firstWhere((row) => row[key] == value);

/// A small valid dataset: two Burgundy appellations and their grapes.
Map<String, dynamic> minimalDataset({String version = '1.0.0'}) => {
  'dataset_version': version,
  'published_at': '2026-01-01T00:00:00.000Z',
  'curriculum_domains': [
    {'id': 'geography', 'display_name': 'Geography', 'position': 1},
    {'id': 'viticulture', 'display_name': 'Viticulture', 'position': 2},
  ],
  'certifications': [
    {
      'id': 'WSET_L1',
      'organization': 'WSET',
      'level': 1,
      'display_name': 'WSET Level 1',
    },
    {
      'id': 'WSET_L2',
      'organization': 'WSET',
      'level': 2,
      'display_name': 'WSET Level 2',
      'includes_certification_id': 'WSET_L1',
      'is_selectable': true,
    },
  ],
  'node_types': [
    {'id': 'country', 'label': 'country'},
    {'id': 'region', 'label': 'region'},
    {'id': 'appellation', 'label': 'appellation'},
    {'id': 'grape', 'label': 'grape variety'},
    {'id': 'berry_colour', 'label': 'berry colour'},
  ],
  'relation_types': [
    {
      'id': 'LOCATED_IN',
      'label': 'is located in',
      'reverse_label': 'contains',
      'cardinality': 'many',
      'is_transitive': true,
      'default_domain_id': 'geography',
    },
    {
      'id': 'HAS_BERRY_COLOUR',
      'label': 'has berry colour',
      'reverse_label': 'is the berry colour of',
      'cardinality': 'one',
      'default_domain_id': 'viticulture',
    },
    {
      'id': 'PERMITS_PRINCIPAL_GRAPE',
      'label': 'permits the principal grape',
      'reverse_label': 'is a principal grape of',
      'cardinality': 'many',
      'default_domain_id': 'geography',
      'distractor_match_relation_type': 'HAS_BERRY_COLOUR',
    },
  ],
  'relation_type_signatures': [
    _signature('LOCATED_IN', 'appellation', 'region'),
    _signature('LOCATED_IN', 'region', 'country'),
    _signature('HAS_BERRY_COLOUR', 'grape', 'berry_colour'),
    _signature('PERMITS_PRINCIPAL_GRAPE', 'appellation', 'grape'),
  ],
  'knowledge_nodes': [
    _node('n_geo_france', 'country', 'France'),
    _node('n_geo_burgundy', 'region', 'Burgundy'),
    _node('n_geo_chablis', 'appellation', 'Chablis'),
    _node('n_geo_volnay', 'appellation', 'Volnay'),
    _node('n_grape_chardonnay', 'grape', 'Chardonnay'),
    _node('n_grape_pinot_noir', 'grape', 'Pinot Noir'),
    _node('n_colour_white', 'berry_colour', 'White'),
    _node('n_colour_black', 'berry_colour', 'Black'),
  ],
  'quantity_values': <dynamic>[],
  'node_alternative_names': [
    {
      'knowledge_node_id': 'n_geo_burgundy',
      'name': 'Bourgogne',
      'kind': 'synonym',
    },
  ],
  'knowledge_relations': [
    _relation('n_geo_burgundy', 'LOCATED_IN', 'n_geo_france'),
    _relation('n_geo_chablis', 'LOCATED_IN', 'n_geo_burgundy'),
    _relation('n_geo_volnay', 'LOCATED_IN', 'n_geo_burgundy'),
    _relation('n_grape_chardonnay', 'HAS_BERRY_COLOUR', 'n_colour_white'),
    _relation('n_grape_pinot_noir', 'HAS_BERRY_COLOUR', 'n_colour_black'),
    _relation('n_geo_chablis', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_chardonnay'),
    _relation('n_geo_volnay', 'PERMITS_PRINCIPAL_GRAPE', 'n_grape_pinot_noir'),
  ],
  'knowledge_items': [
    _item(
      'ki_chablis_grape',
      'n_geo_chablis',
      'PERMITS_PRINCIPAL_GRAPE',
      'n_grape_chardonnay',
    ),
    _item(
      'ki_volnay_grape',
      'n_geo_volnay',
      'PERMITS_PRINCIPAL_GRAPE',
      'n_grape_pinot_noir',
    ),
  ],
  'knowledge_item_prerequisites': [
    {
      'knowledge_item_id': 'ki_volnay_grape',
      'prerequisite_item_id': 'ki_chablis_grape',
    },
  ],
  'certification_knowledge_mappings': [
    _mapping('WSET_L2', 'ki_chablis_grape'),
    _mapping('WSET_L2', 'ki_volnay_grape'),
  ],
  'source_citations': [
    {
      'id': 'src_test_law',
      'kind': 'legislation',
      'title': 'A test cahier des charges',
      'publisher': 'Test publisher',
      'accessed_on': '2026-01-01',
    },
  ],
  'knowledge_item_citations': [
    {
      'knowledge_item_id': 'ki_chablis_grape',
      'source_citation_id': 'src_test_law',
    },
    {
      'knowledge_item_id': 'ki_volnay_grape',
      'source_citation_id': 'src_test_law',
    },
  ],
  'question_templates': [
    {
      'id': 'qt_principal_grape_fwd_mcq',
      'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
      'direction': 'forward',
      'mode': 'mcq',
      'prompt_template':
          'Which of these is a principal grape of {subject.name}?',
    },
  ],
  'tasting_grids': <dynamic>[],
  'tasting_grid_attributes': <dynamic>[],
  'tasting_grid_values': <dynamic>[],
};

Map<String, dynamic> _signature(String type, String subject, String object) => {
  'relation_type': type,
  'subject_node_type': subject,
  'object_node_type': object,
};

Map<String, dynamic> _node(String id, String type, String name) => {
  'id': id,
  'node_type': type,
  'name': name,
};

Map<String, dynamic> _relation(String subject, String type, String object) => {
  'subject_id': subject,
  'relation_type': type,
  'object_id': object,
  'valid_from': '1900-01-01',
};

Map<String, dynamic> _item(
  String id,
  String subject,
  String type,
  String object,
) => {
  'id': id,
  'subject_id': subject,
  'relation_type': type,
  'object_id': object,
  'domain_id': 'geography',
  'assertion_text': 'A test assertion.',
  'last_verified_at': '2026-01-01T00:00:00.000Z',
};

Map<String, dynamic> _mapping(String certification, String item) => {
  'certification_id': certification,
  'knowledge_item_id': item,
  'importance': 'core',
  'minimum_depth': 1,
};
