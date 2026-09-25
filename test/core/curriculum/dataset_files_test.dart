import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show DataClass;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

/// Where each section of the minimal fixture goes when it is split.
const _areas = {
  'areas/core.yaml': [
    'curriculum_domains',
    'certifications',
    'node_types',
    'relation_types',
    'relation_type_signatures',
    'tasting_grids',
    'tasting_grid_attributes',
    'tasting_grid_values',
    'relation_set_assertions',
    'map_layers',
    'map_layer_citations',
    'node_geometries',
  ],
  'areas/burgundy.yaml': [
    'knowledge_nodes',
    'quantity_values',
    'node_alternative_names',
    'knowledge_relations',
    'knowledge_items',
    'knowledge_item_prerequisites',
    'certification_knowledge_mappings',
    'source_citations',
    'knowledge_item_citations',
  ],
  'templates/mcq.yaml': ['question_templates'],
};

/// [sections] as YAML, one row per line: section `a` of rows `{…}`.
String yamlOf(Map<String, dynamic> data, List<String> sections) => [
  for (final section in sections)
    if (data[section] case final List<dynamic> rows)
      rows.isEmpty
          ? '$section: []'
          : [
              '$section:',
              for (final row in rows) '  - ${jsonEncode(row)}',
            ].join('\n'),
].join('\n');

/// The minimal fixture split into a manifest and three files, by path.
Map<String, String> splitFiles(
  Map<String, dynamic> data, {
  List<String>? includes,
}) {
  final manifest = {
    'dataset_version': data['dataset_version'],
    'published_at': data['published_at'],
  };
  return {
    'data/curriculum.yaml': [
      for (final MapEntry(:key, :value) in manifest.entries)
        '$key: ${jsonEncode(value)}',
      'includes:',
      for (final include in includes ?? _areas.keys) '  - $include',
    ].join('\n'),
    for (final MapEntry(key: path, value: sections) in _areas.entries)
      'data/$path': yamlOf(data, sections),
  };
}

CurriculumDataset load(Map<String, String> files) => CurriculumDataset.loadSync(
  'data/curriculum.yaml',
  (path) => files[path] ?? (throw StateError('no file $path')),
);

Matcher formatError(String message) => throwsA(
  isA<DatasetFormatException>().having(
    (e) => e.message,
    'message',
    contains(message),
  ),
);

/// The rows of every section as JSON, section by section.
Map<String, List<DataClass>> rowsIn(CurriculumDataset d) =>
    <String, List<DataClass>>{
      'curriculum_domains': d.curriculumDomains,
      'certifications': d.certifications,
      'node_types': d.nodeTypes,
      'relation_types': d.relationTypes,
      'relation_type_signatures': d.relationTypeSignatures,
      'knowledge_nodes': d.knowledgeNodes,
      'quantity_values': d.quantityValues,
      'node_alternative_names': d.nodeAlternativeNames,
      'knowledge_relations': d.knowledgeRelations,
      'knowledge_items': d.knowledgeItems,
      'knowledge_item_prerequisites': d.knowledgeItemPrerequisites,
      'certification_knowledge_mappings': d.certificationKnowledgeMappings,
      'source_citations': d.sourceCitations,
      'knowledge_item_citations': d.knowledgeItemCitations,
      'question_templates': d.questionTemplates,
      'tasting_grids': d.tastingGrids,
      'tasting_grid_attributes': d.tastingGridAttributes,
      'tasting_grid_values': d.tastingGridValues,
      'relation_set_assertions': d.relationSetAssertions,
      'map_layers': d.mapLayers,
      'map_layer_citations': d.mapLayerCitations,
      'node_geometries': d.nodeGeometries,
    };

void main() {
  test('reads the manifest, then each file it includes, in order', () {
    final dataset = load(splitFiles(minimalDataset()));
    expect(dataset.files, [
      'data/curriculum.yaml',
      'data/areas/core.yaml',
      'data/areas/burgundy.yaml',
      'data/templates/mcq.yaml',
    ]);
    expect(dataset.version, '1.0.0');
    expect(rowsIn(dataset), rowsIn(datasetOf(minimalDataset())));
  });

  test('knows the file and line of every row', () {
    final files = splitFiles(minimalDataset());
    final dataset = load(files);
    final lines = files['data/areas/burgundy.yaml']!.split('\n');
    final line = lines.indexWhere((l) => l.contains('"n_geo_volnay"')) + 1;
    expect(
      dataset.locate((section: 'knowledge_nodes', key: 'n_geo_volnay')),
      DatasetLocation('data/areas/burgundy.yaml', line),
    );
    expect(
      dataset.locate((
        section: 'knowledge_relations',
        key: 'n_geo_chablis LOCATED_IN n_geo_burgundy',
      )),
      isNotNull,
    );
    expect(dataset.locate((section: 'knowledge_nodes', key: 'n_x')), isNull);
  });

  test('a section may be spread over several files', () {
    final data = minimalDataset();
    final files = splitFiles(data);
    files['data/areas/core.yaml'] =
        '${files['data/areas/core.yaml']}\n'
        'knowledge_nodes:\n'
        '  - {"id": "n_geo_meursault", "node_type": "appellation", '
        '"name": "Meursault"}';
    final dataset = load(files);
    expect(
      dataset.knowledgeNodes.map((n) => n.id),
      containsAll(['n_geo_meursault', 'n_geo_chablis']),
    );
    expect(
      dataset.locate((
        section: 'knowledge_nodes',
        key: 'n_geo_meursault',
      ))!.path,
      'data/areas/core.yaml',
    );
  });

  group('rejects', () {
    test('a key written in two files, naming both places', () {
      final files = splitFiles(minimalDataset());
      final core = files['data/areas/core.yaml']!;
      files['data/areas/core.yaml'] =
          '$core\n'
          'knowledge_nodes:\n'
          '  - {"id": "n_geo_chablis", "node_type": "appellation", '
          '"name": "Chablis again"}';
      final coreLine = core.split('\n').length + 2;
      final burgundyLine =
          files['data/areas/burgundy.yaml']!
              .split('\n')
              .indexWhere((l) => l.contains('"id":"n_geo_chablis"')) +
          1;
      expect(
        () => load(files),
        formatError(
          'knowledge_nodes "n_geo_chablis" is written twice, at '
          'data/areas/core.yaml:$coreLine and '
          'data/areas/burgundy.yaml:$burgundyLine',
        ),
      );
    });

    test('a missing include', () {
      final files = splitFiles(
        minimalDataset(),
        includes: [..._areas.keys, 'areas/missing.yaml'],
      );
      expect(
        () => load(files),
        formatError('data/areas/missing.yaml cannot be read'),
      );
    });

    test('an include outside the manifest folder, or listed twice', () {
      for (final include in [
        '../other.yaml',
        '/areas/core.yaml',
        r'areas\core.yaml',
        'areas/core.txt',
        'areas/./core.yaml',
      ]) {
        final files = splitFiles(minimalDataset(), includes: [include]);
        expect(
          () => load(files),
          formatError('is not the relative path of a .yaml file'),
          reason: include,
        );
      }
      final twice = splitFiles(
        minimalDataset(),
        includes: [..._areas.keys, 'areas/core.yaml'],
      );
      expect(
        () => load(twice),
        formatError('areas/core.yaml is included twice'),
      );
    });

    test('release keys outside the manifest', () {
      final files = splitFiles(minimalDataset());
      files['data/templates/mcq.yaml'] =
          'dataset_version: "9.9.9"\n${files['data/templates/mcq.yaml']}';
      expect(
        () => load(files),
        formatError(
          'data/templates/mcq.yaml: only the manifest sets '
          'dataset_version',
        ),
      );
    });

    test('a section in no file', () {
      final files = splitFiles(
        minimalDataset(),
        includes: ['areas/core.yaml', 'areas/burgundy.yaml'],
      );
      expect(
        () => load(files),
        formatError('sections in no file: question_templates'),
      );
    });

    test('files that the manifest does not include', () {
      final files = splitFiles(minimalDataset());
      expect(
        () => CurriculumDataset.fromFiles([
          for (final path in [
            'data/curriculum.yaml',
            'data/areas/core.yaml',
            'data/templates/mcq.yaml',
            'data/areas/burgundy.yaml',
          ])
            DatasetFile(path, files[path]!),
        ]),
        formatError('includes data/areas/burgundy.yaml, which was not loaded'),
      );
    });

    test('a bad row, naming its file and line', () {
      final data = minimalDataset();
      (rowsOf(data, 'knowledge_relations').first as Map)['valid_from'] =
          '2026-02-30';
      final files = splitFiles(data);
      final line =
          files['data/areas/burgundy.yaml']!
              .split('\n')
              .indexWhere((l) => l.contains('2026-02-30')) +
          1;
      expect(
        () => load(files),
        formatError('data/areas/burgundy.yaml:$line: knowledge_relations'),
      );
    });
  });

  group('the checksum', () {
    test('covers every file and each include path', () {
      final files = splitFiles(minimalDataset());
      final original = load(files).checksum;
      expect(load(splitFiles(minimalDataset())).checksum, original);

      final edited = Map.of(files);
      edited['data/templates/mcq.yaml'] =
          '${files['data/templates/mcq.yaml']} ';
      expect(load(edited).checksum, isNot(original));

      final renamed = splitFiles(
        minimalDataset(),
        includes: [
          'areas/core.yaml',
          'areas/burgundy.yaml',
          'templates/a.yaml',
        ],
      )..['data/templates/a.yaml'] = files['data/templates/mcq.yaml']!;
      expect(load(renamed).checksum, isNot(original));

      final reordered = splitFiles(
        minimalDataset(),
        includes: [
          'areas/burgundy.yaml',
          'areas/core.yaml',
          'templates/mcq.yaml',
        ],
      );
      expect(load(reordered).checksum, isNot(original));
    });

    test('of a dataset in one file is the digest of its text', () {
      final text = datasetText(minimalDataset());
      expect(
        CurriculumDataset.parse(text).checksum,
        'sha256:${sha256.convert(utf8.encode(text))}',
      );
    });
  });

  test('validator issues point at the row they are about', () {
    final data = minimalDataset();
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': 'n_geo_chablis',
      'relation_type': 'LOCATED_IN',
      'object_id': 'n_geo_nowhere',
      'valid_from': '1900-01-01',
    });
    final files = splitFiles(data);
    final dataset = load(files);
    final issue = validateDataset(dataset).errors
        .firstWhere((issue) => issue.rule == 'dangling-relation');
    final line =
        files['data/areas/burgundy.yaml']!
            .split('\n')
            .indexWhere((l) => l.contains('n_geo_nowhere')) +
        1;
    expect(
      dataset.locate(issue.row!),
      DatasetLocation('data/areas/burgundy.yaml', line),
    );
  });

  test('every row of the bundled dataset is located by its key', () {
    final dataset = bundledDataset();
    for (final MapEntry(key: section, value: rows) in rowsIn(dataset).entries) {
      for (final row in rows) {
        expect(
          dataset.locate((section: section, key: rowKey(section, row))),
          isNotNull,
          reason: '$section $row',
        );
      }
    }
  });
}
