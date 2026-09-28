import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

int _next = 0;
String newId() => 'group-${_next++}';

List<Vec> rect(double x, double y, double w, double h) => [
  Vec(x, y),
  Vec(x + w, y),
  Vec(x + w, y + h),
  Vec(x, y + h),
];

/// Adds a new layer of [kind] with one closed shape per entry of [pieces].
(GardenDocument, String) addGroup(
  GardenDocument document,
  LayerKind kind,
  List<List<Vec>> pieces, {
  String? parentId,
}) {
  final (withLayer, id) = document.addLayer(
    kind,
    parentId: parentId,
    newId: newId,
  );
  return (addPieces(withLayer, id, pieces), id);
}

/// Draws more closed shapes onto an existing layer.
GardenDocument addPieces(
  GardenDocument document,
  String layerId,
  List<List<Vec>> pieces,
) {
  final geometry = document.geometryOf(layerId).edit((e) {
    for (final corners in pieces) {
      final ids = corners.map(e.addPoint).toList();
      for (var i = 0; i < ids.length; i++) {
        e.connect(ids[i], ids[(i + 1) % ids.length]);
      }
    }
  });
  return document.withGeometry(geometry);
}

void main() {
  final empty = GardenDocument(id: 'doc');

  test('a property of two separate pieces counts all of its land', () {
    final (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 10, 10),
      rect(30, 0, 10, 10),
    ]);
    final geometry = doc.geometryOf(property);
    expect(geometry.stack, hasLength(2));
    expect(geometry.area, closeTo(200, 1e-9));
    expect(doc.isActive(property), isTrue);
    expect(
      geometry.region!.locate(const Vec(35, 5)),
      isNot(PointLocation.outside),
    );
  });

  test('an apple zone may be two separate pieces', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 100, 50),
    ]);
    final (withZone, apples) = addGroup(doc, LayerKind.zone, [
      rect(5, 5, 10, 10),
      rect(60, 20, 10, 10),
    ], parentId: property);
    expect(withZone.problemOf(apples), isNull);
    expect(withZone.isActive(apples), isTrue);
    expect(withZone.geometryOf(apples).area, closeTo(200, 1e-9));
  });

  test('one piece outside the property invalidates the whole zone', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 100, 50),
    ]);
    final (withZone, zone) = addGroup(doc, LayerKind.zone, [
      rect(5, 5, 10, 10),
      rect(200, 5, 10, 10),
    ], parentId: property);
    expect(withZone.problemOf(zone), 'Shape 2 is not inside Property 1');
    expect(withZone.isActive(zone), isFalse);
  });

  test('a zone may have pieces in two pieces of its property', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 10, 10),
      rect(30, 0, 10, 10),
    ]);
    final (withZone, zone) = addGroup(doc, LayerKind.zone, [
      rect(1, 1, 3, 3),
      rect(31, 1, 3, 3),
    ], parentId: property);
    expect(withZone.problemOf(zone), isNull);
    final (straddling, across) = addGroup(withZone, LayerKind.zone, [
      rect(8, 1, 25, 3),
    ], parentId: property);
    expect(straddling.problemOf(across), contains('not inside'));
  });

  test('an unfinished shape invalidates an otherwise valid layer', () {
    for (final kind in LayerKind.values) {
      var (doc, property) = addGroup(empty, LayerKind.property, [
        rect(0, 0, 10, 10),
      ]);
      var layer = property;
      if (kind == LayerKind.zone) {
        (doc, layer) = addGroup(doc, kind, [
          rect(1, 1, 5, 5),
        ], parentId: property);
      }
      final geometry = doc.geometryOf(layer).edit((e) {
        e.connect(e.addPoint(const Vec(7, 8)), e.addPoint(const Vec(9, 8)));
      });
      doc = doc.withGeometry(geometry);
      expect(doc.ruleProblemOf(layer), isNull, reason: kind.label);
      expect(doc.problemOf(layer), isNotNull, reason: kind.label);
      expect(doc.isValid(layer), isFalse);
      expect(doc.isActive(layer), isFalse);
    }
  });

  test('two shapes of a property that overlap make it invalid', () {
    final (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 10, 10),
      rect(5, 5, 10, 10),
    ]);
    expect(doc.problemOf(property), contains('overlaps'));
  });

  test('two shapes of a zone may overlap', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 100, 50),
    ]);
    final (withZone, zone) = addGroup(doc, LayerKind.zone, [
      rect(0, 0, 10, 10),
      rect(5, 5, 10, 10),
    ], parentId: property);
    expect(withZone.problemOf(zone), isNull);
    expect(withZone.netAreaOf(zone), closeTo(175, 1e-9));
    // The overlap is land, not a hole.
    expect(
      withZone.geometryOf(zone).region!.locate(const Vec(7, 7)),
      PointLocation.inside,
    );
  });

  test('a tomato zone may reach across two others', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 100, 50),
    ]);
    final String bedA, bedB;
    (doc, bedA) = addGroup(doc, LayerKind.zone, [
      rect(5, 5, 30, 30),
    ], parentId: property);
    (doc, bedB) = addGroup(doc, LayerKind.zone, [
      rect(35, 5, 30, 30),
    ], parentId: property);
    final (withZone, tomatoes) = addGroup(doc, LayerKind.zone, [
      rect(30, 10, 10, 5),
    ], parentId: property);
    expect(withZone.problemOf(tomatoes), isNull);
    expect(withZone.layers[tomatoes]!.parentId, property);
    expect(withZone.problemOf(bedA), isNull);
    expect(withZone.problemOf(bedB), isNull);
  });

  test('groups, order and labels survive a save and reopen', () {
    var (doc, property) = addGroup(empty, LayerKind.property, [
      rect(0, 0, 10, 10),
      rect(30, 0, 10, 10),
    ]);
    final stack = doc.geometryOf(property).stack;
    doc = doc.withGeometry(
      doc.geometryOf(property).edit((e) {
        e.setLabel(stack.last, 'East bed');
        e.moveInStack(stack.last, 0);
      }),
    );
    final reopened = decodeGgnome(encodeGgnome(doc));
    final geometry = reopened.geometryOf(property);
    expect(geometry.stack, [stack.last, stack.first]);
    expect(geometry.labelOf(stack.last), 'East bed');
    expect(reopened.isActive(property), isTrue);
  });
}
