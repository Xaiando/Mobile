import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/geo_layer.dart';
import 'package:sommelier/core/geography/level_of_detail.dart';
import 'package:sommelier/core/geography/planar.dart';
import 'package:sommelier/core/geography/topojson.dart';

import '../../support/geography_fixture.dart';

/// A wavy line of [n] points, deterministic for [seed].
Float64List wavyArc(int n, {int seed = 1}) {
  final random = math.Random(seed);
  var y = 0.0;
  return Float64List.fromList([
    for (var i = 0; i < n; i++) ...[
      i.toDouble(),
      y += random.nextDouble() * 2 - 1,
    ],
  ]);
}

/// Classic recursive Douglas–Peucker: the indices it keeps at [tolerance].
Set<int> referenceDouglasPeucker(Float64List arc, double tolerance) {
  final kept = <int>{0, arc.length ~/ 2 - 1};
  void split(int first, int last) {
    var farthest = -1;
    var distance = -1.0;
    for (var i = first + 1; i < last; i++) {
      final d = math.sqrt(
        segmentDistanceSquared(
          arc[2 * i],
          arc[2 * i + 1],
          arc[2 * first],
          arc[2 * first + 1],
          arc[2 * last],
          arc[2 * last + 1],
        ),
      );
      if (d > distance) {
        distance = d;
        farthest = i;
      }
    }
    if (farthest < 0 || distance <= tolerance) return;
    kept.add(farthest);
    split(first, farthest);
    split(farthest, last);
  }

  split(0, arc.length ~/ 2 - 1);
  return kept;
}

List<(double, double)> pairs(Float64List coordinates) => [
  for (var i = 0; i < coordinates.length; i += 2)
    (coordinates[i], coordinates[i + 1]),
];

void main() {
  group('zoom buckets', () {
    test('four buckets per zoom level', () {
      for (var bucket = -8; bucket <= 80; bucket++) {
        final scale = LevelOfDetail.scaleOf(bucket);
        expect(LevelOfDetail.bucketOf(scale * 1.1), bucket);
        expect(
          LevelOfDetail.scaleOf(bucket + 4),
          closeTo(scale * 2, scale * 1e-12),
        );
      }
    });

    test('the tolerance is half a logical pixel at the bucket scale', () {
      for (final bucket in [0, 20, 40, 60]) {
        expect(
          LevelOfDetail.toleranceOf(bucket) * LevelOfDetail.scaleOf(bucket),
          closeTo(LevelOfDetail.tolerancePixels, 1e-12),
        );
      }
    });
  });

  group('Douglas–Peucker ranks', () {
    final arc = wavyArc(400);
    final ranks = simplificationRanks(arc);

    test('keep the endpoints at any tolerance', () {
      expect(ranks.first, double.infinity);
      expect(ranks.last, double.infinity);
      expect(pairs(simplifyArc(arc, ranks, 1e9)), [
        pairs(arc).first,
        pairs(arc).last,
      ]);
    });

    test('keep every point at tolerance 0', () {
      expect(simplifyArc(arc, ranks, 0), same(arc));
    });

    test('reproduce Douglas–Peucker at every tolerance', () {
      for (final tolerance in [0.05, 0.2, 0.5, 1.0, 2.0, 5.0]) {
        final kept = {
          for (var i = 0; i < ranks.length; i++)
            if (ranks[i] > tolerance) i,
        };
        expect(
          kept,
          referenceDouglasPeucker(arc, tolerance),
          reason: '$tolerance',
        );
      }
    });

    test('drop fewer points as the tolerance shrinks', () {
      var previous = 0;
      for (final tolerance in [8.0, 4.0, 2.0, 1.0, 0.5, 0.25, 0.1]) {
        final points = simplifyArc(arc, ranks, tolerance).length;
        expect(points, greaterThanOrEqualTo(previous));
        previous = points;
      }
      expect(previous, lessThan(arc.length));
    });

    test('stay within the tolerance of the full line', () {
      for (final tolerance in [0.1, 0.5, 2.0]) {
        final simplified = simplifyArc(arc, ranks, tolerance);
        for (var i = 0; i < arc.length; i += 2) {
          expect(
            lineDistance(simplified, arc[i], arc[i + 1]),
            lessThanOrEqualTo(tolerance + 1e-9),
          );
        }
      }
    });

    test('handle closed arcs and degenerate input', () {
      final loop = Float64List.fromList([0, 0, 4, 0, 4, 4, 0, 4, 0, 0]);
      final loopRanks = simplificationRanks(loop);
      expect(loopRanks[2], closeTo(math.sqrt(32), 1e-12));
      expect(simplifyArc(loop, loopRanks, 1).length, loop.length);
      expect(simplificationRanks(Float64List(0)), isEmpty);
      expect(simplificationRanks(Float64List.fromList([1, 2])), [
        double.infinity,
      ]);
    });
  });

  group('layer level of detail', () {
    test('neighbours keep the same simplified border at every bucket', () {
      final layer = GeoLayer.fromTopology(
        Topology.parse(stressTopoJson()),
        id: 'stress',
      );
      final below = layer.shapeFor('n_stress_3_4')!;
      final above = layer.shapeFor('n_stress_3_5')!;
      final full = pairs(below.polygons.single.single)
          .toSet()
          .intersection(pairs(above.polygons.single.single).toSet());
      expect(full.length, 32, reason: 'the shared wavy border');
      for (var bucket = 40; bucket <= 90; bucket += 3) {
        final a = pairs(below.polygonsAt(bucket).single.single).toSet();
        final b = pairs(above.polygonsAt(bucket).single.single).toSet();
        expect(
          a.intersection(full),
          b.intersection(full),
          reason: 'bucket $bucket',
        );
        expect(a.intersection(full).length, greaterThanOrEqualTo(2));
      }
    });

    test('simplifies more when zoomed out', () {
      final layer = GeoLayer.fromTopology(
        Topology.parse(stressTopoJson()),
        id: 'stress',
      );
      int points(int bucket) => layer.shapes.fold(
        0,
        (sum, shape) => sum + shape.polygonsAt(bucket).single.single.length,
      );
      final zoomedOut = points(LevelOfDetail.bucketOf(256 * 64));
      final zoomedIn = points(LevelOfDetail.bucketOf(256 * 8192));
      final full = layer.shapes.fold(
        0,
        (sum, shape) => sum + shape.polygons.single.single.length,
      );
      expect(zoomedOut, lessThan(zoomedIn));
      expect(zoomedIn, lessThanOrEqualTo(full));
      expect(zoomedOut, lessThan(full ~/ 4));
    });

    test('rings smaller than the tolerance drop out', () {
      final areas = FixtureLayers().areas;
      final tiny = areas.shapeFor('n_fx_tiny')!;
      final north = areas.shapeFor('n_fx_north')!;
      final zoom0 = LevelOfDetail.bucketOf(256);
      final zoom3 = LevelOfDetail.bucketOf(256 * 8);
      final zoom12 = LevelOfDetail.bucketOf(256 * 4096);
      // Tiny Clos, 0.01° across, collapses below zoom 3.
      expect(tiny.polygonsAt(zoom3), isEmpty);
      expect(tiny.polygonsAt(zoom12).single.single.length, 10);
      // At zoom 0 North's 0.2° hole collapses, but North, 1° across, stays.
      expect(north.polygonsAt(zoom0).single, hasLength(1));
      expect(north.polygonsAt(zoom3).single, hasLength(2));
      expect(north.polygonsAt(zoom12).single, hasLength(2));
    });
  });
}
