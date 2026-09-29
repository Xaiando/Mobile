import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final flat = flattenDataset('assets/curriculum/curriculum.yaml');
  final template = rowOf(
    flat,
    'question_templates',
    'id',
    'qt_wset_l3_viticulture_application_40',
  );
  final choices =
      (template['parameters'] as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('40 distinct primary-cited general viticulture choices retain Level 3 scope', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choices, hasLength(40));
    final existingChoices = <String>{};
    for (final other in rowsOf(flat, 'question_templates')) {
      final row = other as Map<String, dynamic>;
      if (row['mode'] != 'authored_choice' || row['id'] == template['id']) {
        continue;
      }
      final itemChoices =
          (row['parameters'] as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      existingChoices.addAll(itemChoices.keys);
    }
    expect(choices.keys.toSet().intersection(existingChoices), isEmpty);

    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final positions = [0, 0, 0, 0];
    for (final entry in choices.entries) {
      final id = entry.key;
      final cue = entry.value as Map<String, dynamic>;
      expect(id, startsWith('ki_vit_'));
      expect(id, isNot(contains('_case_')));
      final item = items[id]!;
      expect(item.domainId, 'viticulture', reason: id);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      final level3 = dataset.certificationKnowledgeMappings.singleWhere(
        (mapping) =>
            mapping.certificationId == 'WSET_L3' &&
            mapping.knowledgeItemId == id,
      );
      expect(level3.importance, 'core', reason: id);
      expect(level3.minimumDepth, 2, reason: id);
      final level2 = dataset.certificationKnowledgeMappings.where(
        (mapping) =>
            mapping.certificationId == 'WSET_L2' &&
            mapping.knowledgeItemId == id,
      );
      expect(level2.length, lessThanOrEqualTo(1), reason: id);
      expect(
        level2.every((mapping) => mapping.importance == 'secondary'),
        isTrue,
        reason: id,
      );
      final cited = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == id)
          .map((citation) => citation.sourceCitationId)
          .toSet();
      expect(cited, contains(cue['sourceCitationId']), reason: id);
      final options = (cue['options'] as List).cast<String>();
      expect(options, hasLength(4), reason: id);
      expect(
        options.map((option) => option.toLowerCase().trim()).toSet(),
        hasLength(4),
        reason: id,
      );
      final correctIndex = cue['correctIndex'] as int;
      positions[correctIndex]++;
      final lengths = options.map((option) => option.length).toList();
      final answerLength = lengths[correctIndex];
      expect(
        answerLength == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == answerLength).length == 1,
        isFalse,
        reason: 'Keyed answer is uniquely longest: $id',
      );
      expect(
        answerLength == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == answerLength).length == 1,
        isFalse,
        reason: 'Keyed answer is uniquely shortest: $id',
      );
      expect((cue['prompt'] as String).length, greaterThan(35), reason: id);
      expect(
        (cue['explanation'] as String).length,
        greaterThan(35),
        reason: id,
      );
    }
    expect(positions, [10, 10, 10, 10]);
  });
}
