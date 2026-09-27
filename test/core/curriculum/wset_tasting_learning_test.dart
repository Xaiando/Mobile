import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';
import 'package:sommelier/core/progress/wset_scope.dart';
import 'package:sommelier/core/tasting_guidance/guided_tasting.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final scope = WsetScope.fromJson(
    File('assets/progress/wset_scope.json').readAsStringSync(),
  );
  final bank = GuidedTastingBank.fromJson(
    File('assets/study/guided_tasting.json').readAsStringSync(),
  );
  test('tasting lessons retain sourced, level-specific original teaching', () {
    expect(validateDataset(dataset).errors, isEmpty);
    final facts = dataset.knowledgeItems
        .where((item) => item.id.startsWith('ki_wset_taste_'))
        .toList();
    expect(facts, hasLength(39));
    for (final item in facts) {
      expect(item.domainId, 'tasting');
      expect(item.verificationStatus, 'unverified');
      expect(item.mcqDisabled, isTrue);
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
      final authoredMappings = mappings.where(
        (mapping) =>
            dataset
                .locate((
                  section: 'certification_knowledge_mappings',
                  key: rowKey('certification_knowledge_mappings', mapping),
                ))
                ?.path
                .endsWith('wset_tasting_learning.yaml') ??
            false,
      );
      expect(authoredMappings, hasLength(1), reason: item.id);
      final requiredLevels =
          scope.levels
              .where((level) => level.requiredItemIds.contains(item.id))
              .map((level) => level.certificationId)
              .toList()
            ..sort();
      expect(requiredLevels, isNotEmpty, reason: item.id);
      final expectedTracks = {
        authoredMappings.single.certificationId,
        requiredLevels.first,
      };
      expect(mappings, hasLength(expectedTracks.length), reason: item.id);
      expect(
        mappings.map((mapping) => mapping.certificationId).toSet(),
        expectedTracks,
        reason: '${item.id}: only its authored level and required lower reuse',
      );
      expect(
        {'WSET_L1', 'WSET_L2', 'WSET_L3'},
        contains(authoredMappings.single.certificationId),
        reason: item.id,
      );
    }
  });
  test(
    'all original cases describe every required field with valid grid values',
    () {
      expect(bank.cases, hasLength(9));
      for (final calibration in bank.cases) {
        final level = bank.levels.singleWhere(
          (l) => l.level == calibration.level,
        );
        final required = dataset.tastingGridAttributes.where(
          (a) => a.tastingGridId == level.gridId && a.isRequired,
        );
        expect(
          calibration.referenceObservations.map((r) => r.attributeKey).toSet(),
          containsAll(required.map((a) => a.attributeKey)),
        );
        for (final reference in calibration.referenceObservations) {
          final valid = dataset.tastingGridValues
              .where(
                (v) =>
                    v.tastingGridId == level.gridId &&
                    v.attributeKey == reference.attributeKey,
              )
              .map((v) => v.valueKey)
              .toSet();
          expect(valid, containsAll(reference.valueKeys));
        }
        for (final id in calibration.itemIds) {
          expect(
            dataset.knowledgeItems.where((item) => item.id == id),
            hasLength(1),
          );
          final mappings = dataset.certificationKnowledgeMappings.where(
            (m) =>
                m.knowledgeItemId == id &&
                m.certificationId.startsWith('WSET_'),
          );
          expect(
            mappings.any(
              (mapping) =>
                  int.parse(mapping.certificationId.substring(6)) <=
                  calibration.level,
            ),
            isTrue,
            reason: id,
          );
        }
        expect(calibration.description, startsWith('Original fictional'));
        expect(calibration.feedback, contains('not marks'));
      }
    },
  );
  test(
    'new grids append distinct app vocabulary and do not redefine legacy grids',
    () {
      final appended = dataset.tastingGrids.where(
        (g) => g.id.startsWith('tg_guided_wine_'),
      );
      expect(appended, hasLength(3));
      expect(appended.map((g) => g.framework), everyElement('WSET_SAT'));
      expect(
        dataset.tastingGridAttributes.where(
          (attribute) =>
              attribute.tastingGridId == 'tg_guided_wine_l1_v1' &&
              attribute.attributeKey == 'flavours' &&
              attribute.isRequired,
        ),
        hasLength(1),
      );
      expect(
        bank.levels
            .singleWhere((level) => level.level == 1)
            .evidencePrompts
            .single
            .prompt,
        contains('tasted flavours'),
      );
      for (final id in ['tg_structured', 'tg_deductive']) {
        expect(dataset.tastingGrids.where((g) => g.id == id), hasLength(1));
      }
    },
  );
}
