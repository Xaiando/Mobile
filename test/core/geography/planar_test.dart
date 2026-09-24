import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/label_point.dart';
import 'package:sommelier/core/geography/planar.dart';

/// A closed ring through [points].
Float64List ring(List<(double, double)> points) => Float64List.fromList([
  for (final (x, y) in [...points, points.first]) ...[x, y],
]);

Float64List square(double left, double top, double size) => ring([
  (left, top),
  (left + size, top),
  (left + size, top + size),
  (left, top + size),
]);

void main() {
  // A 10 × 10 square with a 4 × 4 hole in the middle.
  final framed = [square(0, 0, 10), square(3, 3, 4)];
  // Two separate squares: a multipolygon.
  final pair = [
    [square(0, 0, 2)],
    [square(5, 5, 2)],
  ];

  group('point in polygon', () {
    test('inside and outside a simple ring', () {
      final s = square(0, 0, 10);
      expect(ringContains(s, 5, 5), isTrue);
      expect(ringContains(s, 0.001, 9.999), isTrue);
      expect(ringContains(s, -0.001, 5), isFalse);
      expect(ringContains(s, 5, 10.5), isFalse);
    });

    test('a concave ring: the notch is outside', () {
      // A U shape opening upwards.
      final u = ring([
        (0, 0),
        (9, 0),
        (9, 9),
        (6, 9),
        (6, 3),
        (3, 3),
        (3, 9),
        (0, 9),
      ]);
      expect(ringContains(u, 1.5, 6), isTrue);
      expect(ringContains(u, 4.5, 6), isFalse);
      expect(ringContains(u, 4.5, 1.5), isTrue);
    });

    test('a hole is outside its polygon', () {
      expect(polygonContains(framed, 1, 1), isTrue);
      expect(polygonContains(framed, 5, 5), isFalse, reason: 'in the hole');
      expect(polygonContains(framed, 8, 5), isTrue);
      expect(polygonContains(framed, 11, 5), isFalse);
    });

    test('holes count whatever their winding', () {
      final otherWay = [
        square(0, 0, 10),
        ring([(3, 3), (3, 7), (7, 7), (7, 3)]),
      ];
      expect(ringArea(otherWay[1]).sign, -ringArea(framed[1]).sign);
      expect(polygonContains(otherWay, 5, 5), isFalse);
      expect(polygonContains(otherWay, 1, 1), isTrue);
    });

    test('a multipolygon contains the points of each part', () {
      expect(polygonsContain(pair, 1, 1), isTrue);
      expect(polygonsContain(pair, 6, 6), isTrue);
      expect(
        polygonsContain(pair, 3.5, 3.5),
        isFalse,
        reason: 'between the parts',
      );
    });
  });

  group('distance to an outline', () {
    test('to a segment: perpendicular, or to the nearer end', () {
      expect(segmentDistanceSquared(5, 3, 0, 0, 10, 0), 9);
      expect(segmentDistanceSquared(-3, 4, 0, 0, 10, 0), 25);
      expect(segmentDistanceSquared(13, -4, 0, 0, 10, 0), 25);
      expect(segmentDistanceSquared(1, 1, 2, 2, 2, 2), 2, reason: 'a point');
    });

    test('from inside and outside a ring', () {
      final s = square(0, 0, 10);
      expect(lineDistance(s, 2, 5), 2);
      expect(lineDistance(s, 5, -3), 3);
      expect(lineDistance(s, 13, 14), 5, reason: 'to the corner');
    });

    test('a hole has an outline too', () {
      // Inside the hole, 1 from its edge and 4 from the exterior.
      expect(outlineDistance([framed], 4, 5), 1);
      expect(outlineDistance([framed], 1.5, 5), 1.5);
    });

    test('the nearest part of a multipolygon counts', () {
      expect(outlineDistance(pair, 4, 6), 1);
      expect(outlineDistance(pair, 3, 1), 1);
    });

    test('to a polyline and a lone point', () {
      final line = Float64List.fromList([0, 0, 10, 0, 10, 10]);
      expect(lineDistance(line, 5, 2), 2);
      expect(lineDistance(line, 12, 5), 2);
      expect(lineDistance(Float64List.fromList([3, 4]), 0, 0), 5);
    });
  });

  group('areas, bounds and label points', () {
    test('area of a polygon less its holes', () {
      expect(ringArea(square(0, 0, 10)).abs(), 100);
      expect(polygonArea(framed), 100 - 16);
    });

    test('bounds of rings', () {
      expect(boundsOf(pair.map((p) => p.first)), const WorldRect(0, 0, 7, 7));
    });

    test('a line midpoint is halfway along it', () {
      final line = Float64List.fromList([0, 0, 10, 0, 10, 10]);
      expect(lineLength(line), 20);
      expect(lineMidpoint(line), const WorldPoint(10, 0));
      expect(
        lineMidpoint(Float64List.fromList([0, 0, 4, 0])),
        const WorldPoint(2, 0),
      );
    });

    test('the label point of a concave shape lies inside it', () {
      final u = [
        ring([(0, 0), (9, 0), (9, 9), (6, 9), (6, 3), (3, 3), (3, 9), (0, 9)]),
      ];
      final p = poleOfInaccessibility(u);
      expect(polygonContains(u, p.x, p.y), isTrue);
      // The widest spot is where the base meets an arm, 3(2 − √2) from the
      // outline.
      expect(outlineDistance([u], p.x, p.y), closeTo(1.757, 0.02));
    });

    test('the label point avoids holes', () {
      final p = poleOfInaccessibility(framed);
      expect(polygonContains(framed, p.x, p.y), isTrue);
      // In a corner of the frame, clear of the hole's corner.
      expect(outlineDistance([framed], p.x, p.y), closeTo(1.757, 0.02));
    });

    test('the label point of a long rectangle is on its middle line', () {
      final p = poleOfInaccessibility([
        ring([(0, 0), (8, 0), (8, 2), (0, 2)]),
      ]);
      expect(p.y, closeTo(1, 0.01));
      expect(p.x, inInclusiveRange(0.9, 7.1));
    });
  });
}
