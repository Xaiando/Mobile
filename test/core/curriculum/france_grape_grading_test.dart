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

  setUpAll(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(
      db,
      clock: Clock.fixed(DateTime.utc(2026, 10, 1)),
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
  });

  Future<Set<String>> rivals(String itemId, String templateId) => db
      .customSelect(
        '''
        SELECT knowledge_node_id FROM question_distractors
        WHERE knowledge_item_id = ? AND question_template_id = ?
        ''',
        variables: [
          Variable.withString(itemId),
          Variable.withString(templateId),
        ],
      )
      .map((row) => row.read<String>('knowledge_node_id'))
      .get()
      .then((nodes) => nodes.toSet());

  test(
    'all eight Champagne principal varieties are answers, never rivals',
    () async {
      const principal = {
        'n_grape_arbane': 'Arbane',
        'n_grape_chardonnay': 'Chardonnay',
        'n_grape_chardonnay_rose': 'Chardonnay rose',
        'n_grape_meunier': 'Meunier',
        'n_grape_petit_meslier': 'Petit Meslier',
        'n_grape_pinot_blanc': 'Pinot Blanc',
        'n_grape_pinot_gris': 'Pinot Gris',
        'n_grape_pinot_noir': 'Pinot Noir',
      };
      final presenter = ExercisePresenter(db);
      for (final item in [
        'ki_champagne_chardonnay',
        'ki_champagne_pinot_noir',
        'ki_champagne_meunier',
      ]) {
        final question = await presenter.present(
          item,
          'qt_principal_grape_fwd_typed',
          seed: 1,
        );
        expect(question.prompt, contains('principal grape variety'));
        for (final name in principal.values) {
          expect(
            typed.grade(question, name).single.rating,
            fsrs.Rating.good,
            reason: '$item: $name',
          );
        }
        expect(
          typed.grade(question, 'Voltis').single.rating,
          fsrs.Rating.again,
          reason: 'conditional VIFA permission does not make Voltis principal',
        );
        final wrong = await rivals(item, 'qt_principal_grape_fwd_mcq');
        expect(
          wrong,
          isNotEmpty,
          reason: 'the MCQ remains available for $item',
        );
        expect(
          wrong.intersection(principal.keys.toSet()),
          isEmpty,
          reason: item,
        );
      }
    },
  );

  test(
    'Volnay accessory answers remain distinct from its principal grape',
    () async {
      const accessory = {
        'n_grape_chardonnay': 'Chardonnay',
        'n_grape_pinot_blanc': 'Pinot Blanc',
        'n_grape_pinot_gris': 'Pinot Gris',
      };
      final presenter = ExercisePresenter(db);
      final principal = await presenter.present(
        'ki_volnay_grape',
        'qt_principal_grape_fwd_typed',
        seed: 1,
      );
      expect(
        typed.grade(principal, 'Pinot Noir').single.rating,
        fsrs.Rating.good,
      );
      for (final item in [
        'ki_volnay_accessory_chardonnay',
        'ki_fr_atlas_volnay_permits_accessory_grape_pinot_blanc',
        'ki_fr_atlas_volnay_permits_accessory_grape_pinot_gris',
      ]) {
        final question = await presenter.present(
          item,
          'qt_accessory_grape_fwd_typed',
          seed: 1,
        );
        for (final name in accessory.values) {
          expect(typed.grade(question, name).single.rating, fsrs.Rating.good);
          expect(typed.grade(principal, name).single.rating, fsrs.Rating.again);
        }
        expect(
          typed.grade(question, 'Pinot Noir').single.rating,
          fsrs.Rating.again,
        );
        final wrong = await rivals(item, 'qt_accessory_grape_fwd_mcq');
        expect(
          wrong,
          item == 'ki_fr_atlas_volnay_permits_accessory_grape_pinot_gris'
              ? isEmpty
              : isNotEmpty,
          reason: 'grey-skinned Pinot Gris lacks three defensible grey rivals',
        );
        expect(
          wrong.intersection(accessory.keys.toSet()),
          isEmpty,
          reason: item,
        );
      }
    },
  );
}
