import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_l3_winemaking_case_criteria_16',
  );
  final scope = CaseCriteriaFormat.scopeNodeIdsOf(template);
  final distractors = CaseCriteriaFormat.distractorsOf(template);
  final scenarioPrompts = CaseCriteriaFormat.scenarioPromptsOf(template);
  late AppDatabase db;
  late TrackCoverage report;
  late TestClock time;

  setUpAll(() async {
    time = TestClock(DateTime.utc(2026, 9, 29, 16, 35));
    db = openTestDatabase();
    final generation = await CurriculumIngester(
      db,
      clock: time.clock,
    ).ingest(dataset);
    const path = 'assets/curriculum/coverage_policy.yaml';
    report = await CoverageChecker(
      db,
      CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
    ).check('WSET_L3', on: '2026-09-29', skipped: generation.skipped);
  });

  tearDownAll(() async => db.close());

  test(
    '16 complete cases have four distinct cited roles and tailored errors',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(template.mode, CaseCriteriaFormat.formatId);
      expect(scope, hasLength(16));
      expect(distractors.keys.toSet(), scope);
      expect(scenarioPrompts, hasLength(12));
      for (final entry in scenarioPrompts.entries) {
        final written = dataset.questionTemplates.singleWhere((row) {
          if (row.mode != 'short_answer') return false;
          final parameters =
              jsonDecode(row.parameters!) as Map<String, dynamic>;
          return (parameters['scope_node_ids'] as List?)?.contains(entry.key) ??
              false;
        });
        expect(
          entry.value.replaceAll(RegExp(r'\s+'), ' ').trim(),
          written.promptTemplate.replaceAll(RegExp(r'\s+'), ' ').trim(),
          reason: entry.key,
        );
      }
      final items = dataset.knowledgeItems;
      final citations = {
        for (final citation in dataset.knowledgeItemCitations)
          citation.knowledgeItemId,
      };
      final links = {
        for (final source in dataset.sourceCitations) source.id: source.url,
      };
      final byCitation = {
        for (final citation in dataset.knowledgeItemCitations)
          citation.knowledgeItemId: citation.sourceCitationId,
      };
      final subjects = {
        for (final node in dataset.knowledgeNodes) node.id: node,
      };
      final authoredSummaryKeys = <String>{};
      for (final subject in scope) {
        expect(distractors[subject], hasLength(2));
        expect(subjects[subject]!.name.length, greaterThan(25));
        final roles = [
          for (final item in items)
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
        expect(roles.every((item) => item.domainId == 'winemaking'), isTrue);
        for (final item in roles) {
          expect(item.verificationStatus, 'unverified', reason: item.id);
          expect(citations, contains(item.id), reason: item.id);
          final uri = Uri.parse(links[byCitation[item.id]]!);
          expect(uri.scheme, 'https', reason: item.id);
          expect(uri.host, isNotEmpty, reason: item.id);
          final mapping = dataset.certificationKnowledgeMappings.singleWhere(
            (row) =>
                row.certificationId == 'WSET_L3' &&
                row.knowledgeItemId == item.id,
          );
          expect(mapping.importance, 'core', reason: item.id);
          expect(mapping.minimumDepth, 2, reason: item.id);
        }
        for (final wrong in distractors[subject]!) {
          expect(wrong.summary.length, greaterThan(35), reason: subject);
          expect(wrong.explanation!.length, greaterThan(50), reason: subject);
          expect(authoredSummaryKeys.add(wrong.summary.toLowerCase()), isTrue);
        }
      }
    },
  );

  test('scenario overrides reject unscoped or truncated premises', () {
    final parameters = jsonDecode(template.parameters!) as Map<String, dynamic>;
    final prompts = parameters['scenario_prompts'] as Map<String, dynamic>;
    final wrongScope = template.copyWith(
      parameters: Value(
        jsonEncode({
          ...parameters,
          'scenario_prompts': {
            ...prompts,
            'n_not_in_pool': 'A detailed but unscoped prompt cannot appear in this exercise pool.',
          },
        }),
      ),
    );
    expect(
      () => CaseCriteriaFormat.scenarioPromptsOf(wrongScope),
      throwsFormatException,
    );
    final shortPrompt = template.copyWith(
      parameters: Value(
        jsonEncode({
          ...parameters,
          'scenario_prompts': {...prompts, 'n_win_case_low_yan': 'Low YAN'},
        }),
      ),
    );
    expect(
      () => CaseCriteriaFormat.scenarioPromptsOf(shortPrompt),
      throwsFormatException,
    );
  });

  test(
    'all 64 core roles retain written study and gain useful matching',
    () async {
      final pools = (await db.select(db.exercisePools).get())
          .where((pool) => pool.questionTemplateId == template.id)
          .toList();
      expect(pools, hasLength(16));
      expect(pools.map((pool) => pool.scopeNodeId).toSet(), scope);
      final members = await db.select(db.exercisePoolItems).get();
      for (final pool in pools) {
        expect(
          members.where((member) => member.exercisePoolId == pool.id),
          hasLength(4),
          reason: pool.scopeNodeId,
        );
        if (scenarioPrompts.containsKey(pool.scopeNodeId)) {
          expect(
            pool.promptText,
            scenarioPrompts[pool.scopeNodeId],
            reason: pool.scopeNodeId,
          );
        } else {
          expect(pool.promptText.length, greaterThan(200));
        }
      }
      final byId = {for (final item in report.items) item.id: item};
      for (final item in dataset.knowledgeItems.where(
        (item) =>
            scope.contains(item.subjectId) &&
            caseCriterionRoles.contains(item.relationType),
      )) {
        final measured = byId[item.id]!;
        expect(measured.isCore, isTrue, reason: item.id);
        expect(
          measured.servedFormats,
          contains('short_answer'),
          reason: item.id,
        );
        expect(measured.servedFormats, contains('typed'), reason: item.id);
        expect(
          measured.servedFormats,
          contains('case_criteria'),
          reason: item.id,
        );
        expect(measured.hasUsefulPractice, isTrue, reason: item.id);
      }
      final domain = report.domains.singleWhere((d) => d.id == 'winemaking');
      expect(domain.counts[CoverageMetric.coreUsefulPractice], 404);
      expect(domain.counts[CoverageMetric.structured], 87);
      expect(domain.counts[CoverageMetric.core], 451);
    },
  );

  test(
    'one case grades each role independently, including a false plan',
    () async {
      const id = 'ki_win_case_low_yan_tradeoff';
      final exercise = await ExercisePresenter(
        db,
        clock: time.clock,
      ).present(id, template.id, seed: 9) as CaseCriteriaExercise;
      expect(exercise.primaryItemId, id);
      expect(exercise.prompt, contains('large unmeasured DAP dose'));
      expect(exercise.itemIds, hasLength(4));
      expect(exercise.options, hasLength(6));
      expect(
        exercise.options.where((option) => option.explanation != null),
        hasLength(2),
      );
      for (final criterion in exercise.criteria) {
        expect(criterion.sources, isNotEmpty);
        expect(criterion.sources.first.url, startsWith('https://'));
      }
      final byRole = {for (final c in exercise.criteria) c.role: c.itemId};
      const format = CaseCriteriaFormat();
      final correct = format.grade(exercise, CaseCriteriaResponse(byRole));
      expect(correct, hasLength(4));
      expect(
        correct.every((grade) => grade.rating == fsrs.Rating.good),
        isTrue,
      );

      final falseOption = exercise.options.singleWhere(
        (option) =>
            option.explanation != null && option.summary.contains('large DAP'),
      );
      final withFalseClaim = {...byRole, 'CASE_ACTION': falseOption.id};
      final falseGrades = format.grade(
        exercise,
        CaseCriteriaResponse(withFalseClaim),
      );
      expect(
        falseGrades
            .singleWhere((grade) => grade.itemId == byRole['CASE_ACTION'])
            .rating,
        fsrs.Rating.again,
      );
      expect(
        () => format.grade(
          exercise,
          CaseCriteriaResponse({
            ...byRole,
            'CASE_LIMITATION': byRole['CASE_ACTION']!,
          }),
        ),
        throwsArgumentError,
        reason: 'one response cannot earn credit for two roles',
      );
    },
  );

  test(
    'planner waits for other roles and enforces certification scope',
    () async {
      const id = 'ki_win_case_low_yan_tradeoff';
      final planner = StudyPlanner(db, clock: time.clock);
      final before = (await planner.cards('WSET_L3'))
          .singleWhere((card) => card.itemId == id);
      expect(
        before.formats.map((format) => format.mode),
        isNot(contains('case_criteria')),
      );
      final reviews = ReviewService(db, clock: time.clock);
      for (final (coItem, question) in [
        ('ki_win_case_low_yan_action', 'qt_case_action_flashcard'),
        ('ki_win_case_low_yan_reason', 'qt_case_reason_flashcard'),
        ('ki_win_case_low_yan_limitation', 'qt_case_limitation_flashcard'),
      ]) {
        await reviews.record(
          knowledgeItemId: coItem,
          questionTemplateId: question,
          rating: fsrs.Rating.good,
        );
      }
      final card = (await planner.cards('WSET_L3'))
          .singleWhere((card) => card.itemId == id);
      expect(
        card.formats.map((format) => format.mode),
        contains('case_criteria'),
      );
      expect(
        await ExercisePresenter(
          db,
          clock: time.clock,
        ).present(id, template.id, seed: 9, certificationId: 'WSET_L3'),
        isA<CaseCriteriaExercise>(),
      );
      await expectLater(
        ExercisePresenter(
          db,
          clock: time.clock,
        ).present(id, template.id, seed: 9, certificationId: 'WSET_L2'),
        throwsArgumentError,
      );
    },
  );
}
