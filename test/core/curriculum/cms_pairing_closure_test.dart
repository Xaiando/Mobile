import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_cms_pairing_'))
      .toList();
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const caseRoles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };

  test('new CMS pairing lessons are conditional, CMS-only and cited to education sources', () {
    expect(items, hasLength(14));
    final usedSources = <String>{};
    for (final item in items) {
      expect(item.domainId, 'service', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'CMS_CERTIFIED');
      expect(mappings.single.importance, 'core');
      expect(mappings.single.minimumDepth, 2);
      final citations = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(citation.locator, isNotEmpty, reason: item.id);
        final source = sources[citation.sourceCitationId];
        expect(source, isNotNull, reason: item.id);
        final url = Uri.parse(source!.url!);
        expect(
          url.host,
          anyOf('courtofmastersommeliers.org', 'www.wsetglobal.com'),
        );
        expect(url.path.toLowerCase(), isNot(contains('syllabus')));
        usedSources.add(source.id);
      }
      expect(
        dataset.knowledgeRelations.where(
          (relation) =>
              relation.subjectId == item.subjectId &&
              relation.relationType == item.relationType &&
              relation.objectId == item.objectId,
        ),
        hasLength(1),
        reason: item.id,
      );
    }
    expect(usedSources, {
      'src_cms_pairing_guide',
      'src_cms_pairing_wset_easter',
      'src_cms_pairing_wset_browning',
      'src_wset_srv_food',
      'src_wset_srv_sweet',
    });
    for (final subject in [
      'n_cms_pairing_case_oysters',
      'n_cms_pairing_case_chocolate',
    ]) {
      final rubric = items.where((item) => item.subjectId == subject).toList();
      expect(rubric, hasLength(4));
      expect(rubric.map((item) => item.relationType).toSet(), caseRoles);
    }
    expect(
      items
          .singleWhere(
            (item) => item.id == 'ki_cms_pairing_chocolate_limitation',
          )
          .assertionText,
      contains('do not test this exact chocolate tart'),
    );
  });

  test(
    'a cooking principle and each wine-to-dish case generate scoped recall',
    () async {
      final db = openTestDatabase();
      try {
        final time = TestClock(DateTime.utc(2026, 10, 1, 9));
        await CurriculumIngester(
          db,
          clock: time.clock,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final certifiedCards = await StudyPlanner(
          db,
          clock: time.clock,
        ).cards('CMS_CERTIFIED');
        expect(
          certifiedCards.map((card) => card.itemId).toSet(),
          containsAll(items.map((item) => item.id)),
          reason: 'every pairing point must be reachable in ordinary Study',
        );
        final reviews = ReviewService(
          db,
          clock: time.clock,
          schedulerFactory: unfuzzedScheduler,
          random: Random(1),
        );
        final presenter = ExercisePresenter(db, clock: time.clock);
        for (final (templateId, actionId, candidate) in [
          (
            'qt_cms_pairing_case_oysters',
            'ki_cms_pairing_oysters_action',
            'Muscadet',
          ),
          (
            'qt_cms_pairing_case_chocolate',
            'ki_cms_pairing_chocolate_action',
            'Tawny Port',
          ),
        ]) {
          final firstAttempt = await presenter.present(
            actionId,
            templateId,
            seed: 11,
          ) as ShortAnswerExercise;
          expect(firstAttempt.prompt, contains(candidate));
          expect(firstAttempt.itemIds, contains(actionId));
          expect(firstAttempt.keyPoints, hasLength(2));
        }
        final flashcards = {
          for (final template in dataset.questionTemplates.where(
            (template) =>
                template.id == 'qt_principle_explanation_flashcard' ||
                (template.id.startsWith('qt_case_') &&
                    template.mode == 'flashcard'),
          ))
            template.relationType: template.id,
        };
        for (final item in items) {
          await reviews.record(
            knowledgeItemId: item.id,
            questionTemplateId: flashcards[item.relationType]!,
            rating: fsrs.Rating.good,
          );
        }
        final cooking = await presenter.present(
          'ki_cms_pairing_browning',
          'qt_principle_explanation_short_answer',
          seed: 7,
        ) as ShortAnswerExercise;
        expect(cooking.prompt, contains('cooking'));
        expect(cooking.keyPoints, hasLength(3));
        expect(cooking.keyPoints.map((point) => point.itemId).toSet(), {
          'ki_cms_pairing_browning',
          'ki_cms_pairing_preparation',
          'ki_cms_pairing_sauce',
        });
        for (final (templateId, actionId, subjectId) in [
          (
            'qt_cms_pairing_case_oysters',
            'ki_cms_pairing_oysters_action',
            'n_cms_pairing_case_oysters',
          ),
          (
            'qt_cms_pairing_case_chocolate',
            'ki_cms_pairing_chocolate_action',
            'n_cms_pairing_case_chocolate',
          ),
        ]) {
          final template = dataset.questionTemplates.singleWhere(
            (candidate) => candidate.id == templateId,
          );
          expect(ShortAnswerFormat.scopeNodeIdsOf(template), {subjectId});
          expect(
            ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(),
            caseRoles,
          );
          final exercise = await presenter.present(
            actionId,
            templateId,
            seed: 11,
          ) as ShortAnswerExercise;
          expect(exercise.prompt, contains('wine'));
          expect(exercise.keyPoints, hasLength(4));
          final rubric = items
              .where((item) => item.subjectId == subjectId)
              .toList();
          expect(
            exercise.itemIds.toSet(),
            rubric.map((item) => item.id).toSet(),
          );
          expect(
            exercise.keyPoints.map((point) => point.statement).toSet(),
            rubric.map((item) => item.assertionText).toSet(),
          );
        }
      } finally {
        await db.close();
      }
    },
  );
}
