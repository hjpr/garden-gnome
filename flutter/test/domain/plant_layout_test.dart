import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/plant_layout.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

const _smallSeed = ZoneSeed(
  varietyId: 'test',
  name: 'Test',
  inRow: 0.5,
  betweenRows: 0.5,
);
const _wideRows = ZoneProperties(
  ground: GroundType.row,
  rows: RowSpec(width: 2, spacing: 0, direction: 0, border: 0),
);

const _seed = ZoneSeed(
  varietyId: 'test',
  name: 'Test',
  inRow: 0.5,
  betweenRows: 0.5,
);
const _flat = ZoneProperties(ground: GroundType.flat);
const _rows = ZoneProperties(
  ground: GroundType.row,
  rows: RowSpec(width: 0.5, spacing: 0.5, direction: 0, border: 0),
);

void main() {
  group('soil precedence', _overlapTests);
  final square = _rect(0, 0, 10, 10);
  final triangle = PolygonRegion(const [Vec(0, 0), Vec(10, 0), Vec(0, 10)]);
  // The hole misses the row centre at x=1 but intersects its shifted lines.
  final holed = CurveRegion([
    ...square.contours,
    ..._rect(1.5, 4, 2, 6).contours,
  ]);
  for (final (name, soil) in [('triangle', triangle), ('hole', holed)]) {
    test('shifted row plant lines stay inside soil: $name', () {
      final document = _garden([(soil, _wideRows)], square, _smallSeed);
      final layout = document.plantLayoutOf('grow')!;
      expect(layout.count, greaterThan(0));
      if (name == 'triangle') {
        expect(layout.positions, isNot(contains(const Vec(1.75, 8.75))));
      }
      for (final position in layout.positions) {
        expect(
          soil.locate(position),
          isNot(PointLocation.outside),
          reason: 'plant at $position',
        );
      }
      for (final line in layout.lines) {
        expect(
          soil.containsSegment(line.start, line.end),
          isTrue,
          reason: 'line ${line.start} to ${line.end}',
        );
      }
    });
  }
}

void _overlapTests() {
  final soil = _rect(2, 2, 12, 12);
  final grow = _rect(4, 4, 8, 10);
  test('identical Flat soils count and draw one layout', () {
    final layout = _garden(
      [(soil, _flat), (soil, _flat)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 96);
    expect(layout.positions.toSet(), hasLength(96));
    expect(layout.lines, hasLength(8));
    expect(layout.lineLength, closeTo(48, 1e-9));
  });

  test('partially overlapping Flat soils do not repeat the overlap', () {
    final layout = _garden(
      [(_rect(2, 2, 7, 12), _flat), (_rect(6, 2, 12, 12), _flat)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 96);
    expect(layout.positions.toSet(), hasLength(96));
    expect(layout.lineLength, closeTo(48, 1e-9));
  });

  for (final (name, bottom, top, count) in [
    ('Row above Flat', _flat, _rows, 48),
    ('Flat above Row', _rows, _flat, 96),
  ]) {
    test('topmost soil wins in drawingOrder: $name', () {
      final document = _garden([(soil, bottom), (soil, top)], grow, _seed);
      expect(document.drawingOrder, ['property', 'soil-0', 'soil-1', 'grow']);
      final layout = document.plantLayoutOf('grow')!;
      final topOnly = _garden(
        [(soil, top)],
        grow,
        _seed,
      ).plantLayoutOf('grow')!;
      expect(layout.count, count);
      expect(layout.positions, topOnly.positions);
      expect(layout.lineLength, topOnly.lineLength);
      expect(layout.soils, {top.ground});
    });
  }

  test('partial Row overlap owns its paths as well as its beds', () {
    final topSoil = _rect(6, 2, 12, 12);
    final layout = _garden(
      [(soil, _flat), (topSoil, _rows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    final topOnly = _garden(
      [(topSoil, _rows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 72);
    expect(layout.positions.toSet(), hasLength(72));
    expect(
      layout.positions.where((p) => p.x >= 6).toSet(),
      topOnly.positions.toSet(),
    );
    expect(layout.positions.where((p) => p.x < 6), hasLength(48));
    expect(layout.soils, {GroundType.flat, GroundType.row});
  });

  test('partial Flat overlap clips lower rows without realigning them', () {
    final topSoil = _rect(5, 6, 8, 8);
    final layout = _garden(
      [(soil, _rows), (topSoil, _flat)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    final lowerOnly = _garden(
      [(soil, _rows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    bool outsideTop(Vec p) => topSoil.locate(p) == PointLocation.outside;
    expect(layout.count, 60);
    expect(layout.positions.toSet(), hasLength(60));
    expect(
      layout.positions.where(outsideTop).toSet(),
      lowerOnly.positions.where(outsideTop).toSet(),
    );
  });

  test('topmost soil still owns land when its rows cannot fit the seed', () {
    final narrowRows = _rows.copyWith(rows: const RowSpec(width: 0.25));
    final layout = _garden(
      [(soil, _flat), (soil, narrowRows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 0);
    expect(layout.positions, isEmpty);
    expect(layout.lines, isEmpty);
    expect(layout.soils, isEmpty);
  });

  test('overlap counts stay exact beyond the drawing position cap', () {
    final denseSeed = _seed.copyWith(inRow: 0.02, betweenRows: 0.02);
    final layout = _garden(
      [(soil, _flat), (soil, _flat)],
      grow,
      denseSeed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 60000);
    expect(layout.positions, hasLength(PlantLayout.maxPositions));
    expect(layout.positions.toSet(), hasLength(PlantLayout.maxPositions));
  });

  test('holes in topmost soil expose the lower soil', () {
    final topSoil = CurveRegion([
      ...soil.contours,
      ..._rect(4, 5, 8, 9).contours,
    ]);
    final layout = _garden(
      [(soil, _flat), (topSoil, _rows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    // 64 Flat plants in the hole, 16 Row plants above and below it.
    expect(layout.count, 80);
    expect(layout.positions.toSet(), hasLength(80));
    expect(layout.positions.where((p) => p.y > 5 && p.y < 9), hasLength(64));
  });

  test('non-overlapping soils keep both layouts and their exact counts', () {
    final layout = _garden(
      [(_rect(2, 2, 5, 12), _flat), (_rect(6, 2, 12, 12), _rows)],
      grow,
      _seed,
    ).plantLayoutOf('grow')!;
    expect(layout.count, 48);
    expect(layout.positions, hasLength(48));
    expect(layout.positions.toSet(), hasLength(48));
    expect(layout.positions.where((p) => p.x < 5), hasLength(24));
    expect(layout.positions.where((p) => p.x > 6), hasLength(24));
    expect(layout.lineLength, closeTo(24, 1e-9));
  });
}

PolygonRegion _rect(double left, double top, double right, double bottom) =>
    PolygonRegion([
      Vec(left, top),
      Vec(right, top),
      Vec(right, bottom),
      Vec(left, bottom),
    ]);

GardenDocument _garden(
  List<(Region, ZoneProperties)> soils,
  Region grow,
  ZoneSeed seed,
) {
  final zones = [
    ...soils,
    (grow, ZoneProperties(ground: GroundType.grow, seed: seed)),
  ];
  final ids = [for (var i = 0; i < soils.length; i++) 'soil-$i', 'grow'];
  return GardenDocument(
    id: 'test',
    propertyIds: const ['property'],
    layers: {
      'property': Layer(
        id: 'property',
        kind: LayerKind.property,
        name: 'Property',
        geometryId: 'property-geometry',
        properties: const PropertyProperties(),
        children: ids,
      ),
      for (var i = 0; i < zones.length; i++)
        ids[i]: Layer(
          id: ids[i],
          kind: LayerKind.zone,
          name: ids[i],
          parentId: 'property',
          geometryId: '${ids[i]}-geometry',
          properties: zones[i].$2,
        ),
    },
    geometries: {
      'property-geometry': _geometry('property', _rect(-1, -1, 20, 20)),
      for (var i = 0; i < zones.length; i++)
        '${ids[i]}-geometry': _geometry(ids[i], zones[i].$1),
    },
  );
}

Geometry _geometry(String owner, Region region) {
  final points = <String, Vec>{};
  final lines = <String, LineSegment>{};
  final rings = <List<SegmentRef>>[];
  for (var r = 0; r < region.contours.length; r++) {
    final contour = region.contours[r];
    final ring = <SegmentRef>[];
    for (var i = 0; i < contour.length; i++) {
      final pointId = 'p-$r-$i';
      final lineId = 'l-$r-$i';
      points[pointId] = contour[i].start;
      lines[lineId] = LineSegment(
        lineId,
        pointId,
        'p-$r-${(i + 1) % contour.length}',
        bulge: contour[i].bulge,
      );
      ring.add(SegmentRef(lineId));
    }
    rings.add(ring);
  }
  return Geometry(
    id: '$owner-geometry',
    ownerLayerId: owner,
    points: points,
    lines: lines,
    shapes: {
      'shape-1': ClosedShape(
        'shape-1',
        rings.first,
        holes: rings.skip(1).toList(),
      ),
    },
  );
}
