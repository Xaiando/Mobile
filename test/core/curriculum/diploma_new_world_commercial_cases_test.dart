import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/questions/question_presenter.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const criteriaId = 'qt_d4commercial_case_criteria_3';
  const writtenId = 'qt_d4commercial_case_written_3';
  const actions = {
    'n_d4commercial_case_us_offer': 'ki_d4commercial_case_us_offer_action',
    'n_d4commercial_case_andes_offer':
        'ki_d4commercial_case_andes_offer_action',
    'n_d4commercial_case_oceania_africa_offer':
        'ki_d4commercial_case_oceania_africa_offer_action',
  };
  const expectedIds = {
    'ki_d4commercial_case_us_offer_action',
    'ki_d4commercial_case_us_offer_reason',
    'ki_d4commercial_case_us_offer_tradeoff',
    'ki_d4commercial_case_us_offer_limitation',
    'ki_d4commercial_case_andes_offer_action',
    'ki_d4commercial_case_andes_offer_reason',
    'ki_d4commercial_case_andes_offer_tradeoff',
    'ki_d4commercial_case_andes_offer_limitation',
    'ki_d4commercial_case_oceania_africa_offer_action',
    'ki_d4commercial_case_oceania_africa_offer_reason',
    'ki_d4commercial_case_oceania_africa_offer_tradeoff',
    'ki_d4commercial_case_oceania_africa_offer_limitation',
  };
  final criteriaTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == criteriaId,
  );
  final writtenTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == writtenId,
  );
  final prompts = CaseCriteriaFormat.scenarioPromptsOf(criteriaTemplate);
  final scope = actions.keys.toSet();

  test(
    'three original D4 cases retain supplied premises and twelve sourced roles',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), scope);
      expect(ShortAnswerFormat.scopeNodeIdsOf(writtenTemplate), scope);
      expect(prompts.keys.toSet(), scope);
      final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
      expect(distractors.keys.toSet(), scope);
      final items = dataset.knowledgeItems
          .where((row) => row.id.startsWith('ki_d4commercial_case_'))
          .toList();
      expect(items.map((row) => row.id).toSet(), expectedIds);
      final sourceUrls = {
        for (final source in dataset.sourceCitations) source.id: source.url,
      };
      for (final subject in scope) {
        final node = dataset.knowledgeNodes.singleWhere(
          (row) => row.id == subject,
        );
        expect(node.nodeType, 'production_case');
        expect(node.name, prompts[subject]);
        expect(prompts[subject], contains('Fictional buying exercise'));
        final roles = items.where((row) => row.subjectId == subject).toList();
        expect(roles, hasLength(4), reason: subject);
        expect(
          roles.map((row) => row.relationType).toSet(),
          caseCriterionRoles.toSet(),
          reason: subject,
        );
        expect(distractors[subject], hasLength(2), reason: subject);
        expect(
          distractors[subject]!.map((row) => row.summary).toSet(),
          hasLength(2),
        );
        for (final falseOption in distractors[subject]!) {
          expect(falseOption.explanation, isNotEmpty, reason: subject);
        }
        for (final item in roles) {
          expect(item.domainId, 'business', reason: item.id);
          expect(item.verificationStatus, 'unverified', reason: item.id);
          expect(item.mcqDisabled, isTrue, reason: item.id);
          final mappings = dataset.certificationKnowledgeMappings
              .where((row) => row.knowledgeItemId == item.id)
              .toList();
          expect(mappings, hasLength(1), reason: item.id);
          expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
          expect(mappings.single.importance, 'core', reason: item.id);
          expect(mappings.single.minimumDepth, 3, reason: item.id);
          final citations = dataset.knowledgeItemCitations
              .where((row) => row.knowledgeItemId == item.id)
              .toList();
          expect(citations, isNotEmpty, reason: item.id);
          for (final citation in citations) {
            expect(
              sourceUrls[citation.sourceCitationId],
              startsWith('https://'),
            );
            expect(citation.locator, isNotEmpty, reason: item.id);
          }
        }
      }
      // Preserve the constraints that make each decision bounded.
      expect(
        prompts['n_d4commercial_case_us_offer'],
        contains('before freight'),
      );
      expect(
        prompts['n_d4commercial_case_us_offer'],
        contains('no fermentation or lees records'),
      );
      expect(prompts['n_d4commercial_case_andes_offer'], contains('six weeks'));
      expect(
        prompts['n_d4commercial_case_andes_offer'],
        contains('eight-week delivery'),
      );
      expect(prompts['n_d4commercial_case_andes_offer'], contains('2023'));
      expect(
        prompts['n_d4commercial_case_oceania_africa_offer'],
        contains('entire cost of goods sold'),
      );
      expect(
        prompts['n_d4commercial_case_oceania_africa_offer'],
        contains('not a real tax or landed-cost schedule'),
      );
    },
  );

  test('cold and studied cases preserve isolation and independently grade twelve criteria', () async {
    final db = openTestDatabase();
    try {
      final fixed = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: fixed,
        assets: (path) async => File(path).readAsBytesSync(),
      ).ingest(dataset);
      final pools = (await db.select(db.exercisePools).get())
          .where((row) => row.questionTemplateId == criteriaId)
          .toList();
      expect(pools, hasLength(3));
      expect(pools.map((row) => row.scopeNodeId).toSet(), scope);
      final poolItems = await db.select(db.exercisePoolItems).get();
      for (final pool in pools) {
        expect(
          poolItems.where((row) => row.exercisePoolId == pool.id),
          hasLength(4),
          reason: pool.scopeNodeId,
        );
      }

      final planner = StudyPlanner(db, clock: fixed);
      for (final track in [
        'WSET_L1',
        'WSET_L2',
        'WSET_L3',
        'CMS_INTRODUCTORY',
        'CMS_CERTIFIED',
      ]) {
        expect(
          (await planner.cards(track))
              .map((row) => row.itemId)
              .toSet()
              .intersection(expectedIds),
          isEmpty,
          reason: track,
        );
      }
      final cold = {
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      expect(cold.keys.toSet(), containsAll(expectedIds));
      for (final id in actions.values) {
        expect(
          cold[id]!.formats.map((row) => row.mode),
          isNot(contains(CaseCriteriaFormat.formatId)),
          reason: id,
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
      for (final item in dataset.knowledgeItems.where(
        (row) => expectedIds.contains(row.id),
      )) {
        final question = await flashcardPresenter.present(
          item.id,
          flashcards[item.relationType]!,
          seed: 11,
        );
        await reviews.gradeFlashcard(question, fsrs.Rating.good);
      }
      final studied = {
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      for (final id in actions.values) {
        expect(
          studied[id]!.formats.map((row) => row.mode),
          contains(CaseCriteriaFormat.formatId),
          reason: id,
        );
      }

      final presenter = ExercisePresenter(db, clock: fixed);
      const criteriaFormat = CaseCriteriaFormat();
      const writtenFormat = ShortAnswerFormat();
      final servedIds = <String>{};
      for (final entry in actions.entries) {
        final exercise = await presenter.present(
          entry.value,
          criteriaId,
          certificationId: 'WSET_L4',
          seed: 11,
        ) as CaseCriteriaExercise;
        expect(exercise.prompt, prompts[entry.key]);
        final caseIds = expectedIds.where((id) {
          final item = dataset.knowledgeItems.singleWhere(
            (row) => row.id == id,
          );
          return item.subjectId == entry.key;
        }).toSet();
        expect(exercise.itemIds.toSet(), caseIds, reason: entry.key);
        expect(exercise.options, hasLength(6), reason: entry.key);
        expect(
          exercise.options.map((row) => row.summary).toSet(),
          hasLength(6),
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
        servedIds.addAll(exercise.itemIds);
        final correctByRole = {
          for (final criterion in exercise.criteria)
            criterion.role: criterion.itemId,
        };
        final correct = criteriaFormat.grade(
          exercise,
          CaseCriteriaResponse(correctByRole),
        );
        expect(correct, hasLength(4));
        expect(correct.every((row) => row.rating == fsrs.Rating.good), isTrue);
        final falseOptions = exercise.options
            .where((row) => row.explanation != null)
            .toList();
        expect(falseOptions, hasLength(2));
        for (final falseOption in falseOptions) {
          for (final role in caseCriterionRoles) {
            final grades = criteriaFormat.grade(
              exercise,
              CaseCriteriaResponse({...correctByRole, role: falseOption.id}),
            );
            final ratings = {
              for (final grade in grades) grade.itemId: grade.rating,
            };
            expect(
              ratings[correctByRole[role]],
              fsrs.Rating.again,
              reason: entry.key,
            );
            for (final other in caseCriterionRoles.where(
              (row) => row != role,
            )) {
              expect(
                ratings[correctByRole[other]],
                fsrs.Rating.good,
                reason: entry.key,
              );
            }
          }
        }
        // A supported case point assigned to the wrong role also fails that role.
        final mixed = criteriaFormat.grade(
          exercise,
          CaseCriteriaResponse({
            ...correctByRole,
            'CASE_ACTION': correctByRole['CASE_REASON']!,
            'CASE_REASON': correctByRole['CASE_ACTION']!,
          }),
        );
        expect(
          mixed.singleWhere((row) => row.itemId == entry.value).rating,
          fsrs.Rating.again,
        );
        expect(
          mixed
              .singleWhere((row) => row.itemId == correctByRole['CASE_REASON'])
              .rating,
          fsrs.Rating.again,
        );
        for (final role in ['CASE_TRADEOFF', 'CASE_LIMITATION']) {
          expect(
            mixed
                .singleWhere((row) => row.itemId == correctByRole[role])
                .rating,
            fsrs.Rating.good,
          );
        }

        final written = await presenter.present(
          entry.value,
          writtenId,
          certificationId: 'WSET_L4',
          seed: 11,
        ) as ShortAnswerExercise;
        expect(written.prompt, prompts[entry.key]);
        expect(written.itemIds.toSet(), caseIds, reason: entry.key);
        expect(written.keyPoints, hasLength(4));
        expect(
          written.keyPoints.every((row) => row.statement.isNotEmpty),
          isTrue,
        );
        final writtenCorrect = writtenFormat.grade(
          written,
          ShortAnswerResponse('My original case analysis', caseIds),
        );
        expect(
          writtenCorrect.every((row) => row.rating == fsrs.Rating.good),
          isTrue,
        );
        final uncovered = writtenFormat.grade(
          written,
          ShortAnswerResponse(
            'I omitted the limitation',
            {...caseIds}..remove(correctByRole['CASE_LIMITATION']),
          ),
        );
        expect(
          uncovered
              .singleWhere(
                (row) => row.itemId == correctByRole['CASE_LIMITATION'],
              )
              .rating,
          fsrs.Rating.again,
        );
      }
      expect(servedIds, expectedIds);

      const policyPath = 'assets/curriculum/coverage_policy.yaml';
      final report =
          await CoverageChecker(
            db,
            CoveragePolicy.parse(
              File(policyPath).readAsStringSync(),
              path: policyPath,
            ),
          ).check(
            'WSET_L4',
            on: dataset.publishedAt.toIso8601String().substring(0, 10),
            skipped: generation.skipped,
          );
      final measured = report.items
          .where((row) => expectedIds.contains(row.id))
          .toList();
      expect(measured, hasLength(12));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(row.servedFormats, contains('case_criteria'), reason: row.id);
        expect(row.servedFormats, contains('short_answer'), reason: row.id);
      }
    } finally {
      await db.close();
    }
  });
}
