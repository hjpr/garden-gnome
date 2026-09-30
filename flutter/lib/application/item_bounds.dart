import 'dart:math' as math;

import '../domain/geometry.dart';
import '../domain/vec.dart';

/// The bounding box (low, high corners) of one shape, circle, line or
/// point, or null when [itemId] is not in [geometry].
(Vec, Vec)? boundsOfItem(
  Geometry geometry,
  String itemId, {
  bool includeOpenShapes = true,
}) {
  if (geometry.shapes.containsKey(itemId) ||
      geometry.circles.containsKey(itemId)) {
    final region = geometry.regionOf(itemId);
    if (region != null) return region.bounds;
    if (!includeOpenShapes) return null;
    // Align can still act on the remaining points of an open shape.
    return unionBounds([
      for (final p in geometry.definingPoints([itemId]))
        (geometry.points[p]!, geometry.points[p]!),
    ]);
  }
  if (geometry.lines[itemId] case final line?) {
    return line.bounds(geometry.points);
  }
  if (geometry.points[itemId] case final point?) return (point, point);
  return null;
}

(Vec, Vec)? unionBounds(List<(Vec, Vec)> boxes) {
  if (boxes.isEmpty) return null;
  var low = boxes.first.$1, high = boxes.first.$2;
  for (final (l, h) in boxes.skip(1)) {
    low = Vec(math.min(low.x, l.x), math.min(low.y, l.y));
    high = Vec(math.max(high.x, h.x), math.max(high.y, h.y));
  }
  return (low, high);
}
