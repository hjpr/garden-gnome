import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/carried_land.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';

int _next = 0;
String newId() => 'carried-${_next++}';

/// Adds a layer of [kind] holding one closed square.
(GardenDocument, String) square(
  GardenDocument document,
  LayerKind kind,
  double x,
  double size, {
  String? parentId,
}) {
  final (next, id) = document.addLayer(kind, parentId: parentId, newId: newId);
  final geometry = next.geometryOf(id).edit((e) {
    final ids = [
      for (final p in [
        Vec(x, 0),
        Vec(x + size, 0),
        Vec(x + size, size),
        Vec(x, size),
      ])
        e.addPoint(p),
    ];
    for (var i = 0; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
  });
  return (next.withGeometry(geometry), id);
}

void main() {
  test('a property shape carries only its own zones inside it', () {
    var (doc, home) = square(
      GardenDocument(id: 'doc'),
      LayerKind.property,
      0,
      20,
    );
    final String neighbour, own, stray, overlapping;
    (doc, neighbour) = square(doc, LayerKind.property, 30, 20);
    (doc, own) = square(doc, LayerKind.zone, 2, 5, parentId: home);
    // Listed under the neighbour but drawn in this property: it is
    // invalid, and not this property's to move.
    (doc, stray) = square(doc, LayerKind.zone, 10, 5, parentId: neighbour);
    // Reaching past the property line, so not wholly inside.
    (doc, overlapping) = square(doc, LayerKind.zone, 15, 10, parentId: home);

    final shape = doc.geometryOf(home).stack.single;
    final carried = landInside(doc, home, shape);
    expect(carried.keys, [own]);
    expect(carried[own], doc.geometryOf(own).points.keys.toSet());
    expect(stray, isNotEmpty);
    expect(overlapping, isNotEmpty);

    final zoneShape = doc.geometryOf(own).stack.single;
    expect(landInside(doc, own, zoneShape), isEmpty);
  });
}
