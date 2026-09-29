import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d6_'))
      .toList();

  test('D6 practice is cited, pending review, and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(17));
    for (final item in lessons) {
      expect(item.domainId, 'business', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.knowledgeItemCitations.any(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isTrue,
        reason: item.id,
      );
      expect(
        dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .map((mapping) => mapping.certificationId)
            .toSet(),
        {'WSET_L4'},
        reason: item.id,
      );
    }
  });

  test('both D6 objectives select the authored source and argument work', () {
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final objective in scope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    expect(
      objectives['wset_l4.research.evidence']!.covers!.within,
      containsAll({
        'n_d6_principle_brief',
        'n_d6_principle_question',
        'n_d6_principle_provenance',
        'n_d6_principle_origin',
        'n_d6_principle_claim',
        'n_d6_principle_comparable',
        'n_d6_case_channel_evidence',
      }),
    );
    expect(
      objectives['wset_l4.research.argument']!.covers!.within,
      containsAll({
        'n_d6_principle_counter',
        'n_d6_principle_structure',
        'n_d6_principle_reference',
        'n_d6_case_campaign_argument',
      }),
    );
  });

  test(
    'progress attributes D6 research items to D6 rather than business D2',
    () {
      final scope = WsetScope.fromJson(
        File('assets/progress/wset_scope.json').readAsStringSync(),
      );
      final diploma = scope.levels.singleWhere(
        (level) => level.certificationId == 'WSET_L4',
      );
      final d6 = diploma.units.singleWhere((unit) => unit.id == 'D6');
      expect(d6.itemIds.toSet(), containsAll(lessons.map((item) => item.id)));
    },
  );

  test('two original D6 cases expose an evidence self-check, not a grade', () {
    for (final subject in [
      'n_d6_case_channel_evidence',
      'n_d6_case_campaign_argument',
    ]) {
      expect(
        lessons
            .where((item) => item.subjectId == subject)
            .map((item) => item.relationType)
            .toSet(),
        {'CASE_ACTION', 'CASE_REASON', 'CASE_TRADEOFF', 'CASE_LIMITATION'},
        reason: subject,
      );
    }
    final templates = dataset.questionTemplates
        .where((template) => template.id.startsWith('qt_d6_case_'))
        .toList();
    expect(templates, hasLength(2));
    for (final template in templates) {
      expect(template.mode, 'short_answer');
      expect(template.promptTemplate, contains('Fictional practice packet'));
      expect(template.parameters, contains('CASE_LIMITATION'));
    }
  });
}
