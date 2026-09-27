import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where(
        (item) =>
            item.id.startsWith('ki_wset_found_') ||
            item.id.startsWith('ki_wset_grape_'),
      )
      .toList();
  final items = {for (final item in lessons) item.id: item};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final evidence = jsonDecode(
    File('docs/research/wset-foundation-grape-evidence.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;

  test('beginner lessons are cited reviewable core study points', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(147));
    for (final item in lessons) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final mapping = dataset.certificationKnowledgeMappings.singleWhere(
        (mapping) => mapping.knowledgeItemId == item.id,
      );
      expect(mapping.certificationId, isIn(['WSET_L1', 'WSET_L2']));
      expect(mapping.minimumDepth, 2);
      expect(mapping.importance, 'core');
      final citations = dataset.knowledgeItemCitations.where(
        (citation) => citation.knowledgeItemId == item.id,
      );
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty, reason: item.id);
        final uri = Uri.parse(sources[citation.sourceCitationId]!.url!);
        expect(uri.scheme, 'https', reason: item.id);
        expect(uri.host, isNotEmpty);
      }
    }
    final principleTemplates = dataset.questionTemplates.where(
      (template) => template.relationType == 'PRINCIPLE_EXPLANATION',
    );
    expect(
      principleTemplates.map((template) => template.mode).toSet(),
      containsAll(['flashcard', 'typed', 'short_answer']),
    );
  });

  test(
    'the exact required grape list has distinct profile and variation evidence',
    () {
      const required = {
        'chardonnay',
        'sauvignon_blanc',
        'pinot_gris',
        'riesling',
        'cabernet_sauvignon',
        'merlot',
        'pinot_noir',
        'syrah',
        'gamay',
        'grenache',
        'tempranillo',
        'nebbiolo',
        'barbera',
        'sangiovese',
        'corvina',
        'montepulciano',
        'zinfandel',
        'pinotage',
        'carmenere',
        'malbec',
        'chenin_blanc',
        'semillon',
        'viognier',
        'gewurztraminer',
        'verdicchio',
        'cortese',
        'garganega',
        'fiano',
        'albarino',
        'furmint',
      };
      final grapes = (evidence['grapes'] as List).cast<Map<String, dynamic>>();
      expect(grapes.map((grape) => grape['id']).toSet(), required);
      expect(
        grapes.where((grape) => grape.containsKey('level1_items')),
        hasLength(8),
      );
      for (final grape in grapes) {
        final id = grape['id'] as String;
        for (final suffix in ['profile', 'variation']) {
          final item = items['ki_wset_grape_${id}_$suffix']!;
          expect(item.relationType, 'PRINCIPLE_EXPLANATION');
          expect(
            dataset.certificationKnowledgeMappings
                .singleWhere((mapping) => mapping.knowledgeItemId == item.id)
                .certificationId,
            'WSET_L2',
          );
        }
      }
    },
  );

  test(
    'the progress evidence uses actual IDs and citations instead of pin counts',
    () {
      final declaredLessons = (evidence['lessons'] as List)
          .cast<Map<String, dynamic>>();
      expect(
        declaredLessons.map((lesson) => lesson['id']).toSet(),
        items.keys.toSet(),
      );
      final grouped = <String>{
        for (final group in evidence['groups'] as List)
          ...List<String>.from(group['items'] as List),
        for (final grape in evidence['grapes'] as List)
          ...List<String>.from(grape['level1_items'] as List? ?? []),
        for (final grape in evidence['grapes'] as List)
          ...List<String>.from(grape['level2_items'] as List),
        ...List<String>.from(evidence['shared_items'] as List),
      };
      expect(grouped, items.keys.toSet());
      for (final lesson in declaredLessons) {
        final id = lesson['id'] as String;
        expect(lesson['requirements'], isNotEmpty, reason: id);
        final actual = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == id)
            .map((citation) => citation.sourceCitationId)
            .toSet();
        expect(
          (lesson['citations'] as List)
              .map((citation) => citation['source_id'])
              .toSet(),
          actual,
          reason: id,
        );
      }
    },
  );

  test('style lessons distinguish production effects from grape identity', () {
    expect(
      items['ki_wset_found_pulp_composition']!.assertionText,
      contains('water, sugars, acids and aroma compounds'),
    );
    expect(
      items['ki_wset_grape_semillon_profile']!.assertionText,
      contains('without requiring oak'),
    );
    expect(
      items['ki_wset_grape_riesling_variation']!.assertionText,
      contains('off-dry and sweet'),
    );
    expect(
      items['ki_wset_grape_corvina_variation']!.assertionText,
      contains('dry wine'),
    );
    expect(
      items['ki_wset_grape_corvina_profile']!.assertionText,
      isNot(contains('bubblegum')),
    );
    expect(
      items['ki_wset_grape_viognier_variation']!.assertionText,
      contains('oaked and unoaked'),
    );
    expect(
      items['ki_wset_grape_gewurztraminer_variation']!.assertionText,
      contains('noble-rot-affected'),
    );
    expect(
      items['ki_wset_found_familiar_white_zinfandel']!.assertionText,
      contains('rosé'),
    );
    expect(
      items['ki_wset_found_familiar_port']!.assertionText,
      contains('white'),
    );
  });

  test(
    'new canonical grapes classify berries and preserve the Primitivo synonym',
    () {
      const colours = {
        'barbera': 'black',
        'corvina': 'black',
        'montepulciano': 'black',
        'zinfandel': 'black',
        'pinotage': 'black',
        'verdicchio': 'white',
        'cortese': 'white',
        'garganega': 'white',
        'fiano': 'white',
      };
      for (final entry in colours.entries) {
        final item = items['ki_wset_grape_${entry.key}_berry_colour']!;
        expect(item.subjectId, 'n_grape_${entry.key}');
        expect(item.relationType, 'HAS_BERRY_COLOUR');
        expect(item.objectId, 'n_colour_${entry.value}');
        expect(
          item.assertionText,
          contains('rather than prescribing finished wine colour'),
        );
      }
      expect(
        dataset.nodeAlternativeNames.where(
          (alias) =>
              alias.knowledgeNodeId == 'n_grape_zinfandel' &&
              alias.name == 'Primitivo' &&
              alias.kind == 'synonym',
        ),
        hasLength(1),
      );
      expect(
        items['ki_wset_grape_zinfandel_identity']!.assertionText,
        contains('clones can show differences'),
      );
    },
  );
}
