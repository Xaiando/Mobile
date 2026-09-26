import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_formats.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/format_registry.dart';
import 'package:sommelier/core/questions/formats/flashcard/flashcard_format.dart';
import 'package:sommelier/core/questions/formats/mcq/mcq_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/pair_format.dart';

/// Backlog F3: the format registry.
void main() {
  test('refuses a second format with the same ID', () {
    expect(
      () => FormatRegistry(const [McqFormat(), FlashcardFormat(), McqFormat()]),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('twice'),
        ),
      ),
    );
    expect(() => appFormats.require('matching'), throwsArgumentError);
  });

  test('the app ships flashcard and MCQ at the depths and ranks of CM-6', () {
    expect(appFormats.ids, [
      'flashcard',
      'mcq',
      'map_locate',
      'map_identify',
      'typed',
      'short_answer',
    ]);
    final mcq = appFormats.require('mcq');
    final card = appFormats.require('flashcard');
    int depth(String id, String direction) =>
        appFormats.require(id).requiredDepth(direction);
    expect(
      [
        depth('mcq', 'forward'),
        depth('flashcard', 'forward'),
        depth('mcq', 'reverse'),
        depth('flashcard', 'reverse'),
      ],
      [1, 2, 3, 3],
    );
    expect(
      [
        mcq.difficultyRank('forward'),
        card.difficultyRank('forward'),
        mcq.difficultyRank('reverse'),
        card.difficultyRank('reverse'),
      ],
      [0, 1, 2, 3],
      reason: 'recognition before recall, forward before reverse',
    );
    expect(
      builtFormats.keys,
      appFormats.ids,
      reason: 'the coverage catalogue is the registry',
    );
    expect(builtFormats['mcq']!.isObjective, isTrue);
    expect(builtFormats['flashcard']!.family, FormatFamily.recall);
  });

  test('the validator knows only the registered formats', () {
    final dataset = datasetOf(datasetWithPairs());
    expect(
      {for (final issue in validateDataset(dataset).errors) issue.rule},
      {'template-format'},
    );
    expect(validateDataset(dataset, formats: pairFormats).errors, isEmpty);
  });

  test('MCQ grades right as Good and wrong as Again; a flashcard takes the '
      "learner's grade (FS-6)", () {
    const answer = QuestionOption('n_grape_chardonnay', 'Chardonnay');
    const wrong = QuestionOption('n_grape_gamay', 'Gamay');
    const question = PresentedQuestion(
      knowledgeItemId: 'ki_chablis_grape',
      questionTemplateId: 'qt_principal_grape_fwd_mcq',
      direction: 'forward',
      mode: 'mcq',
      prompt: 'Which of these is a principal grape variety of Chablis?',
      answer: answer,
      options: [wrong, answer],
      explanation: '',
      seed: 7,
    );
    const mcq = McqFormat();
    final right = mcq.grade(question, answer).single;
    expect(
      (right.itemId, right.rating),
      ('ki_chablis_grape', fsrs.Rating.good),
    );
    expect(right.optionNodeIds, ['n_grape_gamay', 'n_grape_chardonnay']);
    expect(right.selectedNodeId, 'n_grape_chardonnay');
    expect(mcq.grade(question, wrong).single.rating, fsrs.Rating.again);
    expect(
      () => mcq.grade(question, const QuestionOption('n_other', 'Other')),
      throwsArgumentError,
    );

    const card = FlashcardFormat();
    expect(
      card.grade(question, fsrs.Rating.hard).single.rating,
      fsrs.Rating.hard,
    );
    expect(() => card.grade(question, 'Chardonnay'), throwsArgumentError);
  });
}
