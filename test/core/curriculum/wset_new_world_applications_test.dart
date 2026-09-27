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
    File('docs/research/wset-new-world-applications-evidence.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;
  final lessons = (evidence['lessons'] as List).cast<Map<String, dynamic>>();
  final groups = (evidence['group_augmentation'] as List)
      .cast<Map<String, dynamic>>();

  test(
    'named applications load with distinct factual and supplied premises',
    () {
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
        expect(mapping.certificationId, row['level'], reason: id);
        expect(mapping.importance, 'core', reason: id);
        expect(mapping.minimumDepth, 2, reason: id);
        final cited = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == id)
            .map((citation) => citation.sourceCitationId)
            .toSet();
        final anchors = (row['regional_or_label_source_ids'] as List)
            .cast<String>();
        expect(anchors, isNotEmpty, reason: id);
        expect(cited, containsAll(anchors), reason: id);
        for (final sourceId in cited) {
          final uri = Uri.parse(sources[sourceId]!.url!);
          expect(uri.scheme, 'https', reason: id);
          expect(uri.host, isNotEmpty, reason: id);
        }
        if (row['kind'] == 'original_conditional_application') {
          expect(row['supplied_assumptions'], isNotEmpty, reason: id);
          expect(row['mechanism_source_ids'], isNotEmpty, reason: id);
        }
      }
    },
  );

  test(
    'regional catalog uses explanations and shared country label lessons',
    () {
      for (final group in groups) {
        expect(group['location_only_is_explanatory_evidence'], isFalse);
        for (final ids in (group['dimensions'] as Map).values) {
          for (final id in (ids as List).cast<String>()) {
            expect(
              items[id]!.relationType,
              'PRINCIPLE_EXPLANATION',
              reason: id,
            );
            expect(
              lessons.any((row) => row['knowledge_item_id'] == id),
              isTrue,
              reason: id,
            );
          }
        }
      }
      final nzGroups = groups.where(
        (group) => (group['base_group_id'] as String).startsWith('nz_'),
      );
      for (final group in nzGroups) {
        expect(
          (group['dimensions'] as Map)['labels'],
          contains('ki_wset_nwa_nz_enduring_origins'),
        );
      }
    },
  );

  test('named style mechanisms have consequences, rather than recipes', () {
    final chardonnay = items['ki_wset_nwa_monterey_chardonnay']!.assertionText;
    expect(chardonnay, contains('reduce malic acidity'));
    expect(chardonnay, contains('option to trial'));
    final red = items['ki_wset_nwa_great_southern_red']!.assertionText;
    expect(red, contains('colour and tannin'));
    expect(red, contains('balance'));
    final riesling = items['ki_wset_nwa_canterbury_riesling']!.assertionText;
    expect(riesling, contains('stability control'));
    expect(riesling, contains('does not select the fermentation endpoint'));
  });

  test(
    'origin labels keep geographic identity, quality and exceptions apart',
    () {
      final lujan = items['ki_wset_nwa_lujan_doc_distinction']!.assertionText;
      expect(lujan, contains('both an IG and a DOC'));
      expect(lujan, contains('not automatically a DOC wine'));
      final nz = items['ki_wset_nwa_nz_origin_label']!.assertionText;
      expect(nz, contains('85%'));
      expect(nz, contains('Export labelling'));
      final enduring = items['ki_wset_nwa_nz_enduring_origins']!.assertionText;
      expect(enduring, contains('New Zealand, North Island and South Island'));
      expect(enduring, contains('application is not the same as a registered'));
      final cape = items['ki_wset_nwa_western_cape_environment']!.assertionText;
      expect(cape, contains('winter rain'));
      expect(cape, contains('different vineyard conditions'));
      final otago = items['ki_wset_nwa_otago_cost']!.assertionText;
      expect(otago, contains('supplied'));
      expect(otago, contains('avoided crop loss'));
      expect(otago, contains('guarantees a selling price'));
    },
  );
}
