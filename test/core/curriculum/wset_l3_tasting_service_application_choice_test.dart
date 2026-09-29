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

  Map<String, dynamic> choicesFor(String templateId) {
    final template = dataset.questionTemplates.singleWhere(
      (row) => row.id == templateId,
    );
    expect(template.mode, 'authored_choice');
    expect(template.relationType, 'PRINCIPLE_EXPLANATION');
    return (jsonDecode(template.parameters!)
            as Map<String, dynamic>)['item_choices']
        as Map<String, dynamic>;
  }

  test(
    'forty source-linked Level 3 observations have distinct choice practice',
    () async {
      expect(validateDataset(dataset).errors, isEmpty);

      final tasting = choicesFor('qt_wset_l3_tasting_application_23');
      final service = choicesFor('qt_wset_l3_service_application_17');
      expect(tasting, hasLength(23));
      expect(service, hasLength(17));
      expect(tasting.keys.toSet().intersection(service.keys.toSet()), isEmpty);

      final positions = List<int>.filled(4, 0);
      for (final entry in {...tasting, ...service}.entries) {
        final id = entry.key;
        final expectedDomain = tasting.containsKey(id) ? 'tasting' : 'service';
        final item = items[id]!;
        final cue = entry.value as Map<String, dynamic>;
        expect(item.domainId, expectedDomain, reason: id);
        expect(item.mcqDisabled, isTrue, reason: id);
        expect(item.verificationStatus, 'unverified', reason: id);
        final sourceId = cue['sourceCitationId'] as String;
        expect(citations[id], contains(sourceId), reason: id);
        final uri = Uri.parse(sources[sourceId]!.url!);
        expect(uri.scheme, 'https', reason: id);
        expect(uri.host, isNotEmpty, reason: id);
        expect((cue['prompt'] as String).trim(), isNotEmpty, reason: id);
        expect((cue['explanation'] as String).trim(), isNotEmpty, reason: id);
        final options = (cue['options'] as List).cast<String>();
        expect(options, hasLength(4), reason: id);
        expect(
          options.map((option) => option.trim().toLowerCase()).toSet(),
          hasLength(4),
          reason: id,
        );
        final correct = cue['correctIndex'] as int;
        expect(correct, inInclusiveRange(0, 3), reason: id);
        positions[correct]++;
        final others = [
          for (var index = 0; index < options.length; index++)
            if (index != correct) options[index].length,
        ];
        expect(
          options[correct].length,
          greaterThanOrEqualTo(others.reduce((a, b) => a < b ? a : b)),
          reason: id,
        );
        expect(
          options[correct].length,
          lessThanOrEqualTo(others.reduce((a, b) => a > b ? a : b)),
          reason: id,
        );
      }
      expect(positions, [10, 10, 10, 10]);

      final on = isoDate(dataset.publishedAt.toUtc());
      final date = DateTime.parse(on);
      final db = openTestDatabase();
      try {
        final generation = await CurriculumIngester(
          db,
          clock: Clock.fixed(DateTime(date.year, date.month, date.day, 12)),
        ).ingest(dataset);
        final path = 'assets/curriculum/coverage_policy.yaml';
        final checker = CoverageChecker(
          db,
          CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
        );
        final levelThree = await checker.check(
          'WSET_L3',
          on: on,
          skipped: generation.skipped,
        );
        final byId = {for (final item in levelThree.items) item.id: item};
        for (final id in {...tasting.keys, ...service.keys}) {
          final item = byId[id]!;
          expect(item.isCore, isTrue, reason: id);
          expect(item.servedFormats, contains('authored_choice'), reason: id);
          expect(item.hasUsefulPractice, isTrue, reason: id);
        }
      } finally {
        await db.close();
      }
    },
  );
}
