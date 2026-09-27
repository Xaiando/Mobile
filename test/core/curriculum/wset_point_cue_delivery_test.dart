import 'dart:convert';
import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  test(
    'every required shared principle has a served point-specific cue',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(DateTime.utc(2026, 9, 27, 20));
      final dataset = bundledDataset();
      final ledger = jsonDecode(
        File('assets/study/wset_typed_point_cues.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final authored = ledger['itemCues'] as Map<String, dynamic>;
      const cueId = 'qt_wset_principle_point_typed';
      final template = dataset.questionTemplates.singleWhere(
        (t) => t.id == cueId,
      );
      expect(template.variant, 'point_scoped_cue');
      expect(jsonDecode(template.parameters!)['item_cues'], authored);

      final scope = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final sharedObjects = <String, Set<String>>{};
      for (final relation in dataset.knowledgeRelations) {
        if (relation.relationType == 'PRINCIPLE_EXPLANATION') {
          sharedObjects
              .putIfAbsent(relation.subjectId, () => {})
              .add(relation.objectId);
        }
      }
      final items = {for (final item in dataset.knowledgeItems) item.id: item};
      final requiredByLevel = {
        for (final level in scope.levels.take(3))
          level.certificationId: {
            for (final id in level.requiredItemIds)
              if (items[id]?.relationType == 'PRINCIPLE_EXPLANATION' &&
                  (sharedObjects[items[id]!.subjectId]?.length ?? 0) > 1)
                id,
          },
      };
      final required = {for (final ids in requiredByLevel.values) ...ids};
      expect(required.length, 520);
      expect(authored.keys.toSet(), {
        ...required,
        'ki_reg_ah_tokaj_oak',
        'ki_reg_ib_ribera_elevation',
        'ki_reg_inc_chianti_separate',
        'ki_reg_inc_classico_heartland',
        'ki_reg_isi_primitivo_early',
      });

      await CurriculumIngester(
        db,
        clock: clock,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ensureCurrent(dataset);
      final generated = await db.select(db.questions).get();
      final templateModes = {
        for (final t in dataset.questionTemplates) t.id: t.mode,
      };
      expect(
        generated
            .where((q) => q.questionTemplateId == cueId)
            .map((q) => q.knowledgeItemId)
            .toSet(),
        authored.keys.toSet(),
      );
      expect(
        generated.where(
          (q) =>
              templateModes[q.questionTemplateId] == 'typed' &&
              authored.containsKey(q.knowledgeItemId) &&
              q.questionTemplateId != cueId,
        ),
        isEmpty,
        reason: 'A corrected point must not also offer the broad sibling-crediting question.',
      );
      final planner = StudyPlanner(db, clock: clock);
      for (final entry in requiredByLevel.entries) {
        final served = {
          for (final card in await planner.cards(entry.key))
            if (card.formats.any((f) => f.questionTemplateId == cueId))
              card.itemId,
        };
        expect(served, containsAll(entry.value), reason: entry.key);
      }

      final presenter = ExercisePresenter(db, clock: clock);
      const format = TypedFormat();
      for (final entry in authored.entries) {
        final cue = entry.value as Map<String, dynamic>;
        final question = await presenter.present(
          entry.key,
          cueId,
          seed: 42,
        ) as TypedQuestion;
        expect(question.prompt, cue['prompt'], reason: entry.key);
        expect(question.explanation, items[entry.key]!.assertionText);
        for (final answer
            in (cue['acceptedAnswers'] as List<dynamic>).cast<String>()) {
          final grade = format.grade(question, answer).single;
          expect(grade.itemId, entry.key);
          expect(
            grade.rating,
            fsrs.Rating.good,
            reason: '${entry.key}: $answer',
          );
        }
        expect(
          format.grade(question, 'unrelated example response').single.rating,
          fsrs.Rating.again,
        );
      }
      expect(await db.select(db.reviewStates).get(), isEmpty);
      expect(await db.select(db.reviewEvents).get(), isEmpty);
    },
  );
}
