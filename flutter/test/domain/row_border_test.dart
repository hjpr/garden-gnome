import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/ground.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/row_layout.dart';
import 'package:garden_gnome/domain/vec.dart';

void main() {
  final square = PolygonRegion(const [
    Vec(0, 0),
    Vec(12, 0),
    Vec(12, 12),
    Vec(0, 12),
  ]);
  final notch = PolygonRegion(const [
    Vec(0, 0),
    Vec(12, 0),
    Vec(12, 12),
    Vec(8, 12),
    Vec(8, 5),
    Vec(5, 5),
    Vec(5, 12),
    Vec(0, 12),
  ]);
  final hole = CurveRegion([
    square.contours.first,
    PolygonRegion(const [
      Vec(5, 5),
      Vec(7, 5),
      Vec(7, 7),
      Vec(5, 7),
    ]).contours.first,
  ]);
  final circularHole = CurveRegion([
    square.contours.first,
    const DiscRegion(Vec(6, 6), 2).contours.first,
  ]);
  final uneven = PolygonRegion(const [
    Vec(0, 0),
    Vec(10, 2),
    Vec(12, 10),
    Vec(3, 12),
  ]);

  for (final (name, region) in [
    ('sloping outline', uneven),
    ('concave notch', notch),
    ('hole', hole),
    ('circular hole', circularHole),
    ('circle', const DiscRegion(Vec(6, 6), 6)),
  ]) {
    for (final direction in [0.0, 37.0, 90.0, 147.0]) {
      test('$name keeps the whole strip clear at $direction degrees', () {
        final layout = RowLayout.of(
          region,
          RowSpec(width: 1, spacing: 0.5, border: 1, direction: direction),
        );
        expect(layout.runs, isNotEmpty);
        expectStripClearance(region, layout);
      });
    }
  }

  test('circle row lengths allow for the outer side of the full width', () {
    const circle = DiscRegion(Vec.zero, 5);
    final layout = RowLayout.of(
      circle,
      const RowSpec(width: 1, spacing: 1, border: 1),
    );
    expect(layout.rowCount, 4);
    for (final run in layout.runs) {
      final side = run.start.x.abs() + layout.spec.width / 2;
      final expected = 2 * math.sqrt(4 * 4 - side * side);
      expect(run.length, closeTo(expected, 1e-7));
    }
  });

  test('bordered rows leave equal clearance at opposing edges', () {
    for (final region in [square, const DiscRegion(Vec(6, 6), 6)]) {
      for (final width in [0.3048, 0.762, 1.0]) {
        for (final border in [0.3048, 1.0, 1.524]) {
          for (final direction in [0.0, 90.0]) {
            final spec = RowSpec(
              width: width,
              spacing: 0.4572,
              border: border,
              direction: direction,
            );
            final layout = RowLayout.of(region, spec);
            final (ax, ay) = spec.along;
            final across = Vec(-ay, ax);
            final first = layout.runs.first.start.dot(across) - width / 2;
            final last = layout.runs.last.start.dot(across) + width / 2;
            expect(
              first,
              closeTo(12 - last, 1e-7),
              reason:
                  'opposing borders: ${region.runtimeType}, '
                  'width=$width, border=$border, direction=$direction',
            );
            expect(first, greaterThanOrEqualTo(border - 1e-8));
            for (var i = 1; i < layout.runs.length; i++) {
              expect(
                (layout.runs[i].start - layout.runs[i - 1].start).dot(across),
                closeTo(spec.pitch, 1e-7),
              );
            }
          }
        }
      }
    }
  });

  test('turning bordered rows in a circle does not change how much fits', () {
    const circle = DiscRegion(Vec.zero, 5);
    const spec = RowSpec(width: 1, spacing: 1, border: 1);
    final north = RowLayout.of(circle, spec);
    for (final direction in [13.0, 37.0, 90.0, 147.0]) {
      final turned = RowLayout.of(circle, spec.copyWith(direction: direction));
      expect(turned.rowCount, north.rowCount);
      expect(turned.totalLength, closeTo(north.totalLength, 1e-7));
    }
  });

  test('a hole splits rows and reserves space around the hole too', () {
    final layout = RowLayout.of(
      hole,
      const RowSpec(width: 1, spacing: 1, border: 1),
    );
    final split = layout.runs.where((run) => (run.start.x - 6).abs() < 1e-8);
    expect(split, hasLength(2));
    expect(split.map((run) => run.length), everyElement(closeTo(3, 1e-8)));
  });

  test(
    'a circular hole beneath a wide row is not missed between its sides',
    () {
      final land = CurveRegion([
        square.contours.first,
        const DiscRegion(Vec(3.5, 6), 0.25).contours.first,
      ]);
      final layout = RowLayout.of(
        land,
        const RowSpec(width: 4, spacing: 1, border: 1),
      );
      final first = layout.runs.where(
        (run) => (run.start.x - 3.5).abs() < 1e-8,
      );
      expect(first, hasLength(2));
      expect(first.map((run) => run.length), everyElement(closeTo(3.75, 1e-8)));
      expectStripClearance(land, layout);
    },
  );

  test('a border that consumes the land produces no rows', () {
    for (final border in [5.75, 6.0, 20.0]) {
      final layout = RowLayout.of(square, RowSpec(width: 1, border: border));
      expect(layout.rowCount, 0);
      expect(layout.totalLength, 0);
      expect(layout.runs, isEmpty);
    }
  });

  test('a long row never bridges a narrow excluded interval', () {
    final land = CurveRegion([
      PolygonRegion(const [
        Vec(0, 0),
        Vec(1000, 0),
        Vec(1000, 1000),
        Vec(0, 1000),
      ]).contours.first,
      const DiscRegion(Vec(500, 500), 0.0000001).contours.first,
    ]);
    final layout = RowLayout.of(
      land,
      const RowSpec(width: 1, spacing: 2000, border: 0.0000001),
    );
    expect(layout.rowCount, 1);
    expect(layout.runs, hasLength(2));
    expect(layout.runs.first.end.y, greaterThan(500));
    expect(layout.runs.last.start.y, lessThan(500));
  });

  test('each separate piece receives its own border', () {
    final other = PolygonRegion(const [
      Vec(20, 0),
      Vec(26, 0),
      Vec(26, 6),
      Vec(20, 6),
    ]);
    const spec = RowSpec(width: 1, spacing: 1, border: 1);
    final layout = RowLayout.ofPieces([square, other], spec);
    final first = RowLayout.of(square, spec);
    final second = RowLayout.of(other, spec);
    expect(layout.rowCount, first.rowCount + second.rowCount);
    expect(
      layout.totalLength,
      closeTo(first.totalLength + second.totalLength, 1e-8),
    );
    expect(second.runs.first.start.x, closeTo(22, 1e-8));
    expectStripClearance(other, second);
  });

  test('zero border preserves the old edge-to-edge layout', () {
    const spec = RowSpec(width: 1, spacing: 1, direction: 37);
    final original = RowLayout.of(notch, spec);
    final reset = RowLayout.of(
      notch,
      spec.copyWith(border: 2).copyWith(border: 0),
    );
    expect(reset.rowCount, original.rowCount);
    expect(reset.totalLength, original.totalLength);
    expect(
      reset.runs.map((r) => (r.start, r.end)),
      original.runs.map((r) => (r.start, r.end)),
    );
  });

  test('border is validated and retained when other row settings change', () {
    const spec = RowSpec(border: 1.524);
    expect(spec.copyWith(width: 2).border, spec.border);
    expect(spec, isNot(const RowSpec()));
    expect({spec, spec.copyWith()}, hasLength(1));
    for (final value in [
      -1.0,
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      final invalid = spec.copyWith(border: value);
      expect(invalid.problem, isNotNull);
      expect(RowLayout.of(square, invalid).runs, isEmpty);
    }
  });
}

/// Check points throughout the strip, including its sides and square ends.
void expectStripClearance(Region region, RowLayout layout) {
  final (ax, ay) = layout.spec.along;
  final across = Vec(-ay, ax);
  final edges = region.contours.expand((c) => c).toList();
  for (final run in layout.runs) {
    for (var i = 0; i <= 20; i++) {
      for (var j = 0; j <= 10; j++) {
        final point =
            run.start +
            (run.end - run.start) * (i / 20) +
            across * ((j / 10 - 0.5) * layout.spec.width);
        expect(region.locate(point), PointLocation.inside);
        final clearance = edges
            .map((edge) => edge.distanceTo(point))
            .reduce(math.min);
        expect(
          clearance,
          greaterThanOrEqualTo(layout.spec.border - 1e-7),
          reason: 'strip point $point must leave the border clear',
        );
      }
    }
  }
}
