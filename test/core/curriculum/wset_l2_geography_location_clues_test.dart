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

const _templateId = 'qt_wset_l2_geography_location_clues';
const _locationIds = <String>{
  'ki_burgundy_location',
  'ki_wset_geo_argentina_world_location',
  'ki_wset_geo_australia_world_location',
  'ki_wset_geo_canada_world_location',
  'ki_wset_geo_catalunya_do_location',
  'ki_wset_geo_chile_world_location',
  'ki_wset_geo_delle_venezie_location',
  'ki_wset_geo_france_world_location',
  'ki_wset_geo_germany_world_location',
  'ki_wset_geo_hungary_world_location',
  'ki_wset_geo_italy_world_location',
  'ki_wset_geo_navarra_do_location',
  'ki_wset_geo_new_zealand_world_location',
  'ki_wset_geo_pays_doc_location',
  'ki_wset_geo_portugal_world_location',
  'ki_wset_geo_santa_barbara_county_location',
  'ki_wset_geo_sonoma_county_location',
  'ki_wset_geo_south_africa_world_location',
  'ki_wset_geo_spain_world_location',
  'ki_wset_geo_united_states_world_location',
};
const _grapeIds = <String>{
  'ki_chablis_grape',
  'ki_champagne_chardonnay',
  'ki_champagne_pinot_noir',
};

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == _templateId,
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('20 map facts receive distinct, cited and balanced location clues', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.mode, 'authored_choice');
    expect(template.relationType, 'LOCATED_IN');
    expect(choices.keys.toSet(), _locationIds);
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citations = {
      for (final row in dataset.knowledgeItemCitations)
        (row.knowledgeItemId, row.sourceCitationId),
    };
    final mappings = {
      for (final row in dataset.certificationKnowledgeMappings)
        if (row.certificationId == 'WSET_L2') row.knowledgeItemId: row,
    };
    final positions = <int, int>{};
    for (final entry in choices.entries) {
      final id = entry.key;
      final choice = entry.value as Map<String, dynamic>;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final answer = choice['correctIndex'] as int;
      final lengths = options.map((option) => option.length).toList();
      expect(items[id]!.domainId, 'geography', reason: id);
      expect(items[id]!.relationType, 'LOCATED_IN', reason: id);
      expect(mappings[id]!.importance, 'core', reason: id);
      expect(mappings[id]!.minimumDepth, 1, reason: id);
      expect(options, hasLength(4), reason: id);
      expect(options.toSet(), hasLength(4), reason: id);
      expect(answer, inInclusiveRange(0, 3), reason: id);
      expect(choice['prompt'], isNotEmpty, reason: id);
      expect(choice['explanation'], isNotEmpty, reason: id);
      expect(
        (choice['prompt'] as String).toLowerCase(),
        isNot(contains(options[answer].toLowerCase())),
        reason: 'Prompt gives away the location: $id',
      );
      expect(
        citations.contains((id, choice['sourceCitationId'])),
        isTrue,
        reason: id,
      );
      expect(
        lengths[answer] == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == lengths[answer]).length == 1,
        isFalse,
        reason: 'Unique longest answer: $id',
      );
      expect(
        lengths[answer] == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == lengths[answer]).length == 1,
        isFalse,
        reason: 'Unique shortest answer: $id',
      );
      positions[answer] = (positions[answer] ?? 0) + 1;
    }
    expect(positions, {0: 5, 1: 5, 2: 5, 3: 5});
  });

  test(
    'map practice remains and grape recall makes all geography core useful',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final generation = await CurriculumIngester(
        db,
        clock: Clock.fixed(DateTime.utc(2026, 9, 29, 12)),
      ).ingest(dataset);
      final authored = (await db.select(db.questions).get()).where(
        (question) => question.questionTemplateId == _templateId,
      );
      expect(authored, hasLength(20));
      expect(
        authored.map((question) => question.knowledgeItemId).toSet(),
        _locationIds,
      );

      final cards = {
        for (final card in await StudyPlanner(db).cards('WSET_L2'))
          card.itemId: card,
      };
      for (final id in _locationIds) {
        expect(
          cards[id]?.formats.map((format) => format.mode).toSet(),
          containsAll({
            'authored_choice',
            'map_locate',
            'map_identify',
            'map_pair',
          }),
          reason: id,
        );
      }
      for (final id in _grapeIds) {
        expect(
          cards[id]?.formats.map((format) => format.mode).toSet(),
          containsAll({'mcq', 'typed', 'flashcard'}),
          reason: id,
        );
      }

      final audit = await CoverageChecker(
        db,
        CoveragePolicy.parse(
          File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
        ),
      ).check('WSET_L2', on: '2026-09-29', skipped: generation.skipped);
      final geography = audit.domains.singleWhere(
        (domain) => domain.id == 'geography',
      );
      expect(geography.counts[CoverageMetric.core], 276);
      expect(geography.counts[CoverageMetric.coreUsefulPractice], 276);
      for (final id in {..._locationIds, ..._grapeIds}) {
        final item = audit.items.singleWhere((row) => row.id == id);
        expect(item.isCore, isTrue, reason: id);
        expect(item.hasUsefulPractice, isTrue, reason: id);
      }
    },
  );
}
