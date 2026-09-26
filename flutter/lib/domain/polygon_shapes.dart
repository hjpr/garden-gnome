import 'dart:math' as math;

import 'vec.dart';

/// Corner positions for the Polygon tool's two functions.
///
/// Both return corners in drawing order, or null when the two clicks are
/// too close together to make a shape.

/// Smallest width, height, or radius (metres) that still makes a shape.
const double minPolygonSize = 1e-6;

/// A regular polygon with [sides] corners around [centre]. [corner] is
/// where the first corner goes, so it also sets the size and rotation.
List<Vec>? regularPolygonCorners(Vec centre, Vec corner, int sides) {
  if (sides < 3) return null;
  final offset = corner - centre;
  if (offset.length <= minPolygonSize) return null;
  return [
    for (var i = 0; i < sides; i++)
      centre + _rotated(offset, 2 * math.pi * i / sides),
  ];
}

/// An axis-aligned rectangle with opposite corners [first] and [second].
List<Vec>? rectangleCorners(Vec first, Vec second) {
  if ((second.x - first.x).abs() <= minPolygonSize ||
      (second.y - first.y).abs() <= minPolygonSize) {
    return null;
  }
  return [first, Vec(second.x, first.y), second, Vec(first.x, second.y)];
}

Vec _rotated(Vec v, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Vec(v.x * c - v.y * s, v.x * s + v.y * c);
}
