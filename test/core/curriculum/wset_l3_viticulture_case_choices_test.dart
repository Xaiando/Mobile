import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  test(
    'each Level 3 core viticulture case role has cited authored practice',
    () {
      final data = flattenDataset('assets/curriculum/curriculum.yaml');
      final items = {
        for (final row in rowsOf(data, 'knowledge_items'))
          (row as Map<String, dynamic>)['id'] as String: row,
      };
      final citations = {
        for (final row in rowsOf(data, 'source_citations'))
          (row as Map<String, dynamic>)['id'] as String: row,
      };
      final linkedCitations = <String, Set<String>>{};
      for (final row in rowsOf(data, 'knowledge_item_citations')) {
        final link = row as Map<String, dynamic>;
        linkedCitations
            .putIfAbsent(link['knowledge_item_id'] as String, () => {})
            .add(link['source_citation_id'] as String);
      }

      final coreCaseIds = {
        for (final row in rowsOf(data, 'certification_knowledge_mappings'))
          if ((row as Map<String, dynamic>)['certification_id'] == 'WSET_L3' &&
              row['importance'] == 'core' &&
              items[row['knowledge_item_id']]?['domain_id'] == 'viticulture' &&
              (items[row['knowledge_item_id']]?['relation_type'] as String)
                  .startsWith('CASE_'))
            row['knowledge_item_id'] as String,
      };
      expect(coreCaseIds, hasLength(40));

      const templateRoles = {
        'qt_wset_l3_viticulture_case_action_choice': 'CASE_ACTION',
        'qt_wset_l3_viticulture_case_reason_choice': 'CASE_REASON',
        'qt_wset_l3_viticulture_case_tradeoff_choice': 'CASE_TRADEOFF',
        'qt_wset_l3_viticulture_case_limitation_choice': 'CASE_LIMITATION',
      };
      const roleCounts = {
        'CASE_ACTION': 10,
        'CASE_REASON': 13,
        'CASE_TRADEOFF': 7,
        'CASE_LIMITATION': 10,
      };
      final covered = <String>{};
      final answerPositions = [0, 0, 0, 0];
      for (final entry in templateRoles.entries) {
        final template = rowOf(data, 'question_templates', 'id', entry.key);
        expect(template['relation_type'], entry.value);
        expect(template['mode'], 'authored_choice');
        final choices =
            (template['parameters'] as Map<String, dynamic>)['item_choices']
                as Map<String, dynamic>;
        expect(choices, hasLength(roleCounts[entry.value]!));
        for (final choiceEntry in choices.entries) {
          final id = choiceEntry.key;
          final choice = choiceEntry.value as Map<String, dynamic>;
          expect(covered.add(id), isTrue, reason: 'duplicate case item $id');
          expect(coreCaseIds, contains(id));
          expect(items[id]?['relation_type'], entry.value, reason: id);
          expect((choice['prompt'] as String).trim(), isNotEmpty, reason: id);
          expect(
            (choice['explanation'] as String).trim(),
            isNotEmpty,
            reason: id,
          );

          final sourceId = choice['sourceCitationId'] as String;
          expect(linkedCitations[id], contains(sourceId), reason: id);
          expect(
            citations[sourceId]?['url'],
            startsWith('https://'),
            reason: id,
          );

          final options = (choice['options'] as List).cast<String>();
          final answerIndex = choice['correctIndex'] as int;
          expect(options, hasLength(4), reason: id);
          expect(options.toSet(), hasLength(4), reason: id);
          expect(answerIndex, inInclusiveRange(0, 3), reason: id);
          final lengths = options.map((option) => option.length).toList();
          expect(
            lengths[answerIndex] == lengths.reduce(max) &&
                lengths
                        .where((length) => length == lengths[answerIndex])
                        .length ==
                    1,
            isFalse,
            reason: '$id should not reveal its answer by unique length',
          );
          answerPositions[answerIndex]++;
        }
      }
      expect(covered, coreCaseIds);
      expect(answerPositions, [10, 10, 10, 10]);
    },
  );
}
