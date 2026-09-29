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

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d1target_'))
      .toList();
  const roles = {
    'CASE_ACTION',
    'CASE_REASON',
    'CASE_TRADEOFF',
    'CASE_LIMITATION',
  };
  const cases = {
    'qt_d1target_case_vineyard': 'n_d1target_case_vineyard',
    'qt_d1target_case_nolo': 'n_d1target_case_nolo',
    'qt_d1target_case_qc': 'n_d1target_case_qc',
    'qt_d1target_case_pack': 'n_d1target_case_pack',
  };

  test('D1 additions are cited, unverified and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(26));
    final sourceIds = {for (final source in dataset.sourceCitations) source.id};
    for (final item in items) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        {'viticulture', 'winemaking'},
        contains(item.domainId),
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

  test('D1 quality-control selector includes the new preventive controls', () {
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final quality = scope.tracks['WSET_L4']!.objectives.singleWhere(
      (objective) => objective.id == 'wset_l4.production.quality_control',
    );
    expect(
      quality.covers!.within,
      containsAll({
        'n_d1target_qc_haccp',
        'n_d1target_qc_iso_trace',
        'n_d1target_case_qc',
      }),
    );
  });

  test('four written cases and five source-keyed choices reach Diploma study', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    await CurriculumIngester(db).ingest(dataset);
    final diploma = {
      for (final card in await StudyPlanner(db).cards('WSET_L4'))
        card.itemId: card,
    };
    expect(diploma.keys, containsAll(items.map((item) => item.id)));
    final level3 = {
      for (final card in await StudyPlanner(db).cards('WSET_L3')) card.itemId,
    };
    expect(level3.intersection(items.map((item) => item.id).toSet()), isEmpty);

    final presenter = ExercisePresenter(db);
    for (final entry in cases.entries) {
      final template = dataset.questionTemplates.singleWhere(
        (candidate) => candidate.id == entry.key,
      );
      expect(template.mode, 'short_answer');
      expect(ShortAnswerFormat.keyPointsOf(template)!.keys.toSet(), roles);
      final action = items.singleWhere(
        (item) =>
            item.subjectId == entry.value && item.relationType == 'CASE_ACTION',
      );
      final exercise = await presenter.present(
        action.id,
        entry.key,
        seed: 11,
      ) as ShortAnswerExercise;
      expect(exercise.keyPoints, isNotEmpty, reason: entry.key);
      expect(
        exercise.keyPoints
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
    }

    for (final (itemId, answer, sourceId) in [
      (
        'ki_d1target_regen_water',
        'Trial species and timing while measuring vine water status and yield.',
        'src_d1target_awri_cover',
      ),
      (
        'ki_d1target_precision_zones',
        'Field-check soil and vine conditions, then trial zone-specific action.',
        'src_d1target_wa_precision',
      ),
      (
        'ki_d1target_nolo_route',
        'Use supervised vacuum or membrane separation and verify the result.',
        'src_d1target_oiv_dealc',
      ),
      (
        'ki_d1target_qc_haccp',
        'Maintain hygiene prerequisites, then analyse hazards and site controls.',
        'src_d1target_oiv_haccp',
      ),
      (
        'ki_d1target_pack_barrier',
        'Package oxygen, wine stability and intended shelf life for the actual format.',
        'src_wset_prod_package',
      ),
    ]) {
      final choice = await presenter.present(
        itemId,
        'qt_d1target_choices',
        seed: 23,
      ) as AuthoredChoiceQuestion;
      expect(choice.options, hasLength(4), reason: itemId);
      expect(choice.answer.name, answer, reason: itemId);
      expect(choice.sourceCitationId, sourceId, reason: itemId);
    }
  });
}
