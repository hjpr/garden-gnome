import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/geometry_rules.dart';
import 'package:garden_gnome/domain/vec.dart';

const _rim = [SegmentRef('line-1', reversed: true), SegmentRef('line-2')];

Geometry _semicircle({List<List<SegmentRef>> holes = const []}) => Geometry(
  id: 'geometry-1',
  ownerLayerId: 'layer-1',
  points: const {'point-1': Vec(-2, 0), 'point-2': Vec(2, 0)},
  lines: const {
    'line-1': LineSegment('line-1', 'point-2', 'point-1', bulge: -1),
    'line-2': LineSegment('line-2', 'point-2', 'point-1'),
  },
  shapes: {'shape-1': ClosedShape('shape-1', _rim, holes: holes)},
);

void main() {
  group('geometry contour queries', () {
    test(
      'two-edge rings resolve reversed references without changing winding',
      () {
        final geometry = _semicircle();
        final contour = geometry.contourOf(_rim)!;
        expect(geometry.cornersOf('shape-1'), ['point-1', 'point-2']);
        expect(
          [for (final edge in contour) (edge.start, edge.end, edge.bulge)],
          [
            (const Vec(-2, 0), const Vec(2, 0), 1.0),
            (const Vec(2, 0), const Vec(-2, 0), 0.0),
          ],
        );
        expect(geometry.regionOf('line-1')!.area, closeTo(math.pi * 2, 1e-12));
        expect(geometryProblem(geometry), isNull);
        contour.clear();
        expect(geometry.contourOf(_rim), hasLength(2));
        expect(geometry.closedIds, ['shape-1']);
      },
    );

    test(
      'open, missing, disconnected and repeated-corner rings have no contour',
      () {
        final geometry = _semicircle();
        for (final ring in <List<SegmentRef>>[
          [],
          [_rim.first],
          [_rim.first, const SegmentRef('missing')],
          [_rim.first, const SegmentRef('line-2', reversed: true)],
          [..._rim, ..._rim],
        ]) {
          expect(geometry.contourOf(ring), isNull);
        }
        final missingPoint = Geometry(
          id: geometry.id,
          ownerLayerId: geometry.ownerLayerId,
          points: {'point-1': geometry.points['point-1']!},
          lines: geometry.lines,
          shapes: geometry.shapes,
        );
        expect(missingPoint.contourOf(_rim), isNull);
        expect(missingPoint.regionOf('shape-1'), isNull);
        expect(geometryProblem(missingPoint), 'A line is missing an end point');
      },
    );

    test('an open hole keeps the whole shape open, not just the hole', () {
      final geometry = _semicircle(
        holes: [
          const [SegmentRef('missing')],
        ],
      );
      expect(geometry.contourOf(_rim), hasLength(2));
      expect(geometry.cornersOf('shape-1'), isEmpty);
      expect(geometry.regionOf('shape-1'), isNull);
      expect(geometry.closedIds, isEmpty);
      expect(geometry.unfinishedReason, 'Shape 1 is not closed');
      expect(geometryProblem(geometry), 'A shape is missing an edge');
    });

    test('closed references are not a validity check for collapsed drafts', () {
      final collapsed = _semicircle().edit(
        (editor) => editor.movePoint('point-2', const Vec(-2, 0)),
      );
      expect(collapsed.contourOf(_rim), hasLength(2));
      expect(collapsed.regionOf('shape-1'), isNull);
      expect(geometryProblem(collapsed), 'A line must have length');
    });

    test(
      'reversing a Bezier reference reverses every fitted edge and its order',
      () {
        const curve = LineSegment(
          'line-1',
          'point-1',
          'point-2',
          startHandle: Vec(0, -3),
          endHandle: Vec(0, -1),
        );
        const rim = [
          SegmentRef('line-2', reversed: true),
          SegmentRef('line-1', reversed: true),
        ];
        final geometry = Geometry(
          id: 'geometry-1',
          ownerLayerId: 'layer-1',
          points: const {'point-1': Vec(-2, 0), 'point-2': Vec(2, 0)},
          lines: const {
            'line-1': curve,
            'line-2': LineSegment('line-2', 'point-2', 'point-1'),
          },
          shapes: {'shape-1': ClosedShape('shape-1', rim)},
        );
        final contour = geometry.contourOf(rim)!;
        final fitted = curve.edges(geometry.points);
        expect(fitted.length, greaterThan(1));
        expect(contour.first.start, const Vec(-2, 0));
        expect(contour.first.end, const Vec(2, 0));
        expect(
          [
            for (final edge in contour.skip(1))
              (edge.start, edge.end, edge.bulge),
          ],
          [
            for (final edge in fitted.reversed)
              (edge.end, edge.start, -edge.bulge),
          ],
        );
        expect(geometry.cornersOf('shape-1'), ['point-1', 'point-2']);
        expect(geometryProblem(geometry), isNull);
      },
    );
  });

  group('geometry editing API', () {
    test(
      'editing preserves identity, counter floors and compatibility dimensions',
      () {
        const dimensions = PlantingDimensions(
          rowWidth: 1,
          rowSpacing: 2,
          rowDirection: 30,
          moundDiameter: 3,
          moundSpacing: 4,
        );
        final source = Geometry(
          id: 'geometry-7',
          ownerLayerId: 'layer-7',
          points: const {'point-12': Vec.zero},
          counters: const IdCounters(points: 2, lines: 5),
          dimensions: dimensions,
        );
        final editor = GeometryEditor(source);
        final point = editor.addPoint(const Vec(3, 4));
        final line = editor.connect('point-12', point);
        final built = editor.build();
        expect(point, 'point-13');
        expect(line, 'line-6');
        expect(built.id, source.id);
        expect(built.ownerLayerId, source.ownerLayerId);
        expect(built.dimensions, same(dimensions));
        expect(source.points, {'point-12': Vec.zero});
        expect(source.lines, isEmpty);
        editor.movePoint(point, const Vec(6, 8));
        expect(built.points[point], const Vec(3, 4));
        expect(() => built.points.clear(), throwsUnsupportedError);
        final copied = built.edit((edit) => edit.delete([line]));
        expect(copied.dimensions, same(dimensions));
        expect(copied.counters.sameAs(built.counters), isTrue);
        expect(built.lines.keys, [line]);
      },
    );

    test('an unrepresentable edit still reports the same rule error', () {
      final source = _semicircle();
      expect(
        () => source.edit((editor) => editor.connect('point-1', 'point-1')),
        throwsA(
          isA<GeometryRuleError>().having(
            (error) => error.message,
            'message',
            'Choose two different points',
          ),
        ),
      );
      expect(source.closedIds, ['shape-1']);
      expect(geometryProblem(source), isNull);
    });
  });
}
