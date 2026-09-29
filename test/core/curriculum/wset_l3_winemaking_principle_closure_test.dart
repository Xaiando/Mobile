import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l3_winemaking_principle_closure_40',
  );
  final choices =
      (jsonDecode(template.parameters!) as Map<String, dynamic>)['item_choices']
          as Map<String, dynamic>;

  test('40 disjoint winemaking principles have bounded choices', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.mode, 'authored_choice');
    expect(template.relationType, 'PRINCIPLE_EXPLANATION');
    expect(choices, hasLength(40));

    final otherIds = <String>{};
    for (final other in dataset.questionTemplates) {
      if (other.mode != 'authored_choice' || other.id == template.id) continue;
      final otherChoices =
          (jsonDecode(other.parameters!)
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      otherIds.addAll(otherChoices.keys);
    }
    expect(choices.keys.toSet().intersection(otherIds), isEmpty);

    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source,
    };
    final citations = <String, Set<String>>{};
    for (final row in dataset.knowledgeItemCitations) {
      citations
          .putIfAbsent(row.knowledgeItemId, () => {})
          .add(row.sourceCitationId);
    }
    final positions = [0, 0, 0, 0];
    final prefixes = <String, int>{};
    for (final entry in choices.entries) {
      final id = entry.key;
      final cue = entry.value as Map<String, dynamic>;
      final item = items[id]!;
      expect(item.domainId, 'winemaking', reason: id);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      final mapping = dataset.certificationKnowledgeMappings.singleWhere(
        (row) => row.certificationId == 'WSET_L3' && row.knowledgeItemId == id,
      );
      expect(mapping.importance, 'core', reason: id);
      final sourceId = cue['sourceCitationId'] as String;
      expect(citations[id], contains(sourceId), reason: id);
      final sourceUrl = Uri.parse(sources[sourceId]!.url!);
      expect(sourceUrl.scheme, 'https', reason: id);
      expect(sourceUrl.host, isNotEmpty, reason: id);
      expect(sourceUrl.path.length, greaterThan(1), reason: id);
      expect((cue['prompt'] as String).length, greaterThan(50), reason: id);
      expect(
        (cue['explanation'] as String).length,
        greaterThan(55),
        reason: id,
      );
      final options = (cue['options'] as List).cast<String>();
      expect(options, hasLength(4), reason: id);
      expect(
        options.map((option) => option.trim().toLowerCase()).toSet(),
        hasLength(4),
        reason: id,
      );
      final key = cue['correctIndex'] as int;
      expect(key, inInclusiveRange(0, 3), reason: id);
      positions[key]++;
      final lengths = options.map((option) => option.length).toList();
      final keyLength = lengths[key];
      expect(
        keyLength == lengths.reduce((a, b) => a > b ? a : b) &&
            lengths.where((length) => length == keyLength).length == 1,
        isFalse,
        reason: 'key uniquely longest: $id',
      );
      expect(
        keyLength == lengths.reduce((a, b) => a < b ? a : b) &&
            lengths.where((length) => length == keyLength).length == 1,
        isFalse,
        reason: 'key uniquely shortest: $id',
      );
      final prefix = id.split('_')[1];
      prefixes[prefix] = (prefixes[prefix] ?? 0) + 1;
    }
    expect(positions.every((count) => count >= 9 && count <= 11), isTrue);
    expect(prefixes, {
      'fault': 2,
      'fort': 25,
      'spark': 10,
      'wset': 2,
      'reg': 1,
    });
  });

  test('all 40 choices generate useful Level 3 core practice', () async {
    final db = openTestDatabase();
    try {
      final generation = await CurriculumIngester(db).ingest(dataset);
      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final checker = CoverageChecker(
        db,
        CoveragePolicy.parse(
          File(policyPath).readAsStringSync(),
          path: policyPath,
        ),
      );
      final report = await checker.check(
        'WSET_L3',
        on: '2026-09-29',
        skipped: generation.skipped,
      );
      final byId = {for (final item in report.items) item.id: item};
      for (final id in choices.keys) {
        final item = byId[id]!;
        expect(item.isCore, isTrue, reason: id);
        expect(item.servedFormats, contains('authored_choice'), reason: id);
        expect(item.hasUsefulPractice, isTrue, reason: id);
      }
    } finally {
      await db.close();
    }
  });
}
