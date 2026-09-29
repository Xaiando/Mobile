import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/name_normalizer.dart';
import 'package:sommelier/core/questions/formats/authored_choice/authored_choice_format.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();
  final template = dataset.questionTemplates.singleWhere(
    (row) => row.id == 'qt_wset_business_application_26',
  );
  final choices = AuthoredChoiceFormat.itemChoicesOf(template);
  final items = {for (final item in dataset.knowledgeItems) item.id: item};
  final citations = <String, Set<String>>{};
  for (final citation in dataset.knowledgeItemCitations) {
    citations
        .putIfAbsent(citation.knowledgeItemId, () => {})
        .add(citation.sourceCitationId);
  }
  final mappings = {
    for (final mapping in dataset.certificationKnowledgeMappings)
      mapping.knowledgeItemId: mapping,
  };

  test('all 26 choices stay on existing cited core business facts', () {
    const levelTwoIds = {
      'ki_wset_apply_sauternes_selection_cost',
      'ki_wset_nwa_california_cost',
      'ki_wset_nwa_cape_cool_cost',
      'ki_wset_nwa_chile_central_cost',
      'ki_wset_nwa_chile_coastal_cost',
      'ki_wset_nwa_hawkes_cost',
      'ki_wset_nwa_marlborough_cost',
      'ki_wset_nwa_martinborough_cost',
      'ki_wset_nwa_mendoza_cost',
      'ki_wset_nwa_napa_cost',
      'ki_wset_nwa_oregon_cost',
      'ki_wset_nwa_otago_cost',
      'ki_wset_nwa_sonoma_cost',
      'ki_wset_nwa_stellenbosch_cost',
      'ki_wset_nwa_western_cape_cost',
    };
    const levelThreeIds = {
      'ki_wset_apply_bordeaux_white_cost',
      'ki_wset_apply_north_italian_white_cost',
      'ki_wset_apply_abruzzo_cost',
      'ki_wset_apply_aragon_cost',
      'ki_wset_apply_duero_cost',
      'ki_wset_apply_northwest_cost',
      'ki_wset_apply_levante_cost',
      'ki_wset_apply_mancha_cost',
      'ki_wset_apply_alentejo_cost',
      'ki_wset_apply_lisboa_cost',
      'ki_wset_apply_rheinhessen_cost',
    };
    expect(choices.keys.toSet(), {...levelTwoIds, ...levelThreeIds});
    for (final entry in choices.entries) {
      final id = entry.key;
      final item = items[id]!;
      final mapping = mappings[id]!;
      expect(item.domainId, 'business', reason: id);
      expect(item.relationType, 'PRINCIPLE_EXPLANATION', reason: id);
      expect(item.verificationStatus, 'unverified', reason: id);
      expect(item.mcqDisabled, isTrue, reason: id);
      expect(mapping.importance, 'core', reason: id);
      expect(
        mapping.certificationId,
        levelTwoIds.contains(id) ? 'WSET_L2' : 'WSET_L3',
        reason: id,
      );
      expect(citations[id], contains(entry.value.sourceCitationId), reason: id);
      expect(entry.value.options, hasLength(4), reason: id);
      expect(
        entry.value.options.map(normalizeName).toSet(),
        hasLength(4),
        reason: id,
      );
    }
  });

  test('the decisions are distinct and answer positions are balanced', () {
    expect(
      choices.values.map((choice) => choice.prompt).toSet(),
      hasLength(26),
    );
    final positions = List<int>.filled(4, 0);
    final lengthRanks = List<int>.filled(4, 0);
    for (final choice in choices.values) {
      positions[choice.correctIndex]++;
      final orderedLengths =
          choice.options.map((option) => option.length).toList()..sort();
      lengthRanks[orderedLengths.indexOf(
        choice.options[choice.correctIndex].length,
      )]++;
      expect(choice.prompt.contains('?'), isTrue);
      expect(choice.explanation.trim(), isNotEmpty);
    }
    expect(positions, [7, 7, 6, 6]);
    expect(lengthRanks.every((count) => count >= 4), isTrue);
  });

  test('worked cases retain distinct cost and production mechanisms', () {
    const calculatedOutcomes = {
      'ki_wset_apply_sauternes_selection_cost': '€30 per litre',
      'ki_wset_nwa_california_cost': '€4/L versus €1/L',
      'ki_wset_nwa_hawkes_cost': '€1/L less margin',
      'ki_wset_nwa_oregon_cost': '€6,000',
      'ki_wset_nwa_otago_cost': '€2,000 net benefit',
      'ki_wset_nwa_sonoma_cost': '€11.25/kg',
      'ki_wset_apply_aragon_cost': '25% higher',
    };
    for (final entry in calculatedOutcomes.entries) {
      final choice = choices[entry.key]!;
      expect(choice.prompt, contains('€'), reason: entry.key);
      expect(
        choice.options[choice.correctIndex],
        contains(entry.value),
        reason: entry.key,
      );
    }

    const boundedDecisions = {
      'ki_wset_nwa_cape_cool_cost': 'One purchased-oak vessel',
      'ki_wset_nwa_chile_central_cost': 'pools three lots',
      'ki_wset_nwa_chile_coastal_cost': 'contracted incoming lot',
      'ki_wset_apply_northwest_cost': 'vineyard labour',
      'ki_wset_apply_mancha_cost': 'forecast storm',
      'ki_wset_apply_alentejo_cost': '€7,000 vineyard',
      'ki_wset_apply_rheinhessen_cost': 'buyer specifies fresh fruit',
    };
    for (final entry in boundedDecisions.entries) {
      final choice = choices[entry.key]!;
      expect(
        '${choice.prompt} ${choice.options[choice.correctIndex]}',
        contains(entry.value),
        reason: entry.key,
      );
    }
  });
}
