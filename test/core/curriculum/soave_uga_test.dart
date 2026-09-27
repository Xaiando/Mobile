import 'package:flutter_test/flutter_test.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();

  test(
    'six Soave units sit in Soave and the rejected names were not added',
    () {
      const accepted = {
        'n_geo_soave_uga_brognoligo': 'Brognoligo',
        'n_geo_soave_uga_castelcerino': 'Castelcerino',
        'n_geo_soave_uga_colombara': 'Colombara',
        'n_geo_soave_uga_duello': 'Duello',
        'n_geo_soave_uga_fitta': 'Fittà',
        'n_geo_soave_uga_ronca_monte_calvarina': 'Roncà–Monte Calvarina',
      };
      for (final entry in accepted.entries) {
        final node = dataset.knowledgeNodes.singleWhere(
          (n) => n.id == entry.key,
        );
        expect(node.name, entry.value);
        final relation = dataset.knowledgeRelations.singleWhere(
          (r) => r.subjectId == entry.key && r.relationType == 'LOCATED_IN',
        );
        expect(relation.objectId, 'n_geo_soave');
      }
      final names = dataset.knowledgeNodes.map((n) => n.name).toSet();
      expect(names, isNot(contains('Costalunga')));
      expect(names, isNot(contains('Costeggiola')));
      expect(names, isNot(contains('Ca\' del Vento')));
      expect(
        dataset.knowledgeItems
            .singleWhere((i) => i.id == 'ki_soave_uga_brognoligo_location')
            .assertionText,
        contains('not the Costalunga'),
      );
      expect(
        dataset.knowledgeItems
            .singleWhere(
              (i) => i.id == 'ki_soave_uga_ronca_monte_calvarina_location',
            )
            .assertionText,
        contains('one Soave additional geographical unit'),
      );
    },
  );
}
