import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/coverage/coverage_model.dart';

import '../../support/curriculum_fixture.dart';
import 'coverage_fixture.dart';

void addWorldFrame(Map<String, dynamic> data, {bool parents = false}) {
  rowsOf(
    data,
    'node_types',
  ).add({'id': 'informal_area', 'label': 'informal area'});
  rowsOf(data, 'knowledge_nodes').add({
    'id': 'n_geo_world',
    'node_type': 'informal_area',
    // Sort before Burgundy to expose an unrelated same-depth frame candidate.
    'name': 'Atlas world frame',
  });
  rowsOf(data, 'relation_type_signatures').add({
    'relation_type': 'LOCATED_IN',
    'subject_node_type': 'country',
    'object_node_type': 'informal_area',
  });
  if (parents) {
    for (final country in ['n_geo_france', 'n_geo_germany']) {
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': country,
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_world',
        'valid_from': '1900-01-01',
      });
    }
  }
}

Map<String, String> itemAreas(TrackCoverage coverage) => {
  for (final item in coverage.items) item.id: item.area.id,
};

void main() {
  test(
    'a country containment signature cannot demote semantic country roots',
    () async {
      final original = await coverageOf(coverageDataset());
      final data = coverageDataset();
      addWorldFrame(data);
      final framed = await coverageOf(data);
      expect(itemAreas(framed), itemAreas(original));
      expect(framed.counts.toMap(), original.counts.toMap());
      expect(
        framed.items.any((item) => item.area == CoverageArea.unplaced),
        isFalse,
      );
    },
  );

  test(
    'world map parents preserve countries, regional buckets and ancestry',
    () async {
      final data = coverageDataset();
      addWorldFrame(data, parents: true);
      rowsOf(data, 'question_templates').add({
        'id': 'qt_country_frame_flashcard',
        'relation_type': 'LOCATED_IN',
        'direction': 'forward',
        'mode': 'flashcard',
        'prompt_template': 'Where is {subject.name}?',
      });
      rowsOf(data, 'knowledge_items').add({
        ...Map<String, dynamic>.from(
          rowsOf(data, 'knowledge_items').first as Map,
        ),
        'id': 'ki_france_world_frame',
        'subject_id': 'n_geo_france',
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_world',
        'assertion_text': 'France uses the world as its outer map frame.',
      });
      rowsOf(data, 'knowledge_item_citations').add({
        'knowledge_item_id': 'ki_france_world_frame',
        'source_citation_id': 'src_test_law',
      });
      rowsOf(data, 'certification_knowledge_mappings').add({
        'certification_id': 'WSET_L2',
        'knowledge_item_id': 'ki_france_world_frame',
        'importance': 'core',
        'minimum_depth': 2,
      });
      final coverage = await coverageOf(data);
      final areas = itemAreas(coverage);
      expect(areas['ki_chablis_grape'], 'n_geo_burgundy');
      expect(areas['ki_morgon_grape'], 'n_geo_beaujolais');
      expect(areas['ki_walporzheim_grape'], 'n_geo_germany');
      expect(areas['ki_france_world_frame'], 'n_geo_france');
      expect(areas.values, isNot(contains('n_geo_world')));
      expect(areas.values, isNot(contains('unplaced')));
      expect(
        coverage.items.firstWhere((i) => i.id == 'ki_chablis_grape').places,
        containsAll([
          'n_geo_chablis',
          'n_geo_burgundy',
          'n_geo_france',
          'n_geo_world',
        ]),
      );
      expect(
        coverage.items
            .firstWhere((i) => i.id == 'ki_france_world_frame')
            .places,
        containsAll(['n_geo_france', 'n_geo_world']),
      );
    },
  );

  test(
    'an unrelated frame at matching depth is not a regional country bucket',
    () async {
      final data = coverageDataset();
      addWorldFrame(data, parents: true);
      rowsOf(data, 'relation_type_signatures').add({
        'relation_type': 'LOCATED_IN',
        'subject_node_type': 'appellation',
        'object_node_type': 'informal_area',
      });
      rowsOf(data, 'knowledge_relations').add({
        'subject_id': 'n_geo_chablis',
        'relation_type': 'LOCATED_IN',
        'object_id': 'n_geo_world',
        'valid_from': '1900-01-01',
      });
      final coverage = await coverageOf(data);
      final chablis = coverage.items.firstWhere(
        (i) => i.id == 'ki_chablis_grape',
      );
      expect(chablis.area.id, 'n_geo_burgundy');
      expect(chablis.places, contains('n_geo_world'));
    },
  );
}
