import 'dart:math' as math;
import 'dart:typed_data';

import 'planar.dart';

/// Level of detail (geography §8): the renderer caches one picture per layer
/// and zoom bucket, drawn from arcs simplified for that bucket.
///
/// A bucket is a quarter of a zoom level. Within it a cached picture is
/// drawn at up to 2^¼ times the scale it was simplified for, so outlines
/// stay within [tolerancePixels] · 2^¼ logical pixels of their true course.
/// Hit tests always use the full geometry (geography §4).
abstract final class LevelOfDetail {
  static const bucketsPerZoomLevel = 4;

  /// The simplification error allowed on screen, in logical pixels.
  static const tolerancePixels = 0.5;

  /// The bucket for a view of [pixelsPerWorld] logical pixels per world unit.
  static int bucketOf(double pixelsPerWorld) =>
      (math.log(pixelsPerWorld) / math.ln2 * bucketsPerZoomLevel).floor();

  /// The smallest scale in [bucket], in logical pixels per world unit.
  static double scaleOf(int bucket) =>
      math.pow(2, bucket / bucketsPerZoomLevel).toDouble();

  /// The simplification tolerance of [bucket], in world units.
  static double toleranceOf(int bucket) => tolerancePixels / scaleOf(bucket);
}

/// Douglas–Peucker ranks for the points of one arc, `[x0, y0, x1, y1, …]`.
///
/// Simplifying with tolerance t keeps exactly the points ranked above t
/// ([simplifyArc]); the endpoints rank infinitely high. A point's rank is
/// its distance from the chord that Douglas–Peucker splits at it, capped by
/// the rank of the split that exposed that chord, so ranks never grow down
/// the recursion and one threshold reproduces the algorithm at any
/// tolerance. Arcs are ranked, not rings: a border shared by two features is
/// simplified once and stays shared.
Float64List simplificationRanks(Float64List arc) {
  final n = arc.length ~/ 2;
  final ranks = Float64List(n);
  if (n == 0) return ranks;
  ranks[0] = double.infinity;
  ranks[n - 1] = double.infinity;
  // Chords still to split: (first point, last point, cap).
  final stack = <(int, int, double)>[(0, n - 1, double.infinity)];
  while (stack.isNotEmpty) {
    final (first, last, cap) = stack.removeLast();
    if (last - first < 2) continue;
    final ax = arc[2 * first], ay = arc[2 * first + 1];
    final bx = arc[2 * last], by = arc[2 * last + 1];
    var farthest = first + 1;
    var farthestSquared = -1.0;
    for (var i = first + 1; i < last; i++) {
      final d = segmentDistanceSquared(
        arc[2 * i],
        arc[2 * i + 1],
        ax,
        ay,
        bx,
        by,
      );
      if (d > farthestSquared) {
        farthestSquared = d;
        farthest = i;
      }
    }
    final rank = math.min(math.sqrt(farthestSquared), cap);
    ranks[farthest] = rank;
    stack
      ..add((first, farthest, rank))
      ..add((farthest, last, rank));
  }
  return ranks;
}

/// The points of [arc] ranked above [tolerance]: its Douglas–Peucker
/// simplification. A tolerance of 0 drops only points lying exactly on the
/// chord between the points kept around them.
Float64List simplifyArc(Float64List arc, Float64List ranks, double tolerance) {
  var kept = 0;
  for (final rank in ranks) {
    if (rank > tolerance) kept++;
  }
  if (kept == ranks.length) return arc;
  final out = Float64List(kept * 2);
  var o = 0;
  for (var i = 0; i < ranks.length; i++) {
    if (ranks[i] > tolerance) {
      out[o++] = arc[2 * i];
      out[o++] = arc[2 * i + 1];
    }
  }
  return out;
}
