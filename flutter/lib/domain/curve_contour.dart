import 'curve_edge.dart';

/// Translate the area integral to a local origin, and compensate its sum.
/// Large map coordinates must not erase a small parcel's area.
double signedContourArea(List<CurveEdge> contour) {
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

List<CurveEdge> orientContour(List<CurveEdge> ring, {required bool positive}) =>
    (signedContourArea(ring) >= 0) == positive
    ? ring
    : [for (final edge in ring.reversed) edge.reversed()];
