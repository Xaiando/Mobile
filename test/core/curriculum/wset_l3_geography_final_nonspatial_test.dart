import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
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

void main() {
  final dataset = bundledDataset();
  final templates = dataset.questionTemplates
      .where((template) => _templateIds.contains(template.id))
      .toList();
  final expectedIds = _relationIds.values.expand((ids) => ids).toSet();

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
          if (template.relationType == 'PRIVATE_CLASSIFICATION_OF')
            ..._newTierIds,
        });
        // The four secondary tier meanings have separate exact grading tests.
        // Preserve every original eleven-item mapping and answer assertion.
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
    final generation = await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime.utc(2026, 9, 29, 16)),
    ).ingest(dataset);
    final generated = (await db.select(db.questions).get()).where(
      (question) =>
          _templateIds.contains(question.questionTemplateId) &&
          expectedIds.contains(question.knowledgeItemId),
    );
    expect(generated, hasLength(11));
    expect(
      generated.map((question) => question.knowledgeItemId).toSet(),
      expectedIds,
    );
    final cards = {
      for (final card in await StudyPlanner(db).cards('WSET_L3'))
        card.itemId: card,
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
    ).check('WSET_L3', on: '2026-09-29', skipped: generation.skipped);
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
