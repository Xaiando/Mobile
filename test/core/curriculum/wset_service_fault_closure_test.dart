import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final points = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_sfault_'))
      .toList();
  final text = {
    for (final item in dataset.knowledgeItems) item.id: item.assertionText,
  };

  test(
    'all added fault explanations are source-linked Level 3 study points',
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

  test(
    'fault identification preserves compound and intended-style distinctions',
    () {
      expect(
        text['ki_wset_sfault_reduction'],
        contains('volatile sulfur compounds'),
      );
      expect(
        text['ki_wset_sfault_reduction'],
        contains('not a universal cure'),
      );
      expect(
        text['ki_wset_sfault_high_so2'],
        contains('distinct from hydrogen sulfide'),
      );
      expect(text['ki_wset_sfault_high_so2'], contains('does not prove'));
      expect(
        text['ki_wset_sfault_out_of_condition'],
        contains('Beneficial maturity'),
      );
      expect(
        text['ki_wset_sfault_out_of_condition'],
        contains('age or brown colour alone'),
      );
      expect(text['ki_fault_h2s_descriptor'], contains('rotten egg'));
      expect(text['ki_fault_brett_organism'], contains('yeast'));
      expect(text['ki_fault_brett_ep'], contains('medicinal'));
      expect(text['ki_fault_brett_misdiagnosis'], contains('confused'));
    },
  );
}
