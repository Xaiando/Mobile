import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

import '../../support/curriculum_fixture.dart';

Matcher formatError(String fragment) => throwsA(
  isA<DatasetFormatException>().having(
    (e) => e.message,
    'message',
    contains(fragment),
  ),
);

void main() {
  group('the bundled dataset', () {
    late CurriculumDataset dataset;

    setUpAll(() => dataset = CurriculumDataset.parse(bundledDataset()));

    test('parses into every authored table', () {
      expect(dataset.version, '0.1.0');
      expect(dataset.checksum, matches(RegExp(r'^sha256:[0-9a-f]{64}$')));
      expect(dataset.certifications, hasLength(8));
      expect(dataset.curriculumDomains, hasLength(6));
      expect(dataset.knowledgeItems, isNotEmpty);
      expect(dataset.questionTemplates, isNotEmpty);
    });

    test('has at least 50 nodes and 50 relations (TASK-002)', () {
      expect(dataset.knowledgeNodes.length, greaterThanOrEqualTo(50));
      expect(dataset.knowledgeRelations.length, greaterThanOrEqualTo(50));
    });

    test('computes name_norm and applies schema defaults', () {
      final node = dataset.knowledgeNodes.firstWhere(
        (n) => n.id == 'n_geo_chateauneuf_du_pape',
      );
      expect(node.nameNorm, 'chateauneuf du pape');
      final item = dataset.knowledgeItems.first;
      expect(item.revision, 1);
      expect(item.verificationStatus, 'unverified');
      expect(item.lastVerifiedAt.isUtc, isTrue);
      expect(
        dataset.quantityValues.map((q) => q.nodeType),
        everyElement('quantity'),
      );
    });

    test('keeps every item unverified until expert review (D3)', () {
      expect(
        dataset.knowledgeItems.map((i) => i.verificationStatus),
        everyElement('unverified'),
      );
    });
  });

  group('rejects', () {
    test('text that is not YAML', () {
      expect(
        () => CurriculumDataset.parse('a: [b'),
        formatError('not valid YAML'),
      );
    });

    test('an unknown section', () {
      final data = minimalDataset()..['knowledge_edges'] = <dynamic>[];
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('unknown sections: knowledge_edges'),
      );
    });

    test('a missing section', () {
      final data = minimalDataset()..remove('question_templates');
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('"question_templates" must be a list'),
      );
    });

    test('a misspelt column', () {
      final data = minimalDataset();
      rowOf(data, 'knowledge_nodes', 'id', 'n_geo_chablis')['nodetype'] = 'x';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('unknown columns nodetype'),
      );
    });

    test('a computed column set by hand', () {
      final data = minimalDataset();
      rowOf(data, 'knowledge_nodes', 'id', 'n_geo_chablis')['name_norm'] = 'x';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('unknown columns name_norm'),
      );
    });

    test('a mapping without minimum_depth (audit SI-2)', () {
      final data = minimalDataset();
      (rowsOf(data, 'certification_knowledge_mappings').first as Map).remove(
        'minimum_depth',
      );
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('missing minimum_depth'),
      );
    });

    test('a relation without valid_from (audit SI-2)', () {
      final data = minimalDataset();
      (rowsOf(data, 'knowledge_relations').first as Map).remove('valid_from');
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('missing valid_from'),
      );
    });

    test('a malformed date', () {
      final data = minimalDataset();
      (rowsOf(data, 'knowledge_relations').first as Map)['valid_from'] =
          '2026-02-30';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('is not a YYYY-MM-DD date'),
      );
    });

    test('a timestamp that is not UTC with milliseconds', () {
      final data = minimalDataset();
      rowOf(
        data,
        'knowledge_items',
        'id',
        'ki_chablis_grape',
      )['last_verified_at'] = '2026-01-01T00:00:00+02:00';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('is not a UTC instant with milliseconds'),
      );
    });

    test('a version that is not major.minor.patch', () {
      expect(
        () => CurriculumDataset.parse(
          datasetText(minimalDataset(version: '1.0')),
        ),
        formatError('not major.minor.patch'),
      );
    });

    test('a value of the wrong type', () {
      final data = minimalDataset();
      rowOf(data, 'curriculum_domains', 'id', 'geography')['position'] =
          'first';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('wrong type'),
      );
    });
  });

  test('the checksum identifies the exact content', () {
    final original = CurriculumDataset.parse(datasetText(minimalDataset()));
    final edited = minimalDataset();
    rowOf(edited, 'knowledge_nodes', 'id', 'n_geo_chablis')['name'] = 'Chablís';
    expect(
      CurriculumDataset.parse(datasetText(edited)).checksum,
      isNot(original.checksum),
    );
    expect(
      CurriculumDataset.parse(datasetText(minimalDataset())).checksum,
      original.checksum,
    );
  });

  test('versions compare numerically', () {
    expect(compareVersions('0.10.0', '0.9.9'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0'), 0);
    expect(compareVersions('1.2.3', '1.10.0'), lessThan(0));
  });
}
