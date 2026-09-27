import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_sf_'))
      .toList();
  final facts = {for (final item in lessons) item.id: item.assertionText};

  test(
    'sparkling and fortified closure validates with cited review status',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(lessons, hasLength(77));
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
    },
  );

  test(
    'sparkling routes, origin labels and modern categories stay distinct',
    () {
      expect(
        facts['ki_wset_sf_asti_method'],
        contains('one alcoholic fermentation'),
      );
      expect(
        facts['ki_wset_sf_asti_stop'],
        contains('not the spirit addition'),
      );
      expect(facts['ki_wset_sf_asti_current'], contains('does not guarantee'));
      expect(facts['ki_wset_sf_prosecco_identity'], contains('Glera'));
      expect(
        facts['ki_wset_sf_prosecco_labels'],
        contains('Extra Dry sits above Brut in residual sugar'),
      );
      expect(facts['ki_wset_sf_cava_aging'], contains('18'));
      expect(facts['ki_wset_sf_cava_guarda'], contains('2025 harvest'));
      expect(
        facts['ki_wset_sf_sekt_origin'],
        contains('does not establish German'),
      );
      expect(
        facts['ki_wset_sf_cap_environment'],
        contains('does not establish'),
      );
    },
  );

  test(
    'fortified methods explain named styles without universal legal claims',
    () {
      expect(facts['ki_wset_sf_port_autovinifier'], contains('pressure'));
      expect(
        facts['ki_wset_sf_port_mechanical'],
        contains('rather than assuming'),
      );
      expect(facts['ki_wset_sf_port_vintage_lbv'], contains('Vintage'));
      expect(
        facts['ki_wset_sf_sherry_current_route'],
        contains('wine and liqueur-wine'),
      );
      expect(facts['ki_wset_sf_sherry_pale_cream'], contains('rectified'));
      expect(facts['ki_wset_sf_sherry_medium'], contains('sweetened'));
      expect(facts['ki_wset_sf_sherry_cream_style'], contains('blend'));
      expect(facts['ki_wset_sf_beaumes_fresh'], contains('youthful'));
      expect(facts['ki_wset_sf_rutherglen_evolution'], contains('evaporation'));
    },
  );

  test('regional price reasoning names the conditional process and costs', () {
    for (final id in [
      'ki_wset_sf_cremant_cellar_cost',
      'ki_wset_sf_asti_cost',
      'ki_wset_sf_prosecco_cost',
      'ki_wset_sf_sekt_cost',
      'ki_wset_sf_newworld_spark_cost',
    ]) {
      expect(facts[id], isNotNull, reason: id);
      expect(
        facts[id]!.toLowerCase(),
        anyOf(contains('price'), contains('cost')),
        reason: id,
      );
    }
    for (final id in [
      'ki_spark_case_fruit_tank_reason',
      'ki_spark_case_transfer_batch_tradeoff',
      'ki_fort_case_port_fruit_reason',
      'ki_fort_case_flor_oxygen_action',
      'ki_fort_case_ruth_balance_limitation',
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
