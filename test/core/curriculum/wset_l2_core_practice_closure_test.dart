import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

const expectedDomainById = <String, String>{
  'ki_fault_ethyl_acetate': 'tasting',
  'ki_fault_oxidative_aroma': 'tasting',
  'ki_fault_tca_compound': 'tasting',
  'ki_wset_reason_frost_shoots': 'viticulture',
  'ki_wset_reason_ferment_consumed': 'winemaking',
  'ki_wset_nw_mendoza_malbec_range': 'winemaking',
  'ki_wset_nwa_martinborough_pinot': 'winemaking',
  'ki_wset_nwa_otago_pinot': 'winemaking',
};

void main() {
  final dataset = bundledDataset();
  final templates = dataset.questionTemplates.where(
    (template) =>
        template.id == 'qt_wset_l2_core_principle_choices_6' ||
        template.id == 'qt_wset_l2_core_causal_choices_2',
  );
  final choicesById = <String, Map<String, dynamic>>{
    for (final template in templates)
      for (final entry
          in ((jsonDecode(template.parameters!)
                      as Map<String, dynamic>)['item_choices']
                  as Map<String, dynamic>)
              .entries)
        entry.key: entry.value as Map<String, dynamic>,
  };

  test('the eight core questions grade cited, distinct alternatives', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(templates, hasLength(2));
    expect(choicesById.keys.toSet(), expectedDomainById.keys.toSet());
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final citationPairs = {
      for (final citation in dataset.knowledgeItemCitations)
        (citation.knowledgeItemId, citation.sourceCitationId),
    };
    final mappings = {
      for (final mapping in dataset.certificationKnowledgeMappings)
        if (mapping.certificationId == 'WSET_L2')
          mapping.knowledgeItemId: mapping,
    };
    final positions = <int, int>{};
    for (final entry in choicesById.entries) {
      final item = items[entry.key]!;
      final choice = entry.value;
      final options = (choice['options'] as List<dynamic>).cast<String>();
      final index = choice['correctIndex'] as int;
      expect(item.domainId, expectedDomainById[entry.key], reason: entry.key);
      expect(item.verificationStatus, 'unverified', reason: entry.key);
      expect(item.mcqDisabled, isTrue, reason: entry.key);
      expect(mappings[entry.key]?.importance, 'core', reason: entry.key);
      expect(
        item.relationType,
        entry.key.startsWith('ki_wset_reason_')
            ? 'CAUSES_STATE'
            : 'PRINCIPLE_EXPLANATION',
        reason: entry.key,
      );
      expect(options, hasLength(4), reason: entry.key);
      expect(
        options.map((option) => option.trim().toLowerCase()).toSet(),
        hasLength(4),
        reason: entry.key,
      );
      expect(index, inInclusiveRange(0, 3), reason: entry.key);
      expect(choice['prompt'], isNotEmpty, reason: entry.key);
      expect(choice['explanation'], isNotEmpty, reason: entry.key);
      expect(
        citationPairs.contains((entry.key, choice['sourceCitationId'])),
        isTrue,
        reason: entry.key,
      );
      positions[index] = (positions[index] ?? 0) + 1;
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
    expect(positions, {0: 2, 1: 2, 2: 2, 3: 2});
  });

  test(
    'Level 2 serves the choices and closes all three core domains',
    () async {
      final db = openTestDatabase();
      try {
        final on = isoDate(dataset.publishedAt.toUtc());
        final date = DateTime.parse(on);
        final generation = await CurriculumIngester(
          db,
          clock: Clock.fixed(DateTime.utc(date.year, date.month, date.day, 12)),
        ).ingest(dataset);
        final generated = await db.select(db.questions).get();
        final selected = generated.where(
          (question) => templates.any(
            (template) => template.id == question.questionTemplateId,
          ),
        );
        expect(selected, hasLength(8));
        expect(
          selected.map((question) => question.knowledgeItemId).toSet(),
          expectedDomainById.keys.toSet(),
        );
        for (final track in ['WSET_L2', 'WSET_L3', 'WSET_L4']) {
          final cards = {
            for (final card in await StudyPlanner(db).cards(track))
              card.itemId: card,
          };
          for (final id in expectedDomainById.keys) {
            expect(
              cards[id]?.formats.map((format) => format.mode),
              contains('authored_choice'),
              reason: '$track: $id',
            );
          }
        }
        final coverage = await CoverageChecker(
          db,
          CoveragePolicy.parse(
            File('assets/curriculum/coverage_policy.yaml').readAsStringSync(),
          ),
        ).check('WSET_L2', on: on, skipped: generation.skipped);
        const expectedCore = <String, int>{
          'viticulture': 122,
          'winemaking': 123,
          'tasting': 164,
        };
        for (final entry in expectedCore.entries) {
          final domain = coverage.domains.singleWhere(
            (domain) => domain.id == entry.key,
          );
          expect(domain.counts[CoverageMetric.core], entry.value);
          expect(domain.counts[CoverageMetric.coreUsefulPractice], entry.value);
        }
        expect(
          coverage.gaps.where(
            (gap) =>
                expectedCore.containsKey(gap.item.item.domainId) &&
                gap.item.isCore &&
                gap.kind == GapKind.noUsefulPractice,
          ),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    },
  );
}
