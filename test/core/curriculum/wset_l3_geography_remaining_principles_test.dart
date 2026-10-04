import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const _templateId = 'qt_wset_l3_geography_remaining_principles_40';
const _expectedIds = <String>{
  'ki_reg_de_franken_silvaner_palate',
  'ki_reg_fe_beaujolais_chardonnay',
  'ki_reg_fe_beaujolais_hills',
  'ki_reg_fm_languedoc_mediterranean',
  'ki_reg_fm_languedoc_west',
  'ki_reg_fm_larzac_soils',
  'ki_reg_fm_pic_syrah',
  'ki_reg_fm_roussillon_colours',
  'ki_reg_fm_roussillon_seasons',
  'ki_reg_fm_villages_red',
  'ki_reg_fs_lirac_variation',
  'ki_reg_fs_muscadet_melon',
  'ki_reg_fs_pacherenc_grapes',
  'ki_reg_isi_frappato_expression',
  'ki_reg_isi_salice_context',
  'ki_reg_isi_vulture_setting',
  'ki_wset_eu_greece_three_grapes',
  'ki_wset_role_alfrocheiro',
  'ki_wset_role_arinto',
  'ki_wset_role_blaufrankisch',
  'ki_wset_role_bonarda_identity',
  'ki_wset_role_bonarda_style',
  'ki_wset_role_castilla_environment',
  'ki_wset_role_castilla_igp_identity',
  'ki_wset_role_dornfelder_style',
  'ki_wset_role_friuli_identity',
  'ki_wset_role_friuli_white_styles',
  'ki_wset_role_graciano',
  'ki_wset_role_jaen_blend',
  'ki_wset_role_jaen_identity',
  'ki_wset_role_mazuelo',
  'ki_wset_role_petit_verdot',
  'ki_wset_role_saint_laurent',
  'ki_wset_role_sarga_muskotaly',
  'ki_wset_role_saumur_champigny_identity',
  'ki_wset_role_trincadeira_style',
  'ki_wset_role_trincadeira_vine',
  'ki_wset_role_welschriesling_dry',
  'ki_wset_role_welschriesling_sweet',
  'ki_wset_role_zweigelt',
};

Map<String, dynamic> _frozenHistoricalChoices(String templateId) {
  final compressed = File(
    'test/fixtures/curriculum/diploma_release_0_24_73_complete_frozen.json.gz',
  ).readAsBytesSync();
  expect(
    sha256.convert(compressed).toString(),
    '15a944ed92394c94d4ec67b9fb83388bf3b8718e15e3c3da007af5666e211cdf',
  );
  final frozen =
      jsonDecode(utf8.decode(gzip.decode(compressed))) as Map<String, dynamic>;
  expect(frozen['dataset_version'], '0.24.73');
  final template = (frozen['question_templates'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((row) => row['id'] == templateId);
  return (template['parameters'] as Map<String, dynamic>)['item_choices']
      as Map<String, dynamic>;
}

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;
  const retiredId = 'ki_reg_isi_salice_context';
  const successorId = 'ki_reg_isi_salice_context_2026';
  final currentExpectedIds = {
    for (final id in _expectedIds) id == retiredId ? successorId : id,
  };
  final currentChoices = {
    for (final entry in choices.entries)
      if (currentExpectedIds.contains(entry.key)) entry.key: entry.value,
  };

  test('40 distinct Level 3 core comparisons have linked sources and balanced answers', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.mode, 'authored_choice');
    expect(template.relationType, 'PRINCIPLE_EXPLANATION');
    // Legacy cues remain exact historical records; only their successors serve.
    expect(choices.keys.toSet(), {..._expectedIds, successorId});
    final historical = _frozenHistoricalChoices(_templateId);
    expect(historical.keys.toSet(), _expectedIds);
    expect(
      {for (final id in _expectedIds) id: choices[id]},
      historical,
      reason: 'Preserve every original .73 authored choice verbatim.',
    );
    expect(currentChoices.keys.toSet(), currentExpectedIds);
    expect(currentChoices, hasLength(40));
    final items = {for (final row in dataset.knowledgeItems) row.id: row};
    final mappings = {
      for (final row in dataset.certificationKnowledgeMappings)
        if (row.certificationId == 'WSET_L3') row.knowledgeItemId: row,
    };
    final citationPairs = {
      for (final row in dataset.knowledgeItemCitations)
        (row.knowledgeItemId, row.sourceCitationId),
    };
    expect(items[retiredId]!.supersededByItemId, successorId);
    final positions = <int, int>{};
    final absoluteCue = RegExp(
      r'\b(?:all|always|never|every|guarantee|identical|must|only|compulsory|fixed)\b',
      caseSensitive: false,
    );
    var keyedAbsoluteCues = 0;
    var distractorAbsoluteCues = 0;
    for (final entry in currentChoices.entries) {
      final id = entry.key;
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final answer = choice['correctIndex'] as int;
      final lengths = options.map((option) => option.length).toList();
      expect(items[id]!.domainId, 'geography', reason: id);
      expect(items[id]!.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(items[id]!.verificationStatus, 'unverified', reason: id);
      expect(mappings[id]!.importance, 'core', reason: id);
      expect(options, hasLength(4), reason: id);
      expect(
        options.map((option) => option.toLowerCase()).toSet(),
        hasLength(4),
        reason: id,
      );
      expect(answer, inInclusiveRange(0, 3), reason: id);
      expect(choice['prompt'], isNotEmpty, reason: id);
      expect(choice['explanation'], isNotEmpty, reason: id);
      expect(
        citationPairs.contains((id, choice['sourceCitationId'])),
        isTrue,
        reason: id,
      );
      expect(
        lengths[answer] == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == lengths[answer]).length == 1,
        isFalse,
        reason: 'Unique longest key: $id',
      );
      expect(
        lengths[answer] == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == lengths[answer]).length == 1,
        isFalse,
        reason: 'Unique shortest key: $id',
      );
      for (var index = 0; index < options.length; index++) {
        if (absoluteCue.hasMatch(options[index])) {
          if (index == answer) {
            keyedAbsoluteCues++;
          } else {
            distractorAbsoluteCues++;
          }
        }
      }
      positions[answer] = (positions[answer] ?? 0) + 1;
    }
    expect(positions, {0: 10, 1: 10, 2: 10, 3: 10});
    expect(keyedAbsoluteCues, lessThanOrEqualTo(2));
    expect(distractorAbsoluteCues, lessThanOrEqualTo(16));
  });

  test(
    '40 choices ingest and serve with complete Level 3 geography practice',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final servingClock = Clock.fixed(DateTime.utc(2026, 10, 3, 12));
      final generation = await CurriculumIngester(
        db,
        clock: servingClock,
      ).ingest(dataset);
      final generated = (await db.select(db.questions).get()).where(
        (question) => question.questionTemplateId == _templateId,
      );
      expect(generated, hasLength(40));
      expect(
        generated.map((question) => question.knowledgeItemId).toSet(),
        currentExpectedIds,
      );
      expect(
        generated.any((question) => question.knowledgeItemId == retiredId),
        isFalse,
      );
      final planner = StudyPlanner(db, clock: servingClock);
      final cards = {
        for (final card in await planner.cards('WSET_L3')) card.itemId: card,
      };
      for (final id in currentExpectedIds) {
        expect(
          cards[id]?.formats.map((format) => format.mode).toSet(),
          containsAll({'authored_choice', 'typed', 'flashcard'}),
          reason: id,
        );
      }

      final audit = await CoverageChecker(
        db,
        CoveragePolicy.parse(
          File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
        ),
      ).check('WSET_L3', on: '2026-10-03', skipped: generation.skipped);
      final geography = audit.domains.singleWhere(
        (row) => row.id == 'geography',
      );
      expect(geography.counts[CoverageMetric.core], 1071);
      expect(geography.counts[CoverageMetric.coreUsefulPractice], 1071);
      for (final id in currentExpectedIds) {
        final row = audit.items.singleWhere((item) => item.id == id);
        expect(row.hasUsefulPractice, isTrue, reason: id);
      }
      final remaining = audit.items.where(
        (item) =>
            item.item.domainId == 'geography' &&
            item.isCore &&
            !item.hasUsefulPractice,
      );
      expect(remaining, isEmpty);
      expect(
        remaining.where((item) => item.item.relationType == 'LOCATED_IN'),
        isEmpty,
      );
      expect(
        remaining.where(
          (item) => item.item.relationType == 'PRINCIPLE_EXPLANATION',
        ),
        isEmpty,
      );
    },
  );
}
