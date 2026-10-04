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

const _relationIds = <String, Set<String>>{
  'PRINCIPLE_EXPLANATION': {
    'ki_reg_fe_beaujolais_parcels',
    'ki_reg_fs_anjou_oceanic',
    'ki_reg_fs_saumur_season',
    'ki_reg_isi_salice_styles',
    'ki_wset_role_castilla_styles',
    'ki_wset_role_dornfelder_vine',
    'ki_wset_role_friuli_cellar_cost',
    'ki_wset_role_saumur_champigny_cellar',
  },
  'AWARDED_BY': {'ki_grosses_gewaechs_awarder'},
  'PRIVATE_CLASSIFICATION_OF': {'ki_vdp_grosses_gewaechs_private'},
  'RESERVED_FOR_REGION': {'ki_wset_geo_valpolicella_ripasso_origin'},
};

const _newTierIds = <String>{
  'ki_vdp_gutswein_private',
  'ki_vdp_ortswein_private',
  'ki_vdp_erste_lage_private',
  'ki_vdp_grosse_lage_private',
};

const _templateIds = <String>{
  'qt_wset_l3_geography_remaining_8_principles',
  'qt_wset_l3_geography_gg_awarder',
  'qt_wset_l3_geography_vdp_private',
  'qt_wset_l3_geography_ripasso_origin',
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
  final templates = dataset.questionTemplates
      .where((template) => _templateIds.contains(template.id))
      .toList();
  const retiredId = 'ki_reg_isi_salice_styles';
  const successorId = 'ki_reg_isi_salice_styles_2026';
  final currentRelationIds = {
    for (final entry in _relationIds.entries)
      entry.key: {
        for (final id in entry.value) id == retiredId ? successorId : id,
      },
  };
  final expectedIds = currentRelationIds.values.expand((ids) => ids).toSet();

  test(
    '11 final non-spatial choices are distinct, cited, and legally bounded',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(templates, hasLength(4));
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
      final actualIds = <String>{};
      for (final template in templates) {
        expect(template.mode, 'authored_choice');
        final choices =
            (jsonDecode(template.parameters!)
                    as Map<String, dynamic>)['item_choices']
                as Map<String, dynamic>;
        expect(choices.keys.toSet(), {
          ..._relationIds[template.relationType]!,
          if (template.relationType == 'PRINCIPLE_EXPLANATION') successorId,
          if (template.relationType == 'PRIVATE_CLASSIFICATION_OF')
            ..._newTierIds,
        });
        final historical = _frozenHistoricalChoices(template.id);
        expect(historical.keys.toSet(), {
          ..._relationIds[template.relationType]!,
          if (template.relationType == 'PRIVATE_CLASSIFICATION_OF')
            ..._newTierIds,
        });
        expect(
          {for (final id in historical.keys) id: choices[id]},
          historical,
          reason: 'Preserve every original .73 choice, including retired cues.',
        );
        final activeOriginalIds = choices.keys.toSet().intersection(
          expectedIds,
        );
        expect(activeOriginalIds, currentRelationIds[template.relationType]);
        // The four secondary tier meanings have separate exact grading tests.
        // Preserve the current eleven-item cohort by replacing only the retired point.
        for (final entry in choices.entries.where(
          (entry) => expectedIds.contains(entry.key),
        )) {
          final id = entry.key;
          actualIds.add(id);
          final choice = entry.value as Map<String, dynamic>;
          final options = (choice['options'] as List<dynamic>).cast<String>();
          final answer = choice['correctIndex'] as int;
          final lengths = options.map((option) => option.length).toList();
          expect(items[id]!.domainId, 'geography', reason: id);
          expect(items[id]!.relationType, template.relationType, reason: id);
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
                lengths.where((length) => length == lengths[answer]).length ==
                    1,
            isFalse,
            reason: 'Unique longest key: $id',
          );
          expect(
            lengths[answer] == lengths.reduce((a, b) => a < b ? a : b) &&
                lengths.where((length) => length == lengths[answer]).length ==
                    1,
            isFalse,
            reason: 'Unique shortest key: $id',
          );
          positions[answer] = (positions[answer] ?? 0) + 1;
        }
      }
      expect(actualIds, expectedIds);
      expect(positions, {0: 3, 1: 3, 2: 3, 3: 2});

      final byId = {
        for (final template in templates)
          for (final entry
              in ((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .entries)
            entry.key: entry.value as Map<String, dynamic>,
      };
      expect(
        byId['ki_grosses_gewaechs_awarder']!['sourceCitationId'],
        'src_de_weinv',
      );
      expect(
        byId['ki_grosses_gewaechs_awarder']!['prompt'] as String,
        contains('§30'),
      );
      expect(
        byId['ki_grosses_gewaechs_awarder']!['explanation'] as String,
        contains('2030'),
      );
      expect(
        byId['ki_vdp_grosses_gewaechs_private']!['sourceCitationId'],
        'src_de_vdp_classification',
      );
      expect(
        byId['ki_vdp_grosses_gewaechs_private']!['explanation'] as String,
        contains('private'),
      );
      expect(
        byId['ki_wset_geo_valpolicella_ripasso_origin']!['sourceCitationId'],
        'src_wset_geo_ripasso_spec_2023',
      );
      expect(
        byId['ki_wset_geo_valpolicella_ripasso_origin']!['explanation']
            as String,
        contains('not a separate map settlement'),
      );
    },
  );

  test('11 choices serve Level 3 and complete objective geography after regional cases and location clues', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final servingClock = Clock.fixed(DateTime.utc(2026, 10, 3, 12));
    final generation = await CurriculumIngester(
      db,
      clock: servingClock,
    ).ingest(dataset);
    final generated = (await db.select(db.questions).get()).where(
      (question) =>
          _templateIds.contains(question.questionTemplateId) &&
          expectedIds.contains(question.knowledgeItemId),
    );
    expect(generated, hasLength(11));
    expect(
      (await db.select(db.questions).get()).any(
        (question) =>
            _templateIds.contains(question.questionTemplateId) &&
            question.knowledgeItemId == retiredId,
      ),
      isFalse,
      reason: 'Retained old choices must never add a twelfth current question.',
    );
    expect(
      generated.map((question) => question.knowledgeItemId).toSet(),
      expectedIds,
    );
    final planner = StudyPlanner(db, clock: servingClock);
    final cards = {
      for (final card in await planner.cards('WSET_L3')) card.itemId: card,
    };
    for (final id in expectedIds) {
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
    final geography = audit.domains.singleWhere((row) => row.id == 'geography');
    expect(geography.counts[CoverageMetric.core], 1071);
    expect(geography.counts[CoverageMetric.coreUsefulPractice], 1071);
    for (final id in expectedIds) {
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
      remaining.where((item) => item.item.relationType.startsWith('CASE_')),
      isEmpty,
    );
  });
}
