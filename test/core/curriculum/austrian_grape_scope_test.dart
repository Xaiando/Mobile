import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  const typed = TypedFormat();
  const itemIds = [
    'ki_at_weinviertel_gruner',
    'ki_at_mittelburgenland_blaufrankisch',
    'ki_at_kamptal_gruner_veltliner',
    'ki_at_kamptal_riesling',
    'ki_at_kamptal_chardonnay',
    'ki_at_kamptal_pinot_blanc',
    'ki_at_kamptal_pinot_gris',
  ];

  setUpAll(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime.utc(2026, 10, 1)),
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
  });

  test(
    'DAC study prompts ask for principal varieties, not any blend grape',
    () async {
      final presenter = ExercisePresenter(db);
      for (final (itemId, accepted, minorBlend) in [
        ('ki_at_weinviertel_gruner', 'Grüner Veltliner', 'Chardonnay'),
        ('ki_at_mittelburgenland_blaufrankisch', 'Blaufränkisch', 'Merlot'),
      ]) {
        final question = await presenter.present(
          itemId,
          'qt_principal_grape_fwd_typed',
          seed: 1,
        );
        expect(question.prompt, contains('principal grape variety'));
        expect(typed.grade(question, accepted).single.rating, fsrs.Rating.good);
        // These answers concern general blend permission, which this scoped
        // prompt does not ask. Generic permission prompts are not generated.
        expect(
          typed.grade(question, minorBlend).single.rating,
          fsrs.Rating.again,
        );
      }
      for (final itemId in itemIds) {
        final generic = await db
            .customSelect(
              '''
        SELECT q.knowledge_item_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        WHERE q.knowledge_item_id = ? AND t.relation_type = 'PERMITS_GRAPE'
      ''',
              variables: [Variable.withString(itemId)],
            )
            .get();
        expect(generic, isEmpty, reason: itemId);
      }
    },
  );

  test(
    'every Kamptal principal variety is accepted and excluded as a rival',
    () async {
      final presenter = ExercisePresenter(db);
      const grapes = {
        'n_grape_gruner_veltliner': 'Grüner Veltliner',
        'n_grape_riesling': 'Riesling',
        'n_grape_chardonnay': 'Chardonnay',
        'n_grape_pinot_blanc': 'Pinot Blanc',
        'n_grape_pinot_gris': 'Pinot Gris',
      };
      for (final itemId in itemIds.where(
        (id) => id.startsWith('ki_at_kamptal_'),
      )) {
        final question = await presenter.present(
          itemId,
          'qt_principal_grape_fwd_typed',
          seed: 1,
        );
        expect(question.prompt, contains('principal grape variety'));
        for (final name in grapes.values) {
          expect(
            typed.grade(question, name).single.rating,
            fsrs.Rating.good,
            reason: '$itemId: $name',
          );
        }
        final rivals = await db
            .customSelect(
              '''
        SELECT knowledge_node_id FROM question_distractors
        WHERE knowledge_item_id = ?
          AND question_template_id = 'qt_principal_grape_fwd_mcq'
      ''',
              variables: [Variable.withString(itemId)],
            )
            .get();
        expect(
          rivals,
          itemId == 'ki_at_kamptal_pinot_gris' ? isEmpty : isNotEmpty,
          reason: 'grey-skinned Pinot Gris lacks three defensible grey rivals',
        );
        expect(
          rivals
              .map((row) => row.read<String>('knowledge_node_id'))
              .toSet()
              .intersection(grapes.keys.toSet()),
          isEmpty,
          reason: itemId,
        );
      }
    },
  );
}
