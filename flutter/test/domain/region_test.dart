import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/curve_edge.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

final square = PolygonRegion([
  const Vec(0, 0),
  const Vec(10, 0),
  const Vec(10, 10),
  const Vec(0, 10),
]);

void main() {
  test('a disc inside a square, touching its edge, is contained', () {
    expect(square.contains(const DiscRegion(Vec(5, 5), 5)), isTrue);
    expect(square.contains(const DiscRegion(Vec(5, 5), 5.01)), isFalse);
    expect(square.contains(const DiscRegion(Vec(20, 5), 1)), isFalse);
  });

  test('a square inside a disc needs every corner inside', () {
    const disc = DiscRegion(Vec(5, 5), 7.1);
    expect(disc.contains(square), isTrue);
    expect(const DiscRegion(Vec(5, 5), 7).contains(square), isFalse);
  });

  test('discs and polygons overlap only when they share land', () {
    expect(
      const DiscRegion(Vec(15, 5), 5).overlaps(square),
      isFalse,
      reason: 'touching the edge is not overlap',
    );
    expect(const DiscRegion(Vec(14, 5), 5).overlaps(square), isTrue);
    expect(
      square.overlaps(const DiscRegion(Vec(5, 5), 1)),
      isTrue,
      reason: 'a disc wholly inside overlaps',
    );
    expect(
      const DiscRegion(Vec(0, 0), 1).overlaps(const DiscRegion(Vec(2, 0), 1)),
      isFalse,
    );
    expect(
      const DiscRegion(Vec(0, 0), 1).overlaps(const DiscRegion(Vec(1.9, 0), 1)),
      isTrue,
    );
  });

  test('points on a circle are on its boundary', () {
    expect(
      const DiscRegion(Vec(0, 0), 2).locate(const Vec(2, 0)),
      PointLocation.onBoundary,
    );
  });

  group('analytic curve edges', () {
    test('line methods and zero-length draft edges', () {
      const edge = CurveEdge(Vec(1, 2), Vec(4, 6));
      expect(edge.isArc, isFalse);
      expect(edge.length, 5);
      expect(edge.pointAt(0.5), const Vec(2.5, 4));
      expect(edge.tangentAt(0), const Vec(0.6, 0.8));
      expect(edge.closestPoint(const Vec(-3, -2)), edge.start);
      expect(edge.reversed().start, edge.end);
      expect(edge.portion(0.2, 0.8).length, closeTo(3, 1e-12));
      const point = CurveEdge(Vec(2, 3), Vec(2, 3));
      expect(point.length, 0);
      expect(point.pointAt(0.5), point.start);
      expect(point.tangentAt(0), Vec.zero);
      expect(point.distanceTo(const Vec(5, 7)), 5);
    });

    test('quarter arc has exact sweep, length, area and bounds', () {
      final edge = CurveEdge(
        const Vec(1, 0),
        const Vec(0, 1),
        bulge: math.tan(math.pi / 8),
      );
      expect(edge.isArc, isTrue);
      near(edge.centre, Vec.zero);
      expect(edge.radius, closeTo(1, 1e-12));
      expect(edge.sweep, closeTo(math.pi / 2, 1e-12));
      expect(edge.length, closeTo(math.pi / 2, 1e-12));
      expect(edge.signedArea, closeTo(math.pi / 4, 1e-12));
      near(edge.pointAt(0.5), Vec(math.sqrt(0.5), math.sqrt(0.5)));
      near(edge.tangentAt(0), const Vec(0, 1));
      near(edge.tangentAt(1), const Vec(-1, 0));
      near(edge.bounds.$1, Vec.zero);
      near(edge.bounds.$2, const Vec(1, 1));
      near(edge.closestPoint(const Vec(2, 2)), edge.pointAt(0.5));
      near(edge.closestPoint(const Vec(-2, 0)), edge.end);
      expect(edge.reversed().signedArea, closeTo(-edge.signedArea, 1e-12));
    });

    test('three points select both major and reversed sweeps', () {
      final major = CurveEdge.through(
        const Vec(1, 0),
        const Vec(0, -1),
        const Vec(0, 1),
      )!;
      expect(major.sweep, closeTo(-3 * math.pi / 2, 1e-12));
      near(major.centre, Vec.zero);
      near(major.bounds.$1, const Vec(-1, -1));
      near(major.bounds.$2, const Vec(1, 1));
      final portion = major.portion(1.0 / 3, 2.0 / 3);
      near(portion.start, const Vec(0, -1));
      near(portion.end, const Vec(-1, 0));
      expect(portion.sweep, closeTo(-math.pi / 2, 1e-12));
      expect(portion.reversed().sweep, closeTo(math.pi / 2, 1e-12));
      expect(
        CurveEdge.through(Vec.zero, const Vec(1, 1), const Vec(2, 2)),
        isNull,
      );
      expect(CurveEdge.through(Vec.zero, Vec.zero, const Vec(2, 2)), isNull);
      expect(
        CurveEdge.through(Vec.zero, const Vec(1, 1e-10), const Vec(2, 0)),
        isNull,
      );
    });

    test(
      'shallow arc point and area do not lose the bulge to cancellation',
      () {
        const edge = CurveEdge(Vec.zero, Vec(10, 0), bulge: 1e-9);
        near(edge.pointAt(0.5), const Vec(5, -5e-9), 1e-16);
        expect(edge.segmentArea, closeTo(100 * 1e-9 / 3, 1e-20));
        final closed = CurveRegion([
          [edge, const CurveEdge(Vec(10, 0), Vec.zero)],
        ]);
        expect(closed.area, closeTo(edge.segmentArea, 1e-20));
      },
    );

    test('arc portions retain the supporting circle and sum of integrals', () {
      final edge = CurveEdge.through(
        const Vec(7, 2),
        const Vec(2, 7),
        const Vec(-3, 2),
      )!;
      final first = edge.portion(0, 0.173);
      final second = edge.portion(0.173, 1);
      near(first.centre, edge.centre);
      near(second.centre, edge.centre);
      expect(
        first.signedArea + second.signedArea,
        closeTo(edge.signedArea, 1e-10),
      );
      expect(first.length + second.length, closeTo(edge.length, 1e-10));
    });
  });

  group('analytic intersections', () {
    test('line crossings, endpoint contacts and collinear overlap ends', () {
      const a = CurveEdge(Vec.zero, Vec(4, 0));
      expect(intersections(a, const CurveEdge(Vec(2, -1), Vec(2, 1))), [
        const Vec(2, 0),
      ]);
      expect(intersections(a, const CurveEdge(Vec(2, 0), Vec(6, 0))).toSet(), {
        const Vec(2, 0),
        const Vec(4, 0),
      });
      expect(intersections(a, const CurveEdge(Vec(4, 0), Vec(6, 0))), [
        const Vec(4, 0),
      ]);
      expect(intersections(a, const CurveEdge(Vec(5, 0), Vec(6, 0))), isEmpty);
      expect(intersections(a, const CurveEdge(Vec(2, 0), Vec(2, 0))), [
        const Vec(2, 0),
      ]);
    });

    test(
      'line with semicircle has two intersections, tangent one, outside none',
      () {
        const arc = CurveEdge(Vec(2, 0), Vec(-2, 0), bulge: 1);
        final cuts = intersections(arc, const CurveEdge(Vec(-3, 1), Vec(3, 1)));
        expect(cuts, hasLength(2));
        expect(
          cuts.map((p) => p.x).reduce(math.min),
          closeTo(-math.sqrt(3), 1e-12),
        );
        expect(
          cuts.map((p) => p.x).reduce(math.max),
          closeTo(math.sqrt(3), 1e-12),
        );
        final tangent = intersections(
          arc,
          const CurveEdge(Vec(-3, 2), Vec(3, 2)),
        );
        expect(tangent, hasLength(1));
        near(tangent.single, const Vec(0, 2));
        expect(
          intersections(arc, const CurveEdge(Vec(-3, -1), Vec(3, -1))),
          isEmpty,
        );
      },
    );

    test(
      'circle arcs intersect, touch, and report coincident overlap ends',
      () {
        const a = CurveEdge(Vec(2, 0), Vec(-2, 0), bulge: 1);
        const b = CurveEdge(Vec(4, 0), Vec.zero, bulge: 1);
        final cuts = intersections(a, b);
        expect(cuts, hasLength(1));
        near(cuts.single, Vec(1, math.sqrt(3)));
        expect(
          intersections(a, const CurveEdge(Vec(6, 0), Vec(2, 0), bulge: 1)),
          [const Vec(2, 0)],
        );
        expect(intersections(a, a.reversed()).toSet(), {a.start, a.end});
        final part = a.portion(0.25, 0.75);
        final overlap = intersections(a, part);
        expect(overlap, hasLength(2));
        expect(overlap.any((p) => p.distanceTo(part.start) < 1e-10), isTrue);
        expect(overlap.any((p) => p.distanceTo(part.end) < 1e-10), isTrue);
        expect(
          intersections(a, const CurveEdge(Vec(1, 0), Vec(-1, 0), bulge: 1)),
          isEmpty,
        );
      },
    );

    test('long nearly parallel segments still have a real crossing', () {
      final hits = intersections(
        const CurveEdge(Vec.zero, Vec(1000000, 0)),
        const CurveEdge(Vec(0, -0.001), Vec(1000000, 0.001)),
      );
      expect(hits, hasLength(1));
      near(hits.single, const Vec(500000, 0));
    });
  });

  group('multi-contour regions', () {
    test(
      'normalizes reversed contours, nested holes and islands immutably',
      () {
        final outer = square.contours.single.reversed
            .map((e) => e.reversed())
            .toList();
        final hole = const DiscRegion(Vec(5, 5), 2).contours.single;
        final island = const DiscRegion(Vec(5, 5), 1).contours.single;
        final input = [hole, island, outer];
        final region = CurveRegion(input);
        input.clear();
        outer.clear();
        expect(region.contours, hasLength(3));
        expect(region.outerCount, 2);
        expect(region.area, closeTo(100 - 3 * math.pi, 1e-10));
        expect(region.perimeter, closeTo(40 + 6 * math.pi, 1e-10));
        expect(region.locate(const Vec(5, 5)), PointLocation.inside);
        expect(region.locate(const Vec(6.5, 5)), PointLocation.outside);
        expect(region.locate(const Vec(7, 5)), PointLocation.onBoundary);
        expect(() => region.contours.clear(), throwsUnsupportedError);
        expect(() => region.contours.first.clear(), throwsUnsupportedError);
      },
    );

    test('analytic segment containment catches a concave escape', () {
      final concave = PolygonRegion(const [
        Vec(0, 0),
        Vec(4, 0),
        Vec(4, 4),
        Vec(3, 4),
        Vec(3, 1),
        Vec(1, 1),
        Vec(1, 4),
        Vec(0, 4),
      ]);
      expect(
        concave.containsSegment(const Vec(0.5, 3), const Vec(3.5, 3)),
        isFalse,
      );
      expect(
        concave.containsSegment(const Vec(0.5, 0.5), const Vec(3.5, 0.5)),
        isTrue,
      );
      expect(
        square.containsEdge(const CurveEdge(Vec.zero, Vec(10, 0), bulge: 1)),
        isFalse,
      );
      expect(
        square.containsEdge(const CurveEdge(Vec(10, 0), Vec.zero, bulge: 1)),
        isTrue,
      );
    });

    test('ray crossings at circle endpoints and extrema are half open', () {
      final circle = CurveRegion(const DiscRegion(Vec.zero, 2).contours);
      for (final p in [Vec.zero, const Vec(1, 0), const Vec(-1, 0)]) {
        expect(circle.locate(p), PointLocation.inside);
      }
      for (final p in [
        const Vec(-3, 0),
        const Vec(3, 0),
        const Vec(-3, 2),
        const Vec(-3, -2),
      ]) {
        expect(circle.locate(p), PointLocation.outside);
      }
    });

    test('large translated coordinates do not cancel parcel area', () {
      final translated = PolygonRegion(const [
        Vec(1000000000, 1000000000),
        Vec(1000000010, 1000000000),
        Vec(1000000010, 1000000010),
        Vec(1000000000, 1000000010),
      ]);
      expect(translated.area, 100);
    });

    test('empty regions and malformed contour chains are explicit', () {
      final empty = CurveRegion([]);
      expect(empty.area, 0);
      expect(empty.perimeter, 0);
      expect(empty.bounds, (Vec.zero, Vec.zero));
      expect(empty.outerCount, 0);
      expect(empty.locate(Vec.zero), PointLocation.outside);
      expect(square.contains(empty), isTrue);
      expect(empty.contains(square), isFalse);
      expect(empty.overlaps(square), isFalse);
      expect(
        () => CurveRegion([
          [const CurveEdge(Vec.zero, Vec(1, 0))],
        ]),
        throwsArgumentError,
      );
      expect(
        () => CurveRegion([
          [const CurveEdge(Vec.zero, Vec.zero)],
        ]),
        throwsArgumentError,
      );
    });
  });
}

void near(Vec actual, Vec expected, [double epsilon = 1e-10]) {
  expect(actual.x, closeTo(expected.x, epsilon));
  expect(actual.y, closeTo(expected.y, epsilon));
}
