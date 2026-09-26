import 'package:clock/clock.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/database/curriculum_writes.dart';
import 'package:sommelier/core/questions/question_generator.dart';
import 'package:sommelier/core/questions/template_renderer.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  test('templates fill every placeholder', () {
    expect(
      renderPrompt(
        'In which {object.type_label} is {subject.name}? Not {object.name}.',
        subjectName: 'Volnay',
        objectName: 'Touraine',
        objectTypeLabel: 'sub-region',
      ),
      'In which sub-region is Volnay? Not Touraine.',
    );
  });

  group('the bundled curriculum', () {
    late AppDatabase db;
    late GenerationReport report;

    setUp(() async {
      db = openTestDatabase();
      report = await CurriculumIngester(db).ingest(bundledDataset());
    });
    tearDown(() => db.close());

    Future<List<String>> pool(String item, String template) => db
        .customSelect(
          'SELECT knowledge_node_id FROM question_distractors '
          'WHERE knowledge_item_id = ? AND question_template_id = ? '
          'ORDER BY scope_rank, knowledge_node_id',
          variables: [Variable(item), Variable(template)],
        )
        .map((row) => row.read<String>('knowledge_node_id'))
        .get();

    Future<List<String>> templatesOf(String item) => db
        .customSelect(
          'SELECT question_template_id FROM questions '
          'WHERE knowledge_item_id = ? ORDER BY question_template_id',
          variables: [Variable(item)],
        )
        .map((row) => row.read<String>('question_template_id'))
        .get();

    test('every item gets a flashcard, and an MCQ unless disabled', () async {
      expect(report.multipleChoice, greaterThan(0));
      expect(report.flashcards, greaterThan(0));
      // §S.3 gate (register §4): an item without an MCQ must be marked
      // flashcard-only by a curator.
      final withoutMcq = await db.customSelect('''
        SELECT i.id FROM knowledge_items i
        WHERE i.mcq_disabled = 0 AND NOT EXISTS (
          SELECT 1 FROM questions q
          JOIN question_templates t ON t.id = q.question_template_id
          WHERE q.knowledge_item_id = i.id AND t.mode = 'mcq')''').get();
      expect(withoutMcq, isEmpty);
      final withoutFlashcard = await db.customSelect('''
        SELECT i.id FROM knowledge_items i WHERE NOT EXISTS (
          SELECT 1 FROM questions q
          JOIN question_templates t ON t.id = q.question_template_id
          WHERE q.knowledge_item_id = i.id AND t.mode = 'flashcard')''').get();
      expect(withoutFlashcard, isEmpty);
    });

    test('every MCQ has at least 3 distractors (§S.3)', () async {
      final short = await db.customSelect('''
        SELECT q.knowledge_item_id, count(d.knowledge_node_id) AS n
        FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        LEFT JOIN question_distractors d
          ON d.knowledge_item_id = q.knowledge_item_id
         AND d.question_template_id = q.question_template_id
        WHERE t.mode = 'mcq'
        GROUP BY q.knowledge_item_id, q.question_template_id
        HAVING n < 3''').get();
      expect(short, isEmpty);
    });

    test(
      'no distractor is a correct answer in any period (QG-4, QG-5)',
      () async {
        final wrong = await db.customSelect('''
        SELECT d.knowledge_item_id, d.knowledge_node_id
        FROM question_distractors d
        JOIN question_templates t ON t.id = d.question_template_id
        JOIN knowledge_items i ON i.id = d.knowledge_item_id
        WHERE (t.direction = 'forward' AND EXISTS (
                 SELECT 1 FROM knowledge_relations r
                 WHERE r.subject_id = i.subject_id
                   AND r.relation_type = i.relation_type
                   AND r.object_id = d.knowledge_node_id))
           OR (t.direction = 'reverse' AND EXISTS (
                 SELECT 1 FROM knowledge_relations r
                 WHERE r.object_id = i.object_id
                   AND r.relation_type = i.relation_type
                   AND r.subject_id = d.knowledge_node_id))''').get();
        expect(wrong, isEmpty);
      },
    );

    test(
      "distractors share the answer's type, berry colour and unit",
      () async {
        final mismatched = await db.customSelect('''
        SELECT d.knowledge_item_id, d.knowledge_node_id
        FROM question_distractors d
        JOIN question_templates t ON t.id = d.question_template_id
        JOIN knowledge_items i ON i.id = d.knowledge_item_id
        JOIN knowledge_nodes answer ON answer.id =
          CASE t.direction WHEN 'forward' THEN i.object_id ELSE i.subject_id END
        JOIN knowledge_nodes wrong ON wrong.id = d.knowledge_node_id
        LEFT JOIN quantity_values qa ON qa.knowledge_node_id = answer.id
        LEFT JOIN quantity_values qw ON qw.knowledge_node_id = wrong.id
        WHERE wrong.node_type <> answer.node_type
           OR qa.unit IS NOT qw.unit
           OR (answer.node_type = 'grape' AND
               (SELECT object_id FROM knowledge_relations
                WHERE subject_id = answer.id
                  AND relation_type = 'HAS_BERRY_COLOUR') IS NOT
               (SELECT object_id FROM knowledge_relations
                WHERE subject_id = wrong.id
                  AND relation_type = 'HAS_BERRY_COLOUR'))''').get();
        expect(mismatched, isEmpty);
      },
    );

    test('§R sample Q1: Chablis draws other white French grapes', () async {
      final wrong = await pool(
        'ki_chablis_grape',
        'qt_principal_grape_fwd_mcq',
      );
      expect(
        wrong,
        containsAll(['n_grape_sauvignon_blanc', 'n_grape_chenin_blanc']),
      );
      expect(wrong, isNot(contains('n_grape_pinot_noir')), reason: 'black');
      expect(wrong, isNot(contains('n_grape_chardonnay')), reason: 'answer');
    });

    test('§H: Syrah in Cornas widens from the Rhône to France', () async {
      final rows = await db
          .customSelect(
            'SELECT knowledge_node_id, scope_rank FROM question_distractors '
            "WHERE knowledge_item_id = 'ki_cornas_grape' "
            "AND question_template_id = 'qt_principal_grape_fwd_mcq'",
          )
          .get();
      final rank = {
        for (final row in rows)
          row.read<String>('knowledge_node_id'): row.read<int>('scope_rank'),
      };
      // Northern Rhône has no other black principal grape, so the nearest
      // candidates come from the Rhône Valley, then France.
      expect(rank['n_grape_grenache'], rank['n_grape_mourvedre']);
      expect(
        rank['n_grape_pinot_noir'],
        greaterThan(rank['n_grape_grenache']!),
      );
      expect(rank.containsKey('n_grape_syrah'), isFalse);
    });

    test(
      "an appellation's other correct grapes are never wrong answers",
      () async {
        expect(
          await pool('ki_champagne_pinot_noir', 'qt_principal_grape_fwd_mcq'),
          isNot(contains('n_grape_meunier')),
        );
        expect(
          await pool(
            'ki_chateauneuf_du_pape_grenache',
            'qt_principal_grape_fwd_mcq',
          ),
          isNot(
            anyOf(contains('n_grape_syrah'), contains('n_grape_mourvedre')),
          ),
        );
      },
    );

    test('reverse questions only for distinctive items (QG-3)', () async {
      expect(await templatesOf('ki_barolo_min_ageing'), [
        'qt_min_ageing_fwd_flashcard',
        'qt_min_ageing_fwd_mcq',
        'qt_min_ageing_rev_flashcard',
        'qt_min_ageing_rev_mcq',
      ]);
      expect(await templatesOf('ki_champagne_min_ageing'), [
        'qt_min_ageing_fwd_flashcard',
        'qt_min_ageing_fwd_mcq',
      ]);
      expect(
        report.skipped.map((s) => '${s.itemId} ${s.reason.name}'),
        contains('ki_champagne_min_ageing notReverseSafe'),
      );
      expect(await pool('ki_barolo_min_ageing', 'qt_min_ageing_rev_mcq'), [
        'n_geo_barbaresco',
        'n_geo_brunello_di_montalcino',
        'n_geo_chianti_classico',
      ]);
    });

    test('a curator-disabled MCQ leaves the flashcard (QG-6)', () async {
      expect(await templatesOf('ki_champagne_soil'), ['qt_soil_fwd_flashcard']);
    });

    test('quantities draw other durations, nearest first', () async {
      expect(
        (await pool('ki_barolo_min_ageing', 'qt_min_ageing_fwd_mcq')).first,
        'n_qty_26_months',
        reason: 'Barbaresco, also in the Langhe',
      );
    });

    test('prompts are rendered from the template', () async {
      final prompts = await db
          .customSelect(
            'SELECT prompt_text FROM questions '
            "WHERE knowledge_item_id = 'ki_volnay_location' "
            "AND question_template_id NOT LIKE '%_map_%'",
          )
          .map((row) => row.read<String>('prompt_text'))
          .get();
      expect(prompts, everyElement('In which sub-region is Volnay located?'));
    });

    test('re-ingestion regenerates the same questions', () async {
      Future<List<String>> snapshot() => db
          .customSelect(
            "SELECT knowledge_item_id || ' ' || question_template_id || ' ' "
            '|| prompt_text AS q FROM questions ORDER BY q',
          )
          .map((row) => row.read<String>('q'))
          .get();
      final before = await snapshot();
      await CurriculumIngester(db).ingest(bundledDataset());
      expect(await snapshot(), before);
    });
  });

  group('eligibility', () {
    late AppDatabase db;

    setUp(() => db = openTestDatabase());
    tearDown(() => db.close());

    test('too few distractors: no MCQ, reported (QG-6)', () async {
      final report = await CurriculumIngester(db)
          .ingest(CurriculumDataset.parse(datasetText(minimalDataset())));
      // The fixture has two grapes, one white and one black.
      expect(report.multipleChoice, 0);
      expect(
        report.skipped.map((s) => s.reason),
        everyElement(SkipReason.tooFewDistractors),
      );
    });

    test('a past correct answer is never a wrong one (QG-4)', () async {
      final data = _withWhiteGrapes(minimalDataset());
      // Chablis once also permitted Aligoté.
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_geo_chablis',
        'relation_type': 'PERMITS_PRINCIPAL_GRAPE',
        'object_id': 'n_grape_aligote',
        'valid_from': '1900-01-01',
        'valid_until': '1950-01-01',
      });
      await CurriculumIngester(db)
          .ingest(CurriculumDataset.parse(datasetText(data)));
      final wrong = await db
          .customSelect(
            'SELECT knowledge_node_id FROM question_distractors '
            "WHERE knowledge_item_id = 'ki_chablis_grape'",
          )
          .map((row) => row.read<String>('knowledge_node_id'))
          .get();
      expect(wrong, hasLength(3));
      expect(wrong, isNot(contains('n_grape_aligote')));
    });

    test('expired and superseded items get no questions (FS-13)', () async {
      final data = _withWhiteGrapes(minimalDataset());
      rowOf(
        data,
        'knowledge_relations',
        'object_id',
        'n_grape_pinot_noir',
      )['valid_until'] = '2000-01-01';
      rowOf(
        data,
        'knowledge_items',
        'id',
        'ki_chablis_grape',
      )['superseded_by_item_id'] = 'ki_volnay_grape';
      final ingester = CurriculumIngester(
        db,
        clock: Clock.fixed(DateTime(2026, 6, 1)),
      );
      await ingester.ingest(CurriculumDataset.parse(datasetText(data)));
      expect(await db.select(db.questions).get(), isEmpty);
    });

    test('regeneration never touches user history', () async {
      final data = _withWhiteGrapes(minimalDataset());
      final ingester = CurriculumIngester(db);
      await ingester.ingest(CurriculumDataset.parse(datasetText(data)));
      await seedSchedulerConfig(db);
      await db.customStatement(
        'INSERT INTO review_events (id, knowledge_item_id, question_template_id, '
        'reviewed_at, rating, scheduler_config_version, state_after, step_after, '
        'stability_after, difficulty_after, due_after) VALUES '
        "('00000000-0000-4000-8000-000000000001', 'ki_chablis_grape', "
        "'qt_principal_grape_fwd_mcq', '2026-01-01T09:00:00.000Z', 3, 1, 1, 0, "
        "2.3, 5, '2026-01-01T09:10:00.000Z')",
      );
      await db.writeCurriculum(
        () => QuestionGenerator(db, today: '2026-06-01').generate(),
      );
      expect(await db.select(db.reviewEvents).get(), hasLength(1));
      expect(await db.select(db.questions).get(), isNotEmpty);
    });
  });
}

/// Adds three more white grapes, enough for an MCQ on Chablis.
Map<String, dynamic> _withWhiteGrapes(Map<String, dynamic> data) {
  for (final (id, name) in [
    ('n_grape_aligote', 'Aligoté'),
    ('n_grape_sauvignon_blanc', 'Sauvignon Blanc'),
    ('n_grape_chenin_blanc', 'Chenin Blanc'),
    ('n_grape_viognier', 'Viognier'),
  ]) {
    rowsOf(
      data,
      'knowledge_nodes',
    ).add({'id': id, 'node_type': 'grape', 'name': name});
    rowsOf(data, 'knowledge_relations').add({
      'subject_id': id,
      'relation_type': 'HAS_BERRY_COLOUR',
      'object_id': 'n_colour_white',
      'valid_from': '1900-01-01',
    });
  }
  return data;
}
