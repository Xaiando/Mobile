import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  const recognitionId = 'qt_cms_cocktail_recognition_8';
  const recallId = 'qt_cms_cocktail_point_recall_8';
  const guestChoiceId = 'qt_cms_cocktail_guest_choice_2';
  const caseId = 'qt_cms_cocktail_case_criteria_2';
  const writtenId = 'qt_cms_cocktail_case_written_2';
  const principleIds = {
    'ki_cms_cocktail_dry_martini',
    'ki_cms_cocktail_manhattan',
    'ki_cms_cocktail_negroni',
    'ki_cms_cocktail_daiquiri',
    'ki_cms_cocktail_margarita',
    'ki_cms_cocktail_old_fashioned',
    'ki_cms_cocktail_whiskey_sour',
    'ki_cms_cocktail_americano',
  };
  const actions = {
    'n_cms_cocktail_case_aperitif': 'ki_cms_cocktail_aperitif_action',
    'n_cms_cocktail_case_rum_citrus': 'ki_cms_cocktail_rum_citrus_action',
  };
  const caseItemIds = {
    'ki_cms_cocktail_aperitif_action',
    'ki_cms_cocktail_aperitif_reason',
    'ki_cms_cocktail_aperitif_tradeoff',
    'ki_cms_cocktail_aperitif_limit',
    'ki_cms_cocktail_rum_citrus_action',
    'ki_cms_cocktail_rum_citrus_reason',
    'ki_cms_cocktail_rum_citrus_tradeoff',
    'ki_cms_cocktail_rum_citrus_limit',
  };
  const newIds = {...principleIds, ...caseItemIds};
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final recognition = dataset.questionTemplates.singleWhere(
    (row) => row.id == recognitionId,
  );
  final guestChoice = dataset.questionTemplates.singleWhere(
    (row) => row.id == guestChoiceId,
  );
  final recall = dataset.questionTemplates.singleWhere(
    (row) => row.id == recallId,
  );
  final cases = dataset.questionTemplates.singleWhere(
    (row) => row.id == caseId,
  );
  final choices = {
    ...AuthoredChoiceFormat.itemChoicesOf(recognition),
    ...AuthoredChoiceFormat.itemChoicesOf(guestChoice),
  };
  final cues = TypedFormat.itemCuesOf(recall)!;

  test(
    'eight recipe references and two complete cases are CMS-only and cited',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(
        dataset.knowledgeItems
            .where((item) => item.id.startsWith('ki_cms_cocktail_'))
            .map((item) => item.id)
            .toSet(),
        newIds,
      );
      final sources = {
        for (final source in dataset.sourceCitations) source.id: source,
      };
      for (final id in newIds) {
        final item = items[id]!;
        expect(item.domainId, 'service', reason: id);
        expect(item.verificationStatus, 'unverified', reason: id);
        expect(item.mcqDisabled, isTrue, reason: id);
        final mappings = dataset.certificationKnowledgeMappings
            .where((row) => row.knowledgeItemId == id)
            .toList();
        expect(mappings, hasLength(1), reason: id);
        expect(mappings.single.certificationId, 'CMS_CERTIFIED', reason: id);
        expect(mappings.single.importance, 'core', reason: id);
        expect(
          mappings.single.minimumDepth,
          principleIds.contains(id) ? 2 : 3,
          reason: id,
        );
        final linked = dataset.knowledgeItemCitations
            .where((row) => row.knowledgeItemId == id)
            .toList();
        expect(linked, isNotEmpty, reason: id);
        expect(
          linked.any(
            (row) => sources[row.sourceCitationId]!.url!.startsWith(
              'https://iba-world.com/iba-cocktail/',
            ),
          ),
          isTrue,
          reason: id,
        );
        for (final link in linked) {
          expect(link.locator, isNotEmpty, reason: id);
          expect(sources[link.sourceCitationId], isNotNull, reason: id);
        }
      }
      for (final subject in actions.keys) {
        expect(
          dataset.knowledgeItems
              .where((item) => item.subjectId == subject)
              .map((item) => item.relationType)
              .toSet(),
          caseCriterionRoles.toSet(),
        );
      }
      expect(
        items['ki_cms_cocktail_dry_martini']!.assertionText,
        contains('60 ml gin with 10 ml dry vermouth'),
      );
      expect(
        items['ki_cms_cocktail_manhattan']!.assertionText,
        contains('50 ml rye whiskey'),
      );
      expect(
        items['ki_cms_cocktail_negroni']!.assertionText,
        contains('equal 30 ml portions'),
      );
      expect(
        items['ki_cms_cocktail_daiquiri']!.assertionText,
        contains('two bar spoons of superfine sugar'),
      );
      expect(
        items['ki_cms_cocktail_margarita']!.assertionText,
        contains('half salt rim is optional'),
      );
      expect(
        items['ki_cms_cocktail_whiskey_sour']!.assertionText,
        contains('egg white are optional'),
      );
      expect(
        items['ki_cms_cocktail_americano']!.assertionText,
        contains('still an alcoholic drink'),
      );
      expect(
        items['ki_cms_cocktail_rum_citrus_limit']!.assertionText,
        contains('not an exact millilitre conversion'),
      );
    },
  );

  test(
    'original choices and narrow recall have linked keys without length cues',
    () {
      expect(choices.keys.toSet(), {...principleIds, ...actions.values});
      expect(cues.keys.toSet(), principleIds);
      final positions = <int, int>{};
      final lengthRanks = <int, int>{};
      for (final entry in choices.entries) {
        final cue = entry.value;
        expect(cue.options, hasLength(4), reason: entry.key);
        expect(cue.options.toSet(), hasLength(4), reason: entry.key);
        expect(
          dataset.knowledgeItemCitations.any(
            (row) =>
                row.knowledgeItemId == entry.key &&
                row.sourceCitationId == cue.sourceCitationId,
          ),
          isTrue,
          reason: entry.key,
        );
        final key = cue.options[cue.correctIndex];
        expect(cue.prompt.contains(key), isFalse, reason: entry.key);
        positions.update(cue.correctIndex, (n) => n + 1, ifAbsent: () => 1);
        final rank = cue.options
            .where((option) => option.length < key.length)
            .length;
        expect(rank, inInclusiveRange(0, 3), reason: entry.key);
        lengthRanks.update(rank, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(positions, {0: 3, 1: 3, 2: 2, 3: 2});
      expect(lengthRanks, {0: 2, 1: 3, 2: 3, 3: 2});
      expect(CaseCriteriaFormat.scopeNodeIdsOf(cases), actions.keys.toSet());
      final prompts = CaseCriteriaFormat.scenarioPromptsOf(cases);
      final distractors = CaseCriteriaFormat.distractorsOf(cases);
      for (final subject in actions.keys) {
        expect(prompts[subject]!.length, greaterThan(120));
        expect(distractors[subject], hasLength(2));
        for (final option in distractors[subject]!) {
          expect(option.explanation!.length, greaterThan(45));
        }
      }
    },
  );

  test(
    'CMS Study delivers and grades references and complete studied cases',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final fixed = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final planner = StudyPlanner(db, clock: fixed);
      final coldCards = {
        for (final card in await planner.cards('CMS_CERTIFIED'))
          card.itemId: card,
      };
      expect(coldCards.keys, containsAll(newIds));
      for (final id in principleIds) {
        expect(
          coldCards[id]!.formats.map((row) => row.questionTemplateId),
          containsAll([recognitionId, recallId]),
          reason: id,
        );
      }
      for (final id in actions.values) {
        expect(
          coldCards[id]!.formats.map((row) => row.questionTemplateId),
          contains(guestChoiceId),
        );
        expect(
          coldCards[id]!.formats.map((row) => row.mode),
          isNot(contains(CaseCriteriaFormat.formatId)),
        );
      }

      final presenter = ExercisePresenter(db, clock: fixed);
      const choiceFormat = AuthoredChoiceFormat();
      const typedFormat = TypedFormat();
      const wrongRecall = {
        'ki_cms_cocktail_dry_martini': ['sweet red vermouth', 'triple sec'],
        'ki_cms_cocktail_manhattan': ['gin', 'bourbon'],
        'ki_cms_cocktail_negroni': ['double gin', 'twice as much gin'],
        'ki_cms_cocktail_daiquiri': ['triple sec', 'sweet vermouth'],
        'ki_cms_cocktail_margarita': ['Campari', 'dry vermouth'],
        'ki_cms_cocktail_old_fashioned': ['vermouth', 'triple sec'],
        'ki_cms_cocktail_whiskey_sour': ['bourbon', 'lemon juice'],
        'ki_cms_cocktail_americano': ['gin', 'tonic water'],
      };
      for (final entry in choices.entries) {
        final question = await presenter.present(
          entry.key,
          principleIds.contains(entry.key) ? recognitionId : guestChoiceId,
          seed: 17,
          certificationId: 'CMS_CERTIFIED',
        ) as AuthoredChoiceQuestion;
        expect(
          question.answer.name,
          entry.value.options[entry.value.correctIndex],
        );
        expect(question.sourceCitationId, entry.value.sourceCitationId);
        expect(
          choiceFormat.grade(question, question.answer).single.rating,
          fsrs.Rating.good,
        );
        for (final wrong in question.options.where(
          (option) => option != question.answer,
        )) {
          expect(
            choiceFormat.grade(question, wrong).single.rating,
            fsrs.Rating.again,
            reason: entry.key,
          );
        }
      }
      for (final id in principleIds) {
        final question = await presenter.present(
          id,
          recallId,
          seed: 17,
          certificationId: 'CMS_CERTIFIED',
        ) as TypedQuestion;
        expect(question.prompt, cues[id]!.prompt);
        for (final answer in cues[id]!.acceptedAnswers) {
          expect(
            typedFormat.grade(question, answer).single.rating,
            fsrs.Rating.good,
            reason: '$id accepts $answer',
          );
        }
        for (final answer in wrongRecall[id]!) {
          expect(
            typedFormat.grade(question, answer).single.rating,
            fsrs.Rating.again,
            reason: '$id rejects $answer',
          );
        }
      }

      const flashcards = {
        'CASE_ACTION': 'qt_case_action_flashcard',
        'CASE_REASON': 'qt_case_reason_flashcard',
        'CASE_TRADEOFF': 'qt_case_tradeoff_flashcard',
        'CASE_LIMITATION': 'qt_case_limitation_flashcard',
      };
      final flashcardPresenter = QuestionPresenter(db);
      final reviews = ReviewService(db, clock: fixed);
      for (final id in caseItemIds) {
        final question = await flashcardPresenter.present(
          id,
          flashcards[items[id]!.relationType]!,
          seed: 17,
        );
        await reviews.gradeFlashcard(question, fsrs.Rating.good);
      }
      final studiedCards = {
        for (final card in await planner.cards('CMS_CERTIFIED'))
          card.itemId: card,
      };
      const caseFormat = CaseCriteriaFormat();
      for (final action in actions.values) {
        expect(
          studiedCards[action]!.formats.map((row) => row.mode),
          contains(CaseCriteriaFormat.formatId),
        );
        final exercise = await presenter.present(
          action,
          caseId,
          seed: 17,
          certificationId: 'CMS_CERTIFIED',
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds, hasLength(4));
        expect(exercise.options, hasLength(6));
        for (final criterion in exercise.criteria) {
          expect(criterion.sources, isNotEmpty);
          expect(criterion.assertion, items[criterion.itemId]!.assertionText);
        }
        final byRole = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        final correct = caseFormat.grade(
          exercise,
          CaseCriteriaResponse(byRole),
        );
        expect(correct, hasLength(4));
        expect(
          correct.every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
        final falseOptions = exercise.options
            .where((option) => option.explanation != null)
            .toList();
        expect(falseOptions, hasLength(2));
        for (final falseOption in falseOptions) {
          for (final role in caseCriterionRoles) {
            final grades = caseFormat.grade(
              exercise,
              CaseCriteriaResponse({...byRole, role: falseOption.id}),
            );
            expect(grades, hasLength(4));
            final ratings = {
              for (final grade in grades) grade.itemId: grade.rating,
            };
            expect(ratings[byRole[role]], fsrs.Rating.again);
            for (final otherRole in caseCriterionRoles.where(
              (candidate) => candidate != role,
            )) {
              expect(ratings[byRole[otherRole]], fsrs.Rating.good);
            }
          }
        }
        final written = await presenter.present(
          action,
          writtenId,
          seed: 17,
          certificationId: 'CMS_CERTIFIED',
        ) as ShortAnswerExercise;
        expect(written.itemIds.toSet(), exercise.itemIds.toSet());
      }

      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final report =
          await CoverageChecker(
            db,
            CoveragePolicy.parse(
              File(policyPath).readAsStringSync(),
              path: policyPath,
            ),
          ).check(
            'CMS_CERTIFIED',
            on: dataset.publishedAt.toIso8601String().substring(0, 10),
            skipped: generation.skipped,
          );
      final measured = report.items
          .where((row) => newIds.contains(row.id))
          .toList();
      expect(measured, hasLength(16));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(
          row.servedFormats,
          contains(
            principleIds.contains(row.id) ? 'authored_choice' : 'case_criteria',
          ),
          reason: row.id,
        );
      }
      for (final track in ['CMS_INTRODUCTORY', 'WSET_L3']) {
        final ids = (await planner.cards(track))
            .map((card) => card.itemId)
            .toSet();
        expect(ids.intersection(newIds), isEmpty, reason: track);
      }
    },
  );
}
