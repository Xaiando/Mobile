import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/track_scope.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_d4nw_'))
      .toList();

  test('New World D4 lessons are cited, review-pending and Diploma-only', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(items, hasLength(18));
    for (final item in items) {
      expect(item.domainId, 'winemaking', reason: item.id);
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

  test('every New World D4 selector points at authored material', () {
    final scope = TrackScopeManifest.parse(
      File('assets/curriculum/track_scope.yaml').readAsStringSync(),
    );
    final objectives = {
      for (final objective in scope.tracks['WSET_L4']!.objectives)
        objective.id: objective,
    };
    final groups = <String, Set<String>>{
      'wset_l4.sparkling.americas': {
        'n_d4nw_principle_us_california',
        'n_d4nw_principle_us_oregon',
        'n_d4nw_principle_us_washington',
        'n_d4nw_principle_chile_coast_method',
        'n_d4nw_principle_argentina_market',
        'n_d4nw_principle_argentina_terms',
      },
      'wset_l4.sparkling.south_africa': {
        'n_d4nw_principle_za_association',
        'n_d4nw_principle_za_variation',
      },
      'wset_l4.sparkling.australia': {
        'n_d4nw_principle_au_south_australia',
        'n_d4nw_principle_au_victoria',
        'n_d4nw_principle_au_tasmania',
        'n_d4nw_principle_au_sea_label',
        'n_d4nw_case_australian_offer',
      },
      'wset_l4.sparkling.new_zealand': {
        'n_d4nw_principle_nz_regions',
        'n_d4nw_principle_nz_method',
      },
    };
    for (final entry in groups.entries) {
      final objective = objectives[entry.key]!;
      expect(objective.covers!.within, containsAll(entry.value));
      expect(
        items.any((item) => objective.covers!.within.contains(item.subjectId)),
        isTrue,
        reason: entry.key,
      );
    }
  });

  test('Australian buyer scenario has a complete evidence rubric', () {
    expect(
      items
          .where((item) => item.subjectId == 'n_d4nw_case_australian_offer')
          .map((item) => item.relationType)
          .toSet(),
      {'CASE_ACTION', 'CASE_REASON', 'CASE_TRADEOFF', 'CASE_LIMITATION'},
    );
    final template = dataset.questionTemplates.singleWhere(
      (template) => template.id == 'qt_d4nw_case_australian_offer',
    );
    expect(template.mode, 'short_answer');
    expect(template.parameters, contains('CASE_LIMITATION'));
  });

  test('New World sparkling reviews count in D4 progress', () {
    final scope = WsetScope.fromJson(
      File('assets/progress/wset_scope.json').readAsStringSync(),
    );
    final diploma = scope.levels.singleWhere(
      (level) => level.certificationId == 'WSET_L4',
    );
    final d4 = diploma.units.singleWhere((unit) => unit.id == 'D4');
    expect(d4.itemIds.toSet(), containsAll(items.map((item) => item.id)));
  });
}
