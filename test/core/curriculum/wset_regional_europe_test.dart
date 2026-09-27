import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final scope = WsetScope.fromJson(
    File('assets/progress/wset_scope.json').readAsStringSync(),
  );
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_eu_'))
      .toList();
  final facts = {for (final item in lessons) item.id: item.assertionText};

  test('regional Europe lessons validate and retain cited review status', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(101));
    expect(lessons.map((item) => item.subjectId).toSet(), hasLength(47));
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
        (mapping) =>
            mapping.knowledgeItemId == item.id &&
            mapping.certificationId.startsWith('WSET_'),
      );
      final authoredMappings = mappings.where(
        (mapping) =>
            dataset
                .locate((
                  section: 'certification_knowledge_mappings',
                  key: rowKey('certification_knowledge_mappings', mapping),
                ))
                ?.path
                .endsWith('wset_regional_europe.yaml') ??
            false,
      );
      expect(authoredMappings, hasLength(1), reason: item.id);
      expect(
        {'WSET_L2', 'WSET_L3'},
        contains(authoredMappings.single.certificationId),
        reason: item.id,
      );
      final requiredLevels =
          scope.levels
              .where((level) => level.requiredItemIds.contains(item.id))
              .map((level) => level.certificationId)
              .toList()
            ..sort();
      expect(requiredLevels, isNotEmpty, reason: item.id);
      final expectedTracks = {
        authoredMappings.single.certificationId,
        requiredLevels.first,
      };
      expect(mappings, hasLength(expectedTracks.length), reason: item.id);
      expect(
        mappings.map((mapping) => mapping.certificationId).toSet(),
        expectedTracks,
        reason: '${item.id}: only its authored level and required lower reuse',
      );
    }
    expect(
      dataset.questionTemplates
          .where((template) => template.relationType == 'PRINCIPLE_EXPLANATION')
          .map((template) => template.mode)
          .toSet(),
      containsAll({'short_answer', 'flashcard', 'typed'}),
    );
  });

  test('required wine identities do not collapse distinct label concepts', () {
    expect(
      facts['ki_wset_eu_bourgogne_cote_or_level'],
      contains('does not make it a village'),
    );
    expect(
      facts['ki_wset_eu_saint_emilion_grand_cru_classe'],
      contains('separate'),
    );
    expect(facts['ki_wset_eu_recioto_soave_sweet'], contains('Garganega'));
    expect(facts['ki_wset_eu_recioto_valpolicella_sweet'], contains('sweet'));
    expect(facts['ki_wset_eu_valencia_whites'], contains('Community'));
    expect(facts['ki_wset_eu_sicilia_terre_identity'], contains('separate'));
    expect(facts['ki_wset_eu_it_classico_origin'], contains('separate'));
    expect(facts['ki_wset_eu_es_vino_tierra'], contains('unregulated'));
  });

  test('late-harvest, origin and sweetness labels remain separate', () {
    expect(facts['ki_wset_eu_de_predicate_sweetness'], contains('sweetness'));
    expect(facts['ki_wset_eu_alsace_vt_sgn'], contains('botrytised'));
    expect(facts['ki_wset_eu_at_predikatswein'], contains('harvesting'));
    expect(facts['ki_wset_eu_at_dac_meaning'], contains('regional'));
    expect(
      facts['ki_wset_eu_rioja_generico'],
      contains('maturation does not fit'),
    );
  });

  test(
    'Level 3 regional applications reuse cases without optional scope creep',
    () {
      final areaMappings = dataset.certificationKnowledgeMappings.where(
        (mapping) =>
            dataset
                .locate((
                  section: 'certification_knowledge_mappings',
                  key: rowKey('certification_knowledge_mappings', mapping),
                ))
                ?.path
                .endsWith('wset_regional_europe.yaml') ??
            false,
      );
      // A stable fact lookup avoids promoting advanced geography because a pack
      // happens to contain neighbouring optional regions.
      final mappings = dataset.certificationKnowledgeMappings;
      for (final id in [
        'ki_reg_fr_case_bordeaux_blend_reason',
        'ki_reg_inc_case_nebbiolo_list_reason',
        'ki_reg_ib_case_es_priorat_price_reason',
        'ki_reg_de_case_mosel_steep_budget_reason',
        'ki_reg_ah_case_tokaj_selection_reason',
        'ki_reg_gr_case_santorini_training_reason',
      ]) {
        expect(
          mappings.where(
            (mapping) =>
                mapping.knowledgeItemId == id &&
                mapping.certificationId == 'WSET_L3',
          ),
          hasLength(1),
          reason: id,
        );
      }
      expect(
        areaMappings.where(
          (mapping) =>
              mapping.knowledgeItemId.contains('jura') ||
              mapping.knowledgeItemId.contains('cannonau') ||
              mapping.knowledgeItemId.contains('vienna') ||
              mapping.knowledgeItemId.contains('styria'),
        ),
        isEmpty,
      );
    },
  );
}
