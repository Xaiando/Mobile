import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  const principleKeys = {
    'pdo_origin',
    'pdo_grapes',
    'pdo_method',
    'pgi_hybrid',
    'unprotected_origin',
    'pdo_assessment',
  };
  const caseKeys = {'hybrid_offer', 'category_quality'};
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  const choiceId = 'qt_d4brit_category_choice_6';
  const typedId = 'qt_d4brit_point_typed_6';
  const criteriaId = 'qt_d4brit_case_criteria_2';
  final principleIds = {for (final key in principleKeys) 'ki_d4brit_$key'};
  Set<String> caseIds(String key) => {
    for (final role in roles)
      'ki_d4brit_case_${key}_${role.substring(5).toLowerCase()}',
  };
  final expectedIds = {
    ...principleIds,
    for (final key in caseKeys) ...caseIds(key),
  };
  final dataset = bundledDataset();
  final items = {
    for (final item in dataset.knowledgeItems)
      if (item.id.startsWith('ki_d4brit_')) item.id: item,
  };
  final templates = {
    for (final template in dataset.questionTemplates) template.id: template,
  };
  final choiceTemplate = templates[choiceId]!;
  final typedTemplate = templates[typedId]!;
  final criteriaTemplate = templates[criteriaId]!;
  final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
  final cues = TypedFormat.itemCuesOf(typedTemplate)!;

  test('British category teaching is cited, unverified and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items.keys.toSet(), expectedIds);
    expect(items, hasLength(14));
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source,
    };
    final citedIds = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    for (final item in items.values) {
      expect(item.domainId, 'winemaking', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(citedIds, contains(item.id), reason: item.id);
      final rows = dataset.certificationKnowledgeMappings
          .where((row) => row.knowledgeItemId == item.id)
          .toList();
      expect(rows, hasLength(1), reason: item.id);
      expect(rows.single.certificationId, 'WSET_L4', reason: item.id);
      expect(rows.single.importance, 'core', reason: item.id);
      expect(rows.single.minimumDepth, 3, reason: item.id);
    }
    const primaryUrls = {
      'src_d4brit_english_pdo': 'https://assets.publishing.service.gov.uk/media/5fd361f48fa8f54d6545da82/pfn-english-wine-pdo.pdf',
      'src_d4brit_welsh_pdo': 'https://assets.publishing.service.gov.uk/media/5fd36910e90e076637bb5a45/pfn-welsh-wine-pdo.pdf',
      'src_d4brit_fsa_sparkling': 'https://www.gov.uk/government/publications/uk-quality-wine-schemes-guidance-sparkling-wines/uk-quality-wine-schemes-guidance-sparkling-wines',
    };
    for (final entry in primaryUrls.entries) {
      expect(sources[entry.key]!.url, entry.value);
      expect(
        dataset.sourceCitations.where((row) => row.url == entry.value),
        hasLength(1),
        reason: 'reuse exact URLs instead of duplicate citation records',
      );
    }
    for (final id in ['ki_d4brit_pdo_grapes', 'ki_d4brit_pdo_method']) {
      final refs = dataset.knowledgeItemCitations
          .where((row) => row.knowledgeItemId == id)
          .map((row) => row.sourceCitationId)
          .toSet();
      expect(
        refs,
        containsAll(['src_d4brit_english_pdo', 'src_d4brit_welsh_pdo']),
      );
    }
    // This teaching does not create an unsupported permission-map answer set.
    expect(
      items.values.where((item) => item.relationType == 'PERMITS_GRAPE'),
      isEmpty,
    );
  });

  test(
    'six choices balance cues and two original cases keep complete rubrics',
    () {
      expect(choices.keys.toSet(), principleIds);
      expect(cues.keys.toSet(), principleIds);
      final positions = List<int>.filled(4, 0);
      final lengthRanks = List<int>.filled(4, 0);
      final linkedPairs = {
        for (final row in dataset.knowledgeItemCitations)
          (row.knowledgeItemId, row.sourceCitationId),
      };
      for (final entry in choices.entries) {
        final cue = entry.value;
        expect(cue.options, hasLength(4), reason: entry.key);
        expect(
          cue.options.map((value) => value.toLowerCase().trim()).toSet(),
          hasLength(4),
          reason: entry.key,
        );
        expect(cue.correctIndex, inInclusiveRange(0, 3), reason: entry.key);
        positions[cue.correctIndex]++;
        lengthRanks[cue.options
            .where(
              (value) => value.length < cue.options[cue.correctIndex].length,
            )
            .length]++;
        expect(linkedPairs, contains((entry.key, cue.sourceCitationId)));
        expect(cues[entry.key]!.acceptedAnswers, isNotEmpty);
      }
      expect(positions, [2, 2, 1, 1]);
      expect(lengthRanks, [2, 1, 1, 2]);
      expect(
        CaseCriteriaFormat.datasetProblems(criteriaTemplate, dataset),
        isEmpty,
      );
      expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), {
        for (final key in caseKeys) 'n_d4brit_case_$key',
      });
      final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
      final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
      for (final key in caseKeys) {
        final subject = 'n_d4brit_case_$key';
        final written = templates['qt_d4brit_written_$key']!;
        expect(written.mode, 'short_answer');
        expect(ShortAnswerFormat.scopeNodeIdsOf(written), {subject});
        expect(ShortAnswerFormat.keyPointsOf(written)!.keys.toSet(), roles);
        expect(written.promptTemplate, nodes[subject]!.name);
        expect(written.promptTemplate, contains('Hypothetical'));
        expect(written.promptTemplate, contains('invented'));
        expect(distractors[subject], hasLength(2));
        expect(
          items.values
              .where((item) => item.subjectId == subject)
              .map((item) => item.relationType)
              .toSet(),
          roles,
        );
      }
    },
  );

  test('D4 unit and British objectives select the pack without claiming completion', () {
    final progress = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = progress.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    expect(diploma.curriculumComplete, isFalse);
    final d4 = diploma.units.singleWhere((unit) => unit.id == 'D4');
    final d5 = diploma.units.singleWhere((unit) => unit.id == 'D5');
    expect(d4.itemIds.toSet().intersection(expectedIds), expectedIds);
    expect(d5.itemIds.toSet().intersection(expectedIds), isEmpty);
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final row in scope.tracks['WSET_L4']!.objectives) row.id: row,
    };
    expect(
      objectives['wset_l4.sparkling.britain']!.covers!.within,
      containsAll([
        for (final key in principleKeys) 'n_d4brit_principle_$key',
        for (final key in caseKeys) 'n_d4brit_case_$key',
      ]),
    );
    expect(
      objectives['wset_l4.sparkling.commerce']!.covers!.within,
      containsAll([for (final key in caseKeys) 'n_d4brit_case_$key']),
    );
  });

  test(
    'runtime teaches six category decisions and two complete formative cases',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      await CurriculumIngester(db, clock: clock).ingest(dataset);
      final cards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('WSET_L4'))
          card.itemId: card,
      };
      expect(cards.keys, containsAll(expectedIds));
      for (final id in principleIds) {
        expect(
          cards[id]!.formats.map((row) => row.questionTemplateId),
          containsAll([choiceId, typedId]),
          reason: id,
        );
      }
      final lowerCards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('WSET_L3'))
          card.itemId,
      };
      expect(lowerCards.intersection(expectedIds), isEmpty);
      final cmsCards = {
        for (final card in await StudyPlanner(
          db,
          clock: clock,
        ).cards('CMS_CERTIFIED'))
          card.itemId,
      };
      expect(cmsCards.intersection(expectedIds), isEmpty);
      final presenter = ExercisePresenter(db, clock: clock);
      const wrongRecall = {
        'ki_d4brit_pdo_origin': ['85 percent', 'a UK bottling address'],
        'ki_d4brit_pdo_grapes': ['Bacchus', 'Seyval Blanc'],
        'ki_d4brit_pdo_method': ['three months', 'tank fermentation'],
        'ki_d4brit_pgi_hybrid': ['Pinot Noir', 'Chardonnay'],
        'ki_d4brit_unprotected_origin': [
          'automatic certification',
          'the bottling address',
        ],
        'ki_d4brit_pdo_assessment': [
          'comparative quality ranking',
          'a price test',
        ],
      };
      for (final id in principleIds) {
        final choice = await presenter.present(
          id,
          choiceId,
          seed: 31,
          certificationId: 'WSET_L4',
        ) as AuthoredChoiceQuestion;
        expect(choice.sourceCitationId, choices[id]!.sourceCitationId);
        expect(
          choice.answer.name,
          choices[id]!.options[choices[id]!.correctIndex],
        );
        expect(
          const AuthoredChoiceFormat()
              .grade(choice, choice.answer)
              .single
              .rating,
          fsrs.Rating.good,
        );
        for (final wrong in choice.options.where(
          (value) => value != choice.answer,
        )) {
          expect(
            const AuthoredChoiceFormat().grade(choice, wrong).single.rating,
            fsrs.Rating.again,
          );
        }
        final typed = await presenter.present(
          id,
          typedId,
          seed: 31,
          certificationId: 'WSET_L4',
        ) as TypedQuestion;
        expect(typed.prompt, cues[id]!.prompt);
        for (final answer in cues[id]!.acceptedAnswers) {
          expect(
            const TypedFormat().grade(typed, answer).single.rating,
            fsrs.Rating.good,
            reason: '$id accepts $answer',
          );
        }
        for (final answer in wrongRecall[id]!) {
          expect(
            const TypedFormat().grade(typed, answer).single.rating,
            fsrs.Rating.again,
            reason: '$id rejects $answer',
          );
        }
      }
      final pools = await db.select(db.exercisePools).get();
      expect(
        pools.where((pool) => pool.questionTemplateId == criteriaId),
        hasLength(2),
      );
      final reviews = ReviewService(db, clock: clock);
      for (final key in caseKeys) {
        final id = 'ki_d4brit_case_${key}_action';
        final caseItemIds = caseIds(key);
        final introduction = await presenter.present(
          id,
          'qt_d4brit_written_$key',
          seed: 31,
        ) as ShortAnswerExercise;
        expect(introduction.itemIds, hasLength(2));
        expect(introduction.itemIds, contains(id));
        for (final point in items.values.where(
          (item) => caseItemIds.contains(item.id),
        )) {
          final flashcard = dataset.questionTemplates.singleWhere(
            (row) =>
                row.mode == 'flashcard' &&
                row.relationType == point.relationType,
          );
          await reviews.record(
            knowledgeItemId: point.id,
            questionTemplateId: flashcard.id,
            rating: fsrs.Rating.good,
          );
        }
        final written = await presenter.present(
          id,
          'qt_d4brit_written_$key',
          seed: 31,
        ) as ShortAnswerExercise;
        expect(written.itemIds.toSet(), caseItemIds);
        expect(written.keyPoints, hasLength(4));
        final criteria = await presenter.present(
          id,
          criteriaId,
          seed: 31,
        ) as CaseCriteriaExercise;
        expect(criteria.itemIds.toSet(), caseItemIds);
        expect(criteria.options, hasLength(6));
        expect(
          criteria.criteria.every((point) => point.sources.isNotEmpty),
          isTrue,
        );
        final goodAnswer = {
          for (final point in criteria.criteria) point.role: point.itemId,
        };
        final grades = const CaseCriteriaFormat().grade(
          criteria,
          CaseCriteriaResponse(goodAnswer),
        );
        expect(grades, hasLength(4));
        expect(
          grades.every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
        final wrongAnswer = {...goodAnswer};
        wrongAnswer['CASE_REASON'] = criteria.options
            .firstWhere((option) => !caseItemIds.contains(option.id))
            .id;
        final wrongGrades = const CaseCriteriaFormat().grade(
          criteria,
          CaseCriteriaResponse(wrongAnswer),
        );
        expect(
          wrongGrades.where((grade) => grade.rating == fsrs.Rating.again),
          hasLength(1),
        );
        expect(
          wrongGrades.where((grade) => grade.rating == fsrs.Rating.good),
          hasLength(3),
        );
      }
    },
  );
}
