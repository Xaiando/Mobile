import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/question_presenter.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  late AppDatabase db;
  late QuestionPresenter presenter;
  late List<Question> multipleChoice;

  setUp(() async {
    db = openTestDatabase();
    await CurriculumIngester(db).ensureCurrent(bundledDataset());
    presenter = QuestionPresenter(db);
    multipleChoice = await db
        .customSelect('''
      SELECT q.* FROM questions q
      JOIN question_templates t ON t.id = q.question_template_id
      WHERE t.mode = 'mcq' ORDER BY q.knowledge_item_id, t.id''')
        .map((row) => db.questions.map(row.data))
        .get();
  });
  tearDown(() => db.close());

  test(
    'Phase 2 acceptance: every MCQ has 4 options and no duplicate distractors',
    () async {
      expect(multipleChoice, isNotEmpty);
      for (final question in multipleChoice) {
        for (var seed = 0; seed < 25; seed++) {
          final shown = await presenter.present(
            question.knowledgeItemId,
            question.questionTemplateId,
            seed: seed,
          );
          final where =
              '${question.knowledgeItemId} × ${question.questionTemplateId} '
              'seed $seed: ${shown.options}';
          expect(shown.options, hasLength(4), reason: where);
          expect(
            shown.options.map((o) => o.nodeId).toSet(),
            hasLength(4),
            reason: 'duplicate option in $where',
          );
          expect(
            shown.options.map((o) => normalizeName(o.name)).toSet(),
            hasLength(4),
            reason: 'duplicate option name in $where',
          );
          expect(
            shown.options.where((o) => o == shown.answer),
            hasLength(1),
            reason: where,
          );
          expect(shown.correctIndex, inInclusiveRange(0, 3));
        }
      }
    },
  );

  test('the same seed gives the same question (QG-7)', () async {
    for (final question in multipleChoice) {
      final first = await presenter.present(
        question.knowledgeItemId,
        question.questionTemplateId,
        seed: 42,
      );
      final again = await presenter.present(
        question.knowledgeItemId,
        question.questionTemplateId,
        seed: 42,
      );
      expect(again.options, first.options);
      expect(again.seed, 42);
    }
  });

  test('fresh seeds vary the options and the answer position', () async {
    final positions = <int>{};
    final optionSets = <String>{};
    for (var seed = 0; seed < 20; seed++) {
      final shown = await presenter.present(
        'ki_chablis_grape',
        'qt_principal_grape_fwd_mcq',
        seed: seed,
      );
      positions.add(shown.correctIndex);
      optionSets.add(
        (shown.options.map((o) => o.nodeId).toList()..sort()).join(','),
      );
    }
    expect(positions.length, greaterThan(1));
    expect(
      optionSets.length,
      greaterThan(1),
      reason: 'the pool has 5 candidates for 3 places',
    );
  });

  test('the nearest distractors are always shown', () async {
    for (var seed = 0; seed < 20; seed++) {
      final shown = await presenter.present(
        'ki_barolo_min_ageing',
        'qt_min_ageing_fwd_mcq',
        seed: seed,
      );
      expect(
        shown.options.map((o) => o.name),
        contains('26 months'),
        reason: "Barbaresco's minimum, from the same sub-region",
      );
    }
  });

  test('a reverse MCQ asks for the subject', () async {
    final shown = await presenter.present(
      'ki_barolo_min_ageing',
      'qt_min_ageing_rev_mcq',
      seed: 3,
    );
    expect(
      shown.prompt,
      'Which of these appellations requires a minimum ageing period of '
      '38 months?',
    );
    expect(shown.answer.name, 'Barolo');
    expect(shown.direction, 'reverse');
    expect(shown.options.map((o) => o.name), contains('Barolo'));
  });

  test('a flashcard reveals the answer and the explanation', () async {
    final shown = await presenter.present(
      'ki_champagne_soil',
      'qt_soil_fwd_flashcard',
      seed: 1,
    );
    expect(shown.isMultipleChoice, isFalse);
    expect(shown.options, isEmpty);
    expect(shown.correctIndex, -1);
    expect(shown.prompt, 'Name a characteristic soil of Champagne.');
    expect(shown.answer.name, 'Chalk');
    expect(shown.explanation, contains('Chalk'));
  });

  test('lists the questions of an item', () async {
    final questions = await presenter.questionsFor('ki_barolo_grape');
    expect(questions.map((q) => q.questionTemplateId), [
      'qt_principal_grape_fwd_flashcard',
      'qt_principal_grape_fwd_mcq',
    ]);
  });

  test('new seeds fit in 31 bits, exact on the web', () {
    final random = Random(1);
    for (var i = 0; i < 100; i++) {
      expect(
        QuestionPresenter.newSeed(random),
        inInclusiveRange(0, (1 << 31) - 1),
      );
    }
  });
}
