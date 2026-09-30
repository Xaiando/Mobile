import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/time/utc_clock.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final citations = <String, Set<String>>{};
  for (final row in dataset.knowledgeItemCitations) {
    citations
        .putIfAbsent(row.knowledgeItemId, () => <String>{})
        .add(row.sourceCitationId);
  }
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const templateGroups = {
    'qt_wset_l3_tasting_fault_closure_12': (
      'PRINCIPLE_EXPLANATION',
      'tasting',
      12,
    ),
    'qt_wset_l3_service_principle_closure_8': (
      'PRINCIPLE_EXPLANATION',
      'service',
      8,
    ),
    'qt_wset_l3_service_case_action_closure_4': ('CASE_ACTION', 'service', 4),
    'qt_wset_l3_service_case_reason_closure_4': ('CASE_REASON', 'service', 4),
    'qt_wset_l3_service_case_tradeoff_closure_4': (
      'CASE_TRADEOFF',
      'service',
      4,
    ),
    'qt_wset_l3_service_case_limitation_closure_4': (
      'CASE_LIMITATION',
      'service',
      4,
    ),
  };

  test('Level 3 tasting and service core has sourced, usable practice', () async {
    expect(validateDataset(dataset).errors, isEmpty);
    final positions = List<int>.filled(4, 0);
    final chosenIds = <String>{};
    for (final templateGroup in templateGroups.entries) {
      final template = dataset.questionTemplates.singleWhere(
        (row) => row.id == templateGroup.key,
      );
      expect(template.mode, 'authored_choice');
      expect(template.relationType, templateGroup.value.$1);
      final choices =
          (jsonDecode(template.parameters!)
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      expect(choices, hasLength(templateGroup.value.$3));
      for (final choice in choices.entries) {
        expect(chosenIds.add(choice.key), isTrue, reason: choice.key);
        final item = items[choice.key]!;
        expect(item.domainId, templateGroup.value.$2, reason: choice.key);
        expect(item.relationType, templateGroup.value.$1, reason: choice.key);
        expect(item.mcqDisabled, isTrue, reason: choice.key);
        final cue = choice.value as Map<String, dynamic>;
        final sourceId = cue['sourceCitationId'] as String;
        expect(citations[choice.key], contains(sourceId), reason: choice.key);
        final uri = Uri.parse(sources[sourceId]!.url!);
        expect(uri.scheme, 'https', reason: choice.key);
        expect(uri.host, isNotEmpty, reason: choice.key);
        final options = (cue['options'] as List).cast<String>();
        expect(options, hasLength(4), reason: choice.key);
        expect(
          options.map((option) => option.trim().toLowerCase()).toSet(),
          hasLength(4),
          reason: choice.key,
        );
        final correct = cue['correctIndex'] as int;
        expect(correct, inInclusiveRange(0, 3), reason: choice.key);
        positions[correct]++;
        final others = [
          for (var index = 0; index < options.length; index++)
            if (index != correct) options[index].length,
        ];
        expect(
          options[correct].length,
          greaterThanOrEqualTo(others.reduce((a, b) => a < b ? a : b)),
          reason: choice.key,
        );
        expect(
          options[correct].length,
          lessThanOrEqualTo(others.reduce((a, b) => a > b ? a : b)),
          reason: choice.key,
        );
      }
    }
    expect(chosenIds, hasLength(36));
    expect(positions, [9, 9, 9, 9]);

    final on = isoDate(dataset.publishedAt.toUtc());
    final date = DateTime.parse(on);
    final db = openTestDatabase();
    try {
      final generation = await CurriculumIngester(
        db,
        clock: Clock.fixed(DateTime(date.year, date.month, date.day, 12)),
      ).ingest(dataset);
      const path = 'assets/curriculum/coverage_policy.yaml';
      final checker = CoverageChecker(
        db,
        CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
      );
      final levelThree = await checker.check(
        'WSET_L3',
        on: on,
        skipped: generation.skipped,
      );
      final inScope = levelThree.items.where(
        (item) =>
            item.isCore &&
            (item.item.domainId == 'tasting' ||
                item.item.domainId == 'service'),
      );
      expect(
        inScope.where((item) => item.item.domainId == 'tasting'),
        hasLength(178),
      );
      expect(
        inScope.where((item) => item.item.domainId == 'service'),
        hasLength(104),
      );
      expect(
        inScope.where((item) => !item.hasUsefulPractice),
        isEmpty,
        reason:
            'Every Level 3 tasting and service core fact needs a useful format',
      );
      for (final item in inScope.where((item) => chosenIds.contains(item.id))) {
        expect(
          item.servedFormats,
          contains('authored_choice'),
          reason: item.id,
        );
      }
    } finally {
      await db.close();
    }
  });
}
