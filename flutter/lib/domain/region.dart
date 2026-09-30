import 'dart:math' as math;

import 'curve_contour.dart';
import 'curve_edge.dart';
import 'curve_numeric.dart';
import 'planar.dart';
import 'vec.dart';

part 'curve_region_kernel.dart';

enum BooleanOperation { union, subtract }

/// Filled land bounded by analytic lines and circular arcs.
///
/// Contours put the filled side on their LEFT: outer contours have positive
/// signed area in mathematical coordinates, holes negative. Touching alone is
/// not overlap; containment includes the boundary. Queries do not run Boolean
/// stitching and remain usable while a drawing has a self-crossing outline.
sealed class Region {
  const Region();

  List<List<CurveEdge>> get contours;

  /// Net filled area in square metres, integrating circular arcs analytically.
  double get area => contours
      .fold(0.0, (sum, contour) => sum + signedContourArea(contour))
      .abs();

  /// Total boundary length in metres, including the rims of holes.
  double get perimeter =>
      contours.expand((c) => c).fold(0.0, (sum, edge) => sum + edge.length);

  PointLocation locate(Vec p) => _locate(p, contours);

  bool containsSegment(Vec a, Vec b) => containsEdge(CurveEdge(a, b));

  /// Splitting at every analytic intersection makes one midpoint per open
  /// interval sufficient, even for concave boundaries and extremely thin cuts.
  bool containsEdge(CurveEdge edge) => _containsEdge(contours, edge);

  /// Includes an interior check against this region's holes, not just a check
  /// that the other region's outline fits.
  bool contains(Region other) => _containsRegion(contours, other.contours);

  bool overlaps(Region other) => _regionsOverlap(contours, other.contours);

  /// Empty regions use the zero box.
  (Vec, Vec) get bounds {
    final edges = contours.expand((c) => c);
    if (edges.isEmpty) return (Vec.zero, Vec.zero);
    var low = const Vec(double.infinity, double.infinity);
    var high = const Vec(double.negativeInfinity, double.negativeInfinity);
    for (final edge in edges) {
      final (a, b) = edge.bounds;
      low = Vec(math.min(low.x, a.x), math.min(low.y, a.y));
      high = Vec(math.max(high.x, b.x), math.max(high.y, b.y));
    }
    return (low, high);
  }

  /// Regularized planar union/difference. Disconnected results and holes are
  /// legal here; application policy may reject multiple outer contours.
  /// Throws [StateError] for a crossing/overlapping input contour or topology
  /// that cannot be resolved at [tolerance], rather than returning corrupt land.
  CurveRegion combine(Region other, BooleanOperation operation) =>
      _combine(contours, other.contours, operation);
}

class PolygonRegion extends Region {
  PolygonRegion(List<Vec> corners) : corners = List.unmodifiable(corners);

  final List<Vec> corners;

  @override
  List<List<CurveEdge>> get contours {
    if (corners.isEmpty) return const [];
    final edges = [
      for (var i = 0; i < corners.length; i++)
        if (corners[i] != corners[(i + 1) % corners.length])
          CurveEdge(corners[i], corners[(i + 1) % corners.length]),
    ];
    if (edges.isEmpty) return const [];
    return [signedContourArea(edges) < 0 ? _reverse(edges) : edges];
  }

  double distanceToEdge(Vec p) => contours
      .expand((c) => c)
      .fold(
        double.infinity,
        (distance, edge) => math.min(distance, edge.distanceTo(p)),
      );
}

class DiscRegion extends Region {
  const DiscRegion(this.centre, this.radius);

  final Vec centre;
  final double radius;

  @override
  List<List<CurveEdge>> get contours {
    if (!centre.isFinite || !radius.isFinite || radius <= 0) return const [];
    final a = centre + Vec(radius, 0);
    final b = centre - Vec(radius, 0);
    return [
      [CurveEdge(a, b, bulge: 1), CurveEdge(b, a, bulge: 1)],
    ];
  }

  @override
  PointLocation locate(Vec p) {
    final gap = p.distanceTo(centre) - radius;
    if (gap.abs() <= tolerance) return PointLocation.onBoundary;
    return gap < 0 ? PointLocation.inside : PointLocation.outside;
  }

  @override
  (Vec, Vec) get bounds =>
      (centre - Vec(radius, radius), centre + Vec(radius, radius));
}

/// An immutable collection of closed contours. Input winding and order do not
/// matter: nesting normalizes outer boundaries, holes, and islands in holes.
///
/// Contours must have finite, nonzero edges joined within [tolerance]. Simple,
/// mutually noncrossing contours are required for Boolean operations. Tangent
/// contacts are allowed. A full circle needs at least two nondegenerate arcs.
/// Zero-area contours are queryable drafts, but are not Boolean operands.
///
/// "Analytic" means no polygonal approximation, not arbitrary precision:
/// coordinates use Dart doubles and must resolve the shared 1e-8 metre
/// tolerance. Contacts within that tolerance share a topology node, without
/// modifying the input vertices. Features below that resolution may collapse;
/// an unresolvable stitching junction is reported rather than guessed.
class CurveRegion extends Region {
  CurveRegion(List<List<CurveEdge>> contours)
    : contours = _immutableContours(_normalizeContours(contours));

  CurveRegion._oriented(List<List<CurveEdge>> contours)
    : contours = _immutableContours(contours);

  @override
  final List<List<CurveEdge>> contours;

  int get outerCount => contours.where((c) => signedContourArea(c) > 0).length;
}

/// Whether segment AB crosses or touches the outline of the circle.
bool segmentMeetsCircle(Vec a, Vec b, Vec centre, double radius) {
  final nearest = distanceToSegment(centre, a, b);
  final farthest = math.max(a.distanceTo(centre), b.distanceTo(centre));
  return nearest <= radius + tolerance && farthest >= radius - tolerance;
}
