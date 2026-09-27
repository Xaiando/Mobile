import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_srv_'))
      .toList();

  test('wine service includes complete source-backed mechanism groups', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons.length, greaterThanOrEqualTo(60));
    final groups = <String, int>{};
    for (final item in lessons) {
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(item.domainId, 'service');
      expect(
        dataset.knowledgeItemCitations.where(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isNotEmpty,
        reason: item.id,
      );
      final mappings = dataset.certificationKnowledgeMappings.where(
        (mapping) =>
            mapping.knowledgeItemId == item.id &&
            mapping.certificationId.startsWith('WSET_'),
      );
      const promoted = {
        'ki_wset_srv_food_umami_bitter',
        'ki_wset_srv_food_umami_choice',
        'ki_wset_srv_food_intensity_match',
        'ki_wset_srv_food_intensity_preference',
      };
      expect(mappings, hasLength(promoted.contains(item.id) ? 2 : 1));
      expect(mappings.map((mapping) => mapping.minimumDepth), everyElement(2));
      if (promoted.contains(item.id)) {
        expect(mappings.map((mapping) => mapping.certificationId).toSet(), {
          'WSET_L1',
          'WSET_L2',
        });
      }
      groups.update(item.subjectId, (count) => count + 1, ifAbsent: () => 1);
    }
    expect(groups.values, everyElement(inInclusiveRange(2, 4)));
  });

  test('service distinguishes chemical taint, normal deposits and preservation limits', () {
    final facts = {for (final item in lessons) item.id: item.assertionText};
    expect(
      facts['ki_wset_srv_cork_taint_distinct'],
      contains('physical problem'),
    );
    expect(facts['ki_wset_srv_crystals'], contains('do not by themselves'));
    expect(facts['ki_wset_srv_preserve_check'], contains('cannot guarantee'));
    expect(facts['ki_wset_srv_spark_no_vacuum'], contains('flatten'));
    expect(facts['ki_wset_srv_alcohol_wine_not_health'], contains('risk-free'));
  });

  test('three conditional cases expose four cited criteria at Level 3', () {
    final cases = lessons.where(
      (item) => item.relationType.startsWith('CASE_'),
    );
    expect(cases, hasLength(12));
    final templates = dataset.questionTemplates.where(
      (template) => template.id.startsWith('qt_wset_srv_case_'),
    );
    expect(templates, hasLength(3));
    for (final subject in cases.map((item) => item.subjectId).toSet()) {
      expect(
        cases
            .where((item) => item.subjectId == subject)
            .map((item) => item.relationType)
            .toSet(),
        {'CASE_ACTION', 'CASE_REASON', 'CASE_TRADEOFF', 'CASE_LIMITATION'},
      );
    }
    for (final item in cases) {
      expect(
        dataset.certificationKnowledgeMappings
            .singleWhere(
              (mapping) =>
                  mapping.knowledgeItemId == item.id &&
                  mapping.certificationId.startsWith('WSET_'),
            )
            .certificationId,
        'WSET_L3',
      );
    }
  });
}
