import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_prod_'))
      .toList();
  final facts = {for (final item in lessons) item.id: item.assertionText};

  test('general production closure validates with cited review status', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(67));
    for (final item in lessons) {
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
      expect(
        mappings.map((mapping) => mapping.certificationId),
        contains('WSET_L3'),
        reason: item.id,
      );
      expect(
        mappings.every((mapping) => mapping.minimumDepth == 2),
        isTrue,
        reason: item.id,
      );
      expect(
        mappings.any((mapping) => mapping.certificationId == 'WSET_L1'),
        isFalse,
        reason: item.id,
      );
    }
  });

  test('vine terminology and hazards retain their useful distinctions', () {
    expect(
      facts['ki_wset_prod_cross_hybrid'],
      contains('different vine species'),
    );
    expect(
      facts['ki_wset_prod_graft_not_cross'],
      contains('different from breeding'),
    );
    expect(facts['ki_wset_prod_spur_cane'], contains('one-year'));
    expect(
      facts['ki_wset_prod_continental_diurnal'],
      contains('over the year'),
    );
    expect(facts['ki_wset_prod_winter_hilling'], contains('different hazard'));
    expect(facts['ki_wset_prod_organic_winery'], contains('sulphite-free'));
  });

  test('cellar routes avoid conflating related but different operations', () {
    expect(
      facts['ki_wset_prod_destem_crush'],
      contains('not be treated as synonyms'),
    );
    expect(
      facts['ki_wset_prod_carbonic'],
      contains('yeast fermentation completes'),
    );
    expect(
      facts['ki_wset_prod_semi_carbonic'],
      contains('not a wholly yeast-free'),
    );
    expect(
      facts['ki_wset_prod_enrichment'],
      contains('differs from sweetening'),
    );
    expect(
      facts['ki_wset_prod_sweet_stability'],
      contains('not permanent stability'),
    );
    expect(facts['ki_wset_prod_depth_surface'], contains('different aims'));
  });

  test('price, yield, packaging and closure claims remain conditional', () {
    expect(
      facts['ki_wset_prod_cost_yield'],
      contains('does not universally improve'),
    );
    expect(
      facts['ki_wset_prod_harvest_cost_quality'],
      contains('Either can suit'),
    );
    expect(
      facts['ki_wset_prod_closure_performance'],
      contains('no closure guarantees'),
    );
    expect(
      facts['ki_wset_prod_price_chain'],
      contains('does not prove proportionally'),
    );
    for (final id in [
      'ki_vit_case_radiation_frost_reason',
      'ki_vit_case_rain_harvest_tradeoff',
      'ki_win_case_hot_red_reason',
      'ki_win_case_protein_white_limitation',
      'ki_win_case_sweet_bottling_reason',
    ]) {
      expect(
        dataset.certificationKnowledgeMappings.where(
          (mapping) =>
              mapping.certificationId == 'WSET_L3' &&
              mapping.knowledgeItemId == id,
        ),
        hasLength(1),
        reason: id,
      );
    }
  });
}
