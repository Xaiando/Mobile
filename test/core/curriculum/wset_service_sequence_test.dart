import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final points = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_sseq_'))
      .toList();
  final text = {for (final item in points) item.id: item.assertionText};

  test(
    'service sequence is cited and suitable for the Level 3 advice outcome',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(points, hasLength(2));
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
        expect(mappings.single.minimumDepth, 2);
      }
    },
  );

  test('sequence handles identity, condition and flexible wine order', () {
    expect(
      text['ki_wset_sseq_lineup'],
      contains('shortcut rather than a rule'),
    );
    const reviewedLineup =
        'When serving several wines, a useful starting order moves from lighter, '
        'less intense examples towards fuller, more powerful ones. Consider '
        'aroma intensity, flavour and texture with the menu. Colour is a '
        'shortcut rather than a rule; a fuller white can follow a lighter red, '
        'and the planned food may justify a different order.';
    expect(text['ki_wset_sseq_lineup'], reviewedLineup);
    expect(
      text['ki_wset_sseq_lineup'],
      isNot(contains('fragile mature bottle')),
    );
    final orderCitations = dataset.knowledgeItemCitations.where(
      (citation) => citation.knowledgeItemId == 'ki_wset_sseq_lineup',
    );
    expect(
      orderCitations.map((citation) => citation.sourceCitationId).toSet(),
      {'src_wset_sseq_bordeaux'},
    );
    expect(
      dataset.sourceCitations
          .singleWhere((source) => source.id == 'src_wset_sseq_bordeaux')
          .url,
      'https://www.bordeaux.com/en/wine-tasting-basics/serve/',
    );
    expect(text['ki_wset_sseq_table'], contains('wine and vintage'));
    expect(text['ki_wset_sseq_table'], contains('before pouring the full'));
    expect(text['ki_wset_sseq_table'], contains('replace faulty wine'));
    expect(text['ki_wset_sseq_table'], contains('venue and guests'));
  });
}
