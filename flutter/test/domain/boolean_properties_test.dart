import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/curve_edge.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

PolygonRegion rectangle(double x, double y, double w, double h) =>
    PolygonRegion([Vec(x, y), Vec(x + w, y), Vec(x + w, y + h), Vec(x, y + h)]);

/// Independent membership oracle: sample the INPUTS, never the clipped edges.
/// Sampling belongs in this test only; the production kernel is analytical.
void checkMembership(Region a, Region b, math.Random random) {
  final joined = a.combine(b, BooleanOperation.union);
  final cut = a.combine(b, BooleanOperation.subtract);
  expect(joined.area, closeTo(b.area + cut.area, 1e-7));
  for (var i = 0; i < 80; i++) {
    final p = Vec(random.nextDouble() * 30 - 15, random.nextDouble() * 30 - 15);
    final inA = a.locate(p);
    final inB = b.locate(p);
    if (inA == PointLocation.onBoundary || inB == PointLocation.onBoundary) {
      continue;
    }
    final expectedUnion =
        inA == PointLocation.inside || inB == PointLocation.inside;
    final expectedCut =
        inA == PointLocation.inside && inB == PointLocation.outside;
    expect(
      joined.locate(p) == PointLocation.inside,
      expectedUnion,
      reason: 'union at $p',
    );
    expect(
      cut.locate(p) == PointLocation.inside,
      expectedCut,
      reason: 'subtract at $p',
    );
  }
}

void main() {
  test(
    'seeded polygon/disc operations obey set membership and area identities',
    () {
      final random = math.Random(617);
      for (var i = 0; i < 60; i++) {
        final a = rectangle(
          random.nextDouble() * 10 - 5,
          random.nextDouble() * 10 - 5,
          random.nextDouble() * 7 + 1,
          random.nextDouble() * 7 + 1,
        );
        final b = DiscRegion(
          Vec(random.nextDouble() * 14 - 7, random.nextDouble() * 14 - 7),
          random.nextDouble() * 6 + 0.5,
        );
        checkMembership(a, b, random);
        checkMembership(b, a, random);
      }
    },
  );

  test('seeded disc pairs obey set membership and analytic overlap areas', () {
    final random = math.Random(901);
    for (var i = 0; i < 60; i++) {
      final a = DiscRegion(const Vec(0, 0), random.nextDouble() * 5 + 1);
      final b = DiscRegion(
        Vec(random.nextDouble() * 12 - 6, random.nextDouble() * 12 - 6),
        random.nextDouble() * 5 + 1,
      );
      checkMembership(a, b, random);
      final d = a.centre.distanceTo(b.centre);
      final r = a.radius;
      final s = b.radius;
      final double overlap;
      if (d >= r + s) {
        overlap = 0;
      } else if (d <= (r - s).abs()) {
        overlap = math.pi * math.pow(math.min(r, s), 2);
      } else {
        final first = math.acos(
          ((d * d + r * r - s * s) / (2 * d * r)).clamp(-1, 1),
        );
        final second = math.acos(
          ((d * d + s * s - r * r) / (2 * d * s)).clamp(-1, 1),
        );
        final lens = math.sqrt(
          (-d + r + s) * (d + r - s) * (d - r + s) * (d + r + s),
        );
        overlap = r * r * first + s * s * second - lens / 2;
      }
      expect(
        a.combine(b, BooleanOperation.subtract).area,
        closeTo(a.area - overlap, 1e-7),
      );
      expect(
        a.combine(b, BooleanOperation.union).area,
        closeTo(a.area + b.area - overlap, 1e-7),
      );
    }
  });

  test('repeated cuts preserve holes when another operand crosses them', () {
    final base = rectangle(-10, -10, 20, 20);
    final pond = const DiscRegion(Vec(0, 0), 3);
    final cutter = const DiscRegion(Vec(3, 0), 2);
    final withHole = base.combine(pond, BooleanOperation.subtract);
    checkMembership(withHole, cutter, math.Random(26));
    final twiceCut = withHole.combine(cutter, BooleanOperation.subtract);
    expect(twiceCut.locate(const Vec(0, 0)), PointLocation.outside);
    expect(twiceCut.locate(const Vec(4, 0)), PointLocation.outside);
    expect(twiceCut.locate(const Vec(-8, -8)), PointLocation.inside);
  });

  test('narrow legal gaps and illegal slivers are not hidden by sampling', () {
    final parent = rectangle(
      0,
      0,
      10,
      10,
    ).combine(const DiscRegion(Vec(5, 5), 2), BooleanOperation.subtract);
    expect(parent.contains(rectangle(1, 4, 2 - 1e-5, 2)), isTrue);
    expect(parent.contains(rectangle(1, 4, 2 + 1e-5, 2)), isFalse);
    expect(
      parent.contains(rectangle(1, 1, 8, 8)),
      isFalse,
      reason:
          'all corners and edges inside is insufficient: it covers the hole',
    );
    expect(parent.overlaps(const DiscRegion(Vec(5, 5), 2 - 1e-5)), isFalse);
    expect(parent.overlaps(const DiscRegion(Vec(5, 5), 2 + 1e-5)), isTrue);
  });

  test('three-point arc uses the requested major or minor sweep', () {
    for (final middle in [const Vec(0, 1), const Vec(0, -1)]) {
      final arc = CurveEdge.through(const Vec(1, 0), middle, const Vec(0, 1));
      if (middle == const Vec(0, 1)) {
        expect(arc, isNull, reason: 'through point cannot equal an endpoint');
      } else {
        expect(arc, isNotNull);
        expect(arc!.distanceTo(middle), closeTo(0, 1e-8));
        expect(arc.sweep.abs(), greaterThan(math.pi));
      }
    }
  });
}
