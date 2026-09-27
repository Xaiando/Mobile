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
  final evidence = jsonDecode(
    File('docs/research/wset-grape-structure-evidence.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final grapes = (evidence['grapes'] as List).cast<Map<String, dynamic>>();
  final lessons = (evidence['lessons'] as List).cast<Map<String, dynamic>>();

  test('new grape explanations load as cited reviewable Level 2 content', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, isNotEmpty);
    for (final row in lessons) {
      final id = row['knowledge_item_id'] as String;
      final item = items[id]!;
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      final mapping = dataset.certificationKnowledgeMappings.singleWhere(
        (mapping) => mapping.knowledgeItemId == id,
      );
      expect(mapping.certificationId, 'WSET_L2', reason: id);
      expect(mapping.importance, 'core', reason: id);
      expect(mapping.minimumDepth, 2, reason: id);
      final cited = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == id)
          .map((citation) => citation.sourceCitationId)
          .toSet();
      expect(cited, containsAll((row['source_ids'] as List).cast<String>()));
      expect(cited, isNotEmpty, reason: id);
      for (final sourceId in cited) {
        final uri = Uri.parse(sources[sourceId]!.url!);
        expect(uri.scheme, 'https', reason: id);
        expect(uri.host, isNotEmpty, reason: id);
      }
    }
  });

  test(
    'all thirty required grapes select actual structure and aroma lessons',
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
      const black = {
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
      };
      expect(grapes.map((row) => row['grape_id']).toSet(), required);
      for (final row in grapes) {
        final grape = row['grape_id'] as String;
        final dimensions = row['dimensions'] as Map;
        expect(
          dimensions.keys,
          containsAll(['colour', 'potential_alcohol', 'acidity', 'aroma']),
          reason: grape,
        );
        expect(dimensions.containsKey('tannin'), black.contains(grape));
        expect(row['berry_colour_alone_is_finished_colour_evidence'], isFalse);
        final selected = (row['required_item_ids'] as List).cast<String>();
        for (final ids in dimensions.values) {
          expect(ids, isNotEmpty, reason: grape);
          for (final id in (ids as List).cast<String>()) {
            expect(selected, contains(id), reason: '$grape $id');
            expect(
              items[id]!.relationType,
              'PRINCIPLE_EXPLANATION',
              reason: id,
            );
          }
        }
        final appearance = (dimensions['colour'] as List).cast<String>();
        expect(
          appearance.any((id) => items[id]!.relationType == 'HAS_BERRY_COLOUR'),
          isFalse,
        );
      }
    },
  );

  test(
    'the principal eight include influences and bounded bottle development',
    () {
      final principal = grapes.where((row) => row['learning_outcome'] == 'LO3');
      expect(principal, hasLength(8));
      for (final row in principal) {
        final dimensions = row['dimensions'] as Map;
        expect(
          dimensions.keys,
          containsAll([
            'environment',
            'harvest',
            'production',
            'bottle_ageing',
          ]),
        );
        final ageing = (dimensions['bottle_ageing'] as List).cast<String>();
        expect(ageing, contains('ki_wset_taste_ageing_not_all'));
        expect(ageing, contains('ki_wset_taste_ageing_uncertain'));
      }
    },
  );

  test('colour, tannin and acidity are independent structural dimensions', () {
    final barbera = items['ki_wset_structure_barbera_structure']!.assertionText;
    expect(barbera, contains('relatively little grape tannin'));
    expect(barbera, contains('anthocyanins do not imply'));
    final pinot =
        items['ki_wset_structure_pinot_noir_structure']!.assertionText;
    expect(pinot, contains('less tannin than Cabernet Sauvignon'));
    expect(pinot, contains('fresh acidity'));
    final cabernet =
        items['ki_wset_structure_cabernet_sauvignon_structure']!.assertionText;
    expect(cabernet, contains('naturally high acidity'));
    final grenache =
        items['ki_wset_structure_grenache_structure']!.assertionText;
    expect(grenache, contains('high alcohol in ripe dry wines'));
    expect(grenache, contains('relatively low acidity'));
  });

  test(
    'regional examples and ripeness do not turn into universal guarantees',
    () {
      final syrah = items['ki_wset_structure_syrah_structure']!.assertionText;
      expect(syrah, contains('relatively low acidity at maturity'));
      expect(syrah, contains('does not guarantee high acidity'));
      final pinotage =
          items['ki_wset_structure_pinotage_structure']!.assertionText;
      expect(pinotage, contains('2020 Pinotage'));
      expect(pinotage, contains('variation rather than a universal recipe'));
      final furmint =
          items['ki_wset_structure_furmint_structure']!.assertionText;
      expect(furmint, contains('documented bright-gold'));
      expect(furmint, contains('fermentation may retain sugar'));
      final semillon =
          items['ki_wset_structure_semillon_structure']!.assertionText;
      expect(semillon, contains('Early-picked Hunter'));
      expect(semillon, contains('lower alcohol'));
    },
  );
}
