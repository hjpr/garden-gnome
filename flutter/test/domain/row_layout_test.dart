import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/row_layout.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/ground.dart';

void main() {
  group('Row layout', () {
    final square = PolygonRegion(const [
      Vec(0, 0),
      Vec(10, 0),
      Vec(10, 6),
      Vec(0, 6),
    ]);

    test('north–south rows fill the width edge to edge', () {
      // 10 m wide, 1 m rows with 1 m paths: rows at 0.5, 2.5 … 8.5.
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 1, spacing: 1, direction: 0),
      );
      expect(layout.rowCount, 5);
      expect(layout.totalLength, closeTo(30, 1e-6));
      expect(layout.bedArea, closeTo(30, 1e-6));
      expect(layout.runs.first.start.x, closeTo(0.5, 1e-9));
    });

    test('east–west rows run along the other side', () {
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 1, spacing: 1, direction: 90),
      );
      expect(layout.rowCount, 3);
      expect(layout.totalLength, closeTo(30, 1e-6));
    });

    test('a border reserves space at row sides and both ends', () {
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 1, spacing: 1, border: 1),
      );
      expect(layout.rowCount, 4);
      expect(layout.totalLength, closeTo(16, 1e-6));
      expect(layout.bedArea, closeTo(16, 1e-6));
      expect(layout.runs.first.start.x, closeTo(2, 1e-9));
      expect(layout.runs.last.start.x, closeTo(8, 1e-9));
      for (final run in layout.runs) {
        expect(run.start.y, closeTo(5, 1e-9));
        expect(run.end.y, closeTo(1, 1e-9));
      }
      expect(square.area, 60, reason: 'the zone itself is not resized');
    });

    test('a hole splits a row into two runs', () {
      final holed = CurveRegion([
        PolygonRegion(const [
          Vec(0, 0),
          Vec(10, 0),
          Vec(10, 10),
          Vec(0, 10),
        ]).contours.first,
        PolygonRegion(const [
          Vec(4, 4),
          Vec(6, 4),
          Vec(6, 6),
          Vec(4, 6),
        ]).contours.first,
      ]);
      final layout = RowLayout.of(
        holed,
        const RowSpec(width: 1, spacing: 1, direction: 90),
      );
      // Rows at y = 0.5, 2.5, 4.5, 6.5, 8.5; the one at 4.5 is cut in two.
      expect(layout.rowCount, 5);
      expect(layout.runs, hasLength(6));
      expect(layout.totalLength, closeTo(48, 1e-6));
    });

    test('a whole row fits exactly between five-foot borders', () {
      const foot = 0.3048;
      final garden = PolygonRegion(const [
        Vec(0, 0),
        Vec(12 * foot, 0),
        Vec(12 * foot, 20 * foot),
        Vec(0, 20 * foot),
      ]);
      final layout = RowLayout.of(
        garden,
        const RowSpec(width: 2 * foot, spacing: foot, border: 5 * foot),
      );
      expect(layout.rowCount, 1);
      expect(layout.totalLength, closeTo(10 * foot, 1e-8));
    });

    test('far too many rows lays out none rather than freezing', () {
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 0.0001, spacing: 0),
      );
      expect(layout.runs, isEmpty);
    });
  });
}
