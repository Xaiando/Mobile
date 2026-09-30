import 'dart:io';

import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const keys = {'madeira_compare', 'rutherglen_muscat', 'age_quality'};
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  Set<String> idsFor(String key) => {
    for (final role in roles)
      'ki_d5sensory_case_${key}_${role.substring(5).toLowerCase()}',
  };
  final expectedIds = {for (final key in keys) ...idsFor(key)};
  final subjects = {for (final key in keys) 'n_d5sensory_case_$key'};
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d5sensory_case_'))
      .toList();
  final byId = {for (final item in items) item.id: item};
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final criteriaTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5sensory_case_criteria',
  );
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5sensory_action_choice',
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);

  test('twelve cited tasting facts remain unverified and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(12));
    expect(byId.keys.toSet(), expectedIds);
    const expectedSources = {
      'src_d5madeira_verdelho':
          'https://vinhomadeira.com/o-vinho-madeira/castas/verdelho',
      'src_d5madeira_boal':
          'https://vinhomadeira.com/o-vinho-madeira/castas/boal',
      'src_wset_sf_muscat_aged':
          'https://winemakers.com.au/muscat-of-rutherglen/',
      'src_d5_sherry_age':
          'https://www.sherry.wine/sherry-wine/special-categories',
      'src_wset_taste_awri': 'https://www.awri.com.au/wp-content/uploads/2023/02/01-AWAC-Course-Notes-28092022-1.pdf',
      'src_wset_taste_ageing': 'https://www.wsetglobal.com/knowledge-centre/blog/2023/march/21/why-do-we-age-wine',
    };
    for (final entry in expectedSources.entries) {
      expect(sources[entry.key]!.url, entry.value);
    }
    for (final item in items) {
      expect(item.domainId, 'tasting', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(nodes[item.subjectId]!.nodeType, 'production_case');
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4');
      expect(mappings.single.importance, 'core');
      expect(mappings.single.minimumDepth, 3);
      final citations = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(expectedSources.keys, contains(citation.sourceCitationId));
        expect(citation.locator, isNotEmpty, reason: item.id);
      }
    }
    for (final key in keys) {
      final points = items.where(
        (item) => item.subjectId == 'n_d5sensory_case_$key',
      );
      expect(points, hasLength(4));
      expect(points.map((point) => point.relationType).toSet(), roles);
    }
  });

  test('fictional identities and age claims retain their evidence limits', () {
    expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), subjects);
    expect(
      CaseCriteriaFormat.datasetProblems(criteriaTemplate, dataset),
      isEmpty,
    );
    final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
    final prompts = <String>{};
    for (final key in keys) {
      final subject = 'n_d5sensory_case_$key';
      final template = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d5sensory_written_$key',
      );
      expect(template.mode, 'short_answer');
      expect(ShortAnswerFormat.scopeNodeIdsOf(template), {subject});
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(), roles);
      expect(template.promptTemplate, nodes[subject]!.name);
      expect(template.promptTemplate, startsWith('Hypothetical'));
      expect(template.promptTemplate, contains('identities are assumptions'));
      expect(template.promptTemplate, contains('invented'));
      prompts.add(template.promptTemplate);
      expect(distractors[subject], hasLength(2));
      for (final distractor in distractors[subject]!) {
        expect(distractor.summary.length, greaterThan(40));
        expect(distractor.explanation!.length, greaterThan(60));
      }
    }
    expect(prompts, hasLength(3));
    expect(
      byId['ki_d5sensory_case_madeira_compare_limitation']!.assertionText,
      contains('cannot authenticate Verdelho or Boal'),
    );
    expect(
      byId['ki_d5sensory_case_rutherglen_muscat_limitation']!.assertionText,
      contains('averages, not minimum ages for every component'),
    );
    final ageReason =
        byId['ki_d5sensory_case_age_quality_reason']!.assertionText;
    expect(ageReason, contains('individual saca'));
    expect(ageReason, contains('quality as well as average age'));
    expect(ageReason, contains('not mean every component is exactly twenty'));
    expect(
      byId['ki_d5sensory_case_age_quality_action']!.assertionText,
      contains('does not authenticate either supplied identity'),
    );
    expect(
      byId['ki_d5sensory_case_age_quality_limitation']!.assertionText,
      contains('physical tasting with qualified feedback'),
    );
  });

  test('three scoped action choices avoid position and length shortcuts', () {
    expect(choiceTemplate.mode, 'authored_choice');
    expect(choiceTemplate.relationType, 'CASE_ACTION');
    expect(choices.keys.toSet(), {
      for (final key in keys) 'ki_d5sensory_case_${key}_action',
    });
    final positions = List<int>.filled(4, 0);
    final lengthRanks = List<int>.filled(4, 0);
    for (final entry in choices.entries) {
      final cue = entry.value;
      expect(cue.options, hasLength(4));
      expect(cue.options.toSet(), hasLength(4));
      expect(cue.prompt, contains('invented'));
      expect(cue.prompt, contains('assumptions'));
      expect(cue.explanation.length, greaterThan(80));
      expect(sources, contains(cue.sourceCitationId));
      expect(
        dataset.knowledgeItemCitations.where(
          (citation) =>
              citation.knowledgeItemId == entry.key &&
              citation.sourceCitationId == cue.sourceCitationId,
        ),
        isNotEmpty,
      );
      positions[cue.correctIndex]++;
      final rank = cue.options
          .where(
            (option) => option.length < cue.options[cue.correctIndex].length,
          )
          .length;
      lengthRanks[rank]++;
    }
    expect(positions, [1, 1, 1, 0]);
    expect(lengthRanks, [1, 1, 0, 1]);
  });

  test(
    'D5 and the tasting objective explicitly select the complete packets',
    () {
      final progress = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final diploma = progress.levels.singleWhere(
        (level) => level.certificationId == 'WSET_L4',
      );
      expect(diploma.curriculumComplete, isFalse);
      final unit = diploma.units.singleWhere((unit) => unit.id == 'D5');
      expect(unit.itemIds.toSet().intersection(expectedIds), expectedIds);
      final scope = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      );
      final objective = scope.tracks['WSET_L4']!.objectives.singleWhere(
        (objective) => objective.id == 'wset_l4.fortified.tasting',
      );
      expect(objective.covers!.within, containsAll(subjects));
      expect(objective.covers!.relationTypes, roles);
    },
  );

  test(
    'runtime serves complete cases, written self-review and cited choices',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      final clock = Clock.fixed(dataset.publishedAt);
      final generation = await CurriculumIngester(
        db,
        clock: clock,
      ).ingest(dataset);
      final planner = StudyPlanner(db, clock: clock);
      final diplomaCards = {
        for (final card in await planner.cards('WSET_L4')) card.itemId,
      };
      expect(diplomaCards, containsAll(expectedIds));
      for (final track in ['WSET_L1', 'WSET_L2', 'WSET_L3', 'CMS_CERTIFIED']) {
        final lowerCards = {
          for (final card in await planner.cards(track)) card.itemId,
        };
        expect(lowerCards.intersection(expectedIds), isEmpty, reason: track);
      }
      final pools = await db.select(db.exercisePools).get();
      expect(
        pools.where((pool) => pool.questionTemplateId == criteriaTemplate.id),
        hasLength(3),
      );
      final presenter = ExercisePresenter(db, clock: clock);
      final reviews = ReviewService(db, clock: clock);
      for (final key in keys) {
        final id = 'ki_d5sensory_case_${key}_action';
        final caseIds = idsFor(key);
        final introductory = await presenter.present(
          id,
          'qt_d5sensory_written_$key',
          seed: 17,
        ) as ShortAnswerExercise;
        expect(introductory.itemIds, hasLength(2));
        expect(introductory.itemIds, contains(id));
        // Studying the individual facts enables the full four-point written rubric.
        for (final point in items.where(
          (point) => caseIds.contains(point.id),
        )) {
          final card = dataset.questionTemplates.singleWhere(
            (template) =>
                template.mode == 'flashcard' &&
                template.relationType == point.relationType,
          );
          await reviews.record(
            knowledgeItemId: point.id,
            questionTemplateId: card.id,
            rating: fsrs.Rating.good,
          );
        }
        final written = await presenter.present(
          id,
          'qt_d5sensory_written_$key',
          seed: 17,
        ) as ShortAnswerExercise;
        expect(written.itemIds.toSet(), caseIds);
        expect(written.keyPoints, hasLength(4));
        expect(written.prompt, nodes['n_d5sensory_case_$key']!.name);
        final exercise = await presenter.present(
          id,
          criteriaTemplate.id,
          seed: 17,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds.toSet(), caseIds);
        expect(exercise.options, hasLength(6));
        expect(exercise.criteria.map((point) => point.role).toSet(), roles);
        expect(
          exercise.criteria.every((point) => point.sources.isNotEmpty),
          isTrue,
        );
        final answer = {
          for (final point in exercise.criteria) point.role: point.itemId,
        };
        final good = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(answer),
        );
        expect(good, hasLength(4));
        expect(good.every((grade) => grade.rating == fsrs.Rating.good), isTrue);
        final wrong = {...answer};
        wrong['CASE_REASON'] = exercise.options
            .firstWhere((option) => !caseIds.contains(option.id))
            .id;
        final grades = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(wrong),
        );
        expect(
          grades.where((grade) => grade.rating == fsrs.Rating.again),
          hasLength(1),
        );
        expect(
          grades.where((grade) => grade.rating == fsrs.Rating.good),
          hasLength(3),
        );
        final choice = await presenter.present(
          id,
          choiceTemplate.id,
          seed: 17,
        ) as AuthoredChoiceQuestion;
        final cue = choices[id]!;
        expect(choice.answer.name, cue.options[cue.correctIndex]);
        expect(choice.sourceCitationId, cue.sourceCitationId);
        expect(
          const AuthoredChoiceFormat()
              .grade(choice, choice.answer)
              .single
              .rating,
          fsrs.Rating.good,
        );
        for (final alternative in choice.options.where(
          (option) => option != choice.answer,
        )) {
          expect(
            const AuthoredChoiceFormat()
                .grade(choice, alternative)
                .single
                .rating,
            fsrs.Rating.again,
          );
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
            'WSET_L4',
            on: dataset.publishedAt.toIso8601String().substring(0, 10),
            skipped: generation.skipped,
          );
      final measured = report.items.where(
        (row) => expectedIds.contains(row.id),
      );
      expect(measured, hasLength(12));
      for (final row in measured) {
        expect(row.isCore, isTrue, reason: row.id);
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
        expect(row.servedFormats, contains('case_criteria'), reason: row.id);
        expect(row.servedFormats, contains('short_answer'), reason: row.id);
        if (row.id.endsWith('_action')) {
          expect(
            row.servedFormats,
            contains('authored_choice'),
            reason: row.id,
          );
        }
      }
    },
  );
}
