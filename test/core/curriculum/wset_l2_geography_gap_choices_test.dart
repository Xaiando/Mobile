import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _expectedIdsByTemplate = <String, Set<String>>{
  'qt_wset_l2_geography_principle_choices': {
    'ki_reg_fe_alsace_autumn',
    'ki_reg_fe_alsace_late_fruit',
    'ki_reg_fe_alsace_pinot_blanc',
    'ki_reg_fe_alsace_riesling',
    'ki_reg_fr_nuits_pinot',
    'ki_reg_fr_rhone_south_blends',
    'ki_reg_inc_brunello_maturation',
    'ki_reg_inc_chianti_separate',
    'ki_reg_inc_classico_heartland',
    'ki_reg_inc_jesi_air',
    'ki_reg_sh_cab_styles',
    'ki_wset_eu_alsace_gc_origin',
    'ki_wset_eu_beaujolais_nouveau_identity',
    'ki_wset_eu_bordeaux_superieur_identity',
    'ki_wset_eu_delle_venezie_identity',
    'ki_wset_eu_delle_venezie_style',
    'ki_wset_eu_fr_vin_de_france',
    'ki_wset_eu_maconnais_white_names',
    'ki_wset_eu_rioja_generico',
    'ki_wset_nw_cape_blend_meaning',
    'ki_wset_nw_south_eastern_range',
    'ki_wset_ofinal_recioto_corvina',
    'ki_wset_origin_priorat_grenache',
    'ki_wset_origin_stellenbosch_merlot',
    'ki_wset_origin_western_cape_chardonnay',
  },
  'qt_wset_l2_geography_protection_choices': {
    'ki_landwein_protection',
    'ki_praedikatswein_protection',
    'ki_qualitaetswein_protection',
  },
  'qt_wset_l2_geography_origin_choices': {
    'ki_wset_geo_alsace_grand_cru_origin',
    'ki_wset_geo_amarone_della_valpolicella_origin',
    'ki_wset_geo_porto_origin',
    'ki_wset_geo_recioto_della_valpolicella_origin',
    'ki_wset_geo_recioto_di_soave_origin',
  },
};

void main() {
  final dataset = bundledDataset();
  final templates = {
    for (final template in dataset.questionTemplates)
      if (_expectedIdsByTemplate.containsKey(template.id))
        template.id: template,
  };
  final selectedIds = {for (final ids in _expectedIdsByTemplate.values) ...ids};

  test('33 core geography facts have distinct, cited and balanced choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(templates.keys.toSet(), _expectedIdsByTemplate.keys.toSet());
    expect(selectedIds, hasLength(33));
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final coreIds = {
      for (final mapping in dataset.certificationKnowledgeMappings)
        if (mapping.certificationId == 'WSET_L2' &&
            mapping.importance == 'core')
          mapping.knowledgeItemId,
    };
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final answerPositions = <int, int>{};
    for (final templateEntry in templates.entries) {
      final template = templateEntry.value;
      expect(template.mode, 'authored_choice');
      final choices =
          (jsonDecode(template.parameters!)
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      expect(choices.keys.toSet(), _expectedIdsByTemplate[templateEntry.key]);
      for (final entry in choices.entries) {
        final item = items[entry.key]!;
        final choice = entry.value as Map<String, dynamic>;
        final options = (choice['options'] as List<dynamic>).cast<String>();
        final index = choice['correctIndex'] as int;
        expect(item.domainId, 'geography', reason: entry.key);
        expect(item.relationType, template.relationType, reason: entry.key);
        expect(item.verificationStatus, 'unverified', reason: entry.key);
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
    }
    expect(answerPositions, {0: 8, 1: 8, 2: 8, 3: 9});
  });

  test('questions ingest and route to Level 2 geography cards', () async {
    final db = openTestDatabase();
    try {
      await CurriculumIngester(db).ingest(dataset);
      final selected = (await db.select(db.questions).get()).where(
        (question) => templates.containsKey(question.questionTemplateId),
      );
      expect(selected, hasLength(33));
      expect(
        selected.map((question) => question.knowledgeItemId).toSet(),
        selectedIds,
      );
      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L2'))
          card.itemId: card,
      };
      for (final id in selectedIds) {
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
