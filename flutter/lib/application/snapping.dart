import '../domain/vec.dart';
import 'camera.dart';

/// How far, in logical pixels, a position is pulled onto an alignment guide.
const double alignmentReach = 6;

/// A snapped position and the guides that produced it.
class SnapResult {
  const SnapResult(this.position, {this.guideX, this.guideY});

  final Vec position;

  /// World x of a vertical alignment guide, if one applied.
  final double? guideX;

  /// World y of a horizontal alignment guide, if one applied.
  final double? guideY;
}

/// Moves [position] to the nearest visible grid intersection.
SnapResult snapToGrid(Vec position, Camera camera) {
  final cell = camera.gridCellMetres;
  double nearest(double value) => (value / cell).round() * cell;
  return SnapResult(Vec(nearest(position.x), nearest(position.y)));
}

/// Aligns [position] with the x and y of nearby [guides] independently.
///
/// Each axis takes the closest guide within reach; ties go to the guide
/// listed first, so callers pass guides in a stable order.
SnapResult alignToPoints(Vec position, Camera camera, Iterable<Vec> guides) {
  final reach = camera.metres(alignmentReach);
  double? bestX;
  double? bestY;
  var gapX = reach;
  var gapY = reach;
  for (final guide in guides) {
    final dx = (guide.x - position.x).abs();
    final dy = (guide.y - position.y).abs();
    if (dx <= gapX && (bestX == null || dx < gapX)) {
      bestX = guide.x;
      gapX = dx;
    }
    if (dy <= gapY && (bestY == null || dy < gapY)) {
      bestY = guide.y;
      gapY = dy;
    }
  }
  return SnapResult(
    Vec(bestX ?? position.x, bestY ?? position.y),
    guideX: bestX,
    guideY: bestY,
  );
}
