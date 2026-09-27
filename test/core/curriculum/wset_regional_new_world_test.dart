import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_nw_'))
      .toList();
  final evidence = jsonDecode(
    File('docs/research/wset-regional-new-world-evidence.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final groups = (evidence['groups'] as List).cast<Map<String, dynamic>>();

  bool level2Accessible(String id) =>
      dataset.certificationKnowledgeMappings.any(
        (mapping) =>
            mapping.knowledgeItemId == id &&
            ['WSET_L1', 'WSET_L2'].contains(mapping.certificationId) &&
            mapping.importance == 'core',
      );

  test('New World explanatory lessons are cited and remain reviewable', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons.length, greaterThanOrEqualTo(80));
    for (final item in lessons) {
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final mapping = dataset.certificationKnowledgeMappings.singleWhere(
        (mapping) => mapping.knowledgeItemId == item.id,
      );
      expect(mapping.certificationId, isIn(['WSET_L2', 'WSET_L3']));
      expect(mapping.minimumDepth, 2);
      expect(mapping.importance, 'core');
      final citations = dataset.knowledgeItemCitations.where(
        (citation) => citation.knowledgeItemId == item.id,
      );
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty, reason: item.id);
        final uri = Uri.parse(sources[citation.sourceCitationId]!.url!);
        expect(uri.scheme, 'https');
        expect(uri.host, isNotEmpty);
      }
    }
  });

  test(
    'required Level 2 grape origins have accessible explanatory evidence',
    () {
      final pairs = (evidence['grape_gi_requirements'] as List)
          .cast<Map<String, dynamic>>();
      expect(pairs, hasLength(69));
      expect(pairs.map((pair) => pair['id']).toSet(), hasLength(69));
      final required = {
        'merlot': [
          'California',
          'Napa Valley',
          'Sonoma',
          'Central Valley',
          'Stellenbosch',
          'Margaret River',
          'Hawke’s Bay',
        ],
        'syrah': ['South Eastern Australia', 'Barossa Valley', 'Hunter Valley'],
        'riesling': ['Clare Valley', 'Eden Valley'],
        'semillon': ['Hunter Valley', 'Barossa Valley'],
        'carmenere': ['Central Valley'],
        'malbec': ['Mendoza'],
      };
      for (final entry in required.entries) {
        expect(
          pairs
              .where((pair) => pair['grape'] == entry.key)
              .map((pair) => pair['region'])
              .toSet(),
          entry.value.toSet(),
        );
      }
      for (final pair in pairs) {
        final evidenceIds = [
          ...(pair['grape_items'] as List).cast<String>(),
          ...(pair['regional_items'] as List).cast<String>(),
        ];
        expect(
          pair['regional_items'],
          isNotEmpty,
          reason: pair['id'] as String,
        );
        for (final id in evidenceIds) {
          expect(items[id], isNotNull, reason: id);
          expect(level2Accessible(id), isTrue, reason: id);
          expect(items[id]!.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
        }
      }
    },
  );

  test(
    'regional evidence keeps atlas locations and generic profiles distinct',
    () {
      for (final group in groups) {
        expect(group['canonical_locations'], isNotEmpty);
        for (final location
            in (group['canonical_locations'] as List)
                .cast<Map<String, dynamic>>()) {
          expect(location['counts_as_explanatory_coverage'], isFalse);
          for (final id
              in (location['location_items'] as List).cast<String>()) {
            expect(items[id]!.relationType, 'LOCATED_IN');
          }
        }
        for (final dimension in (group['dimensions'] as Map).values) {
          for (final id in (dimension as List).cast<String>()) {
            expect(items[id], isNotNull, reason: id);
            expect(
              items[id]!.relationType,
              'PRINCIPLE_EXPLANATION',
              reason: id,
            );
          }
        }
      }
      final missing = (evidence['missing_geography'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        missing.map((entry) => entry['name']),
        containsAll([
          'Napa County',
          'Sonoma County',
          'Mendocino County',
          'Santa Barbara County',
        ]),
      );
      expect(
        missing.singleWhere(
          (entry) => entry['name'] == 'Mendocino County',
        )['requested_node_id'],
        isNot('n_geo_mendocino_ava'),
      );
    },
  );

  test('styles and labels retain consequential distinctions', () {
    expect(
      items['ki_wset_nw_napa_chardonnay']!.assertionText,
      contains('malolactic'),
    );
    expect(
      items['ki_wset_nw_napa_sauvignon']!.assertionText,
      contains('Fumé Blanc'),
    );
    expect(
      items['ki_wset_nw_hunter_shiraz_style']!.assertionText,
      contains('medium bodied'),
    );
    expect(
      items['ki_wset_nw_barossa_semillon_range']!.assertionText,
      contains('avoiding oak'),
    );
    expect(
      items['ki_wset_nw_riverina_sweet_exception']!.assertionText,
      contains('selected Semillon'),
    );
    expect(
      items['ki_wset_nw_chile_origin_hierarchy']!.assertionText,
      contains('zones within it'),
    );
    expect(
      items['ki_wset_nw_cape_blend_meaning']!.assertionText,
      contains('competition’s rules'),
    );
    expect(
      items['ki_wset_nw_bc_vqa_origin']!.assertionText,
      contains('separate system'),
    );
    final hunter = groups.singleWhere((group) => group['id'] == 'au_hunter');
    final locations = (hunter['canonical_locations'] as List)
        .cast<Map<String, dynamic>>();
    expect(
      locations.map((entry) => entry['node_id']),
      containsAll(['n_geo_hunter', 'n_geo_hunter_valley_zone']),
    );
  });
}
