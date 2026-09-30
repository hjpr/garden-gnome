part of 'row_layout.dart';

/// Clips a whole row strip, not just its centre, away from the outline.
/// The forbidden area is a border-radius tube around each boundary edge,
/// swept across half a row width in both directions. Its candidate edges
/// split a row into intervals on which clearance cannot change.
class _RowBorder {
  _RowBorder(this.region, this.distance, this.halfWidth) {
    edges = region.contours.expand((c) => c).toList();
    cuts = [
      for (final edge in edges)
        for (final boundary in _tubeEdges(edge)) ..._sweep(boundary),
    ];
  }

  final Region region;
  final double distance;
  final Vec halfWidth;
  late final List<CurveEdge> edges;
  late final List<CurveEdge> cuts;

  Iterable<CurveEdge> _tubeEdges(CurveEdge edge) sync* {
    if (edge.isArc) {
      final centre = edge.centre;
      final radius = edge.radius;
      for (final r in [radius - distance, radius + distance]) {
        if (r <= 0) continue;
        yield CurveEdge(
          centre + (edge.start - centre) * (r / radius),
          centre + (edge.end - centre) * (r / radius),
          bulge: edge.bulge,
        );
      }
    } else {
      final direction = edge.tangentAt(0);
      final normal = Vec(-direction.y, direction.x) * distance;
      yield CurveEdge(edge.start + normal, edge.end + normal);
      yield CurveEdge(edge.start - normal, edge.end - normal);
    }
    for (final end in [edge.start, edge.end]) {
      yield* DiscRegion(end, distance).contours.expand((c) => c);
    }
  }

  Iterable<CurveEdge> _sweep(CurveEdge edge) sync* {
    for (final shift in [halfWidth, -halfWidth]) {
      yield CurveEdge(edge.start + shift, edge.end + shift, bulge: edge.bulge);
    }
    for (final point in [edge.start, edge.end, ..._acrossTangencies(edge)]) {
      yield CurveEdge(point - halfWidth, point + halfWidth);
    }
  }

  /// Circular extrema along the row; their tangents run across it.
  Iterable<Vec> _acrossTangencies(CurveEdge edge) sync* {
    if (!edge.isArc) return;
    final across = halfWidth / halfWidth.length;
    final radial = Vec(-across.y, across.x) * edge.radius;
    for (final point in [edge.centre + radial, edge.centre - radial]) {
      if (edge.parameterOf(point) <= 1) yield point;
    }
  }

  bool contains(Vec centre) {
    if (region.locate(centre) != PointLocation.inside) return false;
    final section = CurveEdge(centre - halfWidth, centre + halfWidth);
    for (final edge in edges) {
      if (intersections(section, edge).isNotEmpty) return false;
      // Segment/curve minima occur at an endpoint or at a circular
      // tangent parallel to the segment. Check both, including hole rims.
      if (edge.distanceTo(section.start) < distance - tolerance ||
          edge.distanceTo(section.end) < distance - tolerance ||
          section.distanceTo(edge.start) < distance - tolerance ||
          section.distanceTo(edge.end) < distance - tolerance) {
        return false;
      }
      for (final point in _acrossTangencies(edge)) {
        if (section.distanceTo(point) < distance - tolerance) return false;
      }
    }
    return true;
  }
}
