import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/map/map_exercise.dart';
import 'package:sommelier/core/questions/formats/map_grape/map_grape_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  late ExercisePresenter presenter;
  const mapTemplate = 'qt_top_planted_grape_fwd_map_grape';
  const primary = 'ki_nz_2025_marlborough_top_sauvignon_blanc';
  const pairs = {
    'n_geo_marlborough': {'n_grape_sauvignon_blanc', 'n_grape_pinot_noir'},
    'n_geo_central_otago': {'n_grape_pinot_noir', 'n_grape_pinot_gris'},
    'n_geo_hawkes_bay': {'n_grape_sauvignon_blanc', 'n_grape_chardonnay'},
    'n_geo_gisborne': {'n_grape_sauvignon_blanc', 'n_grape_chardonnay'},
    'n_geo_nelson': {'n_grape_sauvignon_blanc', 'n_grape_pinot_noir'},
    'n_geo_wairarapa': {'n_grape_sauvignon_blanc', 'n_grape_pinot_noir'},
  };

  setUpAll(() async {
    db = openTestDatabase();
    addTearDown(db.close);
    final time = Clock.fixed(DateTime.utc(2026, 10, 1));
    await CurriculumIngester(
      db,
      clock: time,
      assets: (path) async => File(path).readAsBytesSync(),
    ).ingest(bundledDataset());
    presenter = ExercisePresenter(db, clock: time);
  });

  test('ranking is planted 2025 data, not forecasts or legal permission', () {
    final data = bundledDataset();
    final records = data.knowledgeRelations.where(
      (r) => r.relationType == MapGrapeFormat.plantingRelation,
    );
    expect(records, hasLength(12));
    for (final entry in pairs.entries) {
      expect(
        records
            .where(
              (r) =>
                  r.subjectId ==
                  'n_stat_nz_top_two_planted_2025_${entry.key.substring(6)}',
            )
            .map((r) => r.objectId),
        unorderedEquals(entry.value),
      );
    }
    expect(
      data.relationSetAssertions.where(
        (a) => a.relationType == MapGrapeFormat.plantingRelation,
      ),
      hasLength(6),
    );
    expect(
      data.relationSetAssertions.where(
        (a) => a.relationType == 'PERMITS_GRAPE' && pairs.containsKey(a.nodeId),
      ),
      isEmpty,
    );
  });

  test('all ranked grapes are typed answers and never MCQ rivals', () async {
    final exercise = await presenter.present(
      primary,
      'qt_top_planted_grape_fwd_typed',
      seed: 1,
    );
    for (final name in ['Sauvignon Blanc', 'Pinot Noir']) {
      expect(
        const TypedFormat().grade(exercise, name).single.rating,
        fsrs.Rating.good,
      );
    }
    expect(
      const TypedFormat().grade(exercise, 'Chardonnay').single.rating,
      fsrs.Rating.again,
    );
    final rivals = await db
        .customSelect(
          'SELECT knowledge_node_id FROM question_distractors '
          'WHERE knowledge_item_id = ? AND question_template_id = ?',
          variables: [
            Variable.withString(primary),
            Variable.withString('qt_top_planted_grape_fwd_mcq'),
          ],
        )
        .get();
    expect(rivals.length, greaterThanOrEqualTo(3));
    expect(
      rivals
          .map((r) => r.read<String>('knowledge_node_id'))
          .toSet()
          .intersection(pairs['n_geo_marlborough']!),
      isEmpty,
    );
    const grisItem = 'ki_nz_2025_central_otago_top_pinot_gris';
    final gris = await presenter.present(
      grisItem,
      'qt_top_planted_grape_fwd_typed',
      seed: 1,
    );
    expect(
      const TypedFormat().grade(gris, 'Pinot Gris').single.rating,
      fsrs.Rating.good,
    );
    final grisQuestions = await db
        .customSelect(
          'SELECT question_template_id FROM questions WHERE knowledge_item_id = ?',
          variables: [Variable.withString(grisItem)],
        )
        .get();
    expect(
      grisQuestions.map((r) => r.read<String>('question_template_id')),
      contains('qt_top_planted_grape_fwd_map_grape'),
    );
    expect(
      grisQuestions.map((r) => r.read<String>('question_template_id')),
      isNot(contains('qt_top_planted_grape_fwd_mcq')),
      reason: 'grey-skinned grapes cannot supply three defensible rivals',
    );
  });

  test(
    'combination maps accept every ranked alternative and grade co-items',
    () async {
      final variants = <MapExercise>[];
      for (var seed = 0; seed < 12; seed++) {
        final map = await presenter.present(
          primary,
          mapTemplate,
          seed: seed,
        ) as MapExercise;
        variants.add(map);
        expect(map.candidateIds, unorderedEquals(pairs.keys));
        expect(map.prompt, contains('2025'));
        expect(map.prompt, isNot(contains('permitted')));
        for (final id in map.itemIds) {
          expect(id, startsWith('ki_nz_2025_marlborough_top_'));
        }
      }
      expect(variants.map((v) => v.itemIds.length).toSet(), {1, 2});
      final combination = variants.firstWhere((v) => v.itemIds.length == 2);
      expect(combination.correctNodeIds, {
        'n_geo_marlborough',
        'n_geo_nelson',
        'n_geo_wairarapa',
      });
      final repeated = await presenter.present(
        primary,
        mapTemplate,
        seed: combination.seed,
      ) as MapExercise;
      expect(repeated.prompt, combination.prompt);
      expect(repeated.itemIds, combination.itemIds);
      final accepted = presenter.grade(
        combination,
        const MapLocateAnswer.fromList('n_geo_nelson'),
      );
      expect(accepted.map((g) => g.rating), everyElement(fsrs.Rating.good));
      final partial = presenter.grade(
        combination,
        const MapLocateAnswer.fromList('n_geo_central_otago'),
      );
      expect(partial.first.rating, fsrs.Rating.again);
      expect(partial.last.rating, fsrs.Rating.good);
    },
  );

  test(
    'another survey year cannot alter this record’s accepted locations',
    () async {
      await db.writeCurriculum(() async {
        await db.customStatement(
          'INSERT INTO knowledge_relations '
          '(subject_id,relation_type,object_id,valid_from,valid_until) VALUES '
          "('n_stat_nz_top_two_planted_2025_marlborough','TOP_PLANTED_GRAPE',"
          "'n_grape_merlot','2026-02-26','2026-09-30')",
        );
        await db.customStatement(
          'INSERT INTO knowledge_nodes (id,node_type,name,name_norm) VALUES '
          "('n_stat_nz_gisborne_2024_fixture','statistic',"
          "'Gisborne planted record (2024)','gisborne planted record 2024')",
        );
        await db.customStatement(
          'INSERT INTO knowledge_relations '
          '(subject_id,relation_type,object_id,valid_from) VALUES '
          "('n_stat_nz_gisborne_2024_fixture','STATISTIC_IN_AREA',"
          "'n_geo_gisborne','2026-02-26'),"
          "('n_stat_nz_gisborne_2024_fixture','TOP_PLANTED_GRAPE',"
          "'n_grape_pinot_noir','2026-02-26')",
        );
        await db.customStatement(
          'INSERT INTO relation_set_assertions '
          '(node_id,relation_type,direction,member_node_type,valid_from,source_citation_id,locator) VALUES '
          "('n_stat_nz_gisborne_2024_fixture','TOP_PLANTED_GRAPE','forward',"
          "'grape','2026-02-26','src_nz_vineyard_report_2026','Controlled fixture')",
        );
      });
      MapExercise? combination;
      for (var seed = 0; seed < 12; seed++) {
        final map = await presenter.present(
          primary,
          mapTemplate,
          seed: seed,
        ) as MapExercise;
        if (map.itemIds.length == 2) {
          combination = map;
          break;
        }
      }
      expect(combination, isNotNull);
      expect(combination!.correctNodeIds, isNot(contains('n_geo_gisborne')));
      expect(combination.nodeId, 'n_geo_marlborough');
      final typed = await presenter.present(
        primary,
        'qt_top_planted_grape_fwd_typed',
        seed: 1,
      );
      expect(
        const TypedFormat().grade(typed, 'Merlot').single.rating,
        fsrs.Rating.again,
        reason: 'retired erroneous ranks cannot remain correct typed answers',
      );
    },
  );
}
