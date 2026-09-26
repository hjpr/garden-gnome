import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

int _next = 0;
String _newId() => 'id-${_next++}';

(GardenDocument, String) _land(
  GardenDocument document,
  LayerKind kind,
  Geometry Function(Geometry) draw, {
  String? parentId,
}) {
  final (next, id) = document.addLayer(kind, parentId: parentId, newId: _newId);
  return (next.withGeometry(draw(next.geometryOf(id))), id);
}

Geometry _rectangle(
  Geometry geometry,
  double x,
  double y,
  double w,
  double h,
) => geometry.edit((e) {
  final points = [
    Vec(x, y),
    Vec(x + w, y),
    Vec(x + w, y + h),
    Vec(x, y + h),
  ].map(e.addPoint).toList();
  for (var i = 0; i < points.length; i++) {
    e.connect(points[i], points[(i + 1) % points.length]);
  }
});

Geometry _disc(Geometry geometry, Vec centre, double radius) =>
    geometry.edit((e) => e.addCircle(e.addPoint(centre), radius));

Geometry _annulus(Geometry geometry, double outer, double inner) => _disc(
  _disc(geometry, Vec.zero, outer),
  Vec.zero,
  inner,
).edit((e) => e.boolean('circle-2', BooleanOperation.subtract));

void main() {
  test(
    'a closed child may not cover a parent hole even with all edges inside',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _rectangle(
          _rectangle(g, 0, 0, 20, 20),
          8,
          8,
          4,
          4,
        ).edit((e) => e.boolean('shape-2', BooleanOperation.subtract)),
      );
      final (document, plot) = _land(
        parent,
        LayerKind.plot,
        (g) => _rectangle(g, 4, 4, 12, 12),
        parentId: field,
      );
      final region = document.geometryOf(field).region!;
      final child = document.geometryOf(plot);
      expect(
        child.lines.values.every(
          (line) => region.containsEdge(line.curve(child.points)),
        ),
        isTrue,
      );
      expect(document.problemOf(plot), contains('not inside a field'));
      expect(document.isActive(plot), isFalse);
      expect(document.isActive(field), isTrue);
    },
  );

  test(
    'matching child and parent holes may touch without losing containment',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _annulus(g, 10, 3),
      );
      final (document, plot) = _land(
        parent,
        LayerKind.plot,
        (g) => _annulus(g, 8, 3),
        parentId: field,
      );
      expect(document.problemOf(plot), isNull);
      expect(document.isActive(plot), isTrue);
    },
  );

  test(
    'curved child land ignores arc centres and chords in the parent hole',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _annulus(g, 10, 3.5),
      );
      final (document, plot) = _land(
        parent,
        LayerKind.plot,
        (g) => _annulus(g, 4, 3.6),
        parentId: field,
      );
      final region = document.geometryOf(field).region!;
      final child = document.geometryOf(plot);
      expect(
        child.lines.values.any(
          (line) => !region.containsSegment(
            child.points[line.start]!,
            child.points[line.end]!,
          ),
        ),
        isTrue,
      );
      expect(document.problemOf(plot), isNull);
      expect(document.isActive(plot), isTrue);
    },
  );

  test(
    'an unowned arc can fit even though its centre and chord cross a hole',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _annulus(g, 10, 4),
      );
      final (document, plot) = _land(
        parent,
        LayerKind.plot,
        (g) => g.edit((e) {
          e.connect(
            e.addPoint(const Vec(-5, 0)),
            e.addPoint(const Vec(5, 0)),
            bulge: 1,
          );
        }),
        parentId: field,
      );
      // It breaks no rule, but an open line is unfinished drawing, which
      // makes the layer invalid until it is closed or removed.
      expect(document.ruleProblemOf(plot), isNull);
      expect(document.problemOf(plot), contains('not part of a closed shape'));
      expect(document.isActive(plot), isFalse);
    },
  );

  test(
    'an open arc bulging outside the parent fails despite inside endpoints',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _rectangle(g, -6, -1, 12, 2),
      );
      final (document, plot) = _land(
        parent,
        LayerKind.plot,
        (g) => g.edit((e) {
          e.connect(
            e.addPoint(const Vec(-5, 0)),
            e.addPoint(const Vec(5, 0)),
            bulge: 1,
          );
        }),
        parentId: field,
      );
      expect(document.problemOf(plot), contains('not inside a field'));
    },
  );

  test('a sibling wholly inside a hole does not overlap even when tangent', () {
    final (parent, annulus) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _annulus(g, 10, 3),
    );
    final (document, disc) = _land(
      parent,
      LayerKind.field,
      (g) => _disc(g, Vec.zero, 3),
    );
    expect(document.problemOf(annulus), isNull);
    expect(document.problemOf(disc), isNull);
    expect(document.isActive(disc), isTrue);
  });

  test('a sibling extending out of a hole overlaps the surrounding land', () {
    final (parent, annulus) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _annulus(g, 10, 3),
    );
    final (document, disc) = _land(
      parent,
      LayerKind.field,
      (g) => _disc(g, Vec.zero, 3.1),
    );
    expect(document.problemOf(annulus), contains('Overlaps'));
    expect(document.problemOf(disc), contains('Overlaps'));
  });

  test(
    'inner tangency to a circular parent and sibling point contact are legal',
    () {
      final (parent, field) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.field,
        (g) => _disc(g, Vec.zero, 10),
      );
      final (first, a) = _land(
        parent,
        LayerKind.plot,
        (g) => _disc(g, const Vec(-5, 0), 5),
        parentId: field,
      );
      final (document, b) = _land(
        first,
        LayerKind.plot,
        (g) => _disc(g, const Vec(5, 0), 5),
        parentId: field,
      );
      expect(document.problemOf(a), isNull);
      expect(document.problemOf(b), isNull);
      expect(document.isActive(a), isTrue);
      expect(document.isActive(b), isTrue);
    },
  );

  test('every shape of a plot must sit inside a field', () {
    final (parent, field) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _disc(g, Vec.zero, 10),
    );
    final (document, plot) = _land(
      parent,
      LayerKind.plot,
      (g) => _rectangle(_disc(g, Vec.zero, 3), 20, 20, 10, 10),
      parentId: field,
    );
    expect(document.geometryOf(plot).stack, hasLength(2));
    expect(document.problemOf(plot), 'Shape 1 is not inside a field');
    expect(document.isActive(plot), isFalse);
  });

  test('any shape of a layer overlapping another layer counts', () {
    final (first, a) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _disc(_disc(g, Vec.zero, 3), const Vec(20, 0), 4),
    );
    final (document, b) = _land(
      first,
      LayerKind.field,
      (g) => _disc(g, const Vec(20, 0), 4),
    );
    expect(document.problemOf(a), contains('Overlaps'));
    expect(document.problemOf(b), contains('Overlaps'));
  });

  test('opening a hole makes its descendants inactive until repair', () {
    final (parent, field) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _annulus(g, 10, 3),
    );
    final (document, plot) = _land(
      parent,
      LayerKind.plot,
      (g) => _disc(g, const Vec(6, 0), 1),
      parentId: field,
    );
    expect(document.isActive(plot), isTrue);
    final boundary = document.geometryOf(field);
    final edge =
        boundary.lines[boundary.boundary!.holes.single.first.segmentId]!;
    final opened = document.withGeometry(
      boundary.edit((e) => e.delete([edge.id])),
    );
    expect(opened.isActive(field), isFalse);
    expect(opened.isActive(plot), isFalse);
    final repaired = opened.withGeometry(
      opened
          .geometryOf(field)
          .edit((e) => e.connect(edge.start, edge.end, bulge: edge.bulge)),
    );
    expect(repaired.isActive(field), isTrue);
    expect(repaired.isActive(plot), isTrue);
  });

  test('an isolated child construction point still must stay inside', () {
    final (parent, field) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.field,
      (g) => _annulus(g, 10, 3),
    );
    final (document, plot) = _land(
      parent,
      LayerKind.plot,
      (g) => g.edit((e) => e.addPoint(Vec.zero)),
      parentId: field,
    );
    expect(document.problemOf(plot), contains('not inside a field'));
  });
}
