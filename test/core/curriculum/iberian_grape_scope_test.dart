import 'dart:io';

import 'package:clock/clock.dart';
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
  late ExercisePresenter presenter;
  const typed = TypedFormat();
  final time = Clock.fixed(DateTime.utc(2026, 10, 1));

  setUpAll(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(
      db,
      clock: time,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    presenter = ExercisePresenter(db, clock: time);
  });

  test(
    'current Rías Baixas includes Ratiño, while Rueda excludes Godello',
    () async {
      final rias = await presenter.present(
        'ki_es_map_rias_baixas_albarino',
        'qt_permitted_grape_fwd_typed',
        seed: 1,
      );
      expect(
        typed.grade(rias, 'Ratiño Gallega').single.rating,
        fsrs.Rating.good,
      );
      final rueda = await presenter.present(
        'ki_es_map_rueda_verdejo',
        'qt_permitted_grape_fwd_typed',
        seed: 1,
      );
      expect(typed.grade(rueda, 'Godello').single.rating, fsrs.Rating.again);
    },
  );

  test(
    'historically permitted vines remain accepted with their conditions',
    () async {
      final ribera = await presenter.present(
        'ki_es_map_ribera_del_duero_tempranillo',
        'qt_permitted_grape_fwd_typed',
        seed: 1,
      );
      expect(
        typed.grade(ribera, 'Chasselas Doré').single.rating,
        fsrs.Rating.good,
      );
      final items = bundledDataset().knowledgeItems;
      final historical = items.singleWhere(
        (item) => item.id == 'ki_es_map_ribera_del_duero_chasselas',
      );
      expect(historical.assertionText, contains('before 21 July 1982'));
      expect(historical.assertionText, contains('interplanted'));
      final palomino = items.singleWhere(
        (item) => item.id == 'ki_es_map_rueda_palomino_fino',
      );
      expect(palomino.assertionText, contains('new plantings'));
      expect(palomino.assertionText, contains('not authorised'));
    },
  );

  test('Spanish regional grape synonyms use their cultivar identity', () async {
    for (final (item, answer) in [
      ('ki_es_map_rioja_tempranillo', 'Turruntés'),
      ('ki_es_map_cava_chardonnay', 'Subirat Parent'),
    ]) {
      final exercise = await presenter.present(
        item,
        'qt_permitted_grape_fwd_typed',
        seed: 1,
      );
      expect(typed.grade(exercise, answer).single.rating, fsrs.Rating.good);
    }
    final dataset = bundledDataset();
    final union = dataset.knowledgeRelations
        .where(
          (r) =>
              r.subjectId == 'n_geo_rioja' && r.relationType == 'PERMITS_GRAPE',
        )
        .map((r) => r.objectId)
        .toSet();
    expect(union, contains('n_grape_albillo_mayor'));
    expect(union, contains('n_grape_alarije'));
    expect(union, isNot(contains('n_grape_torrontes_galicia')));
  });

  test(
    'a white-wine variety can have pink berries without white MCQ peers',
    () async {
      final exercise = await presenter.present(
        'ki_es_berry_gewurztraminer',
        'qt_berry_colour_fwd_typed',
        seed: 1,
      );
      expect(typed.grade(exercise, 'Pink').single.rating, fsrs.Rating.good);
      expect(typed.grade(exercise, 'White').single.rating, fsrs.Rating.again);
      final questions = await db.select(db.questions).get();
      final templates = {
        for (final template in await db.select(db.questionTemplates).get())
          template.id: template.mode,
      };
      final permissions = bundledDataset().knowledgeItems.where(
        (item) =>
            item.objectId == 'n_grape_gewurztraminer' &&
            item.relationType == 'PERMITS_GRAPE',
      );
      expect(permissions, isNotEmpty);
      for (final permission in permissions) {
        expect(permission.mcqDisabled, isTrue);
        expect(
          questions.where(
            (q) =>
                q.knowledgeItemId == permission.id &&
                templates[q.questionTemplateId] == 'mcq',
          ),
          isEmpty,
        );
      }
    },
  );
}
