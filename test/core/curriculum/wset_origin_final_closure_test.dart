import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  test('required Recioto association teaches sweet style without a pure-Corvina claim', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final item = dataset.knowledgeItems.singleWhere(
      (item) => item.id == 'ki_wset_ofinal_recioto_corvina',
    );
    expect(item.verificationStatus, 'unverified');
    expect(item.mcqDisabled, isTrue);
    expect(item.assertionText, contains('sweet red dried-grape'));
    expect(item.assertionText, contains('Corvina and/or Corvinone'));
    expect(item.assertionText, contains('does not mean pure Corvina'));
    expect(item.assertionText, contains('contrasts with dry Amarone'));
    expect(
      dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == item.id)
          .map((citation) => citation.sourceCitationId),
      contains('src_wset_geo_recioto_valpo_spec_2023'),
    );
    final mappings = dataset.certificationKnowledgeMappings.where(
      (mapping) => mapping.knowledgeItemId == item.id,
    );
    expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
      'WSET_L2',
      'WSET_L3',
    });
    expect(mappings.every((mapping) => mapping.minimumDepth == 2), isTrue);
  });
}
