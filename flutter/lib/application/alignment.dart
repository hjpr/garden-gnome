import 'dart:math' as math;

import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/vec.dart';
import 'carried_land.dart';

/// Which side of the anchor the moved item lines up with.
enum AlignEdge {
  left('Left', 'align-left.svg'),
  right('Right', 'align-right.svg'),
  top('Top', 'align-top.svg'),
  bottom('Bottom', 'align-bottom.svg'),

  /// Centre on centre, in both directions.
  center('Center', 'align-center.svg');

  const AlignEdge(this.label, this.icon);

  final String label;
  final String icon;
}

/// The result of aligning one item to another: the would-be drawing and
/// the points that moved, by layer (for the dotted move preview).
typedef AlignResult = ({
  GardenDocument document,
  Map<String, Set<String>> moved,
});

/// Moves [movingId] so its bounds line up with [anchorId]'s along [edge].
/// Both items are on [layerId]. A whole property shape carries its zones'
/// shapes inside it along, as a drag does.
///
/// Throws [GeometryRuleError] with a readable reason when it cannot.
AlignResult alignItems(
  GardenDocument document,
  String layerId,
  String anchorId,
  String movingId,
  AlignEdge edge,
) {
  final geometry = document.geometryOf(layerId);
  final anchor = boundsOfItem(geometry, anchorId);
  final target = boundsOfItem(geometry, movingId);
  if (anchor == null || target == null) {
    throw const GeometryRuleError('Those items can no longer be aligned');
  }
  final own = geometry.definingPoints([movingId]);
  if (own.intersection(geometry.definingPoints([anchorId])).isNotEmpty) {
    throw const GeometryRuleError(
      'The two items share points, so one cannot move on its own',
    );
  }
  final isWholeShape =
      geometry.shapes.containsKey(movingId) ||
      geometry.circles.containsKey(movingId);
  final moved = <String, Set<String>>{
    layerId: own,
    if (isWholeShape) ...landInside(document, layerId, movingId),
  };
  for (final id in moved.keys) {
    if (document.isLocked(id)) {
      throw GeometryRuleError(
        '${document.layers[id]!.name} is locked, so '
        '${geometry.labelOf(movingId)} cannot be moved as a whole',
      );
    }
  }

  final delta = _offsetFor(edge, anchor: anchor, moving: target);
  var result = document;
  if (delta != Vec.zero) {
    moved.forEach((id, points) {
      final before = document.geometryOf(id);
      result = result.withGeometry(
        before.edit((e) {
          for (final p in points) {
            e.movePoint(p, before.points[p]! + delta);
          }
        }),
      );
    });
  }
  return (document: result, moved: moved);
}

/// How far the moving bounds shift to meet the anchor's along [edge].
/// Screen y grows downward, so top is the smaller y.
Vec _offsetFor(
  AlignEdge edge, {
  required (Vec, Vec) anchor,
  required (Vec, Vec) moving,
}) {
  final (aLow, aHigh) = anchor;
  final (mLow, mHigh) = moving;
  return switch (edge) {
    AlignEdge.left => Vec(aLow.x - mLow.x, 0),
    AlignEdge.right => Vec(aHigh.x - mHigh.x, 0),
    AlignEdge.top => Vec(0, aLow.y - mLow.y),
    AlignEdge.bottom => Vec(0, aHigh.y - mHigh.y),
    AlignEdge.center => (aLow + aHigh) / 2 - (mLow + mHigh) / 2,
  };
}

/// The bounding box (low, high corners) of one shape, circle, line or
/// point, or null when [itemId] is not in [geometry].
(Vec, Vec)? boundsOfItem(Geometry geometry, String itemId) {
  if (geometry.shapes.containsKey(itemId) ||
      geometry.circles.containsKey(itemId)) {
    final region = geometry.regionOf(itemId);
    if (region != null) return region.bounds;
    // An open shape: fall back to the lines that make it.
    return _union([
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

(Vec, Vec)? _union(List<(Vec, Vec)> boxes) {
  if (boxes.isEmpty) return null;
  var low = boxes.first.$1, high = boxes.first.$2;
  for (final (l, h) in boxes.skip(1)) {
    low = Vec(math.min(low.x, l.x), math.min(low.y, l.y));
    high = Vec(math.max(high.x, h.x), math.max(high.y, h.y));
  }
  return (low, high);
}
