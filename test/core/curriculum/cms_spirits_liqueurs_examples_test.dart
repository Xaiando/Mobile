import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';
import 'package:sommelier/core/questions/formats/short_answer/short_answer_format.dart';
import 'package:sommelier/core/study/study_planner.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final additions = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_cms_example_'))
      .toList();

  test(
    'named spirit and liqueur examples are cited in the right CMS level',
    () {
      expect(validateDataset(dataset).errors, isEmpty);
      expect(additions, hasLength(26));
      final sources = {for (final row in dataset.sourceCitations) row.id: row};
      for (final item in additions) {
        expect(item.domainId, 'service', reason: item.id);
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        final citations = dataset.knowledgeItemCitations
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        expect(citations, isNotEmpty, reason: item.id);
        for (final citation in citations) {
          expect(citation.locator, isNotEmpty, reason: item.id);
          expect(
            sources[citation.sourceCitationId],
            isNotNull,
            reason: item.id,
          );
        }
        final mappings = dataset.certificationKnowledgeMappings
            .where((row) => row.knowledgeItemId == item.id)
            .toList();
        if (item.id == 'ki_cms_example_distillation') {
          expect(mappings, hasLength(2), reason: item.id);
          final byTrack = {
            for (final row in mappings) row.certificationId: row,
          };
          expect(byTrack.keys.toSet(), {'CMS_INTRODUCTORY', 'CMS_CERTIFIED'});
          expect(byTrack['CMS_INTRODUCTORY']!.importance, 'core');
          expect(byTrack['CMS_INTRODUCTORY']!.minimumDepth, 1);
          expect(byTrack['CMS_CERTIFIED']!.importance, 'core');
          expect(byTrack['CMS_CERTIFIED']!.minimumDepth, 2);
        } else {
          expect(mappings, hasLength(1), reason: item.id);
          expect(mappings.single.importance, 'core', reason: item.id);
          expect(
            mappings.single.certificationId,
            'CMS_CERTIFIED',
            reason: item.id,
          );
          expect(mappings.single.minimumDepth, 2, reason: item.id);
        }
      }

      final scope = TrackScopeManifest.parse(
        File('assets/curriculum/track_scope.yaml').readAsStringSync(),
      ).tracks['CMS_CERTIFIED']!;
      final byId = {
        for (final objective in scope.objectives) objective.id: objective,
      };
      expect(
        byId['cms_certified.spirits']!.covers!.within,
        containsAll({
          'n_cms_example_distillation',
          'n_cms_example_islay',
          'n_cms_example_mezcal',
          'n_cms_example_grappa',
          'n_cms_example_fruit_eau_de_vie',
          'n_cms_example_agave_case',
          'n_cms_example_marc_case',
        }),
      );
      expect(
        byId['cms_certified.liqueurs_and_aperitifs']!.covers!.within,
        containsAll({
          'n_cms_example_liqueur_families',
          'n_cms_example_liqueur_case',
          'n_cms_example_other_liqueur',
          'n_cms_example_egg_case',
        }),
      );
      final byItem = {for (final item in additions) item.id: item};
      expect(
        byItem['ki_cms_example_zwarte_kip']!.assertionText,
        contains('not an EU legal category'),
      );
      expect(
        byItem['ki_cms_example_egg_limit']!.assertionText,
        contains('not an ingredient or allergy certification'),
      );
    },
  );

  test('recognition and scenario choices use item-linked primary sources', () {
    final recognition = AuthoredChoiceFormat.itemChoicesOf(
      dataset.questionTemplates.singleWhere(
        (row) => row.id == 'qt_cms_example_recognition',
      ),
    );
    final scenarios = AuthoredChoiceFormat.itemChoicesOf(
      dataset.questionTemplates.singleWhere(
        (row) => row.id == 'qt_cms_example_scenario_choice',
      ),
    );
    expect(recognition, hasLength(10));
    expect(scenarios, hasLength(4));
    final itemIds = additions.map((item) => item.id).toSet();
    final citations = dataset.knowledgeItemCitations;
    for (final entry in {...recognition, ...scenarios}.entries) {
      expect(itemIds, contains(entry.key));
      expect(entry.value.options, hasLength(4));
      expect(entry.value.options.toSet(), hasLength(4));
      expect(
        citations.any(
          (citation) =>
              citation.knowledgeItemId == entry.key &&
              citation.sourceCitationId == entry.value.sourceCitationId,
        ),
        isTrue,
        reason: entry.key,
      );
    }
    expect(
      recognition['ki_cms_example_mezcal']!.options[2],
      contains('protected'),
    );
    expect(
      recognition['ki_cms_example_grappa']!.options[3],
      contains('Grape marc'),
    );
    expect(scenarios['ki_cms_example_agave_action']!.correctIndex, 2);
    expect(scenarios['ki_cms_example_marc_action']!.correctIndex, 3);
    expect(
      recognition['ki_cms_example_zwarte_kip']!.options[2],
      contains('eggs and brandy'),
    );
    expect(scenarios['ki_cms_example_egg_action']!.correctIndex, 3);
  });

  test(
    'the four service cases have four criteria and reach ordinary Study',
    () async {
      const cases = {
        'agave': 'n_cms_example_agave_case',
        'marc': 'n_cms_example_marc_case',
        'liqueur': 'n_cms_example_liqueur_case',
        'egg': 'n_cms_example_egg_case',
      };
      const roles = {
        'CASE_ACTION',
        'CASE_REASON',
        'CASE_TRADEOFF',
        'CASE_LIMITATION',
      };
      for (final entry in cases.entries) {
        expect(
          additions
              .where((item) => item.subjectId == entry.value)
              .map((item) => item.relationType)
              .toSet(),
          roles,
          reason: entry.key,
        );
      }

      final db = openTestDatabase();
      try {
        final time = TestClock(DateTime.utc(2026, 10, 1, 9));
        await CurriculumIngester(
          db,
          clock: time.clock,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final cards = await StudyPlanner(
          db,
          clock: time.clock,
        ).cards('CMS_CERTIFIED');
        expect(
          cards.map((card) => card.itemId).toSet(),
          containsAll(additions.map((item) => item.id)),
        );
        final presenter = ExercisePresenter(db, clock: time.clock);
        for (final name in cases.keys) {
          final id = 'ki_cms_example_${name}_action';
          final exercise = await presenter.present(
            id,
            'qt_cms_example_case_$name',
            seed: 7,
          ) as ShortAnswerExercise;
          expect(exercise.itemIds, contains(id));
          expect(exercise.prompt, isNotEmpty);
        }
        final choice = await presenter.present(
          'ki_cms_example_islay',
          'qt_cms_example_recognition',
          seed: 7,
        ) as AuthoredChoiceQuestion;
        expect(choice.prompt, contains('Islay'));
        final scenario = await presenter.present(
          'ki_cms_example_agave_action',
          'qt_cms_example_scenario_choice',
          seed: 7,
        ) as AuthoredChoiceQuestion;
        expect(scenario.prompt, contains('Mezcal'));
        final eggChoice = await presenter.present(
          'ki_cms_example_zwarte_kip',
          'qt_cms_example_recognition',
          seed: 7,
        ) as AuthoredChoiceQuestion;
        expect(eggChoice.prompt, contains('non-classified'));
        final eggScenario = await presenter.present(
          'ki_cms_example_egg_action',
          'qt_cms_example_scenario_choice',
          seed: 7,
        ) as AuthoredChoiceQuestion;
        expect(eggScenario.prompt, contains('Zwarte Kip'));
      } finally {
        await db.close();
      }
    },
  );
  test(
    'four CMS service cases deliver and grade complete cited rubrics',
    () async {
      const cases = {
        'agave': 'n_cms_example_agave_case',
        'marc': 'n_cms_example_marc_case',
        'liqueur': 'n_cms_example_liqueur_case',
        'egg': 'n_cms_example_egg_case',
      };
      const templateId = 'qt_cms_example_case_criteria_4';
      final template = dataset.questionTemplates.singleWhere(
        (row) => row.id == templateId,
      );
      expect(template.mode, CaseCriteriaFormat.formatId);
      expect(CaseCriteriaFormat.scopeNodeIdsOf(template), cases.values.toSet());
      final prompts = CaseCriteriaFormat.scenarioPromptsOf(template);
      final distractors = CaseCriteriaFormat.distractorsOf(template);
      expect(prompts.keys.toSet(), cases.values.toSet());
      expect(distractors.keys.toSet(), cases.values.toSet());
      for (final subject in cases.values) {
        expect(prompts[subject]!.length, greaterThan(80), reason: subject);
        expect(distractors[subject], hasLength(2), reason: subject);
      }

      final db = openTestDatabase();
      try {
        await CurriculumIngester(
          db,
          assets: (path) async => File(path).readAsBytesSync(),
        ).ingest(dataset);
        final pools = (await db.select(db.exercisePools).get())
            .where((pool) => pool.questionTemplateId == templateId)
            .toList();
        expect(pools, hasLength(4));
        expect(
          pools.map((pool) => pool.scopeNodeId).toSet(),
          cases.values.toSet(),
        );

        final presenter = ExercisePresenter(db);
        const format = CaseCriteriaFormat();
        for (final entry in cases.entries) {
          final id = 'ki_cms_example_${entry.key}_action';
          final exercise = await presenter.present(
            id,
            templateId,
            seed: 7,
          ) as CaseCriteriaExercise;
          expect(exercise.primaryItemId, id);
          expect(exercise.prompt, prompts[entry.value]);
          expect(exercise.itemIds, hasLength(4));
          expect(exercise.options, hasLength(6));
          expect(
            exercise.criteria.map((row) => row.role).toSet(),
            caseCriterionRoles.toSet(),
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
          final byRole = {
            for (final criterion in exercise.criteria)
              criterion.role: criterion.itemId,
          };
          final correct = format.grade(exercise, CaseCriteriaResponse(byRole));
          expect(correct, hasLength(4), reason: entry.key);
          expect(
            correct.every((row) => row.rating == fsrs.Rating.good),
            isTrue,
            reason: entry.key,
          );
          final falseOption = exercise.options.firstWhere(
            (option) => option.explanation != null,
          );
          for (final role in caseCriterionRoles) {
            final wrong = format.grade(
              exercise,
              CaseCriteriaResponse({...byRole, role: falseOption.id}),
            );
            expect(wrong, hasLength(4), reason: '${entry.key} $role');
            final ratings = {for (final row in wrong) row.itemId: row.rating};
            expect(
              ratings[byRole[role]],
              fsrs.Rating.again,
              reason: '${entry.key} $role',
            );
            for (final otherRole in caseCriterionRoles.where(
              (candidate) => candidate != role,
            )) {
              expect(
                ratings[byRole[otherRole]],
                fsrs.Rating.good,
                reason: '${entry.key} $otherRole',
              );
            }
          }
        }
      } finally {
        await db.close();
      }
    },
  );
}
