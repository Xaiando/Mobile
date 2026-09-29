import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';
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
      expect(additions, hasLength(21));
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
        expect(mappings, hasLength(1), reason: item.id);
        expect(mappings.single.importance, 'core', reason: item.id);
        expect(
          mappings.single.certificationId,
          item.id == 'ki_cms_example_distillation'
              ? 'CMS_INTRODUCTORY'
              : 'CMS_CERTIFIED',
          reason: item.id,
        );
        expect(
          mappings.single.minimumDepth,
          item.id == 'ki_cms_example_distillation' ? 1 : 2,
          reason: item.id,
        );
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
        }),
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
    expect(recognition, hasLength(9));
    expect(scenarios, hasLength(3));
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
  });

  test(
    'the three service cases have four criteria and reach ordinary Study',
    () async {
      const cases = {
        'agave': 'n_cms_example_agave_case',
        'marc': 'n_cms_example_marc_case',
        'liqueur': 'n_cms_example_liqueur_case',
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
      } finally {
        await db.close();
      }
    },
  );
}
