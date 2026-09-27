import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_close_'))
      .toList();
  const reusedAtLevel2 = {
    'ki_landwein_protection',
    'ki_qualitaetswein_protection',
    'ki_praedikatswein_protection',
    'ki_wset_eu_alsace_vt_sgn',
    'ki_wset_taste_ageing_not_all',
    'ki_wset_taste_ageing_evolution',
    'ki_wset_taste_ageing_uncertain',
  };
  const advanced = {
    'ki_wset_close_oiv_old_vineyard',
    'ki_wset_close_vine_wood',
    'ki_wset_close_vine_green_parts',
    'ki_wset_close_pump_over',
    'ki_wset_close_punch_down',
  };

  test(
    'closure is cited original explanatory teaching with conservative status',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(lessons, hasLength(20));
      for (final item in lessons) {
        expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        expect(
          dataset.knowledgeItemCitations.where(
            (citation) => citation.knowledgeItemId == item.id,
          ),
          isNotEmpty,
          reason: item.id,
        );
      }
      for (final id in reusedAtLevel2) {
        expect(
          dataset.knowledgeItems.where((item) => item.id == id),
          hasLength(1),
          reason: 'An existing assertion is reused rather than cloned: $id',
        );
        expect(
          dataset.certificationKnowledgeMappings.where(
            (mapping) =>
                mapping.knowledgeItemId == id &&
                mapping.certificationId == 'WSET_L2',
          ),
          hasLength(1),
          reason: id,
        );
      }
    },
  );

  test('installed closure and reused assertions are currently served at the right level', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final clock = Clock.fixed(DateTime.utc(2026, 9, 27, 20));
    await CurriculumIngester(
      db,
      clock: clock,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ensureCurrent(dataset);
    final current = {
      for (final item in await KnowledgeGraph(db, clock: clock).currentItems())
        item.id,
    };
    final planner = StudyPlanner(db, clock: clock);
    final level1 = {
      for (final card in await planner.cards('WSET_L1')) card.itemId,
    };
    final level2 = {
      for (final card in await planner.cards('WSET_L2')) card.itemId: card,
    };
    final level3 = {
      for (final card in await planner.cards('WSET_L3')) card.itemId: card,
    };
    for (final item in lessons) {
      expect(current, contains(item.id), reason: item.id);
      expect(level1, isNot(contains(item.id)), reason: item.id);
      expect(level3.containsKey(item.id), isTrue, reason: item.id);
      expect(
        level2.containsKey(item.id),
        !advanced.contains(item.id),
        reason: item.id,
      );
      for (final card in [
        level3[item.id],
        if (!advanced.contains(item.id)) level2[item.id],
      ]) {
        final served = card!;
        expect(
          served.formats.map((format) => format.mode),
          containsAll(['flashcard', 'typed']),
          reason: item.id,
        );
        expect(
          served.formats.any((format) => format.mode == 'mcq'),
          isFalse,
          reason:
              'Conditional explanation must not generate a context-free MCQ: ${item.id}',
        );
        expect(
          served.mapping.minimumDepth,
          greaterThanOrEqualTo(2),
          reason: item.id,
        );
      }
    }
    for (final id in reusedAtLevel2) {
      expect(current, contains(id), reason: id);
      expect(level2.containsKey(id), isTrue, reason: id);
      expect(level3.containsKey(id), isTrue, reason: id);
      expect(level2[id]!.formats, isNotEmpty, reason: id);
    }
    expect(await db.select(db.reviewStates).get(), isEmpty);
    expect(await db.select(db.reviewEvents).get(), isEmpty);
  });
}
