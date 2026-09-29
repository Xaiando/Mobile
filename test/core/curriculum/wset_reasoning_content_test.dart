import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/curriculum/reasoning_paths.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final nodes = {for (final node in dataset.knowledgeNodes) node.id: node};
  const targets = {
    'frost': 'ki_wset_reason_frost_clusters',
    'ferment': 'ki_wset_reason_ferment_ethanol',
  };

  test(
    'two cited causal paths have three directly contradicted alternatives',
    () {
      final authored = dataset.knowledgeItems
          .where((item) => item.id.startsWith('ki_wset_reason_'))
          .toList();
      expect(authored, hasLength(10));
      final sources = {
        for (final source in dataset.sourceCitations) source.id: source,
      };
      expect(
        sources['src_wset_reason_sugar_alcohol']?.url,
        'https://www.awri.com.au/wp-content/uploads/2018/04/s1809.pdf',
      );
      for (final item in authored) {
        expect(item.verificationStatus, 'unverified', reason: item.id);
        expect(item.mcqDisabled, isTrue, reason: item.id);
        final citations = dataset.knowledgeItemCitations
            .where((citation) => citation.knowledgeItemId == item.id)
            .toList();
        expect(citations, isNotEmpty, reason: item.id);
        for (final citation in citations) {
          expect(sources.containsKey(citation.sourceCitationId), isTrue);
          expect(citation.locator?.trim(), isNotEmpty);
        }
        final mappings = dataset.certificationKnowledgeMappings
            .where((mapping) => mapping.knowledgeItemId == item.id)
            .toList();
        expect(mappings.map((m) => m.certificationId).toSet(), {
          'WSET_L2',
          'WSET_L3',
          'WSET_L4',
        });
        for (final mapping in mappings) {
          expect(
            mapping.minimumDepth,
            item.relationType == 'LEADS_TO'
                ? 4
                : item.relationType == 'CAUSES_STATE'
                ? 3
                : 2,
          );
          expect(
            mapping.importance,
            item.relationType == 'CONTRADICTS' ? 'secondary' : 'core',
          );
        }
      }

      for (final entry in targets.entries) {
        final template = dataset.questionTemplates.singleWhere(
          (template) => template.id == 'qt_wset_reason_${entry.key}_chain',
        );
        expect(template.mode, 'reasoning');
        expect(template.direction, 'forward');
        final parameters = ReasoningParameters.parse(template);
        expect(parameters.pathRelationTypes, ['CAUSES_STATE', 'LEADS_TO']);
        expect(parameters.scopeNodeIds, {'n_wset_reason_${entry.key}_premise'});
        expect(
          ReasoningPaths.templateReferenceProblems(
            dataset,
            template,
            on: '2026-10-01',
          ),
          isEmpty,
        );
        final resolved = ReasoningPaths.inspectDataset(
          dataset,
          template,
          on: '2026-10-01',
        );
        expect(resolved.diagnostics, isEmpty);
        expect(resolved.paths, hasLength(1));
        final path = resolved.paths.single;
        expect(path.target.id, entry.value);
        expect(path.itemIds, hasLength(2));
        expect(path.contrasts, hasLength(3));
        expect(path.contrasts.map((c) => c.optionNodeId).toSet(), hasLength(3));
        final optionNames = {normalizeName(nodes[path.target.objectId]!.name)};
        for (final contrast in path.contrasts) {
          expect(
            optionNames.add(normalizeName(nodes[contrast.optionNodeId]!.name)),
            isTrue,
          );
          expect(contrast.explanation.trim(), isNotEmpty);
          expect(contrast.evidenceItemIds, hasLength(1));
          final evidence = items[contrast.evidenceItemIds.single]!;
          expect(evidence.subjectId, path.premiseNodeId);
          expect(evidence.objectId, contrast.optionNodeId);
          expect(evidence.relationType, 'CONTRADICTS');
        }
        final renderedPrompt = template.promptTemplate.replaceAll(
          '{subject.name}',
          nodes[path.premiseNodeId]!.name,
        );
        expect(renderedPrompt, isNot(contains('{subject.name}')));
        expect(
          renderedPrompt,
          contains(
            entry.key == 'frost'
                ? 'secondary and lateral shoots add no replacement clusters'
                : 'same yeast conversion yield per unit of sugar consumed',
          ),
        );
      }
    },
  );
}
