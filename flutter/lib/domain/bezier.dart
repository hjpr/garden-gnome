import 'dart:math' as math;

import 'curve_edge.dart';
import 'vec.dart';

/// How far, in metres, the arcs that stand in for a Bézier curve may stray
/// from it. Area, land checks and Boolean operations use those arcs, so
/// they are accurate to within this distance (half a millimetre).
const double bezierTolerance = 5e-4;

/// A cubic Bézier curve from [p0] to [p3], pulled by the control points
/// [p1] and [p2]. In metres.
class CubicBezier {
  const CubicBezier(this.p0, this.p1, this.p2, this.p3);

  final Vec p0;
  final Vec p1;
  final Vec p2;
  final Vec p3;

  bool get isFinite => p0.isFinite && p1.isFinite && p2.isFinite && p3.isFinite;

  bool sameAs(CubicBezier other) =>
      p0 == other.p0 && p1 == other.p1 && p2 == other.p2 && p3 == other.p3;

  Vec pointAt(double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }

  /// Direction of travel at [t]; not normalised, zero where a handle has
  /// no length at an end.
  Vec derivativeAt(double t) {
    final u = 1 - t;
    return (p1 - p0) * (3 * u * u) +
        (p2 - p1) * (6 * u * t) +
        (p3 - p2) * (3 * t * t);
  }

  /// Unit tangent at [t], falling back to the chord where the curve has no
  /// direction of its own.
  Vec tangentAt(double t) {
    var d = derivativeAt(t);
    if (d.length == 0) d = p3 - p0;
    return d.length == 0 ? Vec.zero : d / d.length;
  }

  /// The two halves either side of [t], which trace this same curve.
  (CubicBezier, CubicBezier) split(double t) {
    Vec lerp(Vec a, Vec b) => a + (b - a) * t;
    final a = lerp(p0, p1);
    final b = lerp(p1, p2);
    final c = lerp(p2, p3);
    final d = lerp(a, b);
    final e = lerp(b, c);
    final m = lerp(d, e);
    return (CubicBezier(p0, a, d, m), CubicBezier(m, e, c, p3));
  }

  /// The parameter of the point on the curve nearest [p].
  double closestParameter(Vec p) {
    const samples = 64;
    var best = 0.0;
    var bestGap = double.infinity;
    for (var i = 0; i <= samples; i++) {
      final t = i / samples;
      final gap = pointAt(t).distanceTo(p);
      if (gap < bestGap) {
        bestGap = gap;
        best = t;
      }
    }
    // Narrow down around the best sample.
    var low = math.max(0.0, best - 1 / samples);
    var high = math.min(1.0, best + 1 / samples);
    for (var i = 0; i < 60; i++) {
      final a = low + (high - low) / 3;
      final b = high - (high - low) / 3;
      if (pointAt(a).distanceTo(p) < pointAt(b).distanceTo(p)) {
        high = b;
      } else {
        low = a;
      }
    }
    return (low + high) / 2;
  }

  /// Circular arcs and straight pieces, end to end from [p0] to [p3], that
  /// stay within [bezierTolerance] of the curve. Each piece passes exactly
  /// through the curve at its ends and middle.
  List<CurveEdge> toEdges() {
    final pieces = <CurveEdge>[];
    _fit(this, 0, pieces);
    return pieces;
  }

  static void _fit(CubicBezier curve, int depth, List<CurveEdge> out) {
    final edge =
        CurveEdge.through(curve.p0, curve.pointAt(0.5), curve.p3) ??
        CurveEdge(curve.p0, curve.p3);
    if (depth >= 12 || curve._fits(edge)) {
      out.add(edge);
      return;
    }
    final (first, second) = curve.split(0.5);
    _fit(first, depth + 1, out);
    _fit(second, depth + 1, out);
  }

  bool _fits(CurveEdge edge) {
    for (var i = 1; i < 16; i++) {
      if (edge.distanceTo(pointAt(i / 16)) > bezierTolerance) return false;
    }
    return true;
  }
}
