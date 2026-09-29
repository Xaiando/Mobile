import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final caseTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l4_business_case_criteria_37',
  );
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l4_business_principle_choice_29',
  );
  final scope = CaseCriteriaFormat.scopeNodeIdsOf(caseTemplate);
  final distractors = CaseCriteriaFormat.distractorsOf(caseTemplate);
  final scenarioPrompts = CaseCriteriaFormat.scenarioPromptsOf(caseTemplate);
  final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final citations = <String, Set<String>>{};
  for (final citation in dataset.knowledgeItemCitations) {
    citations
        .putIfAbsent(citation.knowledgeItemId, () => {})
        .add(citation.sourceCitationId);
  }
  final sourceUrls = {
    for (final source in dataset.sourceCitations) source.id: source.url,
  };
  late AppDatabase db;
  late TrackCoverage report;
  late TestClock time;

  setUpAll(() async {
    time = TestClock(DateTime.utc(2026, 9, 29, 18));
    db = openTestDatabase();
    final generation = await CurriculumIngester(
      db,
      clock: time.clock,
    ).ingest(dataset);
    const policyPath = 'assets/curriculum/coverage_policy.yaml';
    report = await CoverageChecker(
      db,
      CoveragePolicy.parse(
        File(policyPath).readAsStringSync(),
        path: policyPath,
      ),
    ).check('WSET_L4', on: '2026-09-29', skipped: generation.skipped);
  });

  tearDownAll(() async => db.close());

  test('37 whole-case pools retain distinct, cited four-role assertions', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(scope, hasLength(37));
    expect(distractors.keys.toSet(), scope);
    expect(scenarioPrompts.keys.toSet(), {
      'n_biz_case_cellar_cash',
      'n_biz_case_export_currency',
      'n_biz_case_wine_discount',
    });
    for (final entry in scenarioPrompts.entries) {
      final written = dataset.questionTemplates.singleWhere((row) {
        if (row.mode != 'short_answer') return false;
        final parameters = jsonDecode(row.parameters!) as Map<String, dynamic>;
        return (parameters['scope_node_ids'] as List?)?.contains(entry.key) ??
            false;
      });
      expect(
        entry.value.replaceAll(RegExp(r'\s+'), ' ').trim(),
        written.promptTemplate.replaceAll(RegExp(r'\s+'), ' ').trim(),
        reason: entry.key,
      );
    }
    for (final subject in scope) {
      expect(distractors[subject], hasLength(2));
      for (final falseClaim in distractors[subject]!) {
        expect(falseClaim.summary.length, greaterThan(35));
        expect(falseClaim.explanation!.length, greaterThan(45));
      }
      final roles = items.values.where(
        (item) =>
            item.subjectId == subject &&
            caseCriterionRoles.contains(item.relationType),
      );
      expect(roles, hasLength(4), reason: subject);
      expect(
        roles.map((item) => item.relationType).toSet(),
        caseCriterionRoles.toSet(),
        reason: subject,
      );
      for (final item in roles) {
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(citations[item.id], isNotEmpty, reason: item.id);
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (row) =>
              row.certificationId == 'WSET_L4' &&
              row.knowledgeItemId == item.id,
        );
        expect(mapping.importance, 'core', reason: item.id);
        final served = report.items.singleWhere((row) => row.id == item.id);
        expect(
          served.servedFormats,
          contains('case_criteria'),
          reason: item.id,
        );
        expect(served.hasUsefulPractice, isTrue, reason: item.id);
      }
    }
  });

  test('29 principle choices are distinct and cite their own assertions', () {
    expect(choices, hasLength(29));
    expect(choices.values.map((cue) => cue.prompt).toSet(), hasLength(29));
    final correctAnswerLengthRanks = List<int>.filled(4, 0);
    for (final entry in choices.entries) {
      final item = items[entry.key]!;
      final cue = entry.value;
      expect(item.domainId, 'business', reason: entry.key);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: entry.key);
      expect(item.verificationStatus, 'unverified', reason: entry.key);
      expect(citations[entry.key], contains(cue.sourceCitationId));
      expect(sourceUrls[cue.sourceCitationId], startsWith('https://'));
      expect(cue.options, hasLength(4));
      expect(cue.options.map(normalizeName).toSet(), hasLength(4));
      final answerLength = cue.options[cue.correctIndex].length;
      final distractorLengths = [
        for (var index = 0; index < cue.options.length; index++)
          if (index != cue.correctIndex) cue.options[index].length,
      ];
      final rank = distractorLengths
          .where((length) => length < answerLength)
          .length;
      correctAnswerLengthRanks[rank]++;
      expect(cue.prompt, contains('?'));
      expect(cue.explanation, isNotEmpty);
      final mapping = dataset.certificationKnowledgeMappings.singleWhere(
        (row) =>
            row.certificationId == 'WSET_L4' &&
            row.knowledgeItemId == entry.key,
      );
      expect(mapping.importance, 'core', reason: entry.key);
      final served = report.items.singleWhere((row) => row.id == entry.key);
      expect(served.servedFormats, contains('authored_choice'));
      expect(served.hasUsefulPractice, isTrue);
    }
    for (final count in correctAnswerLengthRanks) {
      expect(
        count,
        inInclusiveRange(4, 11),
        reason: 'Correct answer length rank must not reveal the key',
      );
    }
  });

  test(
    'the complete business domain gains useful practice without new facts',
    () {
      final business = report.domains.singleWhere(
        (row) => row.id == 'business',
      );
      expect(business.counts[CoverageMetric.core], 236);
      expect(business.counts[CoverageMetric.coreUsefulPractice], 236);
      expect(
        report.items
            .where((row) => row.item.domainId == 'business' && row.isCore)
            .every((row) => row.hasUsefulPractice),
        isTrue,
      );
      expect(report.counts[CoverageMetric.coreUsefulPractice], 2766);
    },
  );

  test(
    'the full cash-flow premise is served and each role is graded',
    () async {
      const id = 'ki_biz_case_cellar_cash_action';
      final presenter = ExercisePresenter(db, clock: time.clock);
      final exercise = await presenter.present(
        id,
        caseTemplate.id,
        seed: 12,
      ) as CaseCriteriaExercise;
      expect(exercise.prompt, contains('Supplier bills fall due'));
      expect(exercise.options, hasLength(6));
      expect(exercise.criteria, hasLength(4));
      for (final criterion in exercise.criteria) {
        expect(criterion.sources, isNotEmpty);
        expect(criterion.sources.first.url, startsWith('https://'));
      }
      final correct = {
        for (final criterion in exercise.criteria)
          criterion.role: criterion.itemId,
      };
      expect(
        presenter
            .grade(exercise, CaseCriteriaResponse(correct))
            .every((grade) => grade.rating == fsrs.Rating.good),
        isTrue,
      );
      final falseClaim = exercise.options.firstWhere(
        (option) => option.explanation != null,
      );
      final graded = presenter.grade(
        exercise,
        CaseCriteriaResponse({...correct, 'CASE_ACTION': falseClaim.id}),
      );
      expect(
        graded.singleWhere((row) => row.itemId == id).rating,
        fsrs.Rating.again,
      );
    },
  );

  test(
    'a worked principle choice is presented and graded by its answer',
    () async {
      const id = 'ki_biz_gross_margin';
      final presenter = ExercisePresenter(db, clock: time.clock);
      final exercise = await presenter.present(
        id,
        choiceTemplate.id,
        seed: 12,
      ) as AuthoredChoiceQuestion;
      expect(exercise.options, hasLength(4));
      expect(exercise.answer.name, contains('Net sales'));
      expect(exercise.sourceCitationId, 'src_biz_victoria_pricing');
      expect(
        presenter.grade(exercise, exercise.answer).single.rating,
        fsrs.Rating.good,
      );
      final wrong = exercise.options.firstWhere(
        (option) => option != exercise.answer,
      );
      expect(presenter.grade(exercise, wrong).single.rating, fsrs.Rating.again);
    },
  );
}
