import 'dart:convert';
import 'dart:io';

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
        allOf(
          contains('GeoNames Brognoligo-Costalunga combined locality'),
          contains('not a standalone Brognoligo village centre'),
          contains('the Costalunga additional geographical unit'),
          contains('or a legal boundary'),
        ),
      );
      expect(
        dataset.nodeGeometries
            .singleWhere(
              (g) => g.knowledgeNodeId == 'n_geo_soave_uga_brognoligo',
            )
            .mapLayerId,
        'ml_soave_uga_wikidata_markers',
      );
      expect(
        dataset.knowledgeItemCitations.any(
          (c) =>
              c.knowledgeItemId == 'ki_soave_uga_brognoligo_location' &&
              c.sourceCitationId == 'src_soave_brognoligo_geonames_8948888',
        ),
        isTrue,
      );
      expect(
        dataset.sourceCitations
            .singleWhere((s) => s.id == 'src_soave_brognoligo_geonames_8948888')
            .url,
        'https://www.geonames.org/8948888',
      );
      // Composite geometry identities survive upgrades even when provenance changes.
      for (final node in accepted.keys) {
        final geometries = dataset.nodeGeometries
            .where((g) => g.knowledgeNodeId == node)
            .toList();
        expect(geometries, hasLength(1));
        expect(
          geometries.single.mapLayerId,
          node == 'n_geo_soave_uga_brognoligo' ||
                  node == 'n_geo_soave_uga_castelcerino'
              ? 'ml_soave_uga_wikidata_markers'
              : 'ml_soave_uga_geonames_markers',
        );
      }
      expect(
        dataset.mapLayerCitations
            .where((c) => c.mapLayerId == 'ml_soave_uga_wikidata_markers')
            .map((c) => c.sourceCitationId)
            .toSet(),
        {'src_soave_uga_wikidata_markers', 'src_soave_uga_geonames_markers'},
      );
      final legacySources = dataset.sourceCitations.where(
        (source) => const {
          'src_soave_uga_wikidata_markers',
          'src_soave_uga_geonames_markers',
        }.contains(source.id),
      );
      expect(legacySources.map((source) => source.license).toSet(), {
        'CC0 1.0',
        'CC BY 4.0',
      });
      final legacyAttribution = legacySources
          .map((source) => source.attributionText ?? '')
          .join(' ');
      expect(legacyAttribution, contains('Wikidata'));
      expect(legacyAttribution, contains('GeoNames'));
      expect(legacyAttribution, contains('CC BY 4.0'));
      List<Map<String, dynamic>> servedPoints(String asset) {
        final topology = jsonDecode(
          File('assets/geography/$asset').readAsStringSync(),
        ) as Map<String, dynamic>;
        final objects = topology['objects'] as Map<String, dynamic>;
        return ((objects.values.single as Map<String, dynamic>)['geometries']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }

      final legacyPoints = servedPoints('soave_uga_wikidata_markers.topo.json');
      final separatePoints = servedPoints(
        'soave_uga_geonames_markers.topo.json',
      );
      expect(legacyPoints.map((point) => point['id']).toSet(), {
        'n_geo_soave_uga_brognoligo',
        'n_geo_soave_uga_castelcerino',
      });
      expect(legacyPoints, hasLength(2));
      expect(separatePoints.map((point) => point['id']).toSet(), {
        'n_geo_soave_uga_colombara',
        'n_geo_soave_uga_duello',
        'n_geo_soave_uga_fitta',
        'n_geo_soave_uga_ronca_monte_calvarina',
      });
      expect(separatePoints, hasLength(4));
      final servedReference = legacyPoints.singleWhere(
        (point) => point['id'] == 'n_geo_soave_uga_brognoligo',
      );
      expect(servedReference['type'], 'Point');
      expect(servedReference['coordinates'], [11.29379, 45.44869]);
      final geonames = jsonDecode(
        File('tool/geography/soave_uga_geonames_points.geojson')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(geonames['features'] as List<dynamic>, hasLength(5));
      final reference = (geonames['features'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere(
            (f) => f['properties']['node'] == 'n_geo_soave_uga_brognoligo',
          );
      expect(reference['geometry']['type'], 'Point');
      expect(reference['geometry']['coordinates'], [11.29379, 45.44869]);
      expect(reference['properties']['geonames_id'], '8948888');
      expect(reference['properties']['license'], 'CC BY 4.0');
      final wikidata = jsonDecode(
        File('tool/geography/soave_uga_wikidata_points.geojson')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(
        (wikidata['features'] as List<dynamic>).any(
          (f) => f['properties']['node'] == 'n_geo_soave_uga_brognoligo',
        ),
        isFalse,
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
