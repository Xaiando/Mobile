import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const expectedIds = <String>{
  'ki_reg_ah_tokaj_continental',
  'ki_reg_ah_wachau_air',
  'ki_reg_ah_neusiedler_botrytis',
  'ki_reg_de_mosel_upper_setting',
  'ki_reg_fe_alsace_gewurz',
  'ki_reg_fe_beaujolais_gamay',
  'ki_reg_fs_jurancon_foehn',
  'ki_reg_fm_provence_maritime',
  'ki_reg_fr_hautes_plateaus',
  'ki_reg_fs_chateauneuf_variation',
  'ki_reg_fs_chinon_sites',
  'ki_reg_fs_cahors_terraces',
  'ki_reg_gr_naoussa_variation',
  'ki_reg_gr_nemea_inland_nights',
  'ki_reg_gr_santorini_wind_drought',
  'ki_reg_ib_dao_mountains',
  'ki_reg_ib_ribera_elevation',
  'ki_reg_ib_rueda_ripening',
  'ki_reg_isi_abruzzo_climate',
  'ki_reg_isi_irpinia_terrain',
  'ki_reg_am_niagara_water',
  'ki_reg_am_okanagan_variation',
  'ki_reg_am_alexander_cabernet',
  'ki_reg_am_templeton_air',
  'ki_reg_fs_gigondas_exposure',
  'ki_wset_eu_bordeaux_classifications_scope',
  'ki_wset_eu_burgundy_grand_cru',
  'ki_wset_eu_burgundy_premier_cru',
  'ki_wset_eu_rioja_ageing_labels',
  'ki_wset_eu_saint_emilion_grand_cru_classe',
  'ki_wset_nw_australia_gi_levels',
  'ki_wset_nw_chile_crosswise_terms',
  'ki_wset_nw_chile_origin_hierarchy',
  'ki_wset_nw_south_africa_wo_origin',
  'ki_wset_nw_usa_ava_origin',
  'ki_wset_nwa_nz_origin_label',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_wset_l3_geography_gap_scenarios',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('36 unserved Level 3 core geography assertions have linked choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choices.keys.toSet(), expectedIds);
    expect(template.mode, 'authored_choice');
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    // Level 3 coverage inherits core Level 2 knowledge alongside direct mappings.
    final directCoreIds = {
      for (final mapping in dataset.certificationKnowledgeMappings)
        if (mapping.certificationId == 'WSET_L3' &&
            mapping.importance == 'core')
          mapping.knowledgeItemId,
    };
    final inheritedCoreIds = {
      for (final mapping in dataset.certificationKnowledgeMappings)
        if (mapping.certificationId == 'WSET_L2' &&
            mapping.importance == 'core')
          mapping.knowledgeItemId,
    };
    expect(expectedIds.intersection(directCoreIds), hasLength(28));
    expect(expectedIds.difference(directCoreIds), hasLength(8));
    final answerPositions = <int, int>{};
    for (final entry in choices.entries) {
      final item = items[entry.key]!;
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final index = choice['correctIndex'] as int;
      expect(item.domainId, 'geography', reason: entry.key);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: entry.key);
      expect(item.verificationStatus, 'unverified', reason: entry.key);
      expect(item.mcqDisabled, isTrue, reason: entry.key);
      expect(directCoreIds.union(inheritedCoreIds), contains(entry.key));
      expect(options, hasLength(4), reason: entry.key);
      expect(options.toSet(), hasLength(4), reason: entry.key);
      expect(index, inInclusiveRange(0, 3), reason: entry.key);
      expect(choice['prompt'], isNotEmpty, reason: entry.key);
      expect(choice['explanation'], isNotEmpty, reason: entry.key);
      expect(
        citationPairs.contains((entry.key, choice['sourceCitationId'])),
        isTrue,
        reason: entry.key,
      );
      answerPositions[index] = (answerPositions[index] ?? 0) + 1;
      final lengths = options.map((option) => option.length).toList();
      final keyLength = lengths[index];
      expect(
        keyLength == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == keyLength).length == 1,
        isFalse,
        reason: 'Unique longest key: ${entry.key}',
      );
      expect(
        keyLength == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == keyLength).length == 1,
        isFalse,
        reason: 'Unique shortest key: ${entry.key}',
      );
    }
    expect(answerPositions, {0: 9, 1: 9, 2: 9, 3: 9});
  });

  test('the 36 questions ingest and enter Level 3 practice', () async {
    final db = openTestDatabase();
    try {
      await CurriculumIngester(db).ingest(dataset);
      final questions = await db.select(db.questions).get();
      final selected = questions.where(
        (question) => question.questionTemplateId == template.id,
      );
      expect(selected, hasLength(36));
      expect(
        selected.map((question) => question.knowledgeItemId).toSet(),
        expectedIds,
      );
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L3'))
          card.itemId: card,
      };
      for (final id in expectedIds) {
        expect(
          cards[id]?.formats.map((format) => format.mode),
          contains('authored_choice'),
          reason: id,
        );
      }
    } finally {
      await db.close();
    }
  });
}
