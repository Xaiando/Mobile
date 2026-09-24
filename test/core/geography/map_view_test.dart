import 'package:flutter_test/flutter_test.dart';
import 'package:sommelier/core/geography/coordinates.dart';
import 'package:sommelier/core/geography/map_view.dart';
import 'package:sommelier/core/geography/web_mercator.dart';

void main() {
  group('frame fitting', () {
    const wide = WorldRect(0.2, 0.3, 0.6, 0.4); // 0.4 × 0.1

    test('shows the frame whole, centred', () {
      final view = MapView.fit(wide, width: 800, height: 600);
      expect(view.scale, closeTo(2000, 1e-9), reason: 'the width: 800 / 0.4');
      final visible = view.visibleRect(800, 600);
      expect(visible.containsRect(wide, tolerance: 1e-12), isTrue);
      expect(visible.center.x, closeTo(wide.center.x, 1e-12));
      expect(visible.center.y, closeTo(wide.center.y, 1e-12));
      expect(visible.left, closeTo(wide.left, 1e-12));
    });

    test('the tighter axis sets the scale', () {
      final view = MapView.fit(wide, width: 800, height: 100);
      expect(view.scale, closeTo(1000, 1e-9), reason: '100 / 0.1');
    });

    test('keeps the frame inside the padding', () {
      final view = MapView.fit(wide, width: 800, height: 600, padding: 40);
      expect(view.scale, closeTo(720 / 0.4, 1e-9));
      expect(view.screenX(wide.left), closeTo(40, 1e-9));
      expect(view.screenX(wide.right), closeTo(760, 1e-9));
    });

    test('a point frame does not divide by zero', () {
      final view = MapView.fit(
        const WorldRect(0.5, 0.5, 0.5, 0.5),
        width: 400,
        height: 400,
      );
      expect(view.scale.isFinite, isTrue);
      expect(view.screenX(0.5), closeTo(200, 1e-6));
    });

    test('the zoom of a view is its Web Mercator zoom', () {
      expect(const MapView(scale: 256 * 1024).zoom, closeTo(10, 1e-12));
      final burgundy = MapView.fit(
        WebMercator.projectBounds(
          GeoBounds(minLon: 3.3, minLat: 46.1, maxLon: 5.3, maxLat: 48.1),
        ),
        width: 400,
        height: 700,
      );
      // 2° of longitude across 400 pixels: 72,000 pixels per world width.
      expect(burgundy.zoom, closeTo(8.136, 0.001));
    });
  });

  group('limits', () {
    final limits = MapViewLimits(
      bounds: const WorldRect(0.4, 0.3, 0.6, 0.45),
      minScale: 4000,
      maxScale: 64000,
    );

    test('a view inside the limits is unchanged', () {
      const view = MapView(scale: 8000, dx: -3600, dy: -2600);
      expect(limits.allows(view, width: 400, height: 300), isTrue);
      final clamped = view.clamp(limits, width: 400, height: 300);
      expect(clamped.scale, 8000);
      expect(clamped.dx, closeTo(view.dx, 1e-9));
      expect(clamped.dy, closeTo(view.dy, 1e-9));
    });

    test('panning stops at the bounds', () {
      // Far to the east of the bounds.
      const view = MapView(scale: 8000, dx: -9000, dy: -2600);
      expect(limits.allows(view, width: 400, height: 300), isFalse);
      final clamped = view.clamp(limits, width: 400, height: 300);
      expect(limits.allows(clamped, width: 400, height: 300), isTrue);
      expect(clamped.visibleRect(400, 300).right, closeTo(0.6, 1e-12));
      expect(clamped.scale, 8000);
      expect(clamped.dy, closeTo(view.dy, 1e-9));
    });

    test('zoom stays between the minimum and maximum scale', () {
      const tooClose = MapView(scale: 1e6, dx: -500000, dy: -350000);
      final inward = tooClose.clamp(limits, width: 400, height: 300);
      expect(inward.scale, 64000);
      expect(limits.allows(inward, width: 400, height: 300), isTrue);
      // The clamp keeps the point at the viewport's centre where it was.
      final before = tooClose.toWorld(200, 150);
      final after = inward.toWorld(200, 150);
      expect(after.x, closeTo(before.x, 1e-12));
      expect(after.y, closeTo(before.y, 1e-12));

      const tooFar = MapView(scale: 100, dx: 0, dy: 0);
      final outward = tooFar.clamp(limits, width: 400, height: 300);
      expect(outward.scale, 4000);
      expect(limits.allows(outward, width: 400, height: 300), isTrue);
    });

    test('bounds smaller than the viewport are centred', () {
      // At the minimum scale the bounds are 800 × 600 pixels; the viewport
      // is larger than that in both directions.
      final view = const MapView(
        scale: 4000,
        dx: 0,
        dy: 0,
      ).clamp(limits, width: 1000, height: 900);
      final visible = view.visibleRect(1000, 900);
      expect(visible.center.x, closeTo(0.5, 1e-12));
      expect(visible.center.y, closeTo(0.375, 1e-12));
      expect(limits.allows(view, width: 1000, height: 900), isTrue);
    });

    test('rejects an empty scale range', () {
      expect(
        () => MapViewLimits(
          bounds: const WorldRect(0, 0, 1, 1),
          minScale: 2,
          maxScale: 1,
        ),
        throwsArgumentError,
      );
    });
  });
}
