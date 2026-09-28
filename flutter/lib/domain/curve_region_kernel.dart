part of 'region.dart';

// Geometric decisions use planar.dart's metre tolerance. This dimensionless
// guard is only for floating-point angular roundoff, never a probe distance.
const _angleRoundoff = 64 * 2.220446049250313e-16;
const _fullTurn = 2 * math.pi;

List<CurveEdge> _reverse(List<CurveEdge> contour) =>
    contour.reversed.map((edge) => edge.reversed()).toList();

List<List<CurveEdge>> _immutableContours(List<List<CurveEdge>> contours) =>
    List.unmodifiable(contours.map((c) => List<CurveEdge>.unmodifiable(c)));

/// Translate the area integral to a local origin, and compensate its sum.
/// Large map coordinates must not erase a small parcel's area.
double _signedArea(List<CurveEdge> contour) {
  if (contour.isEmpty) return 0;
  final origin = contour.first.start;
  var sum = 0.0;
  var correction = 0.0;
  for (final edge in contour) {
    final value =
        (edge.start - origin).cross(edge.end - origin) / 2 + edge.segmentArea;
    final adjusted = value - correction;
    final next = sum + adjusted;
    correction = (next - sum) - adjusted;
    sum = next;
  }
  return sum;
}

void _checkContours(List<List<CurveEdge>> contours) {
  for (final contour in contours) {
    if (contour.isEmpty) throw ArgumentError('A contour cannot be empty.');
    for (var i = 0; i < contour.length; i++) {
      final edge = contour[i];
      if (!edge.start.isFinite ||
          !edge.end.isFinite ||
          !edge.bulge.isFinite ||
          !edge.length.isFinite ||
          edge.length == 0) {
        throw ArgumentError('Contour edges must be finite and nonzero.');
      }
      if (edge.end.distanceTo(contour[(i + 1) % contour.length].start) >
          tolerance) {
        throw ArgumentError('Contour edges must form a closed chain.');
      }
    }
  }
}

List<List<CurveEdge>> _normalizeContours(List<List<CurveEdge>> contours) {
  _checkContours(contours);
  return [
    for (var i = 0; i < contours.length; i++) _normalizeContour(contours, i),
  ];
}

List<CurveEdge> _normalizeContour(List<List<CurveEdge>> contours, int index) {
  final contour = contours[index];
  var depth = 0;
  for (var j = 0; j < contours.length; j++) {
    if (j == index) continue;
    final other = contours[j];
    // Tangencies can put a vertex or midpoint on another contour. Splitting
    // provides a representative from a genuine open interval instead.
    bool? inside;
    for (final edge in contour) {
      for (final piece in _splitEdge(edge, other)) {
        if (_coincidentDirection(piece, other) != 0) continue;
        inside = _inside(piece.pointAt(0.5), [other]);
        break;
      }
      if (inside != null) break;
    }
    if (inside == true) depth++;
  }
  final wantsPositive = depth.isEven;
  return (_signedArea(contour) < 0) == wantsPositive
      ? _reverse(contour)
      : contour;
}

PointLocation _locate(Vec p, List<List<CurveEdge>> contours) {
  for (final edge in contours.expand((c) => c)) {
    final (x0, y0, x1, y1) = looseBox(edge);
    if (p.x < x0 || p.x > x1 || p.y < y0 || p.y > y1) continue;
    if (edge.distanceTo(p) <= tolerance) return PointLocation.onBoundary;
  }
  return _inside(p, contours) ? PointLocation.inside : PointLocation.outside;
}

/// Signed ray crossings. Arcs are split ONLY at analytic y extrema, not into
/// polygonal approximations. Half-open intervals count a shared vertex once.
bool _inside(Vec p, List<List<CurveEdge>> contours) {
  var winding = 0;
  for (final edge in contours.expand((c) => c)) {
    if (edge.start == edge.end) continue;
    if (!edge.isArc) {
      final a = edge.start;
      final b = edge.end;
      final side = (b - a).cross(p - a);
      if (a.y <= p.y && b.y > p.y && side > 0) winding++;
      if (b.y <= p.y && a.y > p.y && side < 0) winding--;
      continue;
    }
    // The rightward ray cannot reach an arc wholly above, below or left
    // of the point.
    final (_, y0, x1, y1) = looseBox(edge);
    if (p.y < y0 || p.y > y1 || p.x > x1) continue;
    final c = edge.centre;
    final r = edge.radius;
    final cuts = <double>[0, 1];
    for (final y in [-r, r]) {
      final t = edge.parameterOf(c + Vec(0, y));
      if (t > 0 && t < 1) cuts.add(t);
    }
    cuts.sort();
    final chord = edge.end - edge.start;
    final dy = p.y - edge.start.y;
    final coefficient = (1 / edge.bulge - edge.bulge) / 2;
    final roots = quadraticRoots(
      1,
      -chord.x + coefficient * chord.y,
      dy * dy - chord.y * dy - coefficient * chord.x * dy,
    );
    if (roots.isEmpty) continue;
    for (var i = 1; i < cuts.length; i++) {
      final from = cuts[i - 1];
      final to = cuts[i];
      final a = edge.pointAt(from);
      final b = edge.pointAt(to);
      if ((a.y > p.y) == (b.y > p.y)) continue;
      final rightHalf = edge.pointAt((from + to) / 2).x > c.x;
      final x = edge.start.x + (rightHalf ? roots.last : roots.first);
      if (x > p.x) winding += b.y > a.y ? 1 : -1;
    }
  }
  return winding != 0;
}

List<CurveEdge> _splitEdge(CurveEdge edge, Iterable<CurveEdge> others) {
  if (edge.length == 0) return [edge];
  final cuts = <double>[0, 1];
  for (final other in others) {
    for (final p in intersections(edge, other)) {
      final double t;
      if (p.distanceTo(edge.start) <= tolerance) {
        t = 0;
      } else if (p.distanceTo(edge.end) <= tolerance) {
        t = 1;
      } else {
        t = edge.parameterOf(p).clamp(0.0, 1.0);
      }
      cuts.add(t);
    }
  }
  cuts.sort();
  final distinct = <double>[0];
  for (final t in cuts) {
    if (t > distinct.last && (t - distinct.last) * edge.length > tolerance) {
      distinct.add(t);
    }
  }
  if (distinct.last != 1) {
    if (distinct.length > 1 && (1 - distinct.last) * edge.length <= tolerance) {
      distinct.removeLast();
    }
    distinct.add(1);
  }
  return [
    for (var i = 1; i < distinct.length; i++)
      edge.portion(distinct[i - 1], distinct[i]),
  ];
}

bool _sameSupport(CurveEdge a, CurveEdge b) {
  if (a.isArc != b.isArc) return false;
  if (a.isArc) {
    return a.centre.distanceTo(b.centre) <= tolerance &&
        (a.radius - b.radius).abs() <= tolerance;
  }
  if (a.length == 0 || b.length == 0) return false;
  final direction = (a.end - a.start) / a.length;
  final otherDirection = (b.end - b.start) / b.length;
  return direction.cross(otherDirection).abs() <= _angleRoundoff &&
      direction.cross(b.start - a.start).abs() <= tolerance &&
      direction.cross(b.end - a.start).abs() <= tolerance;
}

/// 1 means both interiors lie to the same side; -1 means opposing sides.
/// This symbolic side test replaces epsilon-offset probes, which can jump
/// across a narrow sliver or across the far side of a small circular hole.
int _coincidentDirection(CurveEdge piece, Iterable<CurveEdge> others) {
  final p = piece.pointAt(0.5);
  for (final other in others) {
    if (_sameSupport(piece, other) && other.distanceTo(p) <= tolerance) {
      return piece.tangentAt(0.5).dot(other.tangentAt(other.parameterOf(p))) > 0
          ? 1
          : -1;
    }
  }
  return 0;
}

enum _Relation { outside, inside, sameBoundary, oppositeBoundary }

_Relation _relation(CurveEdge piece, List<List<CurveEdge>> contours) {
  final direction = _coincidentDirection(piece, contours.expand((c) => c));
  if (direction != 0) {
    return direction > 0 ? _Relation.sameBoundary : _Relation.oppositeBoundary;
  }
  // No displacement and no boundary band here: the open interval's exact
  // winding preserves slivers wider than the shared intersection tolerance.
  return _inside(piece.pointAt(0.5), contours)
      ? _Relation.inside
      : _Relation.outside;
}

bool _containsEdge(List<List<CurveEdge>> contours, CurveEdge edge) {
  if (_locate(edge.start, contours) == PointLocation.outside ||
      _locate(edge.end, contours) == PointLocation.outside) {
    return false;
  }
  return _splitEdge(edge, contours.expand((c) => c)).every(
    (piece) => _locate(piece.pointAt(0.5), contours) != PointLocation.outside,
  );
}

bool _containsRegion(List<List<CurveEdge>> a, List<List<CurveEdge>> b) {
  if (b.isEmpty) return true;
  if (a.isEmpty) return false;
  if (_boxesApart(a, b)) return false;
  final aEdges = a.expand((c) => c).toList();
  final bEdges = b.expand((c) => c).toList();
  for (final edge in bEdges) {
    for (final piece in _splitEdge(edge, aEdges)) {
      final relation = _relation(piece, a);
      if (relation == _Relation.outside ||
          relation == _Relation.oppositeBoundary) {
        return false;
      }
    }
  }
  // A's unfilled side must not enter B. This detects a covered parent hole
  // even when every single point of the child's outline is inside A.
  for (final edge in aEdges) {
    for (final piece in _splitEdge(edge, bEdges)) {
      if (_relation(piece, b) == _Relation.inside) return false;
    }
  }
  return true;
}

/// A box holding every edge of [contours]; see [looseBox].
(double, double, double, double) _looseBounds(List<List<CurveEdge>> contours) {
  var box = (
    double.infinity,
    double.infinity,
    double.negativeInfinity,
    double.negativeInfinity,
  );
  for (final edge in contours.expand((c) => c)) {
    final (x0, y0, x1, y1) = looseBox(edge);
    box = (
      math.min(box.$1, x0),
      math.min(box.$2, y0),
      math.max(box.$3, x1),
      math.max(box.$4, y1),
    );
  }
  return box;
}

bool _boxesApart(List<List<CurveEdge>> a, List<List<CurveEdge>> b) {
  final (ax0, ay0, ax1, ay1) = _looseBounds(a);
  final (bx0, by0, bx1, by1) = _looseBounds(b);
  return ax1 < bx0 || bx1 < ax0 || ay1 < by0 || by1 < ay0;
}

bool _regionsOverlap(List<List<CurveEdge>> a, List<List<CurveEdge>> b) {
  if (a.isEmpty || b.isEmpty) return false;
  // Land far apart cannot overlap.
  if (_boxesApart(a, b)) return false;
  bool enters(List<List<CurveEdge>> first, List<List<CurveEdge>> second) {
    final others = second.expand((c) => c).toList();
    for (final edge in first.expand((c) => c)) {
      for (final piece in _splitEdge(edge, others)) {
        final relation = _relation(piece, second);
        if (relation == _Relation.inside ||
            relation == _Relation.sameBoundary) {
          return true;
        }
      }
    }
    return false;
  }

  return enters(a, b) || enters(b, a);
}

void _requireBooleanContours(List<List<CurveEdge>> contours) {
  try {
    _checkContours(contours);
  } on ArgumentError catch (error) {
    throw StateError(error.message.toString());
  }
  for (final contour in contours) {
    if (_signedArea(contour) == 0) {
      throw StateError('A Boolean contour must enclose land.');
    }
  }
  final edges = contours.expand((c) => c).toList();
  for (var i = 0; i < edges.length; i++) {
    for (var j = i + 1; j < edges.length; j++) {
      final a = edges[i];
      final b = edges[j];
      final hits = intersections(a, b);
      if (_sameSupport(a, b) &&
          hits.length > 1 &&
          (b.distanceTo(a.pointAt(0.5)) <= tolerance ||
              a.distanceTo(b.pointAt(0.5)) <= tolerance)) {
        throw StateError(
          'Input contours contain overlapping boundary intervals.',
        );
      }
      for (final p in hits) {
        final atAEnd =
            p.distanceTo(a.start) <= tolerance ||
            p.distanceTo(a.end) <= tolerance;
        final atBEnd =
            p.distanceTo(b.start) <= tolerance ||
            p.distanceTo(b.end) <= tolerance;
        if (atAEnd && atBEnd) continue;
        final tangentA = a.tangentAt(a.parameterOf(p));
        final tangentB = b.tangentAt(b.parameterOf(p));
        if (tangentA.cross(tangentB).abs() > _angleRoundoff) {
          throw StateError('Input contours cross themselves or each other.');
        }
      }
    }
  }
}

CurveRegion _combine(
  List<List<CurveEdge>> a,
  List<List<CurveEdge>> b,
  BooleanOperation operation,
) {
  _requireBooleanContours(a);
  _requireBooleanContours(b);
  final aEdges = a.expand((c) => c).toList();
  final bEdges = b.expand((c) => c).toList();
  final kept = <CurveEdge>[];
  bool filled(bool inA, bool inB) =>
      operation == BooleanOperation.union ? inA || inB : inA && !inB;

  void select(
    List<CurveEdge> source,
    List<List<CurveEdge>> other,
    List<CurveEdge> cutters,
    bool fromA,
  ) {
    for (final edge in source) {
      for (final piece in _splitEdge(edge, cutters)) {
        final relation = _relation(piece, other);
        final otherLeft =
            relation == _Relation.inside || relation == _Relation.sameBoundary;
        final otherRight =
            relation == _Relation.inside ||
            relation == _Relation.oppositeBoundary;
        final left = fromA ? filled(true, otherLeft) : filled(otherLeft, true);
        final right = fromA
            ? filled(false, otherRight)
            : filled(otherRight, false);
        if (left != right) kept.add(left ? piece : piece.reversed());
      }
    }
  }

  select(aEdges, b, bEdges, true);
  select(bEdges, a, aEdges, false);
  return CurveRegion._oriented(_stitch(kept));
}

class _BoundaryLink {
  const _BoundaryLink(this.edge, this.start, this.end);
  final CurveEdge edge;
  final int start;
  final int end;
}

/// Order outgoing tangent rays by angle, then by signed curvature. The second
/// order tie-break separates circles kissing at one point without sampling an
/// epsilon away from the junction, and also handles tangent outer/hole loops.
double _curvature(CurveEdge edge) =>
    edge.isArc ? edge.sweep.sign / edge.radius : 0;

int _nextLink(
  _BoundaryLink incoming,
  List<int> candidates,
  List<_BoundaryLink> links,
) {
  final reverse = -incoming.edge.tangentAt(1);
  final reverseCurvature = -_curvature(incoming.edge);
  double clockwise(CurveEdge edge) {
    final ray = edge.tangentAt(0);
    final cross = reverse.cross(ray);
    if (cross.abs() <= _angleRoundoff && reverse.dot(ray) > 0) {
      return _curvature(edge) < reverseCurvature ? 0 : _fullTurn;
    }
    final angle = -math.atan2(cross, reverse.dot(ray));
    return angle < 0 ? angle + _fullTurn : angle;
  }

  var best = candidates.first;
  var bestAngle = clockwise(links[best].edge);
  for (final candidate in candidates.skip(1)) {
    final angle = clockwise(links[candidate].edge);
    if (angle < bestAngle - _angleRoundoff ||
        ((angle - bestAngle).abs() <= _angleRoundoff &&
            _curvature(links[candidate].edge) > _curvature(links[best].edge))) {
      best = candidate;
      bestAngle = angle;
    }
  }
  return best;
}

List<List<CurveEdge>> _stitch(List<CurveEdge> edges) {
  final nodes = <Vec>[];
  int nodeFor(Vec p) {
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].distanceTo(p) <= tolerance) return i;
    }
    nodes.add(p);
    return nodes.length - 1;
  }

  final links = <_BoundaryLink>[];
  for (final edge in edges) {
    final start = nodeFor(edge.start);
    final end = nodeFor(edge.end);
    if (start == end && !edge.isArc) continue;
    final duplicate = links.any(
      (link) =>
          link.start == start &&
          link.end == end &&
          _sameSupport(link.edge, edge) &&
          link.edge.pointAt(0.5).distanceTo(edge.pointAt(0.5)) <= tolerance,
    );
    if (!duplicate) links.add(_BoundaryLink(edge, start, end));
  }
  final outgoing = <int, List<int>>{};
  final incoming = <int, List<int>>{};
  for (var i = 0; i < links.length; i++) {
    outgoing.putIfAbsent(links[i].start, () => []).add(i);
    incoming.putIfAbsent(links[i].end, () => []).add(i);
  }
  for (final node in {...outgoing.keys, ...incoming.keys}) {
    if ((outgoing[node]?.length ?? 0) != (incoming[node]?.length ?? 0)) {
      throw StateError('Boolean boundary is not closed at ${nodes[node]}.');
    }
  }
  final next = <int>[
    for (final link in links) _nextLink(link, outgoing[link.end]!, links),
  ];
  if (next.toSet().length != links.length) {
    throw StateError('Ambiguous Boolean junction at the geometry tolerance.');
  }
  final visited = <int>{};
  final contours = <List<CurveEdge>>[];
  for (var start = 0; start < links.length; start++) {
    if (visited.contains(start)) continue;
    final contour = <CurveEdge>[];
    var current = start;
    do {
      if (!visited.add(current)) {
        throw StateError('Boolean boundary does not form cycles.');
      }
      contour.add(links[current].edge);
      current = next[current];
    } while (current != start);
    if (_signedArea(contour).abs() > tolerance * tolerance) {
      contours.add(contour);
    }
  }
  return contours;
}
