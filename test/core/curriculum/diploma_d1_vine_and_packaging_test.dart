import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d1vp_'))
      .toList();
  const cases = {
    'qt_d1vp_case_vines': 'n_d1vp_case_vines',
    'qt_d1vp_case_smoke': 'n_d1vp_case_smoke',
    'qt_d1vp_case_pack': 'n_d1vp_case_pack',
  };
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  const expectedSources = {
    'ki_d1vp_topwork': 'src_d1vp_uc_graft',
    'ki_d1vp_layer': 'src_d1vp_uc_propagation',
    'ki_d1vp_massal': 'src_d1vp_ifv_selection',
    'ki_d1vp_massal_health': 'src_d1vp_ifv_selection',
    'ki_d1vp_fire': 'src_d1vp_awri_fire',
    'ki_d1vp_smoke': 'src_d1vp_awri_smoke',
    'ki_d1vp_cryo': 'src_d1vp_oiv_cryo',
    'ki_d1vp_ice': 'src_d1vp_oiv_ice',
    'ki_d1vp_pouch': 'src_d1vp_awri_pack',
    'ki_d1vp_can': 'src_d1vp_awri_can',
    'ki_d1vp_glass': 'src_d1vp_vinolok',
  };

  test('source-backed additions remain Diploma-only and route to D1', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(23));
    final sourceIds = {for (final source in dataset.sourceCitations) source.id};
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final d1 = scope.tracks['WSET_L4']!.objectives;
    final vineyard = d1.singleWhere(
      (objective) => objective.id == 'wset_l4.production.vineyard',
    );
    final cellar = d1.singleWhere(
      (objective) => objective.id == 'wset_l4.production.cellar',
    );
    final quality = d1.singleWhere(
      (objective) => objective.id == 'wset_l4.production.quality_control',
    );
    expect(
      quality.covers!.within,
      containsAll({
        'n_d1vp_smoke',
        'n_d1vp_case_smoke',
        'n_d1vp_pouch',
        'n_d1vp_can',
        'n_d1vp_glass',
        'n_d1vp_case_pack',
      }),
    );
    for (final item in items) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final selector = item.domainId == 'viticulture'
          ? vineyard.covers!
          : cellar.covers!;
      expect(selector.domains, contains(item.domainId), reason: item.id);
      expect(
        selector.relationTypes.isEmpty ||
            selector.relationTypes.contains(item.relationType),
        isTrue,
        reason: item.id,
      );
      final citations = dataset.knowledgeItemCitations
          .where((join) => join.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(sourceIds, contains(citation.sourceCitationId), reason: item.id);
        expect(citation.locator, isNotEmpty, reason: item.id);
      }
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
      expect(mappings.single.importance, 'core', reason: item.id);
      expect(mappings.single.minimumDepth, 3, reason: item.id);
    }
    for (final subject in cases.values) {
      expect(
        items
            .where((item) => item.subjectId == subject)
            .map((item) => item.relationType)
            .toSet(),
        roles,
        reason: subject,
      );
    }
  });

  test(
    'three comparisons and 11 cited choices reach Diploma practice',
    () async {
      final db = openTestDatabase();
      addTearDown(db.close);
      await CurriculumIngester(db).ingest(dataset);
      final diplomaIds = {
        for (final card in await StudyPlanner(db).cards('WSET_L4')) card.itemId,
      };
      final level3Ids = {
        for (final card in await StudyPlanner(db).cards('WSET_L3')) card.itemId,
      };
      final newIds = items.map((item) => item.id).toSet();
      expect(diplomaIds, containsAll(newIds));
      expect(level3Ids.intersection(newIds), isEmpty);

      final presenter = ExercisePresenter(db);
      final criteriaTemplate = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d1vp_case_criteria',
      );
      expect(
        CaseCriteriaFormat.scopeNodeIdsOf(criteriaTemplate),
        cases.values.toSet(),
      );
      expect(
        CaseCriteriaFormat.datasetProblems(criteriaTemplate, dataset),
        isEmpty,
      );
      for (final entry in cases.entries) {
        final writtenTemplate = dataset.questionTemplates.singleWhere(
          (template) => template.id == entry.key,
        );
        expect(
          ShortAnswerFormat.keyPointsOf(writtenTemplate)!.keys.toSet(),
          roles,
        );
        final action = items.singleWhere(
          (item) =>
              item.subjectId == entry.value &&
              item.relationType == 'CASE_ACTION',
        );
        final written = await presenter.present(
          action.id,
          entry.key,
          seed: 31,
        ) as ShortAnswerExercise;
        expect(written.keyPoints, isNotEmpty);
        expect(
          written.keyPoints
              .map((point) => point.itemId)
              .toSet()
              .difference(
                items
                    .where((item) => item.subjectId == entry.value)
                    .map((item) => item.id)
                    .toSet(),
              ),
          isEmpty,
        );
        final matching = await presenter.present(
          action.id,
          'qt_d1vp_case_criteria',
          seed: 31,
        ) as CaseCriteriaExercise;
        expect(matching.itemIds, hasLength(4));
        expect(matching.options, hasLength(6));
        expect(
          matching.criteria.map((criterion) => criterion.role).toSet(),
          roles,
        );
        for (final criterion in matching.criteria) {
          expect(criterion.sources, isNotEmpty);
          expect(criterion.sources.first.url, startsWith('https://'));
        }
      }

      final choiceTemplate = dataset.questionTemplates.singleWhere(
        (template) => template.id == 'qt_d1vp_choices',
      );
      final choices =
          (jsonDecode(choiceTemplate.parameters!)
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      final positions = List<int>.filled(4, 0);
      for (final entry in expectedSources.entries) {
        final exercise = await presenter.present(
          entry.key,
          'qt_d1vp_choices',
          seed: 31,
        ) as AuthoredChoiceQuestion;
        expect(exercise.options, hasLength(4), reason: entry.key);
        expect(exercise.sourceCitationId, entry.value, reason: entry.key);
        final data = choices[entry.key] as Map<String, dynamic>;
        final options = (data['options'] as List<dynamic>).cast<String>();
        final correct = data['correctIndex'] as int;
        expect(exercise.answer.name, options[correct], reason: entry.key);
        positions[correct]++;
      }
      expect(positions, [3, 3, 3, 2]);
    },
  );
}
