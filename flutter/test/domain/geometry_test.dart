import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/geometry_rules.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

Geometry emptyGeometry() => Geometry(id: 'g', ownerLayerId: 'layer');

/// Draws a closed loop through [corners] and returns the result.
Geometry loop(List<Vec> corners, {Geometry? start}) {
  return (start ?? emptyGeometry()).edit((e) {
    final ids = corners.map(e.addPoint).toList();
    for (var i = 0; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
  });
}

const square = [Vec(0, 0), Vec(10, 0), Vec(10, 10), Vec(0, 10)];

void main() {
  group('boundary', () {
    test('the first closed loop becomes the boundary', () {
      final geometry = loop(square);
      expect(geometry.isClosed, isTrue);
      expect(geometry.boundaryId, 'shape-1');
      expect(geometry.boundaryCorners, hasLength(4));
      expect(geometryProblem(geometry), isNull);
    });

    test('an open path has no boundary', () {
      final geometry = emptyGeometry().edit((e) {
        final a = e.addPoint(const Vec(0, 0));
        final b = e.addPoint(const Vec(5, 0));
        e.connect(a, b);
      });
      expect(geometry.boundaryId, isNull);
      expect(geometry.isClosed, isFalse);
    });

    test(
      'deleting a line reopens the same boundary and repair restores it',
      () {
        final closed = loop(square);
        final opened = closed.edit((e) => e.delete(['line-4']));
        expect(opened.isClosed, isFalse);
        expect(opened.boundaryId, 'shape-1');
        expect(opened.boundary!.segments, hasLength(3));

        final repaired = opened.edit((e) => e.connect('point-4', 'point-1'));
        expect(repaired.isClosed, isTrue);
        expect(repaired.boundaryId, 'shape-1');
        expect(repaired.lines.containsKey('line-5'), isTrue);
      },
    );

    test('repairing through new corners extends the same boundary', () {
      final opened = loop(square).edit((e) => e.delete(['line-4']));
      final repaired = opened.edit((e) {
        final corner = e.addPoint(const Vec(-5, 5));
        e.connect('point-4', corner);
        e.connect(corner, 'point-1');
      });
      expect(repaired.boundaryId, 'shape-1');
      expect(repaired.boundaryCorners, hasLength(5));
    });

    test('a second loop joins the layer as more land, on top', () {
      final geometry = loop(square);
      final grouped = loop(const [
        Vec(20, 0),
        Vec(30, 0),
        Vec(30, 10),
      ], start: geometry);
      expect(grouped.stack, ['shape-1', 'shape-2']);
      expect(grouped.closedIds, ['shape-1', 'shape-2']);
      expect(grouped.area, closeTo(150, 1e-9));
      expect(grouped.region!.area, closeTo(150, 1e-9));
      expect(grouped.unfinishedReason, isNull);
      expect(geometryProblem(grouped), isNull);
    });

    test('shapes get automatic labels until renamed', () {
      final geometry = loop(
        square,
      ).edit((e) => e.addCircle(e.addPoint(const Vec(40, 40)), 2));
      expect(geometry.labelOf('shape-1'), 'Shape 1');
      expect(geometry.labelOf('circle-1'), 'Circle 1');
      final named = geometry.edit((e) => e.setLabel('circle-1', 'Apples'));
      expect(named.labelOf('circle-1'), 'Apples');
      expect(
        named.edit((e) => e.setLabel('circle-1', null)).labelOf('circle-1'),
        'Circle 1',
      );
    });

    test('the stack can be reordered', () {
      final geometry = loop(const [
        Vec(20, 0),
        Vec(30, 0),
        Vec(30, 10),
      ], start: loop(square));
      final moved = geometry.edit((e) => e.moveInStack('shape-2', 0));
      expect(moved.stack, ['shape-2', 'shape-1']);
    });

    test('open lines and loose points are unfinished drawing', () {
      final open = loop(square).edit((e) => e.delete(['line-4']));
      expect(open.unfinishedReason, 'Shape 1 is not closed');
      final loose = loop(square).edit((e) => e.addPoint(const Vec(50, 50)));
      expect(loose.unfinishedReason, contains('point'));
    });

    test('points cannot branch into a third line', () {
      final geometry = loop(square);
      expect(
        () => geometry.edit((e) {
          final extra = e.addPoint(const Vec(5, 5));
          e.connect('point-1', extra);
        }),
        throwsA(isA<GeometryRuleError>()),
      );
    });
  });

  group('editing', () {
    test('inserting a point splits the line and keeps the boundary closed', () {
      final geometry = loop(
        square,
      ).edit((e) => e.insertPoint('line-1', const Vec(5, 0)));
      expect(geometry.lines.containsKey('line-1'), isFalse);
      expect(geometry.lines.keys, containsAll(['line-5', 'line-6']));
      expect(geometry.isClosed, isTrue);
      expect(geometry.boundaryCorners, hasLength(5));
    });

    test('deleting a point removes its lines without reconnecting', () {
      final geometry = loop(square).edit((e) => e.delete(['point-1']));
      expect(geometry.points, hasLength(3));
      expect(geometry.lines, hasLength(2));
      expect(geometry.isClosed, isFalse);
    });

    test('deleted ID numbers are never reused', () {
      final geometry = loop(square)
          .edit((e) => e.delete(['point-4']))
          .edit((e) => e.addPoint(const Vec(3, 3)));
      expect(geometry.points.containsKey('point-5'), isTrue);
      expect(geometry.points.containsKey('point-4'), isFalse);
    });

    test('defining points of a line and a boundary are deduplicated', () {
      final geometry = loop(square);
      expect(geometry.definingPoints(['line-1', 'line-2']), hasLength(3));
      expect(geometry.definingPoints(['shape-1']), hasLength(4));
    });
  });

  group('rules', () {
    test('crossing lines are rejected', () {
      final geometry = emptyGeometry().edit((e) {
        final a = e.addPoint(const Vec(0, 0));
        final b = e.addPoint(const Vec(10, 10));
        final c = e.addPoint(const Vec(0, 10));
        final d = e.addPoint(const Vec(10, 0));
        e.connect(a, b);
        e.connect(c, d);
      });
      expect(geometryProblem(geometry), contains('cross'));
    });

    test('a self-crossing loop is rejected', () {
      final bowTie = loop(const [
        Vec(0, 0),
        Vec(10, 10),
        Vec(10, 0),
        Vec(0, 10),
      ]);
      expect(geometryProblem(bowTie), isNotNull);
    });

    test('lines that double back are rejected', () {
      final geometry = emptyGeometry().edit((e) {
        final a = e.addPoint(const Vec(0, 0));
        final b = e.addPoint(const Vec(10, 0));
        final c = e.addPoint(const Vec(5, 0));
        e.connect(a, b);
        e.connect(b, c);
      });
      expect(geometryProblem(geometry), isNotNull);
    });

    test('collapsed edges remain invalid drafts with safe region queries', () {
      final collapsed = loop(
        square,
      ).edit((e) => e.movePoint('point-2', Vec.zero));
      expect(geometryProblem(collapsed), isNotNull);
      expect(() => collapsed.region, returnsNormally);
      final repaired = collapsed.edit(
        (e) => e.movePoint('point-2', const Vec(10, 0)),
      );
      expect(geometryProblem(repaired), isNull);
      expect(repaired.region!.area, closeTo(100, 1e-8));
    });

    test('nonfinite draft coordinates do not make region lookup throw', () {
      final invalid = loop(
        square,
      ).edit((e) => e.movePoint('point-2', const Vec(double.infinity, 0)));
      expect(geometryProblem(invalid), contains('finite'));
      expect(invalid.region, isNull);
    });

    test('collinear corners are allowed', () {
      final geometry = loop(const [
        Vec(0, 0),
        Vec(5, 0),
        Vec(10, 0),
        Vec(10, 10),
        Vec(0, 10),
      ]);
      expect(geometryProblem(geometry), isNull);
    });
  });
}
