import 'dart:math' as math;

import '../domain/curve_edge.dart';
import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/planar.dart';
import '../domain/region.dart';
import '../domain/vec.dart';

/// Which items a marquee or lasso outline picks, found by what the
/// outline touches.
///
/// An item counts as soon as any part of its drawn outline (or the point
/// itself) is inside the area or crosses its edge: it need not be wholly
/// inside. Shapes and circles are picked whole; lines and points are
/// picked on their own only when they are not part of a shape, since the
/// shape already stands for them.

/// The items of [geometry] touched by the closed [outline] (world metres,
/// in order; the last point joins back to the first).
Set<String> itemsTouched(Geometry geometry, List<Vec> outline) {
  final area = _Area.of(outline);
  if (area == null) return const {};
  final result = <String>{};

  final shapeLines = <String>{};
  for (final shape in geometry.shapes.values) {
    final members = [
      for (final ring in shape.rings)
        for (final ref in ring) ref.segmentId,
    ];
    shapeLines.addAll(members);
    final edges = [
      for (final id in members)
        if (geometry.lines[id] case final line?)
          if (geometry.points.containsKey(line.start) &&
              geometry.points.containsKey(line.end))
            ...line.edges(geometry.points),
    ];
    if (edges.any(area.touches)) result.add(shape.id);
  }

  for (final circle in geometry.circles.values) {
    final centre = geometry.points[circle.center];
    if (centre == null) continue;
    final rim = DiscRegion(centre, circle.radius).contours.expand((c) => c);
    if (rim.any(area.touches)) result.add(circle.id);
  }

  final anchored = <String>{};
  for (final line in geometry.lines.values) {
    anchored.addAll([line.start, line.end]);
    if (shapeLines.contains(line.id)) continue;
    if (line.edges(geometry.points).any(area.touches)) result.add(line.id);
  }
  for (final circle in geometry.circles.values) {
    anchored.add(circle.center);
  }

  geometry.points.forEach((id, position) {
    if (!anchored.contains(id) && area.holds(position)) result.add(id);
  });
  return result;
}

/// The touched items on every layer [include] allows, by layer. Layers
/// with nothing touched are left out.
Map<String, Set<String>> itemsTouchedAcrossLayers(
  GardenDocument document,
  List<Vec> outline, {
  required bool Function(String layerId) include,
}) => {
  for (final layerId in document.drawingOrder)
    if (include(layerId))
      if (itemsTouched(document.geometryOf(layerId), outline) case final items
          when items.isNotEmpty)
        layerId: items,
};

/// The four corners of the rectangle with opposite corners [a] and [b].
List<Vec> rectangleOutline(Vec a, Vec b) => [
  a,
  Vec(b.x, a.y),
  b,
  Vec(a.x, b.y),
];

/// A closed outline with its bounding box, for quick touch tests.
class _Area {
  _Area(this.polygon, this.low, this.high);

  /// Null when the outline has no area to speak of (fewer than three
  /// distinct corners).
  static _Area? of(List<Vec> outline) {
    final polygon = <Vec>[];
    for (final p in outline) {
      if (polygon.isEmpty || polygon.last.distanceTo(p) > tolerance) {
        polygon.add(p);
      }
    }
    while (polygon.length > 1 &&
        polygon.first.distanceTo(polygon.last) <= tolerance) {
      polygon.removeLast();
    }
    if (polygon.length < 3) return null;
    var low = polygon.first, high = polygon.first;
    for (final p in polygon) {
      low = Vec(math.min(low.x, p.x), math.min(low.y, p.y));
      high = Vec(math.max(high.x, p.x), math.max(high.y, p.y));
    }
    return _Area(polygon, low, high);
  }

  final List<Vec> polygon;
  final Vec low;
  final Vec high;

  bool holds(Vec p) => locatePoint(p, polygon) != PointLocation.outside;

  /// Whether [edge] lies partly inside the area or crosses its outline.
  bool touches(CurveEdge edge) {
    final (a, b) = edge.bounds;
    if (b.x < low.x || a.x > high.x || b.y < low.y || a.y > high.y) {
      return false;
    }
    if (holds(edge.start) || holds(edge.end)) return true;
    for (var i = 0; i < polygon.length; i++) {
      final side = CurveEdge(polygon[i], polygon[(i + 1) % polygon.length]);
      if (intersections(edge, side).isNotEmpty) return true;
    }
    return false;
  }
}
