import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final points = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_sadvice_'))
      .toList();
  final text = {for (final item in points) item.id: item.assertionText};

  test(
    'advice contexts are cited Level 3 explanations, not automatic diagnoses',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(points, hasLength(3));
      for (final item in points) {
        expect(item.relationType, 'PRINCIPLE_EXPLANATION');
        expect(item.verificationStatus, 'unverified');
        expect(item.mcqDisabled, isTrue);
        expect(
          dataset.knowledgeItemCitations.where(
            (citation) => citation.knowledgeItemId == item.id,
          ),
          isNotEmpty,
        );
        final mappings = dataset.certificationKnowledgeMappings.where(
          (mapping) => mapping.knowledgeItemId == item.id,
        );
        expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
          'WSET_L3',
        });
        expect(mappings.single.importance, 'core');
        expect(mappings.single.minimumDepth, 2);
      }
    },
  );

  test('recommendations preserve person, condition and distinct sensory considerations', () {
    expect(
      text['ki_wset_sadvice_food_bitterness'],
      contains('already present'),
    );
    expect(
      text['ki_wset_sadvice_food_bitterness'],
      contains('not a guaranteed'),
    );
    expect(
      text['ki_wset_sadvice_selection_context'],
      contains('sensitivities'),
    );
    expect(text['ki_wset_sadvice_selection_context'], contains('celebration'));
    expect(
      text['ki_wset_sadvice_selection_context'],
      contains('drinking condition'),
    );
    expect(
      text['ki_wset_sadvice_complexity_fruitiness'],
      contains('neither is identical'),
    );
    expect(
      text['ki_wset_sadvice_complexity_fruitiness'],
      contains('does not automatically'),
    );
  });
}
