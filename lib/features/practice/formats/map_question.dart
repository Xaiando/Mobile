import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/startup.dart';
import '../../../core/curriculum/curriculum_providers.dart';
import '../../../core/geography/coordinates.dart';
import '../../../core/geography/geo_layer.dart';
import '../../../core/geography/geography_providers.dart';
import '../../../core/geography/geometry_repository.dart';
import '../../../core/geography/hit_test.dart';
import '../../../core/geography/topojson.dart';
import '../../../core/questions/formats/map/map_exercise.dart';
import '../../map/map_canvas.dart';
import '../../map/map_presentation.dart';

/// The layers drawn in every mode: coastlines, national borders and major
/// rivers (geography §4).
const baseLayerIds = {
  'ml_world_coastline',
  'ml_world_countries',
  'ml_world_rivers',
};

/// Every map layer, read from the bundle and decoded once, bottom first
/// (geography §8).
///
/// A layer whose asset is missing, or does not match the SHA-256 the
/// database holds, is left off the map. That happens after an app
/// downgrade, which keeps the newer curriculum it finds (GEO-30).
final mapLayersProvider = FutureProvider<List<MapLayer>>((ref) async {
  await ref.watch(appStartupProvider.future);
  final maps = ref.watch(geometryRepositoryProvider);
  final layers = <MapLayer>[];
  for (final entry in await maps.layers()) {
    if (await _load(maps, entry) case final layer?) layers.add(layer);
  }
  return layers;
});

Future<MapLayer?> _load(GeometryRepository maps, LayerWithSources entry) async {
  final layer = entry.layer;
  final Topology topology;
  try {
    final bytes = await readBundledAsset(layer.assetPath);
    if ('${sha256.convert(bytes)}' != layer.assetSha256) return null;
    topology = Topology.parse(utf8.decode(bytes));
  } on Object {
    return null;
  }
  final labels = await maps.labelPointsIn(layer.id);
  final geometry = GeoLayer.fromTopology(
    topology,
    id: layer.id,
    minZoom: layer.minZoom,
    maxZoom: layer.maxZoom,
    attribution: entry.attribution,
    labelPoints: {
      for (final MapEntry(:key, :value) in labels.entries)
        key: LonLat(value.lon, value.lat),
    },
  );
  return baseLayerIds.contains(layer.id)
      ? MapLayer.base(geometry)
      : MapLayer(geometry);
}

/// The layers of a question whose candidates are in [candidateLayerId]: the
/// same layers, with that one drawn at every zoom (geography §5). The list
/// is kept, so the map's picture cache is too.
final questionLayersProvider = FutureProvider.family<List<MapLayer>, String>((
  ref,
  candidateLayerId,
) async {
  final layers = await ref.watch(mapLayersProvider.future);
  return [
    for (final layer in layers)
      layer.geometry.id == candidateLayerId
          ? MapLayer(layer.geometry.drawnFrom(0))
          : layer,
  ];
});

GeoBounds boundsOf(GeoBox box) => GeoBounds(
  minLon: box.minLon,
  minLat: box.minLat,
  maxLon: box.maxLon,
  maxLat: box.maxLat,
);

MapLabelMode labelModeOf(MapMode mode) => switch (mode) {
  MapMode.labelled => MapLabelMode.labelled,
  MapMode.outline => MapLabelMode.outline,
  MapMode.minimal => MapLabelMode.minimal,
  MapMode.blank => MapLabelMode.blank,
};

/// The map of a map question: its frame, its candidates and its mode.
class MapQuestionMap extends ConsumerWidget {
  const MapQuestionMap({
    super.key,
    required this.exercise,
    this.highlights = const {},
    this.revealed = false,
    this.onTap,
  });

  final MapExercise exercise;
  final Map<String, MapHighlight> highlights;
  final bool revealed;
  final ValueChanged<MapTap>? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final zoomedOut = exercise.zoomedOut;
    final candidateLayer = exercise.frame.candidates.first.geometry.mapLayerId;
    final layers = ref.watch(questionLayersProvider(candidateLayer));
    final missing =
        layers.value?.every((l) => l.geometry.id != candidateLayer) ?? false;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: switch (layers) {
          AsyncData() when missing => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'This version of the app cannot draw this map. Answer from '
                'the list instead.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ),
          AsyncData(value: final layers) => MapCanvas(
            layers: layers,
            mode: labelModeOf(exercise.mode),
            candidates: exercise.candidateIds,
            parent: exercise.frame.parent.id,
            highlights: highlights,
            revealed: revealed,
            names: exercise.names,
            frame: boundsOf(exercise.frame.box),
            zoomedOutFrame: zoomedOut == null ? null : boundsOf(zoomedOut),
            onTap: onTap,
          ),
          AsyncError(:final error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('The map could not be loaded: $error'),
            ),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

/// What a map question's answer was, and the fact it practises.
class MapFeedback extends StatelessWidget {
  const MapFeedback({
    super.key,
    required this.exercise,
    required this.correct,
    required this.chosen,
  });

  final MapExercise exercise;
  final bool correct;

  /// The area the learner chose, if it was a candidate.
  final String? chosen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = exercise.nodeName;
    final heading = correct
        ? 'Correct: $name'
        : switch (exercise.names[chosen]) {
            final other? => 'That is $other. $name is marked.',
            null => 'Not there. $name is marked.',
          };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  correct ? Icons.check_circle : Icons.cancel,
                  color: correct
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(heading, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(exercise.explanation, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
