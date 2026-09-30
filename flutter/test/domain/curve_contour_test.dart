import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/curve_contour.dart';
import 'package:garden_gnome/domain/curve_edge.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

List<CurveEdge> _polygon(List<Vec> corners) => [
  for (var i = 0; i < corners.length; i++)
    CurveEdge(corners[i], corners[(i + 1) % corners.length]),
];

List<CurveEdge> _reversed(List<CurveEdge> contour) => [
  for (final edge in contour.reversed) edge.reversed(),
];

void main() {
  test('empty and collinear contours have zero signed area', () {
    expect(signedContourArea(const []), 0);
    final collinear = _polygon(const [Vec(0, 0), Vec(2, 0), Vec(5, 0)]);
    expect(signedContourArea(collinear), 0);
    expect(orientContour(collinear, positive: true), same(collinear));
    expect(orientContour(const [], positive: false), isEmpty);
  });

  test('area keeps winding and small parcels at large world coordinates', () {
    for (final origin in [Vec.zero, const Vec(1e9, -1e9)]) {
      final contour = _polygon([
        origin,
        origin + const Vec(7, 0),
        origin + const Vec(7, 3),
        origin + const Vec(0, 3),
      ]);
      final reversed = _reversed(contour);
      expect(signedContourArea(contour), 21);
      expect(signedContourArea(reversed), -21);
      expect(signedContourArea(orientContour(reversed, positive: true)), 21);
      expect(signedContourArea(orientContour(contour, positive: false)), -21);
      expect(CurveRegion([reversed]).area, 21);
    }
  });

  test('two-edge arc and chord retain analytic area in either direction', () {
    for (final origin in [Vec.zero, const Vec(1e9, -1e9)]) {
      final a = origin + const Vec(-3, 0);
      final b = origin + const Vec(3, 0);
      final contour = [CurveEdge(a, b, bulge: 1), CurveEdge(b, a)];
      final expected = math.pi * 9 / 2;
      expect(signedContourArea(contour), closeTo(expected, 1e-12));
      expect(signedContourArea(_reversed(contour)), closeTo(-expected, 1e-12));
      expect(CurveRegion([contour]).area, closeTo(expected, 1e-12));
    }
  });

  test('small edge contributions survive accumulation after a large area', () {
    const steps = 2048;
    final contour = _polygon([
      Vec.zero,
      const Vec(1e8, 0),
      const Vec(0, 1e8),
      const Vec(0, 2),
      for (var i = 1; i <= steps; i++)
        Vec(
          2 * math.cos(math.pi / 2 + i * math.pi / (2 * steps)),
          2 * math.sin(math.pi / 2 + i * math.pi / (2 * steps)),
        ),
    ]);
    // A large right triangle plus a regular polygonal quarter-disc.
    final expected = 5e15 + steps * 2 * math.sin(math.pi / (2 * steps));
    expect(signedContourArea(contour), expected);
    expect(CurveRegion([contour]).area, expected);
  });

  test(
    'region nesting subtracts a curved hole regardless of input winding',
    () {
      const origin = Vec(1e9, -1e9);
      final outer = _polygon([
        origin + const Vec(-5, -5),
        origin + const Vec(5, -5),
        origin + const Vec(5, 5),
        origin + const Vec(-5, 5),
      ]);
      final a = origin + const Vec(-2, 0);
      final b = origin + const Vec(2, 0);
      final hole = [CurveEdge(a, b, bulge: 1), CurveEdge(b, a, bulge: 1)];
      final region = CurveRegion([hole, _reversed(outer)]);
      expect(region.area, closeTo(100 - math.pi * 4, 1e-12));
      expect(region.outerCount, 1);
      expect(signedContourArea(region.contours.first), lessThan(0));
      expect(signedContourArea(region.contours.last), 100);
    },
  );
}
