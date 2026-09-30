import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/geometry_rules.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

Geometry _empty() => Geometry(id: 'g', ownerLayerId: 'layer');

List<Vec> _rect(double x, double y, double w, double h) => [
  Vec(x, y),
  Vec(x + w, y),
  Vec(x + w, y + h),
  Vec(x, y + h),
];

Geometry _loop(Geometry geometry, List<Vec> corners, {double firstBulge = 0}) =>
    geometry.edit((e) {
      final points = corners.map(e.addPoint).toList();
      for (var i = 0; i < points.length; i++) {
        e.connect(
          points[i],
          points[(i + 1) % points.length],
          bulge: i == 0 ? firstBulge : 0,
        );
      }
    });

Geometry _disc(Geometry geometry, Vec centre, double radius) =>
    geometry.edit((e) => e.addCircle(e.addPoint(centre), radius));

Geometry _annulus() => _disc(
  _disc(_empty(), Vec.zero, 10),
  Vec.zero,
  3,
).edit((e) => e.boolean('circle-2', BooleanOperation.subtract));

void _unchanged(Geometry actual, Geometry before) {
  expect(actual.points, before.points);
  expect(actual.lines, before.lines);
  expect(actual.circles, before.circles);
  expect(actual.shapes, before.shapes);
  expect(actual.stack, before.stack);
  expect(actual.counters.sameAs(before.counters), isTrue);
}

void main() {
  group('shapes on one layer', () {
    test('every closed shape and circle is part of the layer, in order', () {
      var geometry = _disc(_empty(), Vec.zero, 5);
      geometry = _disc(geometry, const Vec(5, 0), 4);
      geometry = _loop(geometry, _rect(2, -2, 7, 7));
      expect(geometry.stack, ['circle-1', 'circle-2', 'shape-1']);
      expect(geometry.closedIds, hasLength(3));
      expect(geometry.regionOf('circle-2'), isNotNull);
      expect(geometry.regionOf('shape-1'), isNotNull);
      expect(geometryProblem(geometry), isNull);
    });

    test('operand lookup accepts corners, outlines, and circle centres', () {
      var geometry = _loop(_empty(), _rect(0, 0, 10, 10));
      geometry = _loop(geometry, _rect(5, 5, 10, 10));
      geometry = _disc(geometry, const Vec(15, 15), 2);
      geometry = geometry.edit((e) => e.addPoint(const Vec(30, 30)));
      expect(geometry.shapeIdFor('line-5'), 'shape-2');
      expect(geometry.shapeIdFor('point-5'), 'shape-2');
      expect(geometry.shapeIdFor('point-9'), 'circle-1');
      expect(geometry.shapeIdFor('point-10'), isNull);
      expect(geometry.regionOf('line-5')!.area, closeTo(100, 1e-8));
      expect(geometry.regionOf('point-10'), isNull);
    });

    test('coincident outlines and tangencies between operands are legal', () {
      final square = _loop(_empty(), _rect(0, 0, 10, 10));
      expect(geometryProblem(_loop(square, _rect(0, 0, 10, 10))), isNull);
      expect(geometryProblem(_loop(square, _rect(10, 0, 5, 10))), isNull);
      expect(geometryProblem(_disc(square, const Vec(15, 5), 5)), isNull);
    });

    test('closing another loop does not claim an existing hole', () {
      final annulus = _annulus();
      final grouped = _loop(annulus, _rect(20, 20, 2, 2));
      expect(grouped.boundaryId, annulus.boundaryId);
      expect(grouped.boundary!.holes, hasLength(1));
      expect(grouped.area, closeTo(annulus.region!.area + 4, 1e-8));
      expect(grouped.shapes, hasLength(2));
    });

    test('an island inside another shape\'s hole is separate land', () {
      final grouped = _disc(_annulus(), Vec.zero, 2);
      expect(grouped.area, closeTo(math.pi * (100 - 9 + 4), 1e-8));
      expect(grouped.region!.locate(Vec.zero), PointLocation.inside);
      expect(grouped.region!.locate(const Vec(2.5, 0)), PointLocation.outside);
    });
  });

  group('destructive Boolean', () {
    test(
      'subtract makes a hole with exact circular area and editable arcs',
      () {
        final before = _disc(
          _loop(_empty(), _rect(-10, -10, 20, 20)),
          Vec.zero,
          3,
        );
        late String resultId;
        final result = before.edit((e) {
          resultId = e.boolean('circle-1', BooleanOperation.subtract).single;
        });
        expect(result.boundaryId, resultId);
        expect(result.boundary!.holes, hasLength(1));
        expect(result.boundary!.rings, hasLength(2));
        expect(result.region!.area, closeTo(400 - math.pi * 9, 1e-8));
        expect(result.region!.locate(Vec.zero), PointLocation.outside);
        expect(result.lines.values.any((line) => line.bulge != 0), isTrue);
        expect(result.circles, isEmpty);
        expect(geometryProblem(result), isNull);
      },
    );

    test('union merges every overlapping shape and leaves the rest alone', () {
      var before = _loop(_empty(), _rect(0, 0, 10, 10));
      before = _loop(before, _rect(5, 0, 10, 10));
      before = _disc(before, const Vec(40, 40), 2);
      late String looseLine;
      late String loosePoint;
      before = before.edit((e) {
        loosePoint = e.addPoint(const Vec(50, 50));
        looseLine = e.connect(
          e.addPoint(const Vec(30, 0)),
          e.addPoint(const Vec(35, 0)),
        );
      });
      final consumedPoints = before.definingPoints(['shape-1', 'shape-2']);
      final consumedLines = {
        for (final shape in before.shapes.values)
          for (final ref in shape.segments) ref.segmentId,
      };
      final result = before.edit(
        (e) => e.boolean('line-5', BooleanOperation.union),
      );
      expect(result.regionOf('shape-3')!.area, closeTo(150, 1e-8));
      expect(result.shapes.keys, ['shape-3']);
      expect(result.stack, ['shape-3', 'circle-1']);
      expect(result.points.keys.toSet().intersection(consumedPoints), isEmpty);
      expect(result.lines.keys.toSet().intersection(consumedLines), isEmpty);
      expect(result.points[loosePoint], before.points[loosePoint]);
      expect(
        identical(result.lines[looseLine], before.lines[looseLine]),
        isTrue,
      );
      expect(
        identical(result.circles['circle-1'], before.circles['circle-1']),
        isTrue,
      );
      expect(geometryProblem(result), isNull);
    });

    test(
      'a consumed circle centre shared with loose construction is retained',
      () {
        var before = _disc(_empty(), Vec.zero, 5);
        before = _disc(before, const Vec(4, 0), 5);
        late String looseLine;
        before = before.edit((e) {
          looseLine = e.connect('point-1', e.addPoint(const Vec(0, 1)));
        });
        final result = before.edit(
          (e) => e.boolean('circle-2', BooleanOperation.union),
        );
        expect(result.points['point-1'], Vec.zero);
        expect(result.points.containsKey('point-2'), isFalse);
        expect(
          identical(result.lines[looseLine], before.lines[looseLine]),
          isTrue,
        );
        expect(result.circles, isEmpty);
      },
    );

    test('the cut shape\'s label and dimensions survive generated IDs', () {
      final base = _loop(_empty(), _rect(0, 0, 10, 10));
      final styled = Geometry(
        id: base.id,
        ownerLayerId: base.ownerLayerId,
        points: base.points,
        lines: base.lines,
        shapes: {
          'shape-1': ClosedShape(
            'shape-1',
            base.boundary!.segments,
            label: 'Beds',
          ),
        },
        counters: base.counters,
        dimensions: const PlantingDimensions(rowWidth: 2),
      );
      final before = _loop(styled, _rect(2, 2, 3, 3));
      final result = before.edit(
        (e) => e.boolean('shape-2', BooleanOperation.subtract),
      );
      expect(result.boundary!.label, 'Beds');
      expect(result.dimensions!.rowWidth, 2);
      expect(result.counters.shapes, greaterThan(before.counters.shapes));
      for (final id in result.points.keys) {
        expect(
          int.parse(id.split('-').last),
          greaterThan(before.counters.points),
        );
      }
      for (final id in result.lines.keys) {
        expect(
          int.parse(id.split('-').last),
          greaterThan(before.counters.lines),
        );
      }
      final next = result.edit((e) {
        e.delete([result.boundaryId!]);
        e.addPoint(const Vec(50, 50));
      });
      expect(next.counters.points, result.counters.points + 1);
    });

    test(
      'refused empty and non-overlapping operations leave the editor unchanged',
      () {
        final main = _loop(_empty(), _rect(0, 0, 10, 10));
        final cases = [
          (
            _loop(main, _rect(-1, -1, 12, 12)),
            BooleanOperation.subtract,
            'remove all',
          ),
          (
            _loop(main, _rect(20, 0, 10, 10)),
            BooleanOperation.union,
            'does not overlap',
          ),
          (
            _loop(main, _rect(20, 0, 10, 10)),
            BooleanOperation.subtract,
            'Nothing below',
          ),
        ];
        for (final (before, operation, message) in cases) {
          final editor = GeometryEditor(before);
          expect(
            () => editor.boolean('shape-2', operation),
            throwsA(
              isA<GeometryRuleError>().having(
                (e) => e.message,
                'message',
                contains(message),
              ),
            ),
          );
          _unchanged(editor.build(), before);
          expect(
            () => before.edit((e) => e.boolean('shape-2', operation)),
            throwsA(isA<GeometryRuleError>()),
          );
          expect(before.shapes, hasLength(2));
        }
      },
    );

    test(
      'self-crossing arcs are refused before either operand is consumed',
      () {
        final before = _loop(
          _loop(_empty(), _rect(-20, -20, 40, 40)),
          _rect(0, 0, 10, 3),
          firstBulge: -1,
        );
        expect(geometryProblem(before), contains('cross'));
        final editor = GeometryEditor(before);
        expect(
          () => editor.boolean('shape-2', BooleanOperation.subtract),
          throwsA(
            isA<GeometryRuleError>().having(
              (e) => e.message,
              'message',
              contains('Cannot combine Shape 2'),
            ),
          ),
        );
        _unchanged(editor.build(), before);
      },
    );

    test('subtract can split the cut shape into separate pieces', () {
      final before = _loop(
        _loop(_empty(), _rect(0, 0, 10, 10)),
        _rect(4, -2, 2, 14),
      );
      late List<String> pieces;
      final result = before.edit(
        (e) => pieces = e.boolean('shape-2', BooleanOperation.subtract),
      );
      expect(pieces, hasLength(2));
      expect(result.stack, pieces);
      expect(result.area, closeTo(80, 1e-8));
      expect(geometryProblem(result), isNull);
    });

    test('subtract only cuts shapes below the cutter in the stack', () {
      var before = _loop(_empty(), _rect(0, 0, 10, 10));
      before = _loop(before, _rect(4, 4, 2, 2));
      before = _loop(before, _rect(20, 0, 10, 10));
      before = before.edit((e) => e.moveInStack('shape-3', 2));
      // shape-2 cuts shape-1 (below it) but not shape-3, which it misses.
      final result = before.edit(
        (e) => e.boolean('shape-2', BooleanOperation.subtract),
      );
      expect(result.area, closeTo(96 + 100, 1e-8));
      expect(result.shapes.containsKey('shape-3'), isTrue);

      // Moved to the bottom, the same cutter has nothing below to cut.
      final bottom = before.edit((e) => e.moveInStack('shape-2', 0));
      expect(
        () =>
            bottom.edit((e) => e.boolean('shape-2', BooleanOperation.subtract)),
        throwsA(isA<GeometryRuleError>()),
      );
    });

    test('new IDs exceed existing IDs even with an old counter floor', () {
      final original = _loop(
        _loop(_empty(), _rect(0, 0, 10, 10)),
        _rect(5, 0, 10, 10),
      );
      final before = original.copyWith(counters: const IdCounters());
      final result = before.edit(
        (e) => e.boolean('shape-2', BooleanOperation.union),
      );
      expect(result.boundaryId, 'shape-3');
      for (final id in result.points.keys) {
        expect(
          int.parse(id.split('-').last),
          greaterThan(original.counters.points),
        );
      }
      for (final id in result.lines.keys) {
        expect(
          int.parse(id.split('-').last),
          greaterThan(original.counters.lines),
        );
      }
    });

    test('large translated inputs keep the correct outer ring and hole', () {
      final before = _loop(
        _loop(_empty(), _rect(1e9, 1e9, 10, 10)),
        _rect(1e9 + 2, 1e9 + 2, 4, 4),
      );
      final result = before.edit(
        (e) => e.boolean('shape-2', BooleanOperation.subtract),
      );
      expect(result.boundary!.holes, hasLength(1));
      expect(result.region!.area, closeTo(100 - 16, 1e-8));
      expect(geometryProblem(result), isNull);
    });

    test(
      'a later union can refill a hole without retaining its old points',
      () {
        final annulus = _annulus();
        final before = _disc(annulus, Vec.zero, 3);
        final holePoints = before.definingPoints(
          before.boundary!.holes.single.map((ref) => ref.segmentId),
        );
        final result = before.edit(
          (e) => e.boolean('circle-3', BooleanOperation.union),
        );
        expect(result.boundary!.holes, isEmpty);
        expect(result.region!.area, closeTo(math.pi * 100, 1e-8));
        expect(result.points.keys.toSet().intersection(holePoints), isEmpty);
        expect(geometryProblem(result), isNull);
      },
    );

    test('external tangency is legal but is not an overlap to Union', () {
      final before = _disc(_disc(_empty(), Vec.zero, 5), const Vec(10, 0), 5);
      expect(geometryProblem(before), isNull);
      final editor = GeometryEditor(before);
      expect(
        () => editor.boolean('circle-2', BooleanOperation.union),
        throwsA(
          isA<GeometryRuleError>().having(
            (e) => e.message,
            'message',
            contains('does not overlap'),
          ),
        ),
      );
      _unchanged(editor.build(), before);
    });

    test('an open or unrelated item cannot be an operand', () {
      final before = _loop(
        _empty(),
        _rect(0, 0, 10, 10),
      ).edit((e) => e.addPoint(const Vec(20, 20)));
      for (final id in ['point-5', 'shape-1', 'shape-99']) {
        expect(
          () => before.edit((e) => e.boolean(id, BooleanOperation.union)),
          throwsA(isA<GeometryRuleError>()),
        );
      }
    });
  });

  group('editable result rings', () {
    test('an arc and its chord form a valid two-edge boundary', () {
      final geometry = _loop(_empty(), const [
        Vec(-5, 0),
        Vec(5, 0),
      ], firstBulge: 1);
      expect(geometry.isClosed, isTrue);
      expect(geometry.region!.area, closeTo(math.pi * 25 / 2, 1e-8));
      expect(geometryProblem(geometry), isNull);
    });

    test(
      'splitting either sweep direction or a major arc preserves the curve',
      () {
        for (final bulge in [1.0, -1.0, 2.0, -2.0]) {
          final original = _empty().edit((e) {
            e.connect(
              e.addPoint(const Vec(-5, 0)),
              e.addPoint(const Vec(5, 0)),
              bulge: bulge,
            );
          });
          final edge = original.lines.values.single.curve(original.points);
          final split = original.edit(
            (e) => e.insertPoint('line-1', edge.pointAt(0.37)),
          );
          final parts = split.lines.values
              .map((line) => line.curve(split.points))
              .toList();
          expect(
            parts.fold(0.0, (v, edge) => v + edge.length),
            closeTo(edge.length, 1e-8),
          );
          expect(
            parts.fold(0.0, (v, edge) => v + edge.sweep),
            closeTo(edge.sweep, 1e-8),
          );
          expect(
            parts.fold(0.0, (v, edge) => v + edge.signedArea),
            closeTo(edge.signedArea, 1e-8),
          );
          expect(
            parts.every((part) => part.centre.distanceTo(edge.centre) < 1e-8),
            isTrue,
          );
          expect(geometryProblem(split), isNull);
        }
      },
    );

    test(
      'splitting and repairing a hole preserve its shape identity and area',
      () {
        final annulus = _annulus();
        final line =
            annulus.lines[annulus.boundary!.holes.single.first.segmentId]!;
        final split = annulus.edit(
          (e) =>
              e.insertPoint(line.id, line.curve(annulus.points).pointAt(0.5)),
        );
        expect(split.boundaryId, annulus.boundaryId);
        expect(
          split.boundary!.holes.single.length,
          annulus.boundary!.holes.single.length + 1,
        );
        expect(split.region!.area, closeTo(annulus.region!.area, 1e-8));
        final removed =
            split.lines[split.boundary!.holes.single.first.segmentId]!;
        final opened = split.edit((e) => e.delete([removed.id]));
        expect(opened.boundaryId, annulus.boundaryId);
        expect(opened.boundary!.holes, hasLength(1));
        expect(opened.isClosed, isFalse);
        final repaired = opened.edit(
          (e) => e.connect(removed.start, removed.end, bulge: removed.bulge),
        );
        expect(repaired.boundaryId, annulus.boundaryId);
        expect(repaired.isClosed, isTrue);
        expect(repaired.region!.area, closeTo(annulus.region!.area, 1e-8));
        expect(geometryProblem(repaired), isNull);
      },
    );

    test(
      'whole-shape movement includes hole points and preserves all bulges',
      () {
        final before = _annulus();
        final anchors = before.definingPoints([before.boundaryId!]);
        expect(anchors.length, before.points.length);
        expect(before.boundaryAnchors.toSet(), anchors);
        final moved = before.edit((e) {
          for (final id in anchors) {
            e.movePoint(id, before.points[id]! + const Vec(20, 30));
          }
        });
        expect(moved.region!.area, closeTo(before.region!.area, 1e-8));
        expect(moved.region!.locate(const Vec(20, 30)), PointLocation.outside);
        expect(moved.region!.locate(const Vec(25, 30)), PointLocation.inside);
        expect(
          moved.lines.values.map((line) => line.bulge),
          before.lines.values.map((line) => line.bulge),
        );
        expect(geometryProblem(moved), isNull);
      },
    );

    test('deleting a whole result removes outer and hole edges', () {
      final before = _annulus();
      final deleted = before.edit((e) => e.delete([before.boundaryId!]));
      expect(deleted.lines, isEmpty);
      expect(
        deleted.points,
        isEmpty,
        reason: 'deleting a whole shape takes its points with it',
      );
      expect(deleted.isClosed, isFalse);
      expect(deleted.shapes, isEmpty);
      expect(deleted.stack, isEmpty);
      final redrawn = _loop(deleted, _rect(20, 20, 5, 5));
      expect(redrawn.stack, hasLength(1));
      expect(redrawn.isClosed, isTrue);
      expect(geometryProblem(redrawn), isNull);
    });

    test('a hole moved outside its outer ring is invalid', () {
      final before = _annulus();
      final holePoints = before.definingPoints(
        before.boundary!.holes.single.map((ref) => ref.segmentId),
      );
      final moved = before.edit((e) {
        for (final id in holePoints) {
          e.movePoint(id, before.points[id]! + const Vec(30, 0));
        }
      });
      expect(geometryProblem(moved), contains('hole'));
    });

    test(
      'splitting a reversed arc reference keeps a two-edge boundary closed',
      () {
        final before = _loop(_empty(), const [
          Vec(-5, 0),
          Vec(5, 0),
        ], firstBulge: -2);
        final arcRef = before.boundary!.segments.singleWhere(
          (ref) => ref.segmentId == 'line-1',
        );
        expect(arcRef.reversed, isTrue);
        final edge = before.lines['line-1']!.curve(before.points);
        final split = before.edit(
          (e) => e.insertPoint('line-1', edge.pointAt(0.4)),
        );
        expect(split.boundaryId, before.boundaryId);
        expect(split.boundaryCorners, hasLength(3));
        expect(split.region!.area, closeTo(before.region!.area, 1e-8));
        expect(geometryProblem(split), isNull);
      },
    );

    test('hole interiors may neither overlap nor nest after editing', () {
      final base = _disc(
        _disc(_empty(), Vec.zero, 20),
        const Vec(-5, 0),
        2,
      ).edit((e) => e.boolean('circle-2', BooleanOperation.subtract));
      final before = _disc(
        base,
        const Vec(5, 0),
        1,
      ).edit((e) => e.boolean('circle-3', BooleanOperation.subtract));
      expect(before.boundary!.holes, hasLength(2));
      final smaller = before.boundary!.holes.singleWhere(
        (ring) =>
            before.lines[ring.first.segmentId]!.curve(before.points).radius <
            1.5,
      );
      final anchors = before.definingPoints(
        smaller.map((ref) => ref.segmentId),
      );
      for (final offset in [const Vec(-8, 0), const Vec(-10, 0)]) {
        final invalid = before.edit((e) {
          for (final id in anchors) {
            e.movePoint(id, before.points[id]! + offset);
          }
        });
        expect(geometryProblem(invalid), isNotNull);
      }
    });

    test('arc crossings are detected even when their chords do not cross', () {
      final crossed = _empty().edit((e) {
        e.connect(
          e.addPoint(const Vec(0, 0)),
          e.addPoint(const Vec(10, 0)),
          bulge: -1,
        );
        e.connect(
          e.addPoint(const Vec(3, 4)),
          e.addPoint(const Vec(7, 4)),
          bulge: -1,
        );
      });
      expect(geometryProblem(crossed), contains('cross'));
    });
  });
}
