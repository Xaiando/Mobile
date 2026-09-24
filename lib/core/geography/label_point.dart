import 'dart:math' as math;
import 'dart:typed_data';

import 'coordinates.dart';
import 'planar.dart';

/// The point of [polygon] farthest from its outline, within [precision]
/// world units: its pole of inaccessibility. It is the label point of an
/// area whose centroid falls outside it, when the manifest gives none
/// (geography §3, §5).
///
/// A quadtree search: cells covering the polygon are split, best bound
/// first, until no cell can hold a point farther inside than the best found
/// by more than [precision]. The centroid of a concave shape, or of a ring
/// around a hole, can fall outside it; this point never does.
WorldPoint poleOfInaccessibility(
  List<Float64List> polygon, {
  double? precision,
  int maxCells = 4096,
}) {
  final bounds = boundsOf([polygon.first]);
  final cellSize = math.min(bounds.width, bounds.height);
  if (cellSize <= 0) return WorldPoint(bounds.left, bounds.top);
  final tolerance = precision ?? math.max(bounds.width, bounds.height) / 1000;

  final queue = _CellQueue();
  final half = cellSize / 2;
  for (var x = bounds.left; x < bounds.right; x += cellSize) {
    for (var y = bounds.top; y < bounds.bottom; y += cellSize) {
      queue.add(_Cell(x + half, y + half, half, polygon));
    }
  }

  var best = _centroidCell(polygon);
  final centre = _Cell(
    bounds.left + bounds.width / 2,
    bounds.top + bounds.height / 2,
    0,
    polygon,
  );
  if (centre.distance > best.distance) best = centre;

  var cells = 0;
  while (queue.isNotEmpty && cells++ < maxCells) {
    final cell = queue.removeFirst();
    if (cell.distance > best.distance) best = cell;
    if (cell.bound - best.distance <= tolerance) continue;
    final h = cell.half / 2;
    queue
      ..add(_Cell(cell.x - h, cell.y - h, h, polygon))
      ..add(_Cell(cell.x + h, cell.y - h, h, polygon))
      ..add(_Cell(cell.x - h, cell.y + h, h, polygon))
      ..add(_Cell(cell.x + h, cell.y + h, h, polygon));
  }
  return WorldPoint(best.x, best.y);
}

/// A square cell of the search, centred on ([x], [y]).
final class _Cell {
  _Cell(this.x, this.y, this.half, List<Float64List> polygon)
    : distance = _signedDistance(x, y, polygon) {
    bound = distance + half * math.sqrt2;
  }

  final double x;
  final double y;
  final double half;

  /// Distance to the outline; negative outside the polygon.
  final double distance;

  /// The farthest any point of the cell can be from the outline.
  late final double bound;
}

double _signedDistance(double x, double y, List<Float64List> polygon) {
  final d = outlineDistance([polygon], x, y);
  return polygonContains(polygon, x, y) ? d : -d;
}

/// A cell at the exterior ring's centroid, a good first guess.
_Cell _centroidCell(List<Float64List> polygon) {
  final ring = polygon.first;
  final centroid = ringCentroid(ring) ?? WorldPoint(ring[0], ring[1]);
  return _Cell(centroid.x, centroid.y, 0, polygon);
}

/// A binary max-heap of cells by [_Cell.bound].
final class _CellQueue {
  final _cells = <_Cell>[];

  bool get isNotEmpty => _cells.isNotEmpty;

  void add(_Cell cell) {
    _cells.add(cell);
    var i = _cells.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_cells[parent].bound >= cell.bound) break;
      _cells[i] = _cells[parent];
      i = parent;
    }
    _cells[i] = cell;
  }

  _Cell removeFirst() {
    final first = _cells.first;
    final last = _cells.removeLast();
    if (_cells.isNotEmpty) {
      var i = 0;
      final n = _cells.length;
      while (true) {
        var child = 2 * i + 1;
        if (child >= n) break;
        if (child + 1 < n && _cells[child + 1].bound > _cells[child].bound) {
          child++;
        }
        if (_cells[child].bound <= last.bound) break;
        _cells[i] = _cells[child];
        i = child;
      }
      _cells[i] = last;
    }
    return first;
  }
}
