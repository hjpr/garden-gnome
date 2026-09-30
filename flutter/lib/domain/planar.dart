import 'vec.dart';

/// Distance, in metres, below which two positions are treated as touching.
///
/// Used for every topology decision so previews, commits, and loading agree.
/// It is independent of zoom and never used to merge points.
const double tolerance = 1e-8;

enum PointLocation { inside, onBoundary, outside }

Vec closestPointOnSegment(Vec p, Vec a, Vec b) {
  final direction = b - a;
  final lengthSquared = direction.dot(direction);
  if (lengthSquared == 0) return a;
  final t = ((p - a).dot(direction) / lengthSquared).clamp(0.0, 1.0);
  return a + direction * t;
}

double distanceToSegment(Vec p, Vec a, Vec b) =>
    p.distanceTo(closestPointOnSegment(p, a, b));

PointLocation locatePoint(Vec p, List<Vec> polygon) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final a = polygon[j];
    final b = polygon[i];
    if (distanceToSegment(p, a, b) <= tolerance) {
      return PointLocation.onBoundary;
    }
    final crossesRay =
        (a.y > p.y) != (b.y > p.y) &&
        p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x;
    if (crossesRay) inside = !inside;
  }
  return inside ? PointLocation.inside : PointLocation.outside;
}
