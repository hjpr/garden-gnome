import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/curve_edge.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

PolygonRegion box(double x, double y, double width, double height) =>
    PolygonRegion([
      Vec(x, y),
      Vec(x + width, y),
      Vec(x + width, y + height),
      Vec(x, y + height),
    ]);

void closed(CurveRegion region) {
  for (final contour in region.contours) {
    for (var i = 0; i < contour.length; i++) {
      expect(
        contour[i].end.distanceTo(contour[(i + 1) % contour.length].start),
        lessThanOrEqualTo(tolerance),
      );
    }
  }
}

void main() {
  final square = box(0, 0, 10, 10);
  const pond = DiscRegion(Vec(5, 5), 2);

  test(
    'contained circular subtraction creates a negatively oriented exact hole',
    () {
      final result = square.combine(pond, BooleanOperation.subtract);
      expect(result.outerCount, 1);
      expect(result.contours, hasLength(2));
      expect(result.area, closeTo(100 - math.pi * 4, 1e-10));
      expect(result.perimeter, closeTo(40 + math.pi * 4, 1e-10));
      expect(result.locate(const Vec(5, 5)), PointLocation.outside);
      expect(result.locate(const Vec(7, 5)), PointLocation.onBoundary);
      expect(result.locate(const Vec(1, 1)), PointLocation.inside);
      expect(
        result.contours
            .map((c) => c.fold(0.0, (sum, e) => sum + e.signedArea))
            .where((a) => a < 0),
        hasLength(1),
      );
      closed(result);
    },
  );

  test('crossing circle creates an exact semicircular notch', () {
    final result = square.combine(
      const DiscRegion(Vec(10, 5), 2),
      BooleanOperation.subtract,
    );
    expect(result.outerCount, 1);
    expect(result.contours, hasLength(1));
    expect(result.area, closeTo(100 - 2 * math.pi, 1e-10));
    expect(result.perimeter, closeTo(40 - 4 + 2 * math.pi, 1e-10));
    expect(result.contours.single.any((e) => e.isArc && e.bulge < 0), isTrue);
    expect(result.locate(const Vec(9, 5)), PointLocation.outside);
    expect(result.locate(const Vec(7, 5)), PointLocation.inside);
    closed(result);
  });

  test('overlapping discs preserve their analytic lens area', () {
    const a = DiscRegion(Vec.zero, 2);
    const b = DiscRegion(Vec(2, 0), 2);
    final overlap = 8 * math.pi / 3 - 2 * math.sqrt(3);
    final joined = a.combine(b, BooleanOperation.union);
    final cut = a.combine(b, BooleanOperation.subtract);
    expect(joined.area, closeTo(8 * math.pi - overlap, 1e-10));
    expect(cut.area, closeTo(4 * math.pi - overlap, 1e-10));
    expect(joined.outerCount, 1);
    expect(joined.contours.expand((c) => c).every((e) => e.isArc), isTrue);
    expect(a.overlaps(b), isTrue);
    closed(joined);
    closed(cut);
  });

  test(
    'child covering a parent hole fails even with all its edges contained',
    () {
      final parent = square.combine(pond, BooleanOperation.subtract);
      final covering = box(1, 1, 8, 8);
      expect(covering.contours.single.every(parent.containsEdge), isTrue);
      expect(parent.contains(covering), isFalse);
      expect(parent.contains(pond), isFalse);
      expect(parent.overlaps(pond), isFalse);
      expect(pond.overlaps(parent), isFalse);
    },
  );

  test('a child with a matching or larger hole is legal', () {
    final parent = square.combine(pond, BooleanOperation.subtract);
    final matching = box(1, 1, 8, 8).combine(pond, BooleanOperation.subtract);
    final largerHole = box(
      1,
      1,
      8,
      8,
    ).combine(const DiscRegion(Vec(5, 5), 2.5), BooleanOperation.subtract);
    final smallerHole = box(
      1,
      1,
      8,
      8,
    ).combine(const DiscRegion(Vec(5, 5), 1.5), BooleanOperation.subtract);
    expect(parent.contains(matching), isTrue);
    expect(parent.contains(largerHole), isTrue);
    expect(parent.contains(smallerHole), isFalse);
    expect(parent.contains(parent), isTrue);
  });

  test('union can exactly refill a curved hole', () {
    final cut = square.combine(pond, BooleanOperation.subtract);
    final restored = cut.combine(pond, BooleanOperation.union);
    expect(restored.area, closeTo(100, 1e-10));
    expect(restored.contours, hasLength(1));
    expect(restored.contours.single.every((e) => !e.isArc), isTrue);
    expect(restored.contains(square), isTrue);
    expect(square.contains(restored), isTrue);
  });

  test('empty, equal, contained and disjoint operands obey identities', () {
    final empty = CurveRegion([]);
    for (final region in <Region>[square, pond]) {
      expect(
        region.combine(region, BooleanOperation.subtract).contours,
        isEmpty,
      );
      expect(
        region.combine(region, BooleanOperation.union).area,
        closeTo(region.area, 1e-10),
      );
      expect(
        region.combine(empty, BooleanOperation.union).area,
        closeTo(region.area, 1e-10),
      );
      expect(
        empty.combine(region, BooleanOperation.union).area,
        closeTo(region.area, 1e-10),
      );
      expect(
        empty.combine(region, BooleanOperation.subtract).contours,
        isEmpty,
      );
      expect(
        region.combine(empty, BooleanOperation.subtract).area,
        closeTo(region.area, 1e-10),
      );
    }
    expect(pond.combine(square, BooleanOperation.subtract).contours, isEmpty);
    expect(
      square.combine(pond, BooleanOperation.union).area,
      closeTo(100, 1e-10),
    );
    final far = box(20, 0, 2, 2);
    expect(square.combine(far, BooleanOperation.union).outerCount, 2);
    expect(
      square.combine(far, BooleanOperation.union).area,
      closeTo(104, 1e-10),
    );
    expect(
      square.combine(far, BooleanOperation.subtract).area,
      closeTo(100, 1e-10),
    );
  });

  test('a crossing cutter can produce multiple legal outer contours', () {
    final result = square.combine(box(4, -1, 2, 12), BooleanOperation.subtract);
    expect(result.outerCount, 2);
    expect(result.area, closeTo(80, 1e-10));
    expect(result.locate(const Vec(5, 5)), PointLocation.outside);
    expect(result.locate(const Vec(2, 5)), PointLocation.inside);
    expect(result.locate(const Vec(8, 5)), PointLocation.inside);
    closed(result);
  });

  test('coincident straight intervals cancel without losing the outer rim', () {
    final adjacent = box(10, 0, 5, 10);
    expect(square.overlaps(adjacent), isFalse);
    expect(
      square.combine(adjacent, BooleanOperation.union).area,
      closeTo(150, 1e-10),
    );
    expect(square.combine(adjacent, BooleanOperation.union).outerCount, 1);
    expect(
      square.combine(adjacent, BooleanOperation.subtract).area,
      closeTo(100, 1e-10),
    );
    final partial = box(10, 2, 5, 4);
    expect(
      square.combine(partial, BooleanOperation.union).area,
      closeTo(120, 1e-10),
    );
    expect(square.combine(partial, BooleanOperation.union).outerCount, 1);
    final overlapping = box(5, 0, 10, 10);
    expect(
      square.combine(overlapping, BooleanOperation.subtract).area,
      closeTo(50, 1e-10),
    );
    expect(
      square.combine(overlapping, BooleanOperation.union).area,
      closeTo(150, 1e-10),
    );
  });

  test('coincident arcs with different splits are not doubled', () {
    final quarters = CurveRegion([
      [
        for (final e in pond.contours.single) ...[
          e.portion(0, 0.5),
          e.portion(0.5, 1),
        ],
      ],
    ]);
    expect(pond.contains(quarters), isTrue);
    expect(quarters.contains(pond), isTrue);
    expect(pond.overlaps(quarters), isTrue);
    expect(
      pond.combine(quarters, BooleanOperation.union).area,
      closeTo(pond.area, 1e-10),
    );
    expect(pond.combine(quarters, BooleanOperation.subtract).contours, isEmpty);
  });

  test('externally tangent discs remain separate and do not overlap', () {
    for (final centre in [
      const Vec(4, 0),
      const Vec(0, 4),
      const Vec(2.4, 3.2),
    ]) {
      const a = DiscRegion(Vec.zero, 2);
      final b = DiscRegion(centre, 2);
      expect(a.overlaps(b), isFalse);
      final union = a.combine(b, BooleanOperation.union);
      expect(union.area, closeTo(8 * math.pi, 1e-10));
      expect(union.outerCount, 2);
      expect(
        a.combine(b, BooleanOperation.subtract).area,
        closeTo(a.area, 1e-10),
      );
      expect(
        union.combine(a, BooleanOperation.subtract).area,
        closeTo(b.area, 1e-10),
      );
      closed(union);
    }
  });

  test(
    'internally tangent holes and line/circle contacts remain queryable',
    () {
      const outer = DiscRegion(Vec.zero, 3);
      const inner = DiscRegion(Vec(1, 0), 2);
      expect(outer.contains(inner), isTrue);
      final cut = outer.combine(inner, BooleanOperation.subtract);
      expect(cut.area, closeTo(5 * math.pi, 1e-10));
      expect(cut.locate(const Vec(1, 0)), PointLocation.outside);
      expect(cut.locate(const Vec(-2.5, 0)), PointLocation.inside);
      expect(
        cut.combine(inner, BooleanOperation.union).area,
        closeTo(outer.area, 1e-10),
      );
      expect(
        square
            .combine(const DiscRegion(Vec(12, 5), 2), BooleanOperation.subtract)
            .area,
        closeTo(100, 1e-10),
      );
      final tangentHole = square.combine(
        const DiscRegion(Vec(8, 5), 2),
        BooleanOperation.subtract,
      );
      expect(tangentHole.area, closeTo(100 - 4 * math.pi, 1e-10));
      expect(
        tangentHole
            .combine(const DiscRegion(Vec(8, 5), 2), BooleanOperation.union)
            .area,
        closeTo(100, 1e-10),
      );
    },
  );

  test('point-touching polygons keep separate contours', () {
    final diagonal = box(10, 10, 2, 2);
    expect(square.overlaps(diagonal), isFalse);
    final result = square.combine(diagonal, BooleanOperation.union);
    expect(result.outerCount, 2);
    expect(result.area, closeTo(104, 1e-10));
    expect(
      result.combine(square, BooleanOperation.subtract).area,
      closeTo(4, 1e-10),
    );
  });

  test(
    'thin straight slivers above tolerance survive without offset probes',
    () {
      const width = 4e-8;
      final strip = box(0, 0, 10, width);
      final overlapping = box(5, 0, 10, width);
      expect(strip.overlaps(overlapping), isTrue);
      expect(
        strip.combine(overlapping, BooleanOperation.union).area,
        closeTo(15 * width, 1e-14),
      );
      expect(
        strip.combine(overlapping, BooleanOperation.subtract).area,
        closeTo(5 * width, 1e-14),
      );
      final gapped = box(0, width + 4e-8, 10, width);
      expect(strip.overlaps(gapped), isFalse);
      expect(strip.combine(gapped, BooleanOperation.union).outerCount, 2);
    },
  );

  test('a thin concentric annulus retains its hole and exact area', () {
    const outer = DiscRegion(Vec.zero, 2);
    const inner = DiscRegion(Vec.zero, 2 - 4e-8);
    final annulus = outer.combine(inner, BooleanOperation.subtract);
    expect(annulus.contours, hasLength(2));
    expect(
      annulus.area,
      closeTo(
        math.pi * (outer.radius - inner.radius) * (outer.radius + inner.radius),
        1e-14,
      ),
    );
    expect(annulus.locate(Vec.zero), PointLocation.outside);
    expect(annulus.overlaps(inner), isFalse);
    expect(annulus.contains(inner), isFalse);
  });

  test(
    'major-arc regions can be clipped and recombined without tessellation',
    () {
      final arc = CurveEdge.through(
        const Vec(2, 0),
        const Vec(0, -2),
        const Vec(0, 2),
      )!;
      final major = CurveRegion([
        [arc, CurveEdge(arc.end, arc.start)],
      ]);
      final cutter = box(-3, -3, 3, 6);
      final cut = major.combine(cutter, BooleanOperation.subtract);
      final joined = major.combine(cutter, BooleanOperation.union);
      expect(joined.area, closeTo(cutter.area + cut.area, 1e-10));
      expect(major.area, closeTo(3 * math.pi + 2, 1e-10));
      closed(cut);
      closed(joined);
    },
  );

  test('repeated mixed operations preserve holes and exact idempotence', () {
    Region current = square;
    final cutters = <Region>[
      const DiscRegion(Vec(3, 3), 1),
      const DiscRegion(Vec(7, 7), 1),
      const DiscRegion(Vec(10, 3), 2),
      box(4, 8, 2, 4),
    ];
    for (final cutter in cutters) {
      current = current.combine(cutter, BooleanOperation.subtract);
      final repeated = current.combine(cutter, BooleanOperation.subtract);
      expect(repeated.area, closeTo(current.area, 1e-10));
      expect(current.contains(repeated), isTrue);
      expect(repeated.contains(current), isTrue);
      closed(repeated);
    }
    expect(current.area, closeTo(100 - 4 * math.pi - 4, 1e-10));
    expect((current as CurveRegion).outerCount, 1);
  });

  test(
    'small arcs are intersected accurately by long distant-origin lines',
    () {
      const arc = CurveEdge(Vec(1e-6, 0), Vec(-1e-6, 0), bulge: 1);
      final hit = intersections(
        arc,
        const CurveEdge(Vec(0, -100), Vec(0, 100)),
      );
      expect(hit, hasLength(1));
      expect(hit.single.y, closeTo(1e-6, 1e-12));
      final result = box(
        -1,
        -1,
        2,
        2,
      ).combine(const DiscRegion(Vec(1, 0), 1e-6), BooleanOperation.subtract);
      expect(result.contours, hasLength(1));
      expect(result.area, closeTo(4 - math.pi * 1e-12 / 2, 1e-15));
      expect(result.contours.single.any((edge) => edge.isArc), isTrue);
      closed(result);
    },
  );

  test('shallow curved slivers retain their sagitta in topology', () {
    const arc = CurveEdge(Vec.zero, Vec(10, 0), bulge: 1e-8);
    final cap = CurveRegion([
      [arc, const CurveEdge(Vec(10, 0), Vec.zero)],
    ]);
    expect(cap.locate(const Vec(5, -2.5e-8)), PointLocation.inside);
    expect(cap.locate(const Vec(5, -7e-8)), PointLocation.outside);
    expect(cap.bounds.$1.y, closeTo(-5e-8, 1e-20));
    final cuts = intersections(
      arc,
      const CurveEdge(Vec(0, -2.5e-8), Vec(10, -2.5e-8)),
    );
    expect(cuts, hasLength(2));
    for (final p in cuts) {
      expect(arc.distanceTo(p), lessThan(1e-14));
    }
    final cutter = box(4, -1, 2, 2);
    final cut = cap.combine(cutter, BooleanOperation.subtract);
    expect(cut.outerCount, 2);
    expect(cut.area, greaterThan(0));
    expect(cut.locate(const Vec(5, -2.5e-8)), PointLocation.outside);
    expect(cut.locate(const Vec(2, -1.6e-8)), PointLocation.inside);
    expect(
      cut.combine(cutter, BooleanOperation.subtract).area,
      closeTo(cut.area, 1e-15),
    );
    closed(cut);
  });

  test(
    'seeded concave mixed line/arc operands obey set and area identities',
    () {
      final random = math.Random(84729);
      CurveRegion star(Vec centre, double rotation) {
        final points = [
          for (var i = 0; i < 8; i++)
            centre +
                Vec(
                      math.cos(rotation + i * math.pi / 4),
                      math.sin(rotation + i * math.pi / 4),
                    ) *
                    (i.isEven ? 4 : 2),
        ];
        return CurveRegion([
          [
            for (var i = 0; i < points.length; i++)
              CurveEdge(
                points[i],
                points[(i + 1) % points.length],
                bulge: i % 3 == 0 ? 0 : (i.isEven ? 0.15 : -0.1),
              ),
          ],
        ]);
      }

      for (var attempt = 0; attempt < 35; attempt++) {
        final a = star(Vec.zero, random.nextDouble() * math.pi);
        final b = star(
          Vec(random.nextDouble() * 6 - 3, random.nextDouble() * 6 - 3),
          random.nextDouble() * math.pi,
        );
        final joined = a.combine(b, BooleanOperation.union);
        final cut = a.combine(b, BooleanOperation.subtract);
        expect(joined.area, closeTo(b.area + cut.area, 1e-9));
        expect(a.contains(cut), isTrue);
        expect(joined.contains(a), isTrue);
        expect(joined.contains(b), isTrue);
        expect(cut.overlaps(b), isFalse);
        expect(
          joined.combine(b, BooleanOperation.union).area,
          closeTo(joined.area, 1e-9),
        );
        expect(
          cut.combine(b, BooleanOperation.subtract).area,
          closeTo(cut.area, 1e-9),
        );
        for (var probe = 0; probe < 50; probe++) {
          final p = Vec(
            random.nextDouble() * 14 - 7,
            random.nextDouble() * 14 - 7,
          );
          final inA = a.locate(p) == PointLocation.inside;
          final inB = b.locate(p) == PointLocation.inside;
          expect(joined.locate(p) == PointLocation.inside, inA || inB);
          expect(cut.locate(p) == PointLocation.inside, inA && !inB);
        }
        closed(joined);
        closed(cut);
      }
    },
  );

  test('self-crossing drafts can be queried but are not Boolean operands', () {
    final draft = PolygonRegion(const [
      Vec(0, 0),
      Vec(4, 4),
      Vec(0, 4),
      Vec(4, 0),
    ]);
    expect(() => square.contains(draft), returnsNormally);
    expect(() => square.overlaps(draft), returnsNormally);
    expect(() => draft.contains(square), returnsNormally);
    expect(
      () => draft.combine(square, BooleanOperation.union),
      throwsStateError,
    );
  });
}
