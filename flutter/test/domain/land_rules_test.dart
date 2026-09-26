import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';

int _next = 0;
String newId() => 'id-${_next++}';

/// Adds a layer whose boundary is a closed loop through [corners].
(GardenDocument, String) addLand(
  GardenDocument document,
  LayerKind kind,
  List<Vec> corners, {
  String? parentId,
}) {
  final (withLayer, id) = document.addLayer(
    kind,
    parentId: parentId,
    newId: newId,
  );
  final geometry = withLayer.geometryOf(id).edit((e) {
    final ids = corners.map(e.addPoint).toList();
    for (var i = 0; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
  });
  return (withLayer.withGeometry(geometry), id);
}

List<Vec> rect(double x, double y, double w, double h) => [
  Vec(x, y),
  Vec(x + w, y),
  Vec(x + w, y + h),
  Vec(x, y + h),
];

void main() {
  final empty = GardenDocument(id: 'doc');

  test('new layers get sequential names that are not recycled', () {
    var (doc, first) = empty.addLayer(LayerKind.field, newId: newId);
    expect(doc.layers[first]!.name, 'Field 1');
    doc = doc.removeLayer(first);
    final (next, second) = doc.addLayer(LayerKind.field, newId: newId);
    expect(next.layers[second]!.name, 'Field 2');
  });

  test('fields may share an edge but not overlap', () {
    var (doc, a) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (touching, b) = addLand(doc, LayerKind.field, rect(10, 0, 10, 10));
    expect(touching.problemOf(b), isNull);

    final (overlapping, c) = addLand(doc, LayerKind.field, rect(5, 5, 10, 10));
    expect(overlapping.problemOf(c), contains('Overlaps'));
    expect(a, isNotEmpty);
  });

  test('identical sibling regions overlap', () {
    final (doc, _) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (same, b) = addLand(doc, LayerKind.field, rect(0, 0, 10, 10));
    expect(same.problemOf(b), contains('Overlaps'));
  });

  test('one region wholly inside a sibling overlaps', () {
    final (doc, _) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (inner, b) = addLand(doc, LayerKind.field, rect(2, 2, 3, 3));
    expect(inner.problemOf(b), contains('Overlaps'));
  });

  test('a plot must stay inside its field, touching is fine', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (inside, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(0, 0, 5, 5),
      parentId: field,
    );
    expect(inside.problemOf(plot), isNull);

    final (outside, stray) = addLand(
      doc,
      LayerKind.plot,
      rect(8, 8, 5, 5),
      parentId: field,
    );
    expect(outside.problemOf(stray), contains('inside'));
  });

  test('a line crossing a concave notch is outside the parent', () {
    final uShape = const [
      Vec(0, 0),
      Vec(10, 0),
      Vec(10, 10),
      Vec(7, 10),
      Vec(7, 3),
      Vec(3, 3),
      Vec(3, 10),
      Vec(0, 10),
    ];
    final (doc, field) = addLand(empty, LayerKind.field, uShape);
    final (withPlot, plot) = doc.addLayer(
      LayerKind.plot,
      parentId: field,
      newId: newId,
    );
    final geometry = withPlot.geometryOf(plot).edit((e) {
      e.connect(e.addPoint(const Vec(1, 8)), e.addPoint(const Vec(9, 8)));
    });
    expect(withPlot.withGeometry(geometry).problemOf(plot), contains('inside'));
  });

  test('moving a parent must keep its children inside', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (withPlot, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(1, 1, 8, 8),
      parentId: field,
    );
    final shrunk = withPlot.withGeometry(
      withPlot
          .geometryOf(field)
          .edit((e) => e.movePoint('point-3', const Vec(5, 5))),
    );
    expect(shrunk.problemOf(field), isNull, reason: 'the field itself is fine');
    expect(shrunk.problemOf(plot), contains('inside'));
    expect(shrunk.isActive(plot), isFalse);
  });

  test('children become inactive when their parent opens', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (withPlot, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(1, 1, 5, 5),
      parentId: field,
    );
    expect(withPlot.isActive(plot), isTrue);
    final opened = withPlot.withGeometry(
      withPlot.geometryOf(field).edit((e) => e.delete(['line-1'])),
    );
    expect(opened.isActive(field), isFalse);
    expect(opened.isActive(plot), isFalse);
    expect(opened.geometryOf(plot).isClosed, isTrue);
  });

  test('removing a field removes its plots and areas', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (withPlot, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(1, 1, 5, 5),
      parentId: field,
    );
    final (withArea, _) = addLand(
      withPlot,
      LayerKind.area,
      rect(2, 2, 2, 2),
      parentId: plot,
    );
    final removed = withArea.removeLayer(field);
    expect(removed.layers, isEmpty);
    expect(removed.geometries, isEmpty);
    expect(removed.fields, isEmpty);
  });

  test('counters merge upward and never go back', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final earlier = doc.withGeometry(
      doc.geometryOf(field).copyWith(counters: const IdCounters()),
    );
    final merged = earlier.withCountersFrom(doc);
    expect(merged.geometryOf(field).counters.points, 4);
  });

  test('a plot outside its field is kept but invalid and inactive', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (outside, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(8, 8, 5, 5),
      parentId: field,
    );
    expect(outside.geometryOf(plot).isClosed, isTrue);
    expect(outside.isValid(plot), isFalse);
    expect(outside.isActive(plot), isFalse);
    expect(outside.inactiveReason(plot), contains('not inside a field'));
    expect(outside.isActive(field), isTrue, reason: 'the field is unaffected');
  });

  test('only layers that newly broke a rule are reported', () {
    final (doc, field) = addLand(empty, LayerKind.field, rect(0, 0, 10, 10));
    final (inside, plot) = addLand(
      doc,
      LayerKind.plot,
      rect(1, 1, 3, 3),
      parentId: field,
    );
    final moved = inside.withGeometry(
      inside.geometryOf(plot).edit((e) {
        for (final id in inside.geometryOf(plot).points.keys) {
          e.movePoint(
            id,
            inside.geometryOf(plot).points[id]! + const Vec(20, 0),
          );
        }
      }),
    );
    expect(moved.newProblemsSince(inside).keys, [plot]);
    expect(moved.newProblemsSince(moved), isEmpty);
  });

  test('crossing lines make a layer invalid instead of being refused', () {
    final (doc, field) = addLand(empty, LayerKind.field, const []);
    final crossed = doc.withGeometry(
      doc.geometryOf(field).edit((e) {
        e.connect(e.addPoint(const Vec(0, 0)), e.addPoint(const Vec(10, 10)));
        e.connect(e.addPoint(const Vec(0, 10)), e.addPoint(const Vec(10, 0)));
      }),
    );
    expect(crossed.problemOf(field), contains('cross'));
  });
}
