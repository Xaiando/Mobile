import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_enrich_'))
      .toList();
  const caseRoles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };

  test(
    'the enrichment is cited, optional and outside WSET Wines lower tracks',
    () {
      expect(items, hasLength(19));
      final sourceIds = {
        for (final source in dataset.sourceCitations) source.id,
      };
      for (final item in items) {
        expect(item.domainId, 'service', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        final citations = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == item.id)
            .toList();
        expect(citations, isNotEmpty, reason: item.id);
        for (final citation in citations) {
          expect(
            sourceIds,
            contains(citation.sourceCitationId),
            reason: item.id,
          );
          expect(citation.locator, isNotEmpty, reason: item.id);
        }
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(
          mappings.map((mapping) => mapping.certificationId),
          contains('CMS_CERTIFIED'),
          reason: item.id,
        );
        for (final mapping in mappings) {
          expect(mapping.importance, 'secondary', reason: item.id);
          expect(mapping.minimumDepth, 2, reason: item.id);
        }
        expect(
          mappings.map((mapping) => mapping.certificationId).toSet(),
          item.id.contains('amarna') || item.id.contains('ancient_evidence')
              ? {'CMS_CERTIFIED', 'WSET_L4'}
              : {'CMS_CERTIFIED'},
          reason: item.id,
        );
      }
      for (final subject in [
        'n_enrich_case_sake_pairing',
        'n_enrich_case_cigar_service',
        'n_enrich_case_ancient_evidence',
      ]) {
        final rubric = items
            .where((item) => item.subjectId == subject)
            .toList();
        expect(rubric, hasLength(4), reason: subject);
        expect(
          rubric.map((item) => item.relationType).toSet(),
          caseRoles,
          reason: subject,
        );
      }
      expect(
        items
            .singleWhere((item) => item.id == 'ki_enrich_amarna_labels_content')
            .assertionText,
        allOf(
          contains('fourteenth-century BCE'),
          contains('not a modern appellation'),
        ),
      );
      expect(
        items
            .singleWhere(
              (item) => item.id == 'ki_enrich_cigar_service_preparation',
            )
            .assertionText,
        contains('makes tobacco safe'),
      );
    },
  );

  test(
    'the optional cases and authored choices are reachable and source-linked',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final time = TestClock(DateTime.utc(2026, 9, 29, 12));
      await CurriculumIngester(db, clock: time.clock).ingest(dataset);
      final certified = (await StudyPlanner(
        db,
        clock: time.clock,
      ).cards('CMS_CERTIFIED')).map((card) => card.itemId).toSet();
      expect(certified, containsAll(items.map((item) => item.id)));
      final level3 = (await StudyPlanner(
        db,
        clock: time.clock,
      ).cards('WSET_L3')).map((card) => card.itemId).toSet();
      expect(
        level3.intersection(items.map((item) => item.id).toSet()),
        isEmpty,
      );

      final presenter = ExercisePresenter(db, clock: time.clock);
      for (final (templateId, itemId) in [
        ('qt_enrich_sake_food_case', 'ki_enrich_case_sake_pairing_action'),
        ('qt_enrich_cigar_care_case', 'ki_enrich_case_cigar_service_action'),
        (
          'qt_enrich_egypt_evidence_case',
          'ki_enrich_case_ancient_evidence_action',
        ),
      ]) {
        final template = dataset.questionTemplates.singleWhere(
          (candidate) => candidate.id == templateId,
        );
        expect(
          ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(),
          caseRoles,
        );
        final exercise = await presenter.present(
          itemId,
          templateId,
          seed: 11,
        ) as ShortAnswerExercise;
        expect(exercise.keyPoints, hasLength(2), reason: templateId);
      }
      final reviews = ReviewService(
        db,
        clock: time.clock,
        schedulerFactory: unfuzzedScheduler,
        random: Random(1),
      );
      final caseFlashcards = {
        for (final template in dataset.questionTemplates.where(
          (template) =>
              template.id.startsWith('qt_case_') &&
              template.mode == 'flashcard',
        ))
          template.relationType: template.id,
      };
      for (final item in items.where(
        (item) => caseRoles.contains(item.relationType),
      )) {
        await reviews.record(
          knowledgeItemId: item.id,
          questionTemplateId: caseFlashcards[item.relationType]!,
          rating: fsrs.Rating.good,
        );
      }
      for (final (templateId, itemId) in [
        ('qt_enrich_sake_food_case', 'ki_enrich_case_sake_pairing_action'),
        ('qt_enrich_cigar_care_case', 'ki_enrich_case_cigar_service_action'),
        (
          'qt_enrich_egypt_evidence_case',
          'ki_enrich_case_ancient_evidence_action',
        ),
      ]) {
        final exercise = await presenter.present(
          itemId,
          templateId,
          seed: 11,
        ) as ShortAnswerExercise;
        expect(exercise.keyPoints, hasLength(4), reason: templateId);
        final subjectId = items
            .singleWhere((item) => item.id == itemId)
            .subjectId;
        expect(
          exercise.keyPoints.map((point) => point.itemId).toSet(),
          items
              .where((item) => item.subjectId == subjectId)
              .map((item) => item.id)
              .toSet(),
          reason: templateId,
        );
      }
      for (final (itemId, key, sourceId) in [
        (
          'ki_enrich_sake_pairing_intensity',
          "Pair by matching the sake's intensity to the dish.",
          'src_enrich_jss_pairing',
        ),
        (
          'ki_enrich_cigar_service_storage',
          'Use a monitored humidor near 16–18°C and 65–70% RH.',
          'src_enrich_habanos_storage',
        ),
        (
          'ki_enrich_amarna_labels_content',
          'A production year, a vintner and a named vineyard.',
          'src_enrich_ucl_amarna_labels',
        ),
      ]) {
        final question = await presenter.present(
          itemId,
          'qt_enrich_cited_choices',
          seed: 23,
        ) as AuthoredChoiceQuestion;
        expect(question.options, hasLength(4), reason: itemId);
        expect(question.answer.name, key, reason: itemId);
        expect(question.sourceCitationId, sourceId, reason: itemId);
      }
    },
  );
}
