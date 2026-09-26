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

/// True when segments AB and CD cross at a single point interior to both.
bool segmentsCross(Vec a, Vec b, Vec c, Vec d) {
  final ab = b - a;
  final cd = d - c;
  final sideC = ab.cross(c - a);
  final sideD = ab.cross(d - a);
  final sideA = cd.cross(a - c);
  final sideB = cd.cross(b - c);
  final abLength = ab.length;
  final cdLength = cd.length;
  bool clear(double side, double length) => side.abs() > tolerance * length;
  return sideC * sideD < 0 &&
      sideA * sideB < 0 &&
      clear(sideC, abLength) &&
      clear(sideD, abLength) &&
      clear(sideA, cdLength) &&
      clear(sideB, cdLength);
}

/// True when segments AB and CD share any position, including crossings.
bool segmentsTouch(Vec a, Vec b, Vec c, Vec d) =>
    distanceToSegment(a, c, d) <= tolerance ||
    distanceToSegment(b, c, d) <= tolerance ||
    distanceToSegment(c, a, b) <= tolerance ||
    distanceToSegment(d, a, b) <= tolerance ||
    segmentsCross(a, b, c, d);

/// Positions along AB (0 to 1) where AB meets the segment CD.
///
/// Collinear overlaps report both ends of the shared portion.
List<double> intersectionsAlong(Vec a, Vec b, Vec c, Vec d) {
  final ab = b - a;
  final cd = d - c;
  final lengthSquared = ab.dot(ab);
  if (lengthSquared == 0) return const [];
  final denominator = ab.cross(cd);
  if (denominator.abs() > tolerance * ab.length * cd.length) {
    final t = (c - a).cross(cd) / denominator;
    final u = (c - a).cross(ab) / denominator;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return [t];
    return const [];
  }
  if (distanceToSegment(c, a, b) > tolerance &&
      distanceToSegment(d, a, b) > tolerance) {
    return const [];
  }
  return [
    ((c - a).dot(ab) / lengthSquared).clamp(0.0, 1.0),
    ((d - a).dot(ab) / lengthSquared).clamp(0.0, 1.0),
  ];
}

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

double polygonArea(List<Vec> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    sum += polygon[i].cross(polygon[(i + 1) % polygon.length]);
  }
  return sum.abs() / 2;
}

double polygonPerimeter(List<Vec> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    sum += polygon[i].distanceTo(polygon[(i + 1) % polygon.length]);
  }
  return sum;
}

/// Whether the whole segment AB lies inside or on the boundary of [polygon].
bool polygonContainsSegment(List<Vec> polygon, Vec a, Vec b) {
  if (locatePoint(a, polygon) == PointLocation.outside) return false;
  if (locatePoint(b, polygon) == PointLocation.outside) return false;
  for (final t in _pieceMidpoints(a, b, polygon)) {
    if (locatePoint(a + (b - a) * t, polygon) == PointLocation.outside) {
      return false;
    }
  }
  return true;
}

/// Whether the interiors of two simple polygons share any area.
///
/// Touching at points or along edges is not overlap.
bool polygonsOverlap(List<Vec> first, List<Vec> second) =>
    _boundaryEntersInterior(first, second) ||
    _boundaryEntersInterior(second, first);

bool _boundaryEntersInterior(List<Vec> polygon, List<Vec> other) {
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    final edge = b - a;
    if (edge.length <= tolerance) continue;
    final normal = Vec(-edge.y, edge.x) / edge.length;
    for (final t in _pieceMidpoints(a, b, other)) {
      final midpoint = a + edge * t;
      final location = locatePoint(midpoint, other);
      if (location == PointLocation.inside) return true;
      if (location == PointLocation.onBoundary) {
        final step = edge.length * 1e-4 < 1e-4 ? edge.length * 1e-4 : 1e-4;
        for (final side in [normal * step, normal * -step]) {
          final probe = midpoint + side;
          if (locatePoint(probe, polygon) == PointLocation.inside &&
              locatePoint(probe, other) == PointLocation.inside) {
            return true;
          }
        }
      }
    }
  }
  return false;
}

/// Midpoints of the pieces of AB between its meetings with [polygon]'s edges.
List<double> _pieceMidpoints(Vec a, Vec b, List<Vec> polygon) {
  final cuts = <double>[0, 1];
  for (var i = 0; i < polygon.length; i++) {
    cuts.addAll(
      intersectionsAlong(a, b, polygon[i], polygon[(i + 1) % polygon.length]),
    );
  }
  cuts.sort();
  final midpoints = <double>[];
  for (var i = 1; i < cuts.length; i++) {
    if (cuts[i] - cuts[i - 1] > 1e-12) {
      midpoints.add((cuts[i] + cuts[i - 1]) / 2);
    }
  }
  return midpoints;
}
