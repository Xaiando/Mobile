import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/rehearsal/rehearsal.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/study/learner_profile.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final file = File('assets/study/wset_rehearsal.json');
  final bank = RehearsalBank.fromJson(file.readAsStringSync());
  final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  const blueprints = {
    1: {'process': 6, 'styles': 18, 'service': 6},
    2: {
      'vine': 5,
      'winery': 4,
      'principal': 19,
      'regional': 12,
      'sparkfort': 6,
      'service': 4,
    },
    3: {
      'factors': 8,
      'still': 28,
      'sparkling': 5,
      'fortified': 5,
      'service': 4,
    },
  };

  test('original bank has distinct sourced questions and self-assessed written evidence', () {
    expect(bank.mcqs.length, inInclusiveRange(180, 220));
    expect(bank.written.length, greaterThanOrEqualTo(8));
    expect(bank.mcqs.map((q) => q.prompt).toSet(), hasLength(bank.mcqs.length));
    expect(
      bank.mcqs.any(
        (question) => question.itemIds.any((id) => id.contains('madeira')),
      ),
      isFalse,
      reason: 'Optional Madeira enrichment does not enter required wine-level presets.',
    );
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    for (var level = 1; level <= 3; level++) {
      final required = scope.levels
          .firstWhere((l) => l.certificationId == 'WSET_L$level')
          .requirements
          .expand((r) => r.itemIds)
          .toSet();
      final links = {
        for (final q in bank.mcqs.where((q) => q.levels.contains(level)))
          ...q.itemIds,
        for (final q in bank.written.where((q) => q.levels.contains(level)))
          ...q.itemIds,
      };
      expect(
        links.difference(required),
        isEmpty,
        reason: 'L$level required rehearsals use exact reviewed study evidence',
      );
    }
    expect(
      bank.mcqs
          .where((q) => q.levels.contains(2))
          .any(
            (q) =>
                q.id == 'fortified_vdn_mutage' || q.id == 'winery_amber_style',
          ),
      isFalse,
    );
    expect(bank.mcqs.any((q) => q.id == 'region_reg_ah_vienna_joint'), isFalse);
    for (final question in bank.mcqs) {
      expect(question.options, hasLength(4), reason: question.id);
      expect(
        question.options.map((option) => option.text).toSet(),
        hasLength(4),
        reason: question.id,
      );
      expect(
        question.blueprintByLevel.keys.toSet(),
        question.levels.map((l) => '$l').toSet(),
        reason: question.id,
      );
    }
    final linked = {
      for (final q in bank.mcqs) ...q.itemIds,
      for (final q in bank.written) ...q.itemIds,
    };
    for (final id in linked) {
      expect(items.containsKey(id), isTrue, reason: id);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == id,
        ),
        isTrue,
        reason: id,
      );
    }
    expect(
      bank.mcqs.every(
        (q) => q.itemIds.any((id) => items[id]!.relationType != 'LOCATED_IN'),
      ),
      isTrue,
    );
    for (final question in bank.written) {
      expect(
        question.criteria.length,
        greaterThanOrEqualTo(4),
        reason: question.id,
      );
      expect(question.levels, [3]);
      expect(
        question.criteria.map((c) => c.id).toSet(),
        hasLength(question.criteria.length),
      );
    }
  });

  test('bank spans all required Level 2 grape profiles and broad Level 3 still origins', () {
    const grapes = {
      'chardonnay',
      'sauvignon_blanc',
      'pinot_gris',
      'riesling',
      'cabernet_sauvignon',
      'merlot',
      'pinot_noir',
      'syrah',
      'gamay',
      'grenache',
      'tempranillo',
      'nebbiolo',
      'barbera',
      'sangiovese',
      'corvina',
      'montepulciano',
      'zinfandel',
      'pinotage',
      'carmenere',
      'malbec',
      'chenin_blanc',
      'semillon',
      'viognier',
      'gewurztraminer',
      'verdicchio',
      'cortese',
      'garganega',
      'fiano',
      'albarino',
      'furmint',
    };
    for (final grape in grapes) {
      expect(
        bank.mcqs.where(
          (q) =>
              q.levels.contains(2) &&
              q.itemIds.contains('ki_wset_grape_${grape}_profile'),
        ),
        isNotEmpty,
        reason: grape,
      );
    }
    expect(
      bank.mcqs.where(
        (q) => q.levels.contains(1) && q.id.endsWith('_beginner'),
      ),
      hasLength(8),
    );
    final originTags = <String>{
      for (final q in raw['mcqs'] as List)
        if ((q['levels'] as List).contains(3) &&
            q['blueprintByLevel']['3'] == 'still')
          ...List<String>.from(q['coverageTags'] as List)
              .where((tag) => tag.startsWith('origin:')),
    };
    expect(
      originTags,
      containsAll([
        'origin:france',
        'origin:italy',
        'origin:spain',
        'origin:portugal',
        'origin:germany',
        'origin:austria',
        'origin:hungary',
        'origin:greece',
        'origin:usa',
        'origin:canada',
        'origin:chile',
        'origin:argentina',
        'origin:australia',
        'origin:new_zealand',
        'origin:south_africa',
      ]),
    );
    for (final preset in bank.presets) {
      expect(preset.blueprint, blueprints[preset.level]);
      for (final bucket in preset.blueprint.entries) {
        expect(
          bank.mcqs
              .where((q) => q.blueprintByLevel['${preset.level}'] == bucket.key)
              .length,
          greaterThanOrEqualTo(bucket.value),
          reason: '${preset.level}:${bucket.key}',
        );
      }
    }
  });

  test('real installed current facts can sample every full preset with exact topic totals', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final clock = Clock.fixed(DateTime.utc(2026, 9, 27, 20));
    await CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ensureCurrent(dataset);
    final currentIds = {
      for (final item in await KnowledgeGraph(db, clock: clock).currentItems())
        item.id,
    };
    final repository = RehearsalRepository(
      db,
      bank: bank,
      clock: clock,
      random: Random(191),
    );
    for (var level = 1; level <= 3; level++) {
      await LearnerProfiles(db, clock: clock).selectTrack('WSET_L$level');
      final mappings = await StudyPlanner(
        db,
        clock: clock,
      ).effectiveMappings('WSET_L$level');
      // Check every eligible bank row, rather than only the random sample.
      final allLinks = {
        for (final q in bank.mcqs.where((q) => q.levels.contains(level)))
          ...q.itemIds,
        for (final q in bank.written.where((q) => q.levels.contains(level)))
          ...q.itemIds,
      };
      for (final id in allLinks) {
        expect(currentIds.contains(id), isTrue, reason: 'L$level current $id');
        expect(mappings.containsKey(id), isTrue, reason: 'L$level mapped $id');
      }
      for (var sample = 0; sample < 3; sample++) {
        final attempt = await repository.start(level);
        expect(attempt.mcqs, hasLength(level == 1 ? 30 : 50));
        expect(attempt.written, hasLength(level == 3 ? 4 : 0));
        expect(
          attempt.mcqs.map((q) => q.id).toSet(),
          hasLength(attempt.mcqs.length),
        );
        expect(
          attempt.deadline.difference(attempt.startedAt).inSeconds,
          [2700, 3600, 7200][level - 1],
        );
        final counts = <String, int>{};
        for (final question in attempt.mcqs) {
          counts.update(
            question.blueprintByLevel['$level']!,
            (n) => n + 1,
            ifAbsent: () => 1,
          );
        }
        expect(counts, blueprints[level]);
        await repository.finish(attempt.id);
      }
    }
    expect(await repository.history(), hasLength(9));
    expect(await db.select(db.reviewEvents).get(), isEmpty);
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(
      (await db.select(db.userSettings).get()).any(
        (s) => s.name.startsWith('exam_pass_'),
      ),
      isFalse,
    );
  });
}
