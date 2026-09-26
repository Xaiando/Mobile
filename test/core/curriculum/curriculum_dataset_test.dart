import 'dart:convert';

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

    setUpAll(() => dataset = bundledDataset());

    test('parses into every authored table', () {
      // Every content change bumps the version, so only its form is pinned.
      expect(dataset.version, matches(RegExp(r'^\d+\.\d+\.\d+$')));
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
      // The defaults of schema v2's new columns.
      expect(
        dataset.certifications.map((c) => c.kind),
        everyElement('certification'),
      );
      expect(
        dataset.relationTypes.map((t) => t.isSymmetric),
        everyElement(isFalse),
      );
      expect([
        for (final t in dataset.questionTemplates)
          if (t.mode != 'short_answer') (t.variant, t.parameters),
      ], everyElement(('', null)));
      // A mapping of parameters is stored as JSON (QF-14).
      final profile = dataset.questionTemplates.singleWhere(
        (t) => t.id == 'qt_profile_short_answer',
      );
      expect(profile.variant, 'profile');
      expect(
        jsonDecode(profile.parameters!),
        containsPair('key_points', containsPair('HAS_SOIL', 'Soil')),
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
        formatError('sections in no file: question_templates'),
      );
    });

    test('a section that is not a list', () {
      final data = minimalDataset()..['question_templates'] = 'none';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('"question_templates" must be a list'),
      );
    });

    test('a key written twice', () {
      final data = minimalDataset();
      rowsOf(
        data,
        'curriculum_domains',
      ).add({'id': 'geography', 'display_name': 'Again', 'position': 9});
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('curriculum_domains "geography" is written twice'),
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

    test('template parameters that are not a mapping', () {
      final data = v2Dataset();
      rowOf(
        data,
        'question_templates',
        'id',
        'qt_principal_grape_fwd_flashcard',
      )['parameters'] = 'hint';
      expect(
        () => CurriculumDataset.parse(datasetText(data)),
        formatError('parameters must be a mapping'),
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

  test('reads the v2 sections, and stores template parameters as JSON', () {
    final data = v2Dataset();
    rowOf(
      data,
      'question_templates',
      'id',
      'qt_principal_grape_fwd_flashcard',
    )['parameters'] = {
      'hint': false,
      'order': ['north', 'south'],
    };
    final dataset = datasetOf(data);
    final template = dataset.questionTemplates.firstWhere(
      (t) => t.id == 'qt_principal_grape_fwd_flashcard',
    );
    expect(template.variant, 'short');
    expect(template.parameters, '{"hint":false,"order":["north","south"]}');
    final pack = dataset.certifications.firstWhere((c) => c.kind == 'pack');
    expect((pack.organization, pack.level), (null, null));
    expect(dataset.relationSetAssertions.single.memberNodeType, 'grape');
    expect(dataset.mapLayers.single.minZoom, 7.0);
    expect(dataset.mapLayerCitations.single.position, 1);
    expect(dataset.nodeGeometries.single.labelLat, 47.8);
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
