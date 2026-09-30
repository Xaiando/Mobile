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
import 'package:sommelier/core/questions/formats/typed/typed_format.dart';
import 'package:sommelier/core/study/review_service.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';

void main() {
  final dataset = bundledDataset();
  const principleKeys = {
    'poios',
    'levadas',
    'latada',
    'harvest',
    'verdelho',
    'boal',
  };
  const caseKeys = {'terrace_logistics', 'style_comparison'};
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  Set<String> caseIds(String key) => {
    for (final role in roles)
      'ki_d5madeira_case_${key}_${role.substring(5).toLowerCase()}',
  };
  final principleIds = {for (final key in principleKeys) 'ki_d5madeira_$key'};
  final expectedIds = {
    ...principleIds,
    for (final key in caseKeys) ...caseIds(key),
  };
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d5madeira_'))
      .toList();
  final byId = {for (final item in items) item.id: item};
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  final choiceTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5madeira_site_style_choice',
  );
  final typedTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5madeira_site_style_typed',
  );
  final criteriaTemplate = dataset.questionTemplates.singleWhere(
    (template) => template.id == 'qt_d5madeira_case_criteria',
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(choiceTemplate);
  final typedCues = TypedFormat.itemCuesOf(typedTemplate)!;

  test('fourteen source-bounded Madeira facts remain Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(14));
    expect(byId.keys.toSet(), expectedIds);
    const expectedUrls = {
      'src_d5madeira_region': 'https://vinhomadeira.com/o-vinho-madeira/regiao',
      'src_d5madeira_verdelho':
          'https://vinhomadeira.com/o-vinho-madeira/castas/verdelho',
      'src_d5madeira_boal':
          'https://vinhomadeira.com/o-vinho-madeira/castas/boal',
    };
    for (final entry in expectedUrls.entries) {
      expect(sources[entry.key]!.url, entry.value);
      expect(sources[entry.key]!.kind, 'reference_work');
      expect(sources[entry.key]!.publisher, contains('IVBAM'));
      expect(
        sources[entry.key]!.documentIdentifier,
        contains('not a legal sugar or elevation specification'),
      );
    }
    for (final item in items) {
      final domain = item.id.contains('_terrace_logistics_')
          ? 'business'
          : item.id.contains('_style_comparison_')
          ? 'tasting'
          : {'ki_d5madeira_verdelho', 'ki_d5madeira_boal'}.contains(item.id)
          ? 'winemaking'
          : 'viticulture';
      expect(item.domainId, domain, reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
      expect(mappings.single.importance, 'core', reason: item.id);
      expect(mappings.single.minimumDepth, 3, reason: item.id);
      final citations = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(expectedUrls.keys, contains(citation.sourceCitationId));
        expect(citation.locator, isNotEmpty, reason: item.id);
      }
    }
    expect(
      byId['ki_d5madeira_verdelho']!.assertionText,
      contains('not a legal boundary'),
    );
    expect(
      byId['ki_d5madeira_harvest']!.assertionText,
      contains('neither a universal labour rate'),
    );
    expect(
      byId['ki_d5madeira_case_style_comparison_limitation']!.assertionText,
      contains('cannot authenticate Verdelho or Boal'),
    );
    expect(
      byId['ki_d5madeira_case_terrace_logistics_limitation']!.assertionText,
      contains('does not prove seasonal water delivery'),
    );
  });

  test('D5 selects growing and style cases without claiming completion', () {
    final progress = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = progress.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d5 = diploma.units.singleWhere((unit) => unit.id == 'D5');
    expect(d5.itemIds.toSet().intersection(expectedIds), expectedIds);
    expect(diploma.curriculumComplete, isFalse);
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final madeira = scope.tracks['WSET_L4']!.objectives.singleWhere(
      (objective) => objective.id == 'wset_l4.fortified.madeira',
    );
    expect(
      madeira.covers!.within,
      containsAll({
        for (final key in principleKeys) 'n_d5madeira_principle_$key',
        for (final key in caseKeys) 'n_d5madeira_case_$key',
      }),
    );
  });

  test(
    'six authored choices and scoped recall cues have responsive answers',
    () {
      expect(choices.keys.toSet(), principleIds);
      expect(typedCues.keys.toSet(), principleIds);
      final indexCounts = List<int>.filled(4, 0);
      final lengthRanks = List<int>.filled(4, 0);
      for (final entry in choices.entries) {
        final cue = entry.value;
        expect(cue.options, hasLength(4), reason: entry.key);
        expect(cue.options.toSet(), hasLength(4), reason: entry.key);
        indexCounts[cue.correctIndex]++;
        lengthRanks[cue.options
            .where(
              (option) => option.length < cue.options[cue.correctIndex].length,
            )
            .length]++;
        expect(
          dataset.knowledgeItemCitations.any(
            (citation) =>
                citation.knowledgeItemId == entry.key &&
                citation.sourceCitationId == cue.sourceCitationId,
          ),
          isTrue,
          reason: entry.key,
        );
        expect(typedCues[entry.key]!.prompt, isNotEmpty);
        expect(typedCues[entry.key]!.acceptedAnswers, isNotEmpty);
      }
      expect(indexCounts, [2, 2, 1, 1]);
      expect(lengthRanks, [2, 2, 1, 1]);
      expect(
        typedCues['ki_d5madeira_poios']!.acceptedAnswers,
        contains('poios'),
      );
      expect(
        typedCues['ki_d5madeira_levadas']!.acceptedAnswers,
        contains('levadas'),
      );
      expect(
        typedCues['ki_d5madeira_latada']!.acceptedAnswers,
        contains('latada'),
      );
      expect(
        typedCues['ki_d5madeira_harvest']!.acceptedAnswers,
        contains('by hand'),
      );
      expect(
        typedCues['ki_d5madeira_verdelho']!.acceptedAnswers,
        contains('Verdelho'),
      );
      expect(
        typedCues['ki_d5madeira_boal']!.acceptedAnswers,
        contains('semi-sweet'),
      );
    },
  );

  test('two invented cases retain complete four-role written rubrics', () {
    expect(CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate), {
      for (final key in caseKeys) 'n_d5madeira_case_$key',
    });
    expect(
      CaseCriteriaFormat.datasetProblems(criteriaTemplate, dataset),
      isEmpty,
    );
    final distractors = CaseCriteriaFormat.distractorsOf(criteriaTemplate);
    for (final key in caseKeys) {
      final subject = 'n_d5madeira_case_$key';
      final template = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d5madeira_case_$key',
      );
      expect(template.mode, 'short_answer');
      expect(ShortAnswerFormat.scopeNodeIdsOf(template), {subject});
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(), roles);
      expect(template.promptTemplate, nodes[subject]!.name);
      expect(template.promptTemplate, contains('Hypothetical'));
      expect(template.promptTemplate, contains('invented'));
      final caseItems = items.where((item) => item.subjectId == subject);
      expect(caseItems, hasLength(4));
      expect(caseItems.map((item) => item.relationType).toSet(), roles);
      expect(distractors[subject], hasLength(2));
      for (final wrong in distractors[subject]!) {
        expect(wrong.summary.length, greaterThan(35));
        expect(wrong.explanation!.length, greaterThan(45));
      }
    }
  });

  test(
    'runtime grades six cues and two full cases within Diploma Study',
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
        for (final card in await planner.cards('WSET_L4')) card.itemId: card,
      };
      expect(diplomaCards.keys, containsAll(expectedIds));
      for (final track in ['WSET_L3', 'CMS_CERTIFIED']) {
        final lowerIds = {
          for (final card in await planner.cards(track)) card.itemId,
        };
        expect(lowerIds.intersection(expectedIds), isEmpty, reason: track);
      }
      final questions = await db.select(db.questions).get();
      for (final template in [choiceTemplate, typedTemplate]) {
        expect(
          questions
              .where((question) => question.questionTemplateId == template.id)
              .map((question) => question.knowledgeItemId)
              .toSet(),
          principleIds,
          reason: template.id,
        );
      }
      final presenter = ExercisePresenter(db, clock: clock);
      const wrongRecall = {
        'ki_d5madeira_poios': 'levadas',
        'ki_d5madeira_levadas': 'latada',
        'ki_d5madeira_latada': 'espalier',
        'ki_d5madeira_harvest': 'mechanical harvest',
        'ki_d5madeira_verdelho': 'Sercial',
        'ki_d5madeira_boal': 'dry',
      };
      for (final id in principleIds) {
        final choice = await presenter.present(
          id,
          choiceTemplate.id,
          seed: 19,
          certificationId: 'WSET_L4',
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
        for (final wrong in choice.options.where(
          (option) => option != choice.answer,
        )) {
          expect(
            const AuthoredChoiceFormat().grade(choice, wrong).single.rating,
            fsrs.Rating.again,
          );
        }
        final typed = await presenter.present(
          id,
          typedTemplate.id,
          seed: 19,
          certificationId: 'WSET_L4',
        ) as TypedQuestion;
        expect(typed.prompt, typedCues[id]!.prompt);
        for (final answer in typedCues[id]!.acceptedAnswers) {
          expect(
            const TypedFormat().grade(typed, answer).single.rating,
            fsrs.Rating.good,
            reason: '$id: $answer',
          );
        }
        expect(
          const TypedFormat().grade(typed, wrongRecall[id]!).single.rating,
          fsrs.Rating.again,
          reason: id,
        );
      }
      final pools = await db.select(db.exercisePools).get();
      expect(
        pools.where((pool) => pool.questionTemplateId == criteriaTemplate.id),
        hasLength(2),
      );
      final reviews = ReviewService(db, clock: clock);
      for (final key in caseKeys) {
        final ids = caseIds(key);
        final id = 'ki_d5madeira_case_${key}_action';
        final writtenId = 'qt_d5madeira_case_$key';
        // New written exercises introduce two points; individual recall unlocks
        // the complete rubric without removing the introduction budget.
        final introductory = await presenter.present(
          id,
          writtenId,
          seed: 17,
        ) as ShortAnswerExercise;
        expect(introductory.itemIds, hasLength(2));
        expect(introductory.itemIds, contains(id));
        for (final point in items.where((point) => ids.contains(point.id))) {
          final flashcard = dataset.questionTemplates.singleWhere(
            (template) =>
                template.mode == 'flashcard' &&
                template.relationType == point.relationType,
          );
          await reviews.record(
            knowledgeItemId: point.id,
            questionTemplateId: flashcard.id,
            rating: fsrs.Rating.good,
          );
        }
        final written = await presenter.present(
          id,
          writtenId,
          seed: 17,
        ) as ShortAnswerExercise;
        expect(written.itemIds.toSet(), ids);
        expect(written.keyPoints, hasLength(4));
        expect(written.prompt, nodes['n_d5madeira_case_$key']!.name);
        final exercise = await presenter.present(
          id,
          criteriaTemplate.id,
          seed: 17,
        ) as CaseCriteriaExercise;
        expect(exercise.itemIds.toSet(), ids);
        expect(exercise.options, hasLength(6));
        expect(exercise.criteria.map((point) => point.role).toSet(), roles);
        expect(
          exercise.criteria.every((point) => point.sources.isNotEmpty),
          isTrue,
        );
        final answer = {
          for (final point in exercise.criteria) point.role: point.itemId,
        };
        final correct = const CaseCriteriaFormat().grade(
          exercise,
          CaseCriteriaResponse(answer),
        );
        expect(correct, hasLength(4));
        expect(
          correct.every((grade) => grade.rating == fsrs.Rating.good),
          isTrue,
        );
        final wrong = {...answer};
        wrong['CASE_LIMITATION'] = exercise.options
            .firstWhere((option) => !ids.contains(option.id))
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
        (item) => expectedIds.contains(item.id),
      );
      expect(measured, hasLength(14));
      for (final item in measured) {
        expect(item.isCore, isTrue, reason: item.id);
        expect(item.hasUsefulPractice, isTrue, reason: item.id);
        final caseItem = item.id.contains('_case_');
        expect(
          item.servedFormats,
          contains(caseItem ? 'case_criteria' : 'authored_choice'),
          reason: item.id,
        );
        expect(
          item.servedFormats,
          contains(caseItem ? 'short_answer' : 'typed'),
          reason: item.id,
        );
      }
    },
  );
}
