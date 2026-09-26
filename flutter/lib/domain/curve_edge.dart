import 'dart:math' as math;

import 'curve_numeric.dart';
import 'planar.dart';
import 'vec.dart';

const _tau = 2 * math.pi;
const _roundoff = 32 * 2.220446049250313e-16;

/// An oriented line or circular arc, in metres, without any tessellation.
///
/// [bulge] is tan(signed sweep / 4). Positive sweeps are counterclockwise
/// in mathematical coordinates (visually clockwise on the downward-y canvas).
/// A finite bulge represents strictly less than a full turn; use two arcs for
/// a circle. The constructor deliberately permits zero-length draft edges.
class CurveEdge {
  const CurveEdge(this.start, this.end, {this.bulge = 0});

  final Vec start;
  final Vec end;
  final double bulge;

  bool get isArc => bulge != 0;
  double get sweep => 4 * math.atan(bulge);

  /// A line has no circle centre.
  Vec get centre {
    if (!isArc) throw StateError('A straight edge has no circle centre.');
    return start + _centreOffset;
  }

  Vec get _centreOffset {
    final chord = end - start;
    return chord / 2 + Vec(-chord.y, chord.x) * ((1 / bulge - bulge) / 4);
  }

  // |p-centre|²-radius², evaluated without subtracting enormous radius squares.
  // In particular, a tiny sagitta is not lost against a faraway circle centre.
  double _circleValue(Vec p) {
    final q = p - start;
    final chord = end - start;
    return q.dot(q) -
        chord.dot(q) -
        (1 / bulge - bulge) / 2 * Vec(-chord.y, chord.x).dot(q);
  }

  List<double> _lineParameters(Vec origin, Vec direction) {
    final q = origin - start;
    final chord = end - start;
    final normal = Vec(-chord.y, chord.x);
    final heightFactor = (1 / bulge - bulge) / 2;
    final coefficient =
        2 * q.dot(direction) -
        chord.dot(direction) -
        heightFactor * normal.dot(direction);
    final a = direction.dot(direction);
    // Evaluate the discriminant at the quadratic's vertex, near the circle,
    // not as B²-4AC from a potentially distant line endpoint. Otherwise a
    // micrometre circle on a hundred-metre segment looks spuriously tangent.
    final shift = (_centreOffset - q).dot(direction) / a;
    final foot = q + direction * shift;
    final first = foot.dot(foot);
    final second = chord.dot(foot);
    final third = heightFactor * normal.dot(foot);
    var value = first - second - third;
    final error = _roundoff * (first.abs() + second.abs() + third.abs());
    if (value.abs() <= error) value = 0;
    return quadraticRoots(
      a,
      coefficient,
      _circleValue(origin),
      discriminant: -4 * a * value,
    );
  }

  /// Infinite for a straight line.
  double get radius => isArc
      ? start.distanceTo(end) * (bulge.abs() + 1 / bulge.abs()) / 4
      : double.infinity;

  double get startAngle {
    final direction = isArc ? -_centreOffset : end - start;
    return math.atan2(direction.y, direction.x);
  }

  double get length => isArc ? radius * sweep.abs() : start.distanceTo(end);

  /// The signed circular-segment area between this edge and its chord.
  /// The series avoids cancellation in very shallow arcs.
  double get segmentArea {
    if (!isArc || start == end) return 0;
    final angle = sweep;
    final square = angle * angle;
    final difference = angle.abs() < 0.1
        ? angle *
              square /
              6 *
              (1 -
                  square / 20 +
                  square * square / 840 -
                  square * square * square / 60480 +
                  square * square * square * square / 6652800)
        : angle - math.sin(angle);
    return radius * radius * difference / 2;
  }

  /// This edge's contribution to one half of the integral x dy - y dx.
  double get signedArea => start.cross(end) / 2 + segmentArea;

  Vec pointAt(double t) {
    if (t == 0) return start;
    if (t == 1) return end;
    final chord = end - start;
    if (!isArc || start == end) return start + chord * t;
    if (t == 0.5) {
      return start + chord / 2 - Vec(-chord.y, chord.x) * (bulge / 2);
    }
    final angle = sweep * t;
    final sine = math.sin(angle);
    final halfSine = math.sin(angle / 2);
    final halfVersine = halfSine * halfSine;
    final height = (1 / bulge - bulge) / 4;
    // Work relative to the chord, not by subtracting two large centre values.
    return start +
        chord * (halfVersine + height * sine) +
        Vec(-chord.y, chord.x) * (2 * height * halfVersine - sine / 2);
  }

  /// Unit tangent in the direction of travel; zero for a zero-length edge.
  Vec tangentAt(double t) {
    final chord = end - start;
    if (chord.length == 0) return Vec.zero;
    if (!isArc) return chord / chord.length;
    final angle = math.atan2(chord.y, chord.x) + (t - 0.5) * sweep;
    return Vec(math.cos(angle), math.sin(angle));
  }

  /// Parameter of a point on the supporting line/circle. For arcs, positions
  /// outside the sweep continue around in the edge's direction past 1.
  double parameterOf(Vec p) {
    if (p == start) return 0;
    if (p == end) return 1;
    final chord = end - start;
    if (chord.length == 0) return 0;
    if (!isArc) return (p - start).dot(chord) / chord.dot(chord);
    final first = -_centreOffset;
    final radial = p - start + first;
    var angle = math.atan2(first.cross(radial), first.dot(radial));
    if (sweep < 0) angle = -angle;
    if (angle < 0) angle += _tau;
    if (_tau - angle <= _roundoff) angle = 0;
    return angle / sweep.abs();
  }

  bool _includes(Vec p) {
    if (p.distanceTo(start) <= tolerance || p.distanceTo(end) <= tolerance) {
      return true;
    }
    if (!isArc) return distanceToSegment(p, start, end) <= tolerance;
    final radialLength = (p - start - _centreOffset).length;
    if ((_circleValue(p) / (radialLength + radius)).abs() > tolerance) {
      return false;
    }
    return parameterOf(p) <= 1 + tolerance / length;
  }

  Vec closestPoint(Vec p) {
    if (!isArc || start == end) return closestPointOnSegment(p, start, end);
    final radial = p - start - _centreOffset;
    if (radial.length != 0) {
      final gap = _circleValue(p) / (radial.length + radius);
      final candidate = p - radial * (gap / radial.length);
      if (parameterOf(candidate) <= 1) return candidate;
    }
    return p.distanceTo(start) <= p.distanceTo(end) ? start : end;
  }

  double distanceTo(Vec p) => p.distanceTo(closestPoint(p));

  CurveEdge reversed() => CurveEdge(end, start, bulge: -bulge);

  /// Exact subarc, including a reversed interval. Parameters must be in [0, 1].
  CurveEdge portion(double from, double to) {
    if (!from.isFinite ||
        !to.isFinite ||
        from < 0 ||
        from > 1 ||
        to < 0 ||
        to > 1) {
      throw RangeError('An edge portion must be within [0, 1].');
    }
    if (from == 0 && to == 1) return this;
    return CurveEdge(
      pointAt(from),
      pointAt(to),
      bulge: isArc ? math.tan(sweep * (to - from) / 4) : 0,
    );
  }

  (Vec, Vec) get bounds {
    final points = <Vec>[start, end];
    if (isArc && start != end) {
      final c = centre;
      final r = radius;
      for (final offset in [Vec(r, 0), Vec(0, r), Vec(-r, 0), Vec(0, -r)]) {
        final p = c + offset;
        final t = parameterOf(p);
        if (t <= 1) points.add(pointAt(t));
      }
    }
    return (
      Vec(
        points.map((p) => p.x).reduce(math.min),
        points.map((p) => p.y).reduce(math.min),
      ),
      Vec(
        points.map((p) => p.x).reduce(math.max),
        points.map((p) => p.y).reduce(math.max),
      ),
    );
  }

  /// The unique arc through three points, or null for coincident/collinear
  /// points at the shared metre tolerance. The middle point selects the sweep,
  /// including a major arc when appropriate.
  static CurveEdge? through(Vec start, Vec through, Vec end) {
    if (!start.isFinite || !through.isFinite || !end.isFinite) return null;
    final a = through - start;
    final b = end - start;
    if (a.length <= tolerance ||
        b.length <= tolerance ||
        through.distanceTo(end) <= tolerance) {
      return null;
    }
    final cross = a.cross(b);
    if (cross.abs() <= tolerance * math.max(a.length, b.length)) return null;
    final offset =
        Vec(b.y * a.dot(a) - a.y * b.dot(b), a.x * b.dot(b) - b.x * a.dot(a)) /
        (2 * cross);
    final first = -offset;
    final last = b - offset;
    var angle = math.atan2(first.cross(last), first.dot(last));
    if (cross > 0 && angle <= 0) angle += _tau;
    if (cross < 0 && angle >= 0) angle -= _tau;
    return CurveEdge(start, end, bulge: math.tan(angle / 4));
  }
}

/// Analytic intersections of finite edges, including tangent contacts and the
/// endpoints of coincident overlaps. A coincident interval is represented by
/// its ends, not by an arbitrary point cloud.
List<Vec> intersections(CurveEdge a, CurveEdge b) {
  final result = <Vec>[];
  void add(Vec p) {
    if (p.isFinite &&
        a._includes(p) &&
        b._includes(p) &&
        !result.any((q) => p.distanceTo(q) <= tolerance)) {
      result.add(p);
    }
  }

  for (final p in [a.start, a.end, b.start, b.end]) {
    add(p);
  }
  if (a.start == a.end || b.start == b.end) return result;
  if (!a.isArc && !b.isArc) {
    final ab = a.end - a.start;
    final cd = b.end - b.start;
    final determinant = ab.cross(cd);
    // A split line can acquire a few ulps of angular error. Its overlap is
    // still an interval, not an extra arbitrary crossing from dividing by an
    // almost-zero determinant. Require metre collinearity at BOTH ends so
    // genuinely long, shallow crossings are not mistaken for parallel lines.
    if (determinant.abs() <= _roundoff * a.length * b.length &&
        ab.cross(b.start - a.start).abs() <= tolerance * a.length &&
        ab.cross(b.end - a.start).abs() <= tolerance * a.length) {
      return result;
    }
    if (determinant != 0) {
      final t = (b.start - a.start).cross(cd) / determinant;
      final u = (b.start - a.start).cross(ab) / determinant;
      if (t >= -tolerance / a.length &&
          t <= 1 + tolerance / a.length &&
          u >= -tolerance / b.length &&
          u <= 1 + tolerance / b.length) {
        add(a.start + ab * t.clamp(0.0, 1.0));
      }
    }
  } else if (a.isArc && b.isArc) {
    final d = (b.start - a.start) + (b._centreOffset - a._centreOffset);
    final distance = d.length;
    final r = a.radius;
    final s = b.radius;
    if (distance <= tolerance && (r - s).abs() <= tolerance) return result;
    if (distance == 0 ||
        distance > r + s + tolerance ||
        distance < (r - s).abs() - tolerance) {
      return result;
    }
    // Intersect the radical axis with A. The implicit constant is evaluated
    // near the arcs, avoiding subtraction of nearly equal squared radii.
    final unit = d / distance;
    final foot = a.start + unit * (b._circleValue(a.start) / (2 * distance));
    final direction = Vec(-unit.y, unit.x);
    for (final t in a._lineParameters(foot, direction)) {
      add(foot + direction * t);
    }
  } else {
    final line = a.isArc ? b : a;
    final arc = a.isArc ? a : b;
    final unit = (line.end - line.start) / line.length;
    for (final t in arc._lineParameters(line.start, unit)) {
      if (t >= -tolerance && t <= line.length + tolerance) {
        add(line.start + unit * t.clamp(0.0, line.length));
      }
    }
  }
  return result;
}
