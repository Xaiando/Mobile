import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

/// Every curriculum table: the authored ones, then the generated ones.
const curriculumTables = [
  'curriculum_domains',
  'tasting_grids',
  'certifications',
  'node_types',
  'relation_types',
  'relation_type_signatures',
  'knowledge_nodes',
  'quantity_values',
  'node_alternative_names',
  'knowledge_relations',
  'knowledge_items',
  'knowledge_item_prerequisites',
  'certification_knowledge_mappings',
  'source_citations',
  'knowledge_item_citations',
  'question_templates',
  'tasting_grid_attributes',
  'tasting_grid_values',
  'questions',
  'question_distractors',
];

/// Each curriculum table of [db] as sorted JSON rows.
Future<Map<String, List<String>>> contentsOf(AppDatabase db) async => {
  for (final table in curriculumTables)
    table: [
      for (final row in await db.customSelect('SELECT * FROM $table').get())
        jsonEncode(row.data),
    ]..sort(),
};

void main() {
  // Two databases are compared on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test(
    'the split bundle ingests like the same rows in one file (C1)',
    () async {
      final split = bundledDataset();
      final single = CurriculumDataset.parse(
        jsonEncode(flattenDataset(curriculumAssetPath)),
      );
      expect(split.files.length, greaterThan(1), reason: 'the bundle is split');
      expect(single.version, split.version);

      final a = openTestDatabase(), b = openTestDatabase();
      addTearDown(a.close);
      addTearDown(b.close);
      await CurriculumIngester(a).ingest(split);
      await CurriculumIngester(b).ingest(single);
      final splitRows = await contentsOf(a), singleRows = await contentsOf(b);
      for (final table in curriculumTables) {
        expect(splitRows[table], singleRows[table], reason: table);
      }
      expect(splitRows['questions'], isNotEmpty);
    },
  );

  test('the bundle keeps a folder per kind of file', () {
    final files = bundledDataset().files;
    expect(files.first, curriculumAssetPath);
    for (final file in files.skip(1)) {
      expect(
        file,
        matches(r'^assets/curriculum/(areas|templates)/[a-z0-9_]+\.yaml$'),
      );
    }
  });
}
