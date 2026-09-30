import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const templateId = 'qt_cms_service_remaining_case_criteria_7';
  const actions = {
    'n_cms_beer_case_cask': 'ki_cms_beer_case_cask_action',
    'n_cms_beer_case_pair': 'ki_cms_beer_case_pair_action',
    'n_cms_beer_case_belgian': 'ki_cms_beer_case_belgian_action',
    'n_cms_pairing_case_oysters': 'ki_cms_pairing_oysters_action',
    'n_cms_pairing_case_chocolate': 'ki_cms_pairing_chocolate_action',
    'n_cms_irish_case': 'ki_cms_irish_case_action',
    'n_cms_liqueur_case': 'ki_cms_liqueur_case_action',
  };
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == templateId,
  );
  final scope = CaseCriteriaFormat.scopeNodeIdsOf(template);

  test('seven CMS service cases retain full premises and sourced roles', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(template.mode, CaseCriteriaFormat.formatId);
    expect(scope, actions.keys.toSet());
    final prompts = CaseCriteriaFormat.scenarioPromptsOf(template);
    final distractors = CaseCriteriaFormat.distractorsOf(template);
    expect(prompts.keys.toSet(), scope);
    expect(distractors.keys.toSet(), scope);
    final citedIds = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId,
    };
    final sources = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    final itemIds = <String>{};
    for (final subject in scope) {
      expect(prompts[subject]!.length, greaterThan(80), reason: subject);
      expect(distractors[subject], hasLength(2), reason: subject);
      for (final falseOption in distractors[subject]!) {
        expect(falseOption.summary.length, greaterThan(35), reason: subject);
        expect(
          falseOption.explanation!.length,
          greaterThan(45),
          reason: subject,
        );
      }
      final roles = [
        for (final item in dataset.knowledgeItems)
          if (item.subjectId == subject &&
              caseCriterionRoles.contains(item.relationType))
            item,
      ];
      expect(roles, hasLength(4), reason: subject);
      expect(
        roles.map((item) => item.relationType).toSet(),
        caseCriterionRoles.toSet(),
        reason: subject,
      );
      for (final item in roles) {
        itemIds.add(item.id);
        expect(item.domainId, 'service', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(citedIds, contains(item.id), reason: item.id);
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (row) =>
              row.certificationId == 'CMS_CERTIFIED' &&
              row.knowledgeItemId == item.id,
        );
        expect(mapping.importance, 'core', reason: item.id);
        expect(mapping.minimumDepth, 2, reason: item.id);
        for (final citation in dataset.knowledgeItemCitations.where(
          (row) => row.knowledgeItemId == item.id,
        )) {
          final url = sources[citation.sourceCitationId];
          expect(url, isNotNull, reason: item.id);
          expect(Uri.parse(url!).scheme, 'https', reason: item.id);
        }
      }
    }
    expect(itemIds, hasLength(28));
  });

  test(
    'seven pools deliver and grade all 28 CMS criteria independently',
    () async {
      final db = openTestDatabase();
      try {
        final fixed = Clock.fixed(dataset.publishedAt);
        final generation = await CurriculumIngester(
          db,
          clock: fixed,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final pools = (await db.select(db.exercisePools).get())
            .where((pool) => pool.questionTemplateId == templateId)
            .toList();
        expect(pools, hasLength(7));
        expect(pools.map((pool) => pool.scopeNodeId).toSet(), scope);
        final members = await db.select(db.exercisePoolItems).get();
        for (final pool in pools) {
          expect(
            members.where((member) => member.exercisePoolId == pool.id),
            hasLength(4),
            reason: pool.scopeNodeId,
          );
        }

        final planner = StudyPlanner(db, clock: fixed);
        final coldCards = {
          for (final card in await planner.cards('CMS_CERTIFIED'))
            card.itemId: card,
        };
        for (final entry in actions.entries) {
          expect(
            coldCards[entry.value]!.formats.map((row) => row.mode),
            isNot(contains(CaseCriteriaFormat.formatId)),
            reason: entry.key,
          );
        }

        const flashcards = {
          'CASE_ACTION': 'qt_case_action_flashcard',
          'CASE_REASON': 'qt_case_reason_flashcard',
          'CASE_TRADEOFF': 'qt_case_tradeoff_flashcard',
          'CASE_LIMITATION': 'qt_case_limitation_flashcard',
        };
        final flashcardPresenter = QuestionPresenter(db);
        final reviews = ReviewService(db, clock: fixed);
        for (final subject in scope) {
          for (final item in dataset.knowledgeItems.where(
            (row) =>
                row.subjectId == subject &&
                caseCriterionRoles.contains(row.relationType),
          )) {
            final question = await flashcardPresenter.present(
              item.id,
              flashcards[item.relationType]!,
              seed: 7,
            );
            await reviews.gradeFlashcard(question, fsrs.Rating.good);
          }
        }
        final studiedCards = {
          for (final card in await planner.cards('CMS_CERTIFIED'))
            card.itemId: card,
        };
        for (final entry in actions.entries) {
          expect(
            studiedCards[entry.value]!.formats.map((row) => row.mode),
            contains(CaseCriteriaFormat.formatId),
            reason: entry.key,
          );
        }

        final presenter = ExercisePresenter(db, clock: fixed);
        const format = CaseCriteriaFormat();
        final prompts = CaseCriteriaFormat.scenarioPromptsOf(template);
        final itemIds = <String>{};
        for (final entry in actions.entries) {
          final exercise = await presenter.present(
            entry.value,
            templateId,
            certificationId: 'CMS_CERTIFIED',
            seed: 7,
          ) as CaseCriteriaExercise;
          expect(exercise.primaryItemId, entry.value);
          expect(exercise.prompt, prompts[entry.key]);
          expect(exercise.itemIds, hasLength(4), reason: entry.key);
          expect(exercise.options, hasLength(6), reason: entry.key);
          expect(
            exercise.criteria.map((row) => row.role).toSet(),
            caseCriterionRoles.toSet(),
            reason: entry.key,
          );
          expect(
            exercise.criteria.every(
              (row) =>
                  row.assertion.isNotEmpty &&
                  row.sources.isNotEmpty &&
                  row.sources.every(
                    (source) => source.url?.startsWith('https://') == true,
                  ),
            ),
            isTrue,
            reason: entry.key,
          );
          itemIds.addAll(exercise.itemIds);
          final byRole = {
            for (final criterion in exercise.criteria)
              criterion.role: criterion.itemId,
          };
          final correct = format.grade(exercise, CaseCriteriaResponse(byRole));
          expect(correct, hasLength(4), reason: entry.key);
          expect(
            correct.every((grade) => grade.rating == fsrs.Rating.good),
            isTrue,
            reason: entry.key,
          );
          final falseOptions = exercise.options
              .where((option) => option.explanation != null)
              .toList();
          expect(falseOptions, hasLength(2), reason: entry.key);
          for (final falseOption in falseOptions) {
            for (final role in caseCriterionRoles) {
              final wrong = format.grade(
                exercise,
                CaseCriteriaResponse({...byRole, role: falseOption.id}),
              );
              expect(wrong, hasLength(4), reason: entry.key);
              final ratings = {
                for (final grade in wrong) grade.itemId: grade.rating,
              };
              expect(
                ratings[byRole[role]],
                fsrs.Rating.again,
                reason: entry.key,
              );
              for (final otherRole in caseCriterionRoles.where(
                (candidate) => candidate != role,
              )) {
                expect(
                  ratings[byRole[otherRole]],
                  fsrs.Rating.good,
                  reason: entry.key,
                );
              }
            }
          }
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
        final measured = report.items.where((row) => itemIds.contains(row.id));
        expect(measured, hasLength(28));
        for (final row in measured) {
          expect(row.isCore, isTrue, reason: row.id);
          expect(row.hasUsefulPractice, isTrue, reason: row.id);
          expect(row.servedFormats, contains('case_criteria'), reason: row.id);
          expect(row.servedFormats, contains('short_answer'), reason: row.id);
        }
      } finally {
        await db.close();
      }
    },
  );
}
