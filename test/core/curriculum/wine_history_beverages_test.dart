import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();

  test('history and sommelier beverages stay off WSET Levels 1 to 3', () {
    final ids = dataset.knowledgeItems
        .where(
          (item) =>
              item.id.startsWith('ki_hist_') || item.id.startsWith('ki_bev_'),
        )
        .map((item) => item.id)
        .toSet();
    expect(ids.where((id) => id.startsWith('ki_hist_')), hasLength(15));
    expect(ids.where((id) => id.startsWith('ki_bev_')), hasLength(22));
    for (final id in ids) {
      final tracks = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == id)
          .map((mapping) => mapping.certificationId)
          .toSet();
      expect(tracks, isNot(contains('WSET_L1')), reason: id);
      expect(tracks, isNot(contains('WSET_L2')), reason: id);
      expect(tracks, isNot(contains('WSET_L3')), reason: id);
      expect(tracks, contains('CMS_CERTIFIED'), reason: id);
      if (id.startsWith('ki_hist_')) {
        expect(tracks, contains('WSET_L4'), reason: id);
      } else {
        expect(tracks, isNot(contains('WSET_L4')), reason: id);
      }
      final item = dataset.knowledgeItems.singleWhere((row) => row.id == id);
      expect(item.domainId, 'service', reason: id);
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == id,
        ),
        isTrue,
        reason: id,
      );
    }
  });

  test('the history and beverage corrections that are easy to get wrong stay in the text', () {
    String text(String id) => dataset.knowledgeItems
        .singleWhere((item) => item.id == id)
        .assertionText;
    expect(text('ki_hist_classement_1855'), contains('Napoleon III'));
    expect(
      text('ki_hist_classement_1855'),
      contains('not commissioned by Napoleon I'),
    );
    expect(text('ki_hist_areni_cave'), contains('not the oldest wine residue'));
    expect(
      text('ki_hist_berlin_1806'),
      contains('not a Bordeaux classification'),
    );
    expect(
      text('ki_hist_douro_1756'),
      contains('not the first line ever drawn'),
    );
    expect(
      text('ki_hist_perignon_myth'),
      contains('does not make him the inventor'),
    );
    expect(text('ki_hist_methuen_1703'), contains('one third below'));
    expect(text('ki_hist_aoc_1935'), contains('30 July 1935'));
    expect(text('ki_hist_paris_1976'), contains('not a permanent ranking'));
    expect(text('ki_bev_scotch_rules'), contains('at least three years'));
    expect(text('ki_bev_sake_ginjo'), contains('60 percent'));
    expect(text('ki_bev_sake_ginjo'), contains('50 percent'));
    expect(text('ki_bev_sake_junmai'), contains('no added brewer\'s alcohol'));
    expect(
      text('ki_bev_sake_junmai'),
      contains('no single polishing-ratio ceiling'),
    );
    expect(text('ki_bev_cognac_mentions'), contains('Napoleon is at least 6'));
    expect(
      text('ki_bev_cognac_mentions'),
      contains('not the 1855 classification'),
    );
    expect(text('ki_bev_bourbon_corn'), contains('Kentucky is not required'));
    expect(text('ki_bev_cider_perry'), contains('not a world definition'));
    expect(text('ki_bev_habano_name'), contains('not a Habano'));
    expect(text('ki_bev_tobacco_harm'), contains('no safe level'));
    expect(text('ki_bev_alcohol_harm'), contains('no safe level'));
    expect(
      dataset.knowledgeItems.map((item) => item.assertionText).join('\n'),
      isNot(contains('Reinheitsgebot')),
    );
  });
}
