import '../domain/document.dart';
import '../domain/geometry_editor.dart';
import '../domain/vec.dart';
import 'carried_land.dart';
import 'item_bounds.dart';

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
