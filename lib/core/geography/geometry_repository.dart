import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:drift/drift.dart';

import '../curriculum/knowledge_graph.dart';
import '../database/app_database.dart';

/// A rectangle of longitudes and latitudes.
final class GeoBox {
  const GeoBox(this.minLon, this.minLat, this.maxLon, this.maxLat);

  GeoBox.of(NodeGeometry geometry)
    : this(geometry.minLon, geometry.minLat, geometry.maxLon, geometry.maxLat);

  final double minLon;
  final double minLat;
  final double maxLon;
  final double maxLat;

  double get width => maxLon - minLon;
  double get height => maxLat - minLat;

  /// This box grown by [fraction] of its width and height on every side,
  /// kept on the globe.
  GeoBox expand(double fraction) => GeoBox(
    math.max(-180, minLon - width * fraction),
    math.max(-90, minLat - height * fraction),
    math.min(180, maxLon + width * fraction),
    math.min(90, maxLat + height * fraction),
  );

  bool contains(double lon, double lat) =>
      lon >= minLon && lon <= maxLon && lat >= minLat && lat <= maxLat;

  @override
  bool operator ==(Object other) =>
      other is GeoBox &&
      other.minLon == minLon &&
      other.minLat == minLat &&
      other.maxLon == maxLon &&
      other.maxLat == maxLat;

  @override
  int get hashCode => Object.hash(minLon, minLat, maxLon, maxLat);

  @override
  String toString() => 'GeoBox($minLon, $minLat, $maxLon, $maxLat)';
}

/// A node drawn on a map: the node, and its geometry in one layer.
final class MappedNode {
  const MappedNode(this.node, this.geometry);

  final KnowledgeNode node;
  final NodeGeometry geometry;

  String get id => node.id;

  @override
  String toString() => '${node.id} in ${geometry.mapLayerId}';
}

/// A map layer with its sources, in the order its attribution names them
/// (GEO-21, GEO-22).
final class LayerWithSources {
  const LayerWithSources(this.layer, this.sources);

  final MapLayer layer;
  final List<SourceCitation> sources;

  /// The layer's attribution, composed from its sources, each text once
  /// (GEO-14, GEO-22).
  String get attribution =>
      {for (final source in sources) ?source.attributionText}.join(' ');
}

/// The map a question about a node is framed on (geography §5): the area of
/// an ancestor, grown by a margin, and the candidates drawn in it.
final class MapFrame {
  const MapFrame({
    required this.parent,
    required this.box,
    required this.candidates,
  });

  /// The ancestor whose area frames the map.
  final MappedNode parent;

  final GeoBox box;

  /// The nodes of the question's node type drawn in [box], the question's
  /// node among them, by name.
  final List<MappedNode> candidates;
}

/// The queries of the map formats (backlog G2): which nodes are drawn where,
/// the frame of a question, and its candidates.
///
/// Geometry stays in the layer assets; the database holds each drawn node's
/// feature, bounding box and label point (geography §3). Containment follows
/// the `LOCATED_IN` relations in force (GEO-6).
class GeometryRepository {
  GeometryRepository(this.db, {Clock? clock})
    : _graph = KnowledgeGraph(db, clock: clock);

  final AppDatabase db;
  final KnowledgeGraph _graph;

  /// The frame's margin, as a share of the framing area's size on each side.
  static const frameMargin = 0.1;

  /// A map question needs at least this many candidates, or its frame moves
  /// up a level, as an MCQ needs three wrong options (geography §5, QG-6).
  static const minimumCandidates = 4;

  /// Every map layer, the coarsest first, with its sources.
  Future<List<LayerWithSources>> layers() async {
    final layers =
        await (db.select(db.mapLayers)..orderBy([
              (l) => OrderingTerm(expression: l.minZoom),
              (l) => OrderingTerm(expression: l.id),
            ]))
            .get();
    final cited =
        await (db.select(db.mapLayerCitations).join([
              innerJoin(
                db.sourceCitations,
                db.sourceCitations.id.equalsExp(
                  db.mapLayerCitations.sourceCitationId,
                ),
              ),
            ])..orderBy([
              OrderingTerm(expression: db.mapLayerCitations.position),
            ]))
            .get();
    return [
      for (final layer in layers)
        LayerWithSources(layer, [
          for (final row in cited)
            if (row.readTable(db.mapLayerCitations).mapLayerId == layer.id)
              row.readTable(db.sourceCitations),
        ]),
    ];
  }

  /// [nodeId] in each layer that draws it, the coarsest layer first.
  Future<List<MappedNode>> geometriesOf(String nodeId) =>
      _mapped('g.knowledge_node_id = ?1', [Variable(nodeId)]);

  /// The nodes of [nodeType] whose label point lies in [box], by name, each
  /// once: a node drawn in several layers counts in its coarsest.
  Future<List<MappedNode>> candidatesIn(
    GeoBox box, {
    required String nodeType,
  }) async => _once(
    await _mapped(
      'n.node_type = ?1 AND g.label_lon BETWEEN ?2 AND ?3 '
      'AND g.label_lat BETWEEN ?4 AND ?5',
      [
        Variable(nodeType),
        Variable(box.minLon),
        Variable(box.maxLon),
        Variable(box.minLat),
        Variable(box.maxLat),
      ],
    ),
  );

  /// [mapped] with each node once, in its first, coarsest, layer.
  static List<MappedNode> _once(List<MappedNode> mapped) {
    final seen = <String>{};
    return [
      for (final node in mapped)
        if (seen.add(node.id)) node,
    ];
  }

  /// The drawn nodes of [nodeId]'s type that share one of its parents.
  Future<List<MappedNode>> siblingsOf(String nodeId) async {
    final siblings = {for (final s in await _graph.siblings(nodeId)) s.id};
    if (siblings.isEmpty) return const [];
    final ids = siblings.toList();
    return _once(
      await _mapped('g.knowledge_node_id IN (${_marks(ids.length)})', [
        for (final id in ids) Variable(id),
      ]),
    );
  }

  /// The frame of a map question about [nodeId]: its nearest ancestor that
  /// is drawn and whose area, grown by [frameMargin], holds at least
  /// [minimum] candidates of the node's type, the node among them. Null when
  /// the node is not drawn, or no ancestor frames it (geography §5).
  Future<MapFrame?> frameOf(
    String nodeId, {
    int minimum = minimumCandidates,
  }) async {
    final drawn = await geometriesOf(nodeId);
    if (drawn.isEmpty) return null;
    final nodeType = drawn.first.node.nodeType;
    for (final ancestor in await _graph.ancestors(nodeId)) {
      final framing = await geometriesOf(ancestor.id);
      if (framing.isEmpty) continue;
      final box = GeoBox.of(framing.first.geometry).expand(frameMargin);
      final candidates = await candidatesIn(box, nodeType: nodeType);
      if (candidates.length >= minimum &&
          candidates.any((c) => c.id == nodeId)) {
        return MapFrame(
          parent: framing.first,
          box: box,
          candidates: candidates,
        );
      }
    }
    return null;
  }

  Future<List<MappedNode>> _mapped(
    String where,
    List<Variable> variables,
  ) async {
    final rows = await db
        .customSelect(
          '''
      SELECT n.*, g.map_layer_id, g.feature_key, g.min_lon, g.min_lat,
             g.max_lon, g.max_lat, g.label_lon, g.label_lat
      FROM node_geometries g
      JOIN knowledge_nodes n ON n.id = g.knowledge_node_id
      JOIN map_layers l ON l.id = g.map_layer_id
      WHERE $where
      ORDER BY n.name, l.min_zoom, l.id''',
          variables: variables,
          readsFrom: {db.nodeGeometries, db.knowledgeNodes, db.mapLayers},
        )
        .get();
    return [
      for (final row in rows)
        MappedNode(
          db.knowledgeNodes.map(row.data),
          NodeGeometry(
            knowledgeNodeId: row.read<String>('id'),
            mapLayerId: row.read<String>('map_layer_id'),
            featureKey: row.read<String>('feature_key'),
            minLon: row.read<double>('min_lon'),
            minLat: row.read<double>('min_lat'),
            maxLon: row.read<double>('max_lon'),
            maxLat: row.read<double>('max_lat'),
            labelLon: row.read<double>('label_lon'),
            labelLat: row.read<double>('label_lat'),
          ),
        ),
    ];
  }

  static String _marks(int count) => List.filled(count, '?').join(', ');
}
