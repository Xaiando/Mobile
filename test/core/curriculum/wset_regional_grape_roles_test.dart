import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_validator.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final lessons = dataset.knowledgeItems
      .where((item) => item.id.startsWith('ki_wset_role_'))
      .toList();
  final facts = {for (final item in lessons) item.id: item.assertionText};

  test('additional regional roles validate as cited Level 3 explanations', () {
    expect(validateDataset(dataset).errors, isEmpty);
    expect(lessons, hasLength(27));
    for (final item in lessons) {
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: item.id);
      expect(item.verificationStatus, 'unverified', reason: item.id);
      expect(item.mcqDisabled, isTrue, reason: item.id);
      expect(
        dataset.knowledgeItemCitations.where(
          (citation) => citation.knowledgeItemId == item.id,
        ),
        isNotEmpty,
        reason: item.id,
      );
      final mappings = dataset.certificationKnowledgeMappings.where(
        (mapping) => mapping.knowledgeItemId == item.id,
      );
      expect(mappings, hasLength(1), reason: item.id);
      expect(mappings.single.certificationId, 'WSET_L3', reason: item.id);
      expect(mappings.single.minimumDepth, 2, reason: item.id);
    }
  });

  test('all missing grape roles name their actual contribution', () {
    for (final entry in {
      'dornfelder_style': 'Rheinhessen',
      'welschriesling_sweet': 'Burgenland',
      'saint_laurent': 'Thermenregion',
      'arinto': 'acidity',
      'alfrocheiro': 'Dão',
      'jaen_blend': 'Touriga Nacional',
      'trincadeira_vine': 'rot',
      'bonarda_style': 'Mendoza',
      'petit_verdot': 'late-ripening',
      'graciano': 'acidity',
      'mazuelo': 'tannin',
      'sarga_muskotaly': 'Aszú',
    }.entries) {
      expect(
        facts['ki_wset_role_${entry.key}'],
        contains(entry.value),
        reason: entry.key,
      );
    }
  });

  test('similar grape names and regional labels retain distinct meanings', () {
    expect(facts['ki_wset_role_jaen_identity'], contains('synonym'));
    expect(
      facts['ki_wset_role_jaen_identity'],
      contains('unrelated legal entry'),
    );
    expect(
      facts['ki_wset_role_bonarda_identity'],
      contains('different Italian'),
    );
    expect(
      facts['ki_wset_role_welschriesling_dry'],
      contains('separate grape'),
    );
    expect(
      facts['ki_wset_role_saumur_champigny_identity'],
      contains('still red'),
    );
    expect(facts['ki_wset_role_friuli_identity'], contains('distinct from'));
    expect(
      facts['ki_wset_role_castilla_igp_identity'],
      contains('not a tasting score'),
    );
    expect(facts['ki_wset_role_friuli_cellar_cost'], contains('neither'));
    expect(facts['ki_wset_role_castilla_styles'], contains('not a synonym'));
    final names = {
      for (final node in dataset.knowledgeNodes) node.id: node.name,
    };
    expect(names['n_grape_mencia'], 'Mencía');
    expect(names['n_grape_bonarda_argentina'], 'Bonarda (Argentina)');
    expect(names['n_grape_pirule_jaen'], contains('Ribera del Duero'));
    expect(names.containsKey('n_grape_jaen_dao'), isFalse);
  });
}
