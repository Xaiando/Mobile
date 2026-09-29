import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const expectedIds = <String>{
  'ki_reg_ah_tokaj_aszu_selection',
  'ki_reg_ah_tokaj_autumn',
  'ki_reg_ah_tokaj_furmint',
  'ki_reg_ah_tokaj_hars',
  'ki_reg_fm_rose_ripeness',
  'ki_reg_ib_priorat_access',
  'ki_reg_ib_rias_canopy_context',
  'ki_reg_inc_barbera_timing',
  'ki_reg_inc_classico_altitude',
  'ki_reg_inc_garganega_later',
  'ki_reg_inc_nebbiolo_cycle',
  'ki_reg_inc_nebbiolo_site',
  'ki_reg_na_happy_later_grapes',
  'ki_reg_na_sta_rita_grapes',
  'ki_reg_oa_hunter_rain',
  'ki_wset_apply_sauternes_environment',
  'ki_wset_close_oiv_old_vine',
  'ki_wset_close_old_vine_label',
  'ki_wset_eu_gavi_vineyard',
  'ki_wset_found_nutrients',
  'ki_wset_found_seeds_stems',
  'ki_wset_found_site_climate',
  'ki_wset_found_skin_flavour',
  'ki_wset_found_slope_air',
  'ki_wset_found_vine_resources',
  'ki_wset_nw_calistoga_setting',
  'ki_wset_nw_central_valley_whites',
  'ki_wset_nw_eden_riesling_setting',
  'ki_wset_nw_oakville_setting',
  'ki_wset_nw_otago_pinot_style',
  'ki_wset_nw_rutherford_setting',
  'ki_wset_nw_sonoma_grape_sites',
  'ki_wset_prod_dry_on_off_vine',
  'ki_wset_prod_hand_machine',
  'ki_wset_prod_hazard_animals',
  'ki_wset_prod_latitude_altitude',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_wset_l2_viticulture_gap_choices',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('the 36 selected core viticulture assertions have cited choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(choices.keys.toSet(), expectedIds);
    expect(template.mode, 'authored_choice');
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final mappings = dataset.certificationKnowledgeMappings.where(
      (mapping) => mapping.certificationId == 'WSET_L2',
    );
    final coreIds = {
      for (final mapping in mappings)
        if (mapping.importance == 'core') mapping.knowledgeItemId,
    };
    final answerPositions = <int, int>{};
    for (final entry in choices.entries) {
      final item = items[entry.key]!;
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final index = choice['correctIndex'] as int;
      expect(item.domainId, 'viticulture', reason: entry.key);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: entry.key);
      expect(item.verificationStatus, 'unverified', reason: entry.key);
      expect(item.mcqDisabled, isTrue, reason: entry.key);
      expect(coreIds, contains(entry.key));
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
      final keyedLength = lengths[index];
      expect(
        keyedLength == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == keyedLength).length == 1,
        isFalse,
        reason: 'Unique longest key: ${entry.key}',
      );
      expect(
        keyedLength == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == keyedLength).length == 1,
        isFalse,
        reason: 'Unique shortest key: ${entry.key}',
      );
    }
    expect(answerPositions, {0: 9, 1: 9, 2: 9, 3: 9});
  });

  test('questions ingest and route into WSET Level 2 practice', () async {
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
        for (final card in await StudyPlanner(db).cards('WSET_L2'))
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
