import 'dart:convert';
import 'dart:io';

import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:yaml/yaml.dart';

/// The dataset bundled with the app, read from its files.
CurriculumDataset bundledDataset() => CurriculumDataset.loadSync(
  curriculumAssetPath,
  (path) => File(path).readAsStringSync(),
);

/// A copy of [dataset] as dataset text. YAML is a superset of JSON.
String datasetText(Map<String, dynamic> dataset) => jsonEncode(dataset);

/// [dataset] parsed as a dataset in one file.
CurriculumDataset datasetOf(Map<String, dynamic> dataset) =>
    CurriculumDataset.parse(datasetText(dataset));

/// The dataset whose manifest is at [manifestPath] as plain maps and lists,
/// merged into the shape of a dataset in one file: the manifest's keys, and
/// each section's rows from every file, in order.
Map<String, dynamic> flattenDataset(String manifestPath) {
  Map<String, dynamic> read(String path) =>
      jsonDecode(jsonEncode(loadYaml(File(path).readAsStringSync())))
          as Map<String, dynamic>;

  final merged = read(manifestPath)..remove('includes');
  final includes = datasetIncludes(
    manifestPath,
    File(manifestPath).readAsStringSync(),
  );
  for (final path in includes) {
    for (final MapEntry(:key, :value) in read(path).entries) {
      final rows = merged[key] as List<dynamic>? ?? [];
      merged[key] = [...rows, ...value as List<dynamic>];
    }
  }
  return merged;
}

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
  'relation_set_assertions': <dynamic>[],
  'map_layers': <dynamic>[],
  'map_layer_citations': <dynamic>[],
  'node_geometries': <dynamic>[],
};

/// [minimalDataset] with one valid row of each kind schema v2 adds: a pack,
/// a symmetric relation, a completeness assertion, a template variant with
/// parameters, and a map layer with its citation and a geometry.
Map<String, dynamic> v2Dataset() {
  // A JSON copy, so that its lists take rows of any shape.
  final data = copyOf(minimalDataset());
  rowsOf(data, 'certifications').add({
    'id': 'BURGUNDY_PACK',
    'kind': 'pack',
    'display_name': 'Burgundy in depth',
    'description': 'A test pack.',
    'includes_certification_id': 'WSET_L2',
    'is_selectable': true,
  });
  rowsOf(data, 'relation_types').add({
    'id': 'BORDERS',
    'label': 'borders',
    'reverse_label': 'borders',
    'cardinality': 'many',
    'default_domain_id': 'geography',
    'is_symmetric': true,
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'BORDERS',
    'subject_node_type': 'appellation',
    'object_node_type': 'appellation',
  });
  rowsOf(
    data,
    'knowledge_nodes',
  ).add({'id': 'n_geo_pommard', 'node_type': 'appellation', 'name': 'Pommard'});
  rowsOf(data, 'knowledge_relations')
    ..add({
      'subject_id': 'n_geo_pommard',
      'relation_type': 'LOCATED_IN',
      'object_id': 'n_geo_burgundy',
      'valid_from': '1900-01-01',
    })
    ..add({
      'subject_id': 'n_geo_pommard',
      'relation_type': 'BORDERS',
      'object_id': 'n_geo_volnay',
      'valid_from': '1900-01-01',
    });
  rowsOf(data, 'relation_set_assertions').add({
    'node_id': 'n_geo_chablis',
    'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
    'direction': 'forward',
    'member_node_type': 'grape',
    'valid_from': '1938-01-13',
    'source_citation_id': 'src_test_law',
    'locator': 'Article V',
  });
  rowsOf(data, 'question_templates').add({
    'id': 'qt_principal_grape_fwd_flashcard',
    'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
    'direction': 'forward',
    'mode': 'flashcard',
    'variant': 'short',
    'parameters': {'hint': false},
    'prompt_template': 'The principal grape of {subject.name}?',
  });
  rowsOf(data, 'source_citations').add({
    'id': 'src_test_boundaries',
    'kind': 'dataset',
    'title': 'Test boundaries',
    'publisher': 'Test publisher',
    'accessed_on': '2026-01-01',
    'license': 'Licence Ouverte 2.0',
    'attribution_text': 'Test publisher, 2026.',
  });
  rowsOf(data, 'map_layers').add({
    'id': 'ml_test_appellations',
    'display_name': 'Appellations',
    'geometry_kind': 'area',
    'asset_path': 'assets/geography/test_appellations.topo.json',
    'asset_sha256': 'a' * 64,
    'min_zoom': 7,
    'max_zoom': 14,
  });
  rowsOf(data, 'map_layer_citations').add({
    'map_layer_id': 'ml_test_appellations',
    'source_citation_id': 'src_test_boundaries',
    'position': 1,
  });
  rowsOf(data, 'node_geometries').add({
    'knowledge_node_id': 'n_geo_chablis',
    'map_layer_id': 'ml_test_appellations',
    'feature_key': 'n_geo_chablis',
    'min_lon': 3.6,
    'min_lat': 47.7,
    'max_lon': 4.0,
    'max_lat': 47.9,
    'label_lon': 3.8,
    'label_lat': 47.8,
  });
  return data;
}

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
