import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const expectedIds = <String>{
  'ki_reg_fm_cabardes_climate',
  'ki_reg_fm_cabardes_grapes',
  'ki_reg_fm_larzac_nights',
  'ki_reg_fm_maury_dry',
  'ki_reg_fm_pic_climate',
  'ki_reg_fm_picpoul_exposure',
  'ki_reg_fm_varois_inland',
  'ki_reg_fs_saumur_thermal',
  'ki_reg_fs_marsanne_palate',
  'ki_reg_fs_bergerac_dry',
  'ki_reg_isi_fiano_style',
  'ki_reg_isi_greco_style',
  'ki_reg_isi_nero_structure',
  'ki_reg_isi_primitivo_style',
  'ki_reg_isi_gallura_identity',
  'ki_reg_gr_naoussa_seasons',
  'ki_reg_ib_baga_structure',
  'ki_reg_ib_dao_encruzado',
  'ki_reg_ib_sacra_terraces',
  'ki_reg_ib_utiel_bobal',
  'ki_reg_ah_kamptal_climate',
  'ki_reg_ah_kremstal_air',
  'ki_reg_ah_leithaberg_climate',
  'ki_reg_ah_leithaberg_grapes',
  'ki_reg_ah_tokaj_loess',
  'ki_reg_ah_tokaj_volcanic',
  'ki_reg_ah_weinviertel_sites',
  'ki_reg_am_rogue_diversity',
  'ki_reg_de_ruwer_relative_height',
  'ki_reg_de_saar_exposure',
  'ki_reg_sa_neuquen_grapes',
  'ki_reg_sa_rionegro_profiles',
  'ki_wset_nw_bc_vqa_origin',
  'ki_wset_nw_ontario_vqa_origins',
  'ki_wset_nw_south_africa_estate',
  'ki_wset_nw_usa_origin_scale',
  'ki_wset_nwa_argentina_ig_examples',
  'ki_wset_nwa_argentina_origin_terms',
  'ki_wset_nwa_lujan_doc_distinction',
  'ki_wset_nwa_nz_enduring_origins',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_wset_l3_geography_gap_scenarios_2',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('40 further core geography assertions have linked, varied choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choices.keys.toSet(), expectedIds);
    expect(template.mode, 'authored_choice');
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
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
    expect(expectedIds.intersection(directCoreIds), hasLength(39));
    expect(expectedIds.difference(directCoreIds), {
      'ki_wset_nw_usa_origin_scale',
    });

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
    expect(answerPositions, {0: 10, 1: 10, 2: 10, 3: 10});
  });

  test('the 40 questions ingest and enter Level 3 practice', () async {
    final db = openTestDatabase();
    try {
      await CurriculumIngester(db).ingest(dataset);
      final questions = await db.select(db.questions).get();
      final selected = questions.where(
        (question) => question.questionTemplateId == template.id,
      );
      expect(selected, hasLength(40));
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
