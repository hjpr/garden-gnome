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

  test('a field of two separate pieces counts all of its land', () {
    final (doc, field) = addGroup(empty, LayerKind.field, [
      rect(0, 0, 10, 10),
      rect(30, 0, 10, 10),
    ]);
    final geometry = doc.geometryOf(field);
    expect(geometry.stack, hasLength(2));
    expect(geometry.area, closeTo(200, 1e-9));
    expect(doc.isActive(field), isTrue);
    expect(
      geometry.region!.locate(const Vec(35, 5)),
      isNot(PointLocation.outside),
    );
  });

  test('an apple plot may be two separate pieces inside one field', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [rect(0, 0, 100, 50)]);
    final (withPlot, apples) = addGroup(doc, LayerKind.plot, [
      rect(5, 5, 10, 10),
      rect(60, 20, 10, 10),
    ], parentId: field);
    expect(withPlot.problemOf(apples), isNull);
    expect(withPlot.isActive(apples), isTrue);
    expect(withPlot.geometryOf(apples).area, closeTo(200, 1e-9));
    for (final shape in withPlot.geometryOf(apples).closedIds) {
      expect(withPlot.containerOf(apples, shape), field);
    }
  });

  test('one piece outside the field invalidates the whole plot', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [rect(0, 0, 100, 50)]);
    final (withPlot, plot) = addGroup(doc, LayerKind.plot, [
      rect(5, 5, 10, 10),
      rect(200, 5, 10, 10),
    ], parentId: field);
    expect(withPlot.problemOf(plot), contains('not inside a field'));
    expect(withPlot.isActive(plot), isFalse);
  });

  test('an unfinished shape invalidates an otherwise valid layer', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [rect(0, 0, 10, 10)]);
    final geometry = doc.geometryOf(field).edit((e) {
      e.connect(e.addPoint(const Vec(20, 0)), e.addPoint(const Vec(25, 0)));
    });
    doc = doc.withGeometry(geometry);
    expect(doc.ruleProblemOf(field), isNull);
    expect(doc.problemOf(field), isNotNull);
    expect(doc.isValid(field), isFalse);
    expect(doc.isActive(field), isFalse);
  });

  test('two shapes of one layer that overlap make it invalid', () {
    final (doc, field) = addGroup(empty, LayerKind.field, [
      rect(0, 0, 10, 10),
      rect(5, 5, 10, 10),
    ]);
    expect(doc.problemOf(field), contains('overlaps'));
  });

  test('a tomato area may have pieces in two different plots', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [rect(0, 0, 100, 50)]);
    final String plotA, plotB;
    (doc, plotA) = addGroup(doc, LayerKind.plot, [
      rect(5, 5, 30, 30),
    ], parentId: field);
    (doc, plotB) = addGroup(doc, LayerKind.plot, [
      rect(50, 5, 30, 30),
    ], parentId: field);
    final (withArea, tomatoes) = addGroup(doc, LayerKind.area, [
      rect(10, 10, 5, 5),
      rect(60, 10, 5, 5),
    ], parentId: plotA);
    expect(withArea.problemOf(tomatoes), isNull);
    expect(withArea.isActive(tomatoes), isTrue);
    // Listed under the field, with each piece held by a different plot.
    expect(withArea.layers[tomatoes]!.parentId, field);
    final pieces = withArea.geometryOf(tomatoes).closedIds;
    expect(
      {for (final id in pieces) withArea.containerOf(tomatoes, id)},
      {plotA, plotB},
    );
  });

  test('an area piece straddling two plots is invalid', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [rect(0, 0, 100, 50)]);
    final String plotA;
    (doc, plotA) = addGroup(doc, LayerKind.plot, [
      rect(5, 5, 30, 30),
    ], parentId: field);
    (doc, _) = addGroup(doc, LayerKind.plot, [
      rect(35, 5, 30, 30),
    ], parentId: field);
    final (withArea, area) = addGroup(doc, LayerKind.area, [
      rect(30, 10, 10, 5),
    ], parentId: plotA);
    expect(withArea.problemOf(area), contains('not inside a plot'));
  });

  test('groups, order and labels survive a save and reopen', () {
    var (doc, field) = addGroup(empty, LayerKind.field, [
      rect(0, 0, 10, 10),
      rect(30, 0, 10, 10),
    ]);
    final stack = doc.geometryOf(field).stack;
    doc = doc.withGeometry(
      doc.geometryOf(field).edit((e) {
        e.setLabel(stack.last, 'East bed');
        e.moveInStack(stack.last, 0);
      }),
    );
    final reopened = decodeGgnome(encodeGgnome(doc));
    final geometry = reopened.geometryOf(field);
    expect(geometry.stack, [stack.last, stack.first]);
    expect(geometry.labelOf(stack.last), 'East bed');
    expect(reopened.isActive(field), isTrue);
  });
}
