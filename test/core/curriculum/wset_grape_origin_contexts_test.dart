import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final points = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_origin_'))
      .toList();
  final text = {for (final item in points) item.id: item.assertionText};

  test(
    'named grape-origin repairs are cited explanations at suitable depth',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(points, hasLength(17));
      for (final item in points) {
        expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        expect(
          dataset.knowledgeItemCitations.where(
            (citation) => citation.knowledgeItemId == item.id,
          ),
          isNotEmpty,
          reason: item.id,
        );
        final mappings = dataset.certificationKnowledgeMappings.where(
          (mapping) => mapping.knowledgeItemId == item.id,
        );
        expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
          'WSET_L2',
          'WSET_L3',
        }, reason: item.id);
        expect(mappings.every((mapping) => mapping.minimumDepth == 2), isTrue);
      }
    },
  );

  test(
    'wrong neighbour and grape contexts have explicit local replacements',
    () {
      expect(text['ki_wset_origin_condrieu_viognier'], contains('white wine'));
      expect(text['ki_wset_origin_condrieu_viognier'], contains('Viognier'));
      expect(
        text['ki_wset_origin_touraine_sauvignon'],
        contains('Sauvignon Blanc'),
      );
      expect(text['ki_wset_origin_provence_grenache'], contains('rosé'));
      expect(text['ki_wset_origin_priorat_grenache'], contains('Carignan'));
      expect(text['ki_wset_origin_stellenbosch_merlot'], contains('2022'));
      expect(
        text['ki_wset_origin_stellenbosch_merlot'],
        contains('does not prescribe'),
      );
      expect(
        text['ki_wset_origin_western_cape_chardonnay'],
        contains('without barrel'),
      );
      expect(
        text['ki_wset_origin_carneros_pinot'],
        contains('still Pinot Noir'),
      );
    },
  );

  test('wine identity remains separate from misleading colour and sweetness shortcuts', () {
    expect(text['ki_wset_origin_beaune_pinot'], contains('Chardonnay whites'));
    expect(
      text['ki_wset_origin_nuits_pinot'],
      contains('some Chardonnay white'),
    );
    expect(
      text['ki_wset_origin_meursault_chardonnay'],
      contains('Pinot Noir red'),
    );
    expect(text['ki_wset_origin_puligny_chardonnay'], contains('small red'));
    expect(
      text['ki_wset_origin_cava_basic_style'],
      contains('every example is Brut'),
    );
    expect(text['ki_wset_origin_barbera_asti'], contains('different grape'));
  });
}
