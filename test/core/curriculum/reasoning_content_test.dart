import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/curriculum/reasoning_paths.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final original = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_reason_'))
      .toList();
  final originalIds = original.map((item) => item.id).toSet();
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final sources = {
    for (final source in dataset.sourceCitations) source.id: source,
  };
  const on = '2026-10-01';
  const chains = {
    'water': ['ki_reason_water_co2_entry', 'ki_reason_water_assimilation'],
    'bloom': [
      'ki_reason_bloom_carbohydrate',
      'ki_reason_bloom_set',
      'ki_reason_bloom_berries',
    ],
    'mlf': ['ki_reason_mlf_conversion', 'ki_reason_mlf_acidity'],
    'so2': ['ki_reason_so2_molecular', 'ki_reason_so2_protection'],
  };
  final targetIds = chains.values.map((chain) => chain.last).toSet();
  final supportIds = {
    for (final chain in chains.values) ...chain.take(chain.length - 1),
  };

  test('the starter maps only its four conclusions to Diploma depth four', () {
    expect(original, hasLength(21));
    expect(targetIds, hasLength(4));
    expect(supportIds, hasLength(5));
    final contradictions = original
        .where((item) => item.relationType == 'CONTRADICTS')
        .toList();
    expect(contradictions, hasLength(12));
    expect(originalIds, {
      ...targetIds,
      ...supportIds,
      ...contradictions.map((item) => item.id),
    });
    expect(
      targetIds.map((id) => items[id]!.domainId).toList(),
      unorderedEquals([
        'viticulture',
        'viticulture',
        'winemaking',
        'winemaking',
      ]),
    );

    for (final item in original) {
      final mappings = dataset.certificationKnowledgeMappings
          .where((mapping) => mapping.knowledgeItemId == item.id)
          .toList();
      expect(mappings, hasLength(1), reason: item.id);
      final mapping = mappings.single;
      expect(mapping.certificationId, 'WSET_L4', reason: item.id);
      expect(
        mapping.minimumDepth,
        targetIds.contains(item.id)
            ? 4
            : supportIds.contains(item.id)
            ? 3
            : 2,
        reason: item.id,
      );
      expect(
        mapping.importance,
        item.relationType == 'CONTRADICTS' ? 'secondary' : 'core',
        reason: item.id,
      );
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      final citations = dataset.knowledgeItemCitations
          .where((citation) => citation.knowledgeItemId == item.id)
          .toList();
      expect(citations, isNotEmpty, reason: item.id);
      for (final citation in citations) {
        expect(sources.containsKey(citation.sourceCitationId), isTrue);
        expect(citation.locator, isNotNull);
        expect(citation.locator!.trim(), isNotEmpty, reason: item.id);
      }
    }
  });

  test('the mechanisms preserve canonical primary-source identities', () {
    const canonical = {
      'src_vit_water_status': 'https://www.dpi.nsw.gov.au/__data/assets/pdf_file/0004/1158124/Monitoring-vine-water-status-part-1.pdf',
      'src_reason_early_leaf_removal': 'https://extension.psu.edu/early-season-grapevine-canopy-management-part-ii-early-leaf-removal-elr',
      'src_win_mlf': 'https://www.awri.com.au/wp-content/uploads/2011/06/Malolactic-fermentation.pdf',
      'src_reason_molecular_so2':
          'https://www.awri.com.au/wp-content/uploads/2018/03/s1886.pdf',
      'src_win_sulfur': 'https://www.awri.com.au/industry_support/winemaking_resources/fining-stabilities/microbiological/avoidance/sulfur_dioxide/',
    };
    final used = dataset.knowledgeItemCitations
        .where((citation) => originalIds.contains(citation.knowledgeItemId))
        .toList();
    expect(used, hasLength(22));
    expect(
      used.map((citation) => citation.sourceCitationId).toSet(),
      canonical.keys.toSet(),
    );
    for (final entry in canonical.entries) {
      expect(sources[entry.key]!.url, entry.value, reason: entry.key);
      expect(
        dataset.sourceCitations.where((source) => source.url == entry.value),
        hasLength(1),
        reason: 'reuse the source identity rather than duplicate its URL',
      );
    }
    const primaryForChain = {
      'water': 'src_vit_water_status',
      'bloom': 'src_reason_early_leaf_removal',
      'mlf': 'src_win_mlf',
      'so2': 'src_reason_molecular_so2',
    };
    for (final entry in chains.entries) {
      for (final itemId in entry.value) {
        expect(
          used
              .where((citation) => citation.knowledgeItemId == itemId)
              .map((citation) => citation.sourceCitationId),
          contains(primaryForChain[entry.key]),
          reason: itemId,
        );
      }
    }
  });

  test('four complete conditional paths have three explicit contradictions each', () {
    const controls = {
      'water': [
        'Measurements show',
        'restrict CO₂ entry',
        'same cultivar',
        'controlled leaf temperature',
        'otherwise healthy',
      ],
      'bloom': [
        'carbohydrate-sensitive',
        'just before bloom',
        'not compensated',
        'flowering weather',
        'no whole clusters are removed',
      ],
      'mlf': [
        'successful malolactic conversion',
        'isolate the conversion',
        'no acid addition',
        'tartrate precipitation',
        'without assuming a buttery aroma',
      ],
      'so2': [
        'same accurately measured free SO₂',
        'alcohol and temperature',
        'higher pH',
        'all other barriers are held constant',
        'Do not infer a universal killing threshold',
      ],
    };
    final templates = dataset.questionTemplates
        .where(
          (template) =>
              template.id.startsWith('qt_reason_') &&
              template.mode == 'reasoning',
        )
        .toList();
    expect(templates, hasLength(4));
    expect(templates.map((template) => template.variant).toSet(), hasLength(4));
    final allNegativeEvidence = <String>{};

    for (final entry in chains.entries) {
      final template = templates.singleWhere(
        (template) => template.id == 'qt_reason_${entry.key}_chain',
      );
      expect(template.direction, 'forward');
      expect(template.promptTemplate, contains('{subject.name}'));
      expect(template.promptTemplate, isNot(contains('{object.name}')));
      final parameters = ReasoningParameters.parse(template);
      final premiseId = 'n_reason_${entry.key}_premise';
      expect(parameters.scopeNodeIds, {premiseId});
      expect(parameters.pathRelationTypes, [
        'CAUSES_STATE',
        for (var index = 1; index < entry.value.length; index++) 'LEADS_TO',
      ]);
      expect(parameters.contrasts.keys.toSet(), {entry.value.last});
      expect(
        ReasoningPaths.templateReferenceProblems(dataset, template, on: on),
        isEmpty,
        reason: template.id,
      );
      final resolved = ReasoningPaths.inspectDataset(dataset, template, on: on);
      expect(resolved.diagnostics, isEmpty, reason: template.id);
      expect(resolved.paths, hasLength(1), reason: template.id);
      final path = resolved.paths.single;
      expect(path.itemIds, entry.value);
      expect(path.premiseNodeId, premiseId);
      expect(path.target.id, entry.value.last);
      expect(
        path.items.map((item) => item.subjectId).toSet(),
        hasLength(path.items.length),
      );
      expect(
        path.items.any(
          (item) =>
              item.relationType == 'PRINCIPLE_EXPLANATION' ||
              item.relationType.startsWith('CASE_'),
        ),
        isFalse,
        reason:
            'a star of learning points or a case rubric is not a causal chain',
      );
      for (var index = 1; index < path.items.length; index++) {
        expect(path.items[index].subjectId, path.items[index - 1].objectId);
      }
      final premise = nodes[premiseId]!.name;
      final prompt = template.promptTemplate.replaceAll(
        '{subject.name}',
        premise,
      );
      expect(prompt, startsWith(premise));
      expect(prompt, isNot(matches(RegExp(r'[{}]'))));
      for (final condition in controls[entry.key]!) {
        expect(
          prompt,
          contains(condition),
          reason: '${template.id}: retain $condition',
        );
      }

      expect(path.contrasts, hasLength(3));
      expect(
        path.contrasts.map((contrast) => contrast.optionNodeId).toSet(),
        hasLength(3),
      );
      final names = {normalizeName(nodes[path.target.objectId]!.name)};
      for (final contrast in path.contrasts) {
        expect(
          names.add(normalizeName(nodes[contrast.optionNodeId]!.name)),
          isTrue,
        );
        expect(contrast.explanation.trim(), isNotEmpty);
        final evidence = contrast.evidenceItemIds
            .map((id) => items[id]!)
            .toList();
        expect(
          evidence.any(
            (item) =>
                item.subjectId == premiseId &&
                item.objectId == contrast.optionNodeId &&
                item.relationType == 'CONTRADICTS',
          ),
          isTrue,
          reason:
              'each alternative needs direct evidence under its own premise',
        );
        for (final item in evidence) {
          expect(originalIds.contains(item.id), isTrue);
          expect(item.relationType, 'CONTRADICTS');
          expect(
            path.itemIds,
            isNot(contains(item.id)),
            reason: 'contradiction feedback is not an assessed path step',
          );
          allNegativeEvidence.add(item.id);
        }
      }
    }
    expect(allNegativeEvidence, hasLength(12));
    for (final relation in ['CAUSES_STATE', 'LEADS_TO', 'CONTRADICTS']) {
      for (final mode in ['flashcard', 'typed']) {
        expect(
          dataset.questionTemplates.where(
            (template) =>
                template.id.startsWith('qt_reason_') &&
                template.relationType == relation &&
                template.mode == mode &&
                template.direction == 'forward',
          ),
          hasLength(1),
          reason: 'every authored causal/evidence fact retains term recall',
        );
      }
    }
  });

  test(
    'China keeps optional atlas references while analysis remains Diploma-only',
    () {
      final atlas = dataset.knowledgeItems
          .where((item) => item.id.startsWith('ki_cn_atlas_'))
          .toList();
      expect(atlas, hasLength(8));
      for (final item in atlas) {
        final lower = dataset.certificationKnowledgeMappings
            .where(
              (mapping) =>
                  mapping.knowledgeItemId == item.id &&
                  const {
                    'WSET_L3',
                    'CMS_CERTIFIED',
                  }.contains(mapping.certificationId),
            )
            .toList();
        expect(lower.map((mapping) => mapping.certificationId).toSet(), {
          'WSET_L3',
          'CMS_CERTIFIED',
        });
        expect(lower, hasLength(2));
        expect(
          lower.map((mapping) => mapping.importance),
          everyElement('secondary'),
        );
        expect(lower.map((mapping) => mapping.minimumDepth), everyElement(2));
      }
      final analyses = dataset.knowledgeItems
          .where((item) => item.id.startsWith('ki_reg_cn_'))
          .toList();
      expect(analyses, hasLength(44));
      for (final item in analyses) {
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(mappings, hasLength(1));
        expect(mappings.single.certificationId, 'WSET_L4', reason: item.id);
        expect(mappings.single.importance, 'core');
        expect(mappings.single.minimumDepth, 3);
      }
    },
  );
}
