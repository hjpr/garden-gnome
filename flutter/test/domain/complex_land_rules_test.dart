import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
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
    'a zone may not cover its property\'s hole even with all edges inside',
    () {
      final (parent, property) = _land(
        GardenDocument(id: 'doc'),
        LayerKind.property,
        (g) => _rectangle(
          _rectangle(g, 0, 0, 20, 20),
          8,
          8,
          4,
          4,
        ).edit((e) => e.boolean('shape-2', BooleanOperation.subtract)),
      );
      final (document, zone) = _land(
        parent,
        LayerKind.zone,
        (g) => _rectangle(g, 4, 4, 12, 12),
        parentId: property,
      );
      final region = document.geometryOf(property).region!;
      final child = document.geometryOf(zone);
      expect(
        child.lines.values.every(
          (line) => region.containsEdge(line.curve(child.points)),
        ),
        isTrue,
      );
      expect(document.problemOf(zone), contains('not inside Property 1'));
      expect(document.isActive(zone), isFalse);
      expect(document.isActive(property), isTrue);
    },
  );

  test('matching zone and property holes may touch and stay inside', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => _annulus(g, 8, 3),
      parentId: property,
    );
    expect(document.problemOf(zone), isNull);
    expect(document.isActive(zone), isTrue);
  });

  test('a curved zone ignores arc centres and chords in the hole', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3.5),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => _annulus(g, 4, 3.6),
      parentId: property,
    );
    final region = document.geometryOf(property).region!;
    final child = document.geometryOf(zone);
    expect(
      child.lines.values.any(
        (line) => !region.containsSegment(
          child.points[line.start]!,
          child.points[line.end]!,
        ),
      ),
      isTrue,
    );
    expect(document.problemOf(zone), isNull);
    expect(document.isActive(zone), isTrue);
  });

  test('an open arc is unfinished drawing, not a rule problem', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 4),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => g.edit((e) {
        e.connect(
          e.addPoint(const Vec(-5, 0)),
          e.addPoint(const Vec(5, 0)),
          bulge: 1,
        );
      }),
      parentId: property,
    );
    // It breaks no rule, but an open line is unfinished drawing, which
    // makes the layer invalid until it is closed or removed.
    expect(document.ruleProblemOf(zone), isNull);
    expect(document.problemOf(zone), contains('not part of a closed shape'));
    expect(document.isActive(zone), isFalse);
  });

  test('an open arc bulging outside the property fails, ends inside', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _rectangle(g, -6, -1, 12, 2),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => g.edit((e) {
        e.connect(
          e.addPoint(const Vec(-5, 0)),
          e.addPoint(const Vec(5, 0)),
          bulge: 1,
        );
      }),
      parentId: property,
    );
    expect(document.problemOf(zone), contains('not inside Property 1'));
  });

  test('a lone point makes a zone unfinished', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => _disc(
        g,
        const Vec(6, 0),
        1,
      ).edit((e) => e.addPoint(const Vec(-6, 0))),
      parentId: property,
    );
    expect(document.ruleProblemOf(zone), isNull);
    expect(document.problemOf(zone), contains('point is not part'));
    expect(document.isActive(zone), isFalse);
  });

  test('a lone point in the property\'s hole is outside it', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => g.edit((e) => e.addPoint(Vec.zero)),
      parentId: property,
    );
    expect(document.problemOf(zone), contains('not inside Property 1'));
  });

  test('a property wholly inside another\'s hole does not overlap', () {
    final (parent, annulus) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, disc) = _land(
      parent,
      LayerKind.property,
      (g) => _disc(g, Vec.zero, 3),
    );
    expect(document.problemOf(annulus), isNull);
    expect(document.problemOf(disc), isNull);
    expect(document.isActive(disc), isTrue);
  });

  test('a property extending out of a hole overlaps the land around it', () {
    final (parent, annulus) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, disc) = _land(
      parent,
      LayerKind.property,
      (g) => _disc(g, Vec.zero, 3.1),
    );
    expect(document.problemOf(annulus), contains('Overlaps'));
    expect(document.problemOf(disc), contains('Overlaps'));
  });

  test('any shape of a property overlapping another property counts', () {
    final (first, a) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _disc(_disc(g, Vec.zero, 3), const Vec(20, 0), 4),
    );
    final (document, b) = _land(
      first,
      LayerKind.property,
      (g) => _disc(g, const Vec(20, 0), 4),
    );
    expect(document.problemOf(a), contains('Overlaps'));
    expect(document.problemOf(b), contains('Overlaps'));
  });

  test('circular zones may touch the property line and overlap', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _disc(g, Vec.zero, 10),
    );
    final (first, a) = _land(
      parent,
      LayerKind.zone,
      (g) => _disc(g, const Vec(-5, 0), 5),
      parentId: property,
    );
    final (second, b) = _land(
      first,
      LayerKind.zone,
      (g) => _disc(g, const Vec(5, 0), 5),
      parentId: property,
    );
    final (document, c) = _land(
      second,
      LayerKind.zone,
      (g) => _disc(g, const Vec(3, 0), 5),
      parentId: property,
    );
    for (final zone in [a, b, c]) {
      expect(document.problemOf(zone), isNull);
      expect(document.isActive(zone), isTrue);
    }
    final (crossing, d) = _land(
      document,
      LayerKind.zone,
      (g) => _disc(g, const Vec(8, 0), 5),
      parentId: property,
    );
    expect(crossing.problemOf(d), contains('not inside Property 1'));
  });

  test('two overlapping circles in one zone count their shared land once', () {
    const r = 5.0, d = 6.0;
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _disc(g, Vec.zero, 20),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => _disc(_disc(g, Vec.zero, r), const Vec(d, 0), r),
      parentId: property,
    );
    expect(document.problemOf(zone), isNull);
    final lens =
        2 * r * r * math.acos(d / (2 * r)) -
        d / 2 * math.sqrt(4 * r * r - d * d);
    expect(document.netAreaOf(zone), closeTo(2 * math.pi * r * r - lens, 1e-6));
  });

  test('opening a property\'s hole deactivates its zones until repair', () {
    final (parent, property) = _land(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      (g) => _annulus(g, 10, 3),
    );
    final (document, zone) = _land(
      parent,
      LayerKind.zone,
      (g) => _disc(g, const Vec(6, 0), 1),
      parentId: property,
    );
    expect(document.isActive(zone), isTrue);
    final boundary = document.geometryOf(property);
    final edge =
        boundary.lines[boundary.boundary!.holes.single.first.segmentId]!;
    final opened = document.withGeometry(
      boundary.edit((e) => e.delete([edge.id])),
    );
    expect(opened.isActive(property), isFalse);
    expect(opened.isActive(zone), isFalse);
    final repaired = opened.withGeometry(
      opened
          .geometryOf(property)
          .edit((e) => e.connect(edge.start, edge.end, bulge: edge.bulge)),
    );
    expect(repaired.isActive(property), isTrue);
    expect(repaired.isActive(zone), isTrue);
  });
}
