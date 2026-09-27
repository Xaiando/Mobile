import 'dart:io';

import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/knowledge_graph.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  late ExercisePresenter presenter;
  const itemId = 'ki_berry_pinot_gris_grey';
  const correctedPermissions = [
    'ki_at_kamptal_pinot_gris',
    'ki_fr_atlas_volnay_permits_grape_pinot_gris',
    'ki_fr_atlas_volnay_permits_accessory_grape_pinot_gris',
    'ki_fr_atlas_champagne_permits_grape_pinot_gris',
    'ki_nz_2025_central_otago_top_pinot_gris',
  ];
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

  test('retired legacy white metadata is preserved; grey is the only current value', () async {
    final data = bundledDataset();
    final rows = data.knowledgeRelations
        .where(
          (relation) =>
              relation.subjectId == 'n_grape_pinot_gris' &&
              relation.relationType == 'HAS_BERRY_COLOUR',
        )
        .toList();
    expect(rows, hasLength(2));
    final legacy = rows.singleWhere((row) => row.objectId == 'n_colour_white');
    expect(legacy.validFrom, '1900-01-01');
    expect(legacy.validUntil, '2026-09-26');
    expect(
      rows.singleWhere((row) => row.objectId == 'n_colour_grey').validFrom,
      '2026-09-26',
    );
    final graph = KnowledgeGraph(db, clock: time);
    for (final on in ['2026-09-26', '2026-10-01']) {
      final current = (await graph.relationsOf(
        'n_grape_pinot_gris',
        on: on,
      )).where((row) => row.relationType == 'HAS_BERRY_COLOUR');
      expect(current.map((row) => row.objectId), ['n_colour_grey']);
    }
  });

  test(
    'grey physical colour fact is cited and inherited from Level 2',
    () async {
      final data = bundledDataset();
      final item = data.knowledgeItems.singleWhere((row) => row.id == itemId);
      expect(item.objectId, 'n_colour_grey');
      expect(item.domainId, 'viticulture');
      expect(item.assertionText, contains('berry skins at maturity'));
      expect(item.mcqDisabled, isTrue);
      final citation = data.knowledgeItemCitations.singleWhere(
        (row) => row.knowledgeItemId == itemId,
      );
      expect(citation.sourceCitationId, 'src_plantgrape_pinot_gris_colour');
      expect(citation.locator, contains('Description elements'));
      final source = data.sourceCitations.singleWhere(
        (row) => row.id == citation.sourceCitationId,
      );
      expect(
        source.url,
        'https://www.plantgrape.fr/en/varieties/fruit-varieties/217/export',
      );
      expect(source.publisher, contains('INRAE'));
      final planner = StudyPlanner(db, clock: time);
      for (final track in ['WSET_L2', 'WSET_L3', 'WSET_L4']) {
        final mapping = (await planner.effectiveMappings(track))[itemId]!;
        expect(mapping.certificationId, 'WSET_L2');
        expect(mapping.importance, 'secondary');
        expect(mapping.minimumDepth, 2);
      }
      expect(
        (await planner.effectiveMappings('CMS_CERTIFIED'))[itemId]!.importance,
        'tertiary',
      );
    },
  );

  test(
    'current typed colour accepts Grey and Gray and rejects retired White',
    () async {
      final question = await presenter.present(
        itemId,
        'qt_berry_colour_fwd_typed',
        seed: 7,
      );
      const typed = TypedFormat();
      for (final answer in ['Grey', 'Gray', 'grey berry colour', 'GRAY']) {
        expect(
          typed.grade(question, answer).single.rating,
          fsrs.Rating.good,
          reason: answer,
        );
      }
      for (final answer in ['White', 'Black', 'Pink']) {
        expect(
          typed.grade(question, answer).single.rating,
          fsrs.Rating.again,
          reason: answer,
        );
      }
    },
  );

  test('small grey pool disables MCQ while factual recall and maps remain available', () async {
    for (final id in correctedPermissions) {
      final item = await (db.select(
        db.knowledgeItems,
      )..where((row) => row.id.equals(id))).getSingle();
      expect(item.mcqDisabled, isTrue, reason: id);
      final modes = await db
          .customSelect(
            'SELECT t.mode FROM questions q JOIN question_templates t ON t.id=q.question_template_id '
            'WHERE q.knowledge_item_id=?',
            variables: [Variable.withString(id)],
          )
          .get();
      expect(
        modes.map((row) => row.read<String>('mode')),
        isNot(contains('mcq')),
        reason: id,
      );
      expect(
        modes.map((row) => row.read<String>('mode')),
        containsAll(['typed', 'flashcard']),
        reason: id,
      );
    }
    final map = await presenter.present(
      'ki_nz_2025_central_otago_top_pinot_gris',
      'qt_top_planted_grape_fwd_map_grape',
      seed: 4,
    );
    expect(map.prompt, contains('Pinot Gris'));
    expect(map.prompt, contains('2025'));
  });
}
