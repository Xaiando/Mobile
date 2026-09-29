import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:sommelier/core/coverage/coverage_checker.dart';
import 'package:sommelier/core/coverage/coverage_policy.dart';
import 'package:sommelier/core/curriculum/curriculum_ingestion.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/database/app_database.dart';
import 'package:sommelier/core/questions/exercise_presenter.dart';
import 'package:sommelier/core/questions/formats/case_criteria/case_criteria_format.dart';

import '../../support/curriculum_fixture.dart';
import '../../support/fixture.dart';
import '../../support/study_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final flat = flattenDataset('assets/curriculum/curriculum.yaml');
  final rawTemplates = {
    for (final row in rowsOf(flat, 'question_templates'))
      (row as Map<String, dynamic>)['id'] as String: row,
  };
  final templates = {
    for (final template in dataset.questionTemplates) template.id: template,
  };
  final principle = templates['qt_wset_l4_viticulture_principle_closure_51']!;
  final causalFirst = templates['qt_wset_l4_viticulture_causal_causes_state']!;
  final causalLast = templates['qt_wset_l4_viticulture_causal_leads_to']!;
  final caseTemplate = templates['qt_wset_l4_viticulture_case_criteria_4']!;
  final pools = [principle, causalFirst, causalLast];
  final targetIds = {
    for (final template in pools)
      ...((rawTemplates[template.id]!['parameters']
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>)
          .keys,
  };
  final caseScope = CaseCriteriaFormat.scopeNodeIdsOf(caseTemplate);
  late AppDatabase db;

  setUpAll(() async {
    db = openTestDatabase();
    await CurriculumIngester(
      db,
      clock: TestClock(DateTime.utc(2026, 9, 29, 18)).clock,
    ).ingest(dataset);
  });

  tearDownAll(() async => db.close());

  test('58 cited, unique objective choices target Level 4 vineyard facts', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final items = {for (final item in dataset.knowledgeItems) item.id: item};
    final cited = {
      for (final citation in dataset.knowledgeItemCitations)
        citation.knowledgeItemId: <String>{
          for (final other in dataset.knowledgeItemCitations)
            if (other.knowledgeItemId == citation.knowledgeItemId)
              other.sourceCitationId,
        },
    };
    final sourceUrls = {
      for (final source in dataset.sourceCitations) source.id: source.url,
    };
    final otherTargets = <String>{};
    for (final template in dataset.questionTemplates) {
      if (template.mode != 'authored_choice' || pools.contains(template)) {
        continue;
      }
      otherTargets.addAll(
        ((rawTemplates[template.id]!['parameters']
                    as Map<String, dynamic>)['item_choices']
                as Map<String, dynamic>)
            .keys,
      );
    }
    final answerPositions = [0, 0, 0, 0];
    final seenTargets = <String>{};
    for (final template in pools) {
      final choices =
          (rawTemplates[template.id]!['parameters']
                  as Map<String, dynamic>)['item_choices']
              as Map<String, dynamic>;
      for (final entry in choices.entries) {
        final id = entry.key;
        final cue = entry.value as Map<String, dynamic>;
        expect(seenTargets.add(id), isTrue, reason: id);
        expect(otherTargets, isNot(contains(id)), reason: id);
        final item = items[id]!;
        expect(item.domainId, 'viticulture', reason: id);
        expect(item.relationType, template.relationType, reason: id);
        expect(item.verificationStatus, 'unverified', reason: id);
        final mapping = dataset.certificationKnowledgeMappings.singleWhere(
          (mapping) =>
              mapping.certificationId == 'WSET_L4' &&
              mapping.knowledgeItemId == id,
        );
        expect(mapping.importance, 'core', reason: id);
        final sourceId = cue['sourceCitationId'] as String;
        expect(cited[id], contains(sourceId), reason: id);
        expect(sourceUrls[sourceId], startsWith('https://'), reason: id);
        final options = (cue['options'] as List).cast<String>();
        expect(options, hasLength(4), reason: id);
        expect(options.map((option) => option.trim()).toSet(), hasLength(4));
        final correctIndex = cue['correctIndex'] as int;
        expect(correctIndex, inInclusiveRange(0, 3), reason: id);
        answerPositions[correctIndex]++;
        expect((cue['prompt'] as String).length, greaterThan(35));
        expect((cue['explanation'] as String).length, greaterThan(35));
      }
    }
    expect(targetIds, hasLength(58));
    expect(answerPositions, [15, 15, 15, 13]);
  });

  test(
    'four distinct vineyard cases offer complete source-linked decisions',
    () async {
      expect(caseScope, hasLength(4));
      expect(
        CaseCriteriaFormat.distractorsOf(caseTemplate).keys.toSet(),
        caseScope,
      );
      final itemRows = <String>{};
      for (final subject in caseScope) {
        final roles = [
          for (final item in dataset.knowledgeItems)
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
        for (final item in roles) {
          itemRows.add(item.id);
          expect(item.verificationStatus, 'unverified', reason: item.id);
          expect(
            dataset.knowledgeItemCitations.where(
              (citation) => citation.knowledgeItemId == item.id,
            ),
            isNotEmpty,
            reason: item.id,
          );
        }
      }
      const path = 'assets/curriculum/coverage_policy.yaml';
      final report = await CoverageChecker(
        db,
        CoveragePolicy.parse(File(path).readAsStringSync(), path: path),
      ).check('WSET_L4', on: '2026-09-29');
      for (final row in report.items.where(
        (row) => targetIds.contains(row.id) || itemRows.contains(row.id),
      )) {
        expect(row.hasUsefulPractice, isTrue, reason: row.id);
      }
      expect(itemRows, hasLength(16));
    },
  );

  test(
    'a false Bairrada criterion fails while all four cited roles pass',
    () async {
      final exercise = await ExercisePresenter(db).present(
        'ki_d3rt_case_bairrada_rain_action',
        caseTemplate.id,
        seed: 11,
      ) as CaseCriteriaExercise;
      expect(exercise.itemIds, hasLength(4));
      expect(exercise.options, hasLength(6));
      final byRole = {
        for (final criterion in exercise.criteria)
          criterion.role: criterion.itemId,
      };
      const format = CaseCriteriaFormat();
      expect(
        format
            .grade(exercise, CaseCriteriaResponse(byRole))
            .every((grade) => grade.rating == fsrs.Rating.good),
        isTrue,
      );
      final falseOption = exercise.options.singleWhere(
        (option) => option.summary.startsWith('Combine ripe sound parcel A'),
      );
      final incorrect = {...byRole, 'CASE_REASON': falseOption.id};
      expect(
        format
            .grade(exercise, CaseCriteriaResponse(incorrect))
            .singleWhere((grade) => grade.itemId == byRole['CASE_REASON'])
            .rating,
        fsrs.Rating.again,
      );
    },
  );
}
