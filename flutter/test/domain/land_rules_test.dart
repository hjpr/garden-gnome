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
  return (addLoop(withLayer, id, corners), id);
}

/// Draws one more closed loop through [corners] onto an existing layer.
GardenDocument addLoop(
  GardenDocument document,
  String layerId,
  List<Vec> corners,
) {
  final geometry = document.geometryOf(layerId).edit((e) {
    final ids = corners.map(e.addPoint).toList();
    for (var i = 0; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
  });
  return document.withGeometry(geometry);
}

/// Draws an open line from [a] to [b] onto an existing layer.
GardenDocument addLine(GardenDocument document, String layerId, Vec a, Vec b) {
  final geometry = document
      .geometryOf(layerId)
      .edit((e) => e.connect(e.addPoint(a), e.addPoint(b)));
  return document.withGeometry(geometry);
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
    var (doc, first) = empty.addLayer(LayerKind.property, newId: newId);
    expect(doc.layers[first]!.name, 'Property 1');
    doc = doc.removeLayer(first);
    final (next, second) = doc.addLayer(LayerKind.property, newId: newId);
    expect(next.layers[second]!.name, 'Property 2');
    final (withZone, zone) = next.addLayer(
      LayerKind.zone,
      parentId: second,
      newId: newId,
    );
    expect(withZone.layers[zone]!.name, 'Zone 1');
    expect(withZone.layers[zone]!.parentId, second);
  });

  test('a zone must be listed under a property', () {
    expect(
      () => empty.addLayer(LayerKind.zone, newId: newId),
      throwsArgumentError,
    );
  });

  group('properties', () {
    test('may share an edge but not overlap', () {
      final (doc, _) = addLand(empty, LayerKind.property, rect(0, 0, 10, 10));
      final (touching, b) = addLand(
        doc,
        LayerKind.property,
        rect(10, 0, 10, 10),
      );
      expect(touching.problemOf(b), isNull);

      final (overlapping, c) = addLand(
        doc,
        LayerKind.property,
        rect(5, 5, 10, 10),
      );
      expect(overlapping.problemOf(c), contains('Overlaps'));
    });

    test('identical properties overlap', () {
      final (doc, _) = addLand(empty, LayerKind.property, rect(0, 0, 10, 10));
      final (same, b) = addLand(doc, LayerKind.property, rect(0, 0, 10, 10));
      expect(same.problemOf(b), contains('Overlaps'));
    });

    test('one property wholly inside another overlaps', () {
      final (doc, _) = addLand(empty, LayerKind.property, rect(0, 0, 10, 10));
      final (inner, b) = addLand(doc, LayerKind.property, rect(2, 2, 3, 3));
      expect(inner.problemOf(b), contains('Overlaps'));
    });

    test('two shapes of one property may not overlap', () {
      final (doc, property) = addLand(
        empty,
        LayerKind.property,
        rect(0, 0, 10, 10),
      );
      final overlapping = addLoop(doc, property, rect(5, 5, 10, 10));
      expect(overlapping.problemOf(property), contains('overlaps'));
      // Each shape counts in full until they are combined.
      expect(overlapping.netAreaOf(property), closeTo(200, 1e-6));
      expect(overlapping.isActive(property), isFalse);
    });

    test('a loose line may not cross a finished property shape', () {
      final (doc, property) = addLand(
        empty,
        LayerKind.property,
        rect(0, 0, 10, 10),
      );
      final crossing = addLine(
        doc,
        property,
        const Vec(5, 5),
        const Vec(15, 5),
      );
      expect(crossing.ruleProblemOf(property), contains('cross'));
    });

    test('crossing lines make a layer invalid instead of being refused', () {
      final (doc, property) = addLand(empty, LayerKind.property, const []);
      final crossed = doc.withGeometry(
        doc.geometryOf(property).edit((e) {
          e.connect(e.addPoint(const Vec(0, 0)), e.addPoint(const Vec(10, 10)));
          e.connect(e.addPoint(const Vec(0, 10)), e.addPoint(const Vec(10, 0)));
        }),
      );
      expect(crossed.problemOf(property), contains('cross'));
    });

    test('only layers that newly broke a rule are reported', () {
      var (doc, a) = addLand(empty, LayerKind.property, rect(0, 0, 10, 10));
      (doc, _) = addLand(doc, LayerKind.property, rect(0, 40, 10, 10));
      final (apart, moving) = addLand(
        doc,
        LayerKind.property,
        rect(20, 0, 10, 10),
      );
      final geometry = apart.geometryOf(moving);
      final moved = apart.withGeometry(
        geometry.edit((e) {
          for (final entry in geometry.points.entries) {
            e.movePoint(entry.key, entry.value - const Vec(15, 0));
          }
        }),
      );
      // Both properties in the overlap break the rule; the one far away
      // does not.
      expect(moved.newProblemsSince(apart).keys, [a, moving]);
      expect(moved.newProblemsSince(moved), isEmpty);
    });
  });

  group('zones', () {
    late GardenDocument doc;
    late String property;
    setUp(() {
      (doc, property) = addLand(empty, LayerKind.property, rect(0, 0, 100, 50));
    });

    test('must stay inside their property; touching its edge is fine', () {
      for (final corners in [rect(10, 10, 10, 10), rect(0, 0, 5, 5)]) {
        final (withZone, zone) = addLand(
          doc,
          LayerKind.zone,
          corners,
          parentId: property,
        );
        expect(withZone.problemOf(zone), isNull);
        expect(withZone.isActive(zone), isTrue);
      }
      for (final corners in [rect(90, 10, 20, 10), rect(200, 200, 10, 10)]) {
        final (withZone, zone) = addLand(
          doc,
          LayerKind.zone,
          corners,
          parentId: property,
        );
        expect(withZone.problemOf(zone), 'Shape 1 is not inside Property 1');
        expect(withZone.isActive(zone), isFalse);
      }
    });

    test('must sit inside their own property, not a neighbour', () {
      final (withNeighbour, _) = addLand(
        doc,
        LayerKind.property,
        rect(100, 0, 50, 50),
      );
      final (withZone, zone) = addLand(
        withNeighbour,
        LayerKind.zone,
        rect(110, 10, 10, 10),
        parentId: property,
      );
      expect(withZone.problemOf(zone), contains('not inside Property 1'));
    });

    test('turn red as soon as a stroke leaves the property', () {
      final (withZone, zone) = doc.addLayer(
        LayerKind.zone,
        parentId: property,
        newId: newId,
      );
      final inside = addLine(withZone, zone, const Vec(5, 5), const Vec(50, 5));
      expect(inside.ruleProblemOf(zone), isNull);
      final leaving = addLine(
        withZone,
        zone,
        const Vec(5, 5),
        const Vec(150, 5),
      );
      expect(leaving.ruleProblemOf(zone), 'Drawing is not inside Property 1');
      expect(leaving.newProblemsSince(withZone).keys, [zone]);
    });

    test('a line crossing a concave notch is outside the property', () {
      final (uShaped, owner) = addLand(empty, LayerKind.property, const [
        Vec(0, 0),
        Vec(10, 0),
        Vec(10, 10),
        Vec(7, 10),
        Vec(7, 3),
        Vec(3, 3),
        Vec(3, 10),
        Vec(0, 10),
      ]);
      final (withZone, zone) = uShaped.addLayer(
        LayerKind.zone,
        parentId: owner,
        newId: newId,
      );
      final across = addLine(withZone, zone, const Vec(1, 8), const Vec(9, 8));
      expect(across.problemOf(zone), contains('not inside'));
    });

    test('may overlap and touch other zones', () {
      var (next, a) = addLand(
        doc,
        LayerKind.zone,
        rect(10, 10, 20, 20),
        parentId: property,
      );
      final String b, c, d;
      (next, b) = addLand(
        next,
        LayerKind.zone,
        rect(20, 20, 20, 20),
        parentId: property,
      );
      (next, c) = addLand(
        next,
        LayerKind.zone,
        rect(10, 10, 20, 20),
        parentId: property,
      );
      (next, d) = addLand(
        next,
        LayerKind.zone,
        rect(30, 10, 5, 5),
        parentId: property,
      );
      for (final id in [a, b, c, d]) {
        expect(next.problemOf(id), isNull, reason: next.layers[id]!.name);
        expect(next.isActive(id), isTrue);
      }
      expect(next.problemOf(property), isNull);
    });

    test('may have shapes that overlap and touch each other', () {
      var (next, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(0, 0, 10, 10),
        parentId: property,
      );
      next = addLoop(next, zone, rect(5, 5, 10, 10));
      next = addLoop(next, zone, rect(15, 0, 5, 5));
      next = addLoop(next, zone, rect(2, 2, 2, 2));
      expect(next.problemOf(zone), isNull);
      expect(next.isActive(zone), isTrue);
      // Shared land is counted once: 100 + 100 - 25 where the first two
      // overlap, + 25 for the square touching them. The 2 m square lies
      // inside the first. Shape by shape, the sum would be 229.
      expect(next.netAreaOf(zone), closeTo(200, 1e-6));
      expect(next.geometryOf(zone).area, closeTo(229, 1e-6));
    });

    test('may have a corner resting on another of its shapes', () {
      var (next, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(0, 0, 10, 10),
        parentId: property,
      );
      next = addLoop(next, zone, const [Vec(10, 10), Vec(20, 10), Vec(20, 20)]);
      next = addLoop(next, zone, const [Vec(5, 10), Vec(8, 15), Vec(2, 15)]);
      expect(next.problemOf(zone), isNull);
    });

    test('may draw a new outline across a finished shape', () {
      final (withZone, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(0, 0, 10, 10),
        parentId: property,
      );
      final crossing = addLine(
        withZone,
        zone,
        const Vec(5, 5),
        const Vec(15, 5),
      );
      expect(crossing.ruleProblemOf(zone), isNull);
      expect(crossing.newProblemsSince(withZone), isEmpty);
      // Unfinished until the new outline closes.
      expect(crossing.problemOf(zone), isNotNull);
      expect(crossing.isActive(zone), isFalse);
    });

    test('are invalid while drawing is unfinished', () {
      final (withZone, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(0, 0, 10, 10),
        parentId: property,
      );
      final loosePoint = withZone.withGeometry(
        withZone.geometryOf(zone).edit((e) => e.addPoint(const Vec(50, 5))),
      );
      expect(loosePoint.problemOf(zone), contains('point'));
      final opened = withZone.withGeometry(
        withZone.geometryOf(zone).edit((e) => e.delete(['line-1'])),
      );
      expect(opened.problemOf(zone), contains('not closed'));
      expect(opened.isActive(zone), isFalse);
    });

    test('still may not have an outline that crosses itself', () {
      final (withZone, zone) = doc.addLayer(
        LayerKind.zone,
        parentId: property,
        newId: newId,
      );
      final bowtie = addLoop(withZone, zone, const [
        Vec(0, 0),
        Vec(10, 10),
        Vec(10, 0),
        Vec(0, 10),
      ]);
      expect(bowtie.problemOf(zone), contains('cross'));
    });

    test('must stay inside when their property changes', () {
      final (withZone, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(10, 10, 10, 10),
        parentId: property,
      );
      final shrunk = withZone.withGeometry(
        withZone
            .geometryOf(property)
            .edit((e) => e.movePoint('point-3', const Vec(5, 5))),
      );
      expect(shrunk.problemOf(property), isNull, reason: 'it is fine itself');
      expect(shrunk.problemOf(zone), contains('not inside'));
      expect(shrunk.newProblemsSince(withZone).keys, [zone]);

      final opened = withZone.withGeometry(
        withZone.geometryOf(property).edit((e) => e.delete(['line-1'])),
      );
      expect(opened.isActive(property), isFalse);
      expect(opened.isActive(zone), isFalse);
      expect(opened.geometryOf(zone).isClosed, isTrue);
    });

    test('are inactive while their property is', () {
      final (withZone, zone) = addLand(
        doc,
        LayerKind.zone,
        rect(10, 10, 10, 10),
        parentId: property,
      );
      final (overlapped, _) = addLand(
        withZone,
        LayerKind.property,
        rect(90, 0, 20, 20),
      );
      expect(overlapped.problemOf(property), contains('Overlaps'));
      expect(overlapped.problemOf(zone), isNull);
      expect(overlapped.inactiveReason(zone), 'Property 1 is not active');
    });
  });

  test('removing a property removes its zones', () {
    final (doc, property) = addLand(
      empty,
      LayerKind.property,
      rect(0, 0, 10, 10),
    );
    final (withZone, _) = addLand(
      doc,
      LayerKind.zone,
      rect(1, 1, 5, 5),
      parentId: property,
    );
    final removed = withZone.removeLayer(property);
    expect(removed.layers, isEmpty);
    expect(removed.geometries, isEmpty);
    expect(removed.propertyIds, isEmpty);
  });

  test('counters merge upward and never go back', () {
    final (doc, property) = addLand(
      empty,
      LayerKind.property,
      rect(0, 0, 10, 10),
    );
    final earlier = doc.withGeometry(
      doc.geometryOf(property).copyWith(counters: const IdCounters()),
    );
    final merged = earlier.withCountersFrom(doc);
    expect(merged.geometryOf(property).counters.points, 4);
  });
}
