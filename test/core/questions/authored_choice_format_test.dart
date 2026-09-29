import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';
import 'package:sommelier/features/practice/format_views.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

const _itemId = 'ki_test_sugar_to_alcohol';
const _templateId = 'qt_test_authored_choice';

Map<String, dynamic> _fixture() {
  final data = copyOf(minimalDataset());
  rowsOf(data, 'node_types').addAll([
    {'id': 'production_principle', 'label': 'production principle'},
    {'id': 'learning_point', 'label': 'learning point'},
  ]);
  rowsOf(data, 'relation_types').add({
    'id': 'PRINCIPLE_EXPLANATION',
    'label': 'explains',
    'reverse_label': 'is explained by',
    'cardinality': 'many',
    'default_domain_id': 'viticulture',
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'subject_node_type': 'production_principle',
    'object_node_type': 'learning_point',
  });
  rowsOf(data, 'knowledge_nodes').addAll([
    {
      'id': 'n_test_fermentation_question',
      'node_type': 'production_principle',
      'name': 'What does yeast produce?',
    },
    {
      'id': 'n_test_fermentation_point',
      'node_type': 'learning_point',
      'name': 'Alcoholic fermentation',
    },
  ]);
  rowsOf(data, 'knowledge_relations').add({
    'subject_id': 'n_test_fermentation_question',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_fermentation_point',
    'valid_from': '1900-01-01',
  });
  rowsOf(data, 'knowledge_items').add({
    'id': _itemId,
    'subject_id': 'n_test_fermentation_question',
    'relation_type': 'PRINCIPLE_EXPLANATION',
    'object_id': 'n_test_fermentation_point',
    'domain_id': 'viticulture',
    'assertion_text': 'Yeast converts grape sugars into alcohol and CO2.',
    'mcq_disabled': true,
    'last_verified_at': '2026-01-01T00:00:00.000Z',
  });
  rowsOf(
    data,
    'knowledge_item_citations',
  ).add({'knowledge_item_id': _itemId, 'source_citation_id': 'src_test_law'});
  rowsOf(data, 'certification_knowledge_mappings').add({
    'certification_id': 'WSET_L1',
    'knowledge_item_id': _itemId,
    'importance': 'core',
    'minimum_depth': 2,
  });
  rowsOf(data, 'question_templates').addAll([
    {
      'id': 'qt_test_principle_flashcard',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'flashcard',
      'prompt_template': '{subject.name}',
    },
    {
      'id': 'qt_test_principle_mcq',
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'mcq',
      'prompt_template': '{subject.name}',
    },
    {
      'id': _templateId,
      'relation_type': 'PRINCIPLE_EXPLANATION',
      'direction': 'forward',
      'mode': 'authored_choice',
      'prompt_template': '{subject.name}',
      'parameters': {
        'item_choices': {
          _itemId: {
            'prompt': 'What two products does yeast make from grape sugar?',
            'options': [
              'Malic and lactic acids',
              'Alcohol and carbon dioxide',
              'Tannins and pigments',
              'Water and oxygen',
            ],
            'correctIndex': 1,
            'explanation': 'Yeast makes ethanol and carbon dioxide.',
            'sourceCitationId': 'src_test_law',
          },
        },
      },
    },
  ]);
  return data;
}

List<String> _parameterErrors(Map<String, dynamic> data) => [
  for (final issue in validateDataset(datasetOf(data)).errors)
    if (issue.rule == 'template-parameters') issue.message,
];

Map<String, dynamic> _cue(Map<String, dynamic> data) =>
    ((rowOf(data, 'question_templates', 'id', _templateId)['parameters']
                as Map<String, dynamic>)['item_choices']
            as Map<String, dynamic>)[_itemId]
        as Map<String, dynamic>;

void main() {
  test('daily practice has a view for authored choices', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(formatViewsProvider)['authored_choice'], isNotNull);
  });

  test(
    'authored choice rejects malformed or uncited item-specific options',
    () {
      final duplicate = _fixture();
      (_cue(duplicate)['options'] as List)[2] = 'alcohol AND carbon dioxide';
      expect(
        _parameterErrors(duplicate).join('\n'),
        contains('Duplicate authored options'),
      );

      final wrongIndex = _fixture();
      _cue(wrongIndex)['correctIndex'] = 4;
      expect(
        _parameterErrors(wrongIndex).join('\n'),
        contains('Invalid authored choice'),
      );

      final uncited = _fixture();
      _cue(uncited)['sourceCitationId'] = 'src_missing';
      expect(
        _parameterErrors(uncited).join('\n'),
        contains('not cited by this item'),
      );

      final unknown = _fixture();
      final entries =
          (rowOf(unknown, 'question_templates', 'id', _templateId)['parameters']
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      entries['ki_missing'] = entries.remove(_itemId);
      expect(
        _parameterErrors(unknown).join('\n'),
        contains('no knowledge item'),
      );
    },
  );

  test(
    'literal choice reviews remain durable without node foreign keys',
    () async {
      final db = openTestDatabase();
      final time = TestClock(DateTime.utc(2026, 10, 1, 9));
      try {
        final report = await CurriculumIngester(
          db,
          clock: time.clock,
        ).ingest(datasetOf(_fixture()));
        expect(report.byFormat['authored_choice'], 1);
        final questions = await QuestionPresenter(db).questionsFor(_itemId);
        expect(
          questions.map((question) => question.questionTemplateId),
          contains(_templateId),
        );
        expect(
          questions.map((question) => question.questionTemplateId),
          isNot(contains('qt_test_principle_mcq')),
          reason: 'mcq_disabled still blocks inferred graph distractors',
        );
        final card = (await StudyPlanner(db, clock: time.clock).cards(
          'WSET_L1',
        )).singleWhere((candidate) => candidate.itemId == _itemId);
        expect(card.formats.map((format) => format.mode).toSet(), {
          'flashcard',
          'authored_choice',
        });

        final presenter = ExercisePresenter(db, clock: time.clock);
        final question = await presenter.present(
          _itemId,
          _templateId,
          seed: 19,
        ) as AuthoredChoiceQuestion;
        final sameSeed = await presenter.present(
          _itemId,
          _templateId,
          seed: 19,
        ) as AuthoredChoiceQuestion;
        expect(
          question.options.map((option) => option.name).toList(),
          sameSeed.options.map((option) => option.name).toList(),
        );
        expect(question.options, hasLength(4));
        expect(question.answer.name, 'Alcohol and carbon dioxide');
        expect(question.explanation, contains('ethanol'));
        expect(question.sourceCitationId, 'src_test_law');

        final wrong = question.options.firstWhere(
          (option) => option != question.answer,
        );
        final grades = presenter.grade(question, wrong);
        expect(grades.single.rating, fsrs.Rating.again);
        expect(
          presenter.grade(question, question.answer).single.rating,
          fsrs.Rating.good,
        );
        expect(
          () => presenter.grade(
            question,
            QuestionOption(wrong.nodeId, 'forged literal'),
          ),
          throwsArgumentError,
        );
        expect(grades.single.optionNodeIds, isEmpty);
        expect(grades.single.selectedNodeId, isNull);
        final reviews = ReviewService(
          db,
          clock: time.clock,
          random: Random(17),
        );
        await expectLater(
          reviews.answerMultipleChoice(question, question.answer),
          throwsArgumentError,
        );
        final result = (await reviews.recordExercise(question, grades)).single;
        expect(result.event.selectedNodeId, isNull);
        expect(await db.select(db.reviewEventOptions).get(), isEmpty);
        final payload =
            jsonDecode(result.event.answerPayload!) as Map<String, dynamic>;
        expect(
          payload['options'],
          question.options.map((option) => option.name).toList(),
        );
        expect(payload['selectedIndex'], question.options.indexOf(wrong));
        expect(payload['correctIndex'], question.correctIndex);
        expect(payload['sourceCitationId'], 'src_test_law');
        expect(payload['prompt'], question.prompt);
        expect(payload['explanation'], question.explanation);
        expect(
          (await db.select(db.reviewStates).get()).single.knowledgeItemId,
          _itemId,
        );
      } finally {
        await db.close();
      }
    },
  );

  test(
    '359 cited Level 1–3 questions are generated and served across domains',
    () async {
      final db = openTestDatabase();
      try {
        await CurriculumIngester(db).ingest(bundledDataset());
        const foundationExamples = {
          'ki_wset_found_flower_to_fruit': 'viticulture',
          'ki_wset_found_fermentation': 'winemaking',
          'ki_wset_found_acidity': 'tasting',
          'ki_wset_found_familiar_chablis': 'geography',
          'ki_wset_srv_storage_cool': 'service',
        };
        final templates = await (db.select(
          db.questionTemplates,
        )..where((row) => row.mode.equals('authored_choice'))).get();
        expect(templates, hasLength(15));
        final expectedIds = {
          for (final template in templates)
            ...((jsonDecode(template.parameters!)
                        as Map<String, dynamic>)['item_choices']
                    as Map<String, dynamic>)
                .keys,
        };
        final levelOneIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_wset_l1_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final levelTwoIds = {
          for (final template in templates)
            if (template.id.startsWith('qt_wset_l2_'))
              ...((jsonDecode(template.parameters!)
                          as Map<String, dynamic>)['item_choices']
                      as Map<String, dynamic>)
                  .keys,
        };
        final levelThreeIds = expectedIds.difference({
          ...levelOneIds,
          ...levelTwoIds,
        });
        expect(expectedIds, hasLength(359));
        expect(levelOneIds, hasLength(132));
        expect(levelTwoIds, hasLength(142));
        expect(levelThreeIds, hasLength(85));
        final rows = await db.customSelect('''
        SELECT q.knowledge_item_id, i.domain_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        JOIN knowledge_items i ON i.id = q.knowledge_item_id
        WHERE t.mode = 'authored_choice' ORDER BY q.knowledge_item_id
      ''').get();
        expect(rows, hasLength(359));
        final actual = {
          for (final row in rows)
            row.read<String>('knowledge_item_id'): row.read<String>(
              'domain_id',
            ),
        };
        expect(actual.keys.toSet(), expectedIds);
        for (final entry in foundationExamples.entries) {
          expect(actual[entry.key], entry.value, reason: entry.key);
        }
        final levelOneCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L1'))
            card.itemId: card,
        };
        final levelTwoCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L2'))
            card.itemId: card,
        };
        final levelThreeCards = {
          for (final card in await StudyPlanner(db).cards('WSET_L3'))
            card.itemId: card,
        };
        for (final id in expectedIds) {
          expect(
            (levelOneIds.contains(id)
                    ? levelOneCards[id]
                    : levelTwoIds.contains(id)
                    ? levelTwoCards[id]
                    : levelThreeCards[id])
                ?.formats
                .map((format) => format.mode),
            contains('authored_choice'),
            reason: id,
          );
          final item = await (db.select(
            db.knowledgeItems,
          )..where((row) => row.id.equals(id))).getSingle();
          expect(item.mcqDisabled, isTrue, reason: id);
        }
        final genericDisabled = await db.customSelect('''
        SELECT q.knowledge_item_id FROM questions q
        JOIN question_templates t ON t.id = q.question_template_id
        JOIN knowledge_items i ON i.id = q.knowledge_item_id
        WHERE t.mode = 'mcq' AND i.mcq_disabled = 1
      ''').get();
        expect(genericDisabled, isEmpty);
      } finally {
        await db.close();
      }
    },
  );
}
