import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import '../support/first_shape.dart';

int _next = 0;
String newId() => 'id-${_next++}';

GardenDocument sampleDocument() {
  var (doc, field) = GardenDocument(
    id: 'doc-1',
  ).addLayer(LayerKind.field, newId: newId);
  doc = doc.withGeometry(
    doc.geometryOf(field).edit((e) {
      final ids = [
        e.addPoint(const Vec(0, 0)),
        e.addPoint(const Vec(10, 0)),
        e.addPoint(const Vec(10, 10)),
        e.addPoint(const Vec(0, 10)),
      ];
      for (var i = 0; i < 4; i++) {
        e.connect(ids[i], ids[(i + 1) % 4]);
      }
      e.addPoint(const Vec(5, 5));
    }),
  );
  final (withPlot, plot) = doc.addLayer(
    LayerKind.plot,
    parentId: field,
    newId: newId,
  );
  doc = withPlot.withGeometry(
    withPlot.geometryOf(plot).edit((e) {
      e.connect(e.addPoint(const Vec(1, 1)), e.addPoint(const Vec(4, 1)));
    }),
  );
  return doc.withLayer(
    doc.layers[field]!.copyWith(
      name: 'North field',
      properties: const FieldProperties(
        color: OutlineColor.blue,
        drainage: SoilDrainage.good,
      ),
    ),
  );
}

Uint8List zipWith(Map<String, Object?> json) => ZipEncoder().encodeBytes(
  Archive()
    ..add(ArchiveFile.bytes(documentEntry, utf8.encode(jsonEncode(json)))),
);

void main() {
  test('a drawing survives a save and reopen unchanged', () {
    final original = sampleDocument();
    final reopened = decodeGgnome(encodeGgnome(original));
    expect(
      jsonEncode(documentToJson(reopened)),
      jsonEncode(documentToJson(original)),
    );
    final field = reopened.layers[reopened.fields.single]!;
    expect(field.name, 'North field');
    expect((field.properties as FieldProperties).color, OutlineColor.blue);
    // The loose point is kept; it is unfinished drawing, not damage.
    expect(reopened.ruleProblemOf(field.id), isNull);
    expect(reopened.problemOf(field.id), contains('point'));
    expect(reopened.geometryOf(field.children.single).isClosed, isFalse);
  });

  test('a layer lock is saved; older files without one open unlocked', () {
    final original = sampleDocument();
    final fieldId = original.fields.single;
    final locked = original.withLayer(
      original.layers[fieldId]!.copyWith(locked: true),
    );
    expect(decodeGgnome(encodeGgnome(locked)).layers[fieldId]!.locked, isTrue);

    final json = documentToJson(original);
    for (final layer in (json['layers'] as Map).values) {
      (layer as Map).remove('locked');
    }
    expect(decodeGgnome(zipWith(json)).layers[fieldId]!.locked, isFalse);
  });

  test('a circular boundary survives a save and reopen', () {
    var (doc, field) = GardenDocument(
      id: 'doc-2',
    ).addLayer(LayerKind.field, newId: newId);
    doc = doc.withGeometry(
      doc
          .geometryOf(field)
          .edit((e) => e.addCircle(e.addPoint(const Vec(3, 4)), 2.5)),
    );
    final reopened = decodeGgnome(encodeGgnome(doc));
    final geometry = reopened.geometryOf(field);
    expect(geometry.boundaryCircle!.radius, 2.5);
    expect(reopened.isActive(field), isTrue);
    expect(
      jsonEncode(documentToJson(reopened)),
      jsonEncode(documentToJson(doc)),
    );
  });

  test('files from a newer version are refused', () {
    final json = documentToJson(sampleDocument())..['schema_version'] = 99;
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(
        isA<DocumentFormatError>().having(
          (e) => e.message,
          'message',
          contains('newer'),
        ),
      ),
    );
  });

  test('a line pointing at a missing point is refused, not repaired', () {
    final json = documentToJson(sampleDocument());
    final geometries = json['geometries'] as Map<String, Object?>;
    final first = geometries.values.first as Map<String, Object?>;
    (first['points'] as Map).remove('point-1');
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(isA<DocumentFormatError>()),
    );
  });

  test('counters lower than the IDs in use are refused', () {
    final json = documentToJson(sampleDocument());
    final geometries = json['geometries'] as Map<String, Object?>;
    final first = geometries.values.first as Map<String, Object?>;
    (first['last_ids'] as Map)['points'] = 1;
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(isA<DocumentFormatError>()),
    );
  });

  test('overlapping fields open and are shown invalid', () {
    var doc = sampleDocument();
    final (withSecond, second) = doc.addLayer(LayerKind.field, newId: newId);
    doc = withSecond.withGeometry(
      withSecond.geometryOf(second).edit((e) {
        final ids = [
          e.addPoint(const Vec(5, 5)),
          e.addPoint(const Vec(15, 5)),
          e.addPoint(const Vec(15, 15)),
        ];
        for (var i = 0; i < 3; i++) {
          e.connect(ids[i], ids[(i + 1) % 3]);
        }
      }),
    );
    final reopened = decodeGgnome(encodeGgnome(doc));
    expect(reopened.isValid(second), isFalse);
    expect(reopened.problemOf(second), contains('Overlaps'));
  });

  test('entries that escape the archive are refused', () {
    final bytes = ZipEncoder().encodeBytes(
      Archive()
        ..add(ArchiveFile.bytes(documentEntry, encodeGgnome(sampleDocument())))
        ..add(ArchiveFile.string('../evil.txt', 'x')),
    );
    expect(() => decodeGgnome(bytes), throwsA(isA<DocumentFormatError>()));
  });

  test('random bytes are refused with a plain message', () {
    expect(
      () => decodeGgnome(Uint8List.fromList(List.generate(64, (i) => i))),
      throwsA(isA<DocumentFormatError>()),
    );
  });
}
