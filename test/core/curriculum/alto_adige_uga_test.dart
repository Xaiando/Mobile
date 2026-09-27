import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/curriculum/curriculum_dataset.dart';

import '../../support/curriculum_fixture.dart';

void main() {
  final dataset = bundledDataset();

  test('five Alto Adige units sit in Alto Adige and the lookalikes were not added', () {
    const accepted = {
      'n_geo_alto_adige_uga_buchholz': 'Buchholz',
      'n_geo_alto_adige_uga_girlan': 'Girlan',
      'n_geo_alto_adige_uga_gries': 'Gries',
      'n_geo_alto_adige_uga_penon': 'Penon',
      'n_geo_alto_adige_uga_rain': 'Rain',
    };
    for (final entry in accepted.entries) {
      final node = dataset.knowledgeNodes.singleWhere((n) => n.id == entry.key);
      expect(node.name, entry.value);
      final relation = dataset.knowledgeRelations.singleWhere(
        (r) => r.subjectId == entry.key && r.relationType == 'LOCATED_IN',
      );
      expect(relation.objectId, 'n_geo_alto_adige');
    }
    final names = dataset.knowledgeNodes.map((n) => n.name).toSet();
    expect(names, isNot(contains('Missian')));
    expect(names, isNot(contains('Montiggl')));
    expect(names, isNot(contains('Mazon')));
    expect(names, isNot(contains('Gries-Moritzing')));
    expect(
      dataset.knowledgeItems
          .singleWhere((i) => i.id == 'ki_alto_adige_uga_gries_location')
          .assertionText,
      contains('not the Gries-Moritzing'),
    );
    expect(
      dataset.knowledgeItems
          .singleWhere((i) => i.id == 'ki_alto_adige_uga_rain_location')
          .assertionText,
      contains('not Goldrain'),
    );
    expect(
      dataset.knowledgeItems
          .singleWhere((i) => i.id == 'ki_alto_adige_uga_girlan_location')
          .assertionText,
      contains('not the Girlan-Gschleier'),
    );
  });
}
