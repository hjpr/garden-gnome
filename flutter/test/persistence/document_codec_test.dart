import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry_editor.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import 'package:garden_gnome/persistence/document_json.dart' as mapping;
import '../support/first_shape.dart';

int _next = 0;
String newId() => 'id-${_next++}';

GardenDocument sampleDocument() {
  var (doc, property) = GardenDocument(
    id: 'doc-1',
  ).addLayer(LayerKind.property, newId: newId);
  doc = doc.withGeometry(
    doc.geometryOf(property).edit((e) {
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
  final (withZone, zone) = doc.addLayer(
    LayerKind.zone,
    parentId: property,
    newId: newId,
  );
  doc = withZone.withGeometry(
    withZone.geometryOf(zone).edit((e) {
      e.connect(e.addPoint(const Vec(1, 1)), e.addPoint(const Vec(4, 1)));
    }),
  );
  return doc.withLayer(
    doc.layers[property]!.copyWith(
      name: 'North property',
      properties: const PropertyProperties(color: OutlineColor.blue),
    ),
  );
}

Uint8List zipWith(Map<String, Object?> json) => ZipEncoder().encodeBytes(
  Archive()
    ..add(ArchiveFile.bytes(documentEntry, utf8.encode(jsonEncode(json)))),
);

void main() {
  test('schema 2 retains rows and features without a seed field', () {
    final json = documentToJson(sampleDocument())..['schema_version'] = 2;
    final zone = (json['layers'] as Map).values.cast<Map>().singleWhere(
      (layer) => layer['kind'] == 'zone',
    );
    final props = zone['properties'] as Map;
    props
      ..remove('seed')
      ..['ground'] = 'row'
      ..['rows'] = {'width': 2.0, 'spacing': 0.5, 'direction': 45.0};
    json['feature_counter'] = 1;
    json['features'] = [
      {
        'id': 'feature-1',
        'kind': 'highTunnel',
        'centre': {'x': 3.0, 'y': 4.0},
        'length': 12.0,
        'width': 4.0,
        'height': 3.0,
        'rotation': 30.0,
        'label': 'Tunnel',
      },
    ];
    const codec = GgnomeCodec();
    final opened = codec.decode(zipWith(json));
    final zoneProps =
        opened.layers.values
                .singleWhere((layer) => layer.kind == LayerKind.zone)
                .properties
            as ZoneProperties;
    expect(zoneProps.seed, isNull);
    expect(zoneProps.ground, GroundType.row);
    expect(
      zoneProps.rows,
      const RowSpec(width: 2, spacing: 0.5, direction: 45),
    );
    expect(opened.features.single.label, 'Tunnel');
    expect(opened.features.single.length, 12);
    final jsonOnly = mapping.documentFromJson(json);
    expect(mapping.documentToJson(jsonOnly), documentToJson(opened));
    expect(
      documentToJson(codec.decode(codec.encode(opened))),
      documentToJson(opened),
    );
  });

  test('schema 4 files open with soil drainage and sample values dropped', () {
    final json = documentToJson(sampleDocument())..['schema_version'] = 4;
    final property = (json['layers'] as Map).values.cast<Map>().singleWhere(
      (layer) => layer['kind'] == 'property',
    );
    property['properties'] = <String, Object?>{
      ...property['properties'] as Map<String, Object?>,
      'drainage': 'good',
      'soil': {'ph': 6.5, 'organic_matter': 3.2},
    };
    final opened = mapping.documentFromJson(json);
    final props =
        opened.layers.values
                .singleWhere((layer) => layer.kind == LayerKind.property)
                .properties
            as PropertyProperties;
    expect(props.color, OutlineColor.blue);
    final saved = documentToJson(opened)['layers'] as Map;
    final savedProps = saved.values.cast<Map>().singleWhere(
      (layer) => layer['kind'] == 'property',
    )['properties'];
    expect(savedProps, {'color': 'blue'});
  });

  test('ZIP assets resolve through the JSON mapping boundary', () {
    final json = documentToJson(sampleDocument());
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2uoAAAAASUVORK5CYII=',
    );
    json['image_counter'] = 1;
    json['reference_layer'] = true;
    json['references'] = [
      {
        'id': 'image-1',
        'label': 'Plan',
        'file_name': 'plan.png',
        'asset': 'assets/image-1.png',
        'mime_type': 'image/png',
        'pixel_width': 1,
        'pixel_height': 1,
        'top_left': {'x': 3.0, 'y': 4.0},
        'metres_per_pixel': 2.0,
        'line_start': {'x': 0.0, 'y': 0.0},
        'line_end': {'x': 1.0, 'y': 0.0},
        'known_distance': 2.0,
        'opacity': 0.4,
        'locked': true,
      },
    ];
    final requested = <String>[];
    final mapped = mapping.documentFromJson(
      json,
      readAsset: (name) {
        requested.add(name);
        return name == 'assets/image-1.png' ? png : null;
      },
    );
    expect(requested, ['assets/image-1.png']);
    final bytes = const GgnomeCodec().encode(mapped);
    final archive = ZipDecoder().decodeBytes(bytes);
    expect(archive.files.map((file) => file.name), [
      'document.json',
      'assets/image-1.png',
    ]);
    final reopened = const GgnomeCodec().decode(bytes);
    expect(reopened.references.single.bytes, png);
    expect(mapping.documentToJson(reopened), json);
    expect(
      () => mapping.documentFromJson(json),
      throwsA(isA<DocumentFormatError>()),
    );
  });

  test('a drawing survives a save and reopen unchanged', () {
    final original = sampleDocument();
    final reopened = decodeGgnome(encodeGgnome(original));
    expect(
      jsonEncode(documentToJson(reopened)),
      jsonEncode(documentToJson(original)),
    );
    final property = reopened.layers[reopened.propertyIds.single]!;
    expect(property.name, 'North property');
    expect(
      (property.properties as PropertyProperties).color,
      OutlineColor.blue,
    );
    // The loose point is kept; it is unfinished drawing, not damage.
    expect(reopened.ruleProblemOf(property.id), isNull);
    expect(reopened.problemOf(property.id), contains('point'));
    expect(reopened.geometryOf(property.children.single).isClosed, isFalse);
  });

  test('a layer lock is saved and reopened', () {
    final original = sampleDocument();
    final propertyId = original.propertyIds.single;
    final locked = original.withLayer(
      original.layers[propertyId]!.copyWith(locked: true),
    );
    expect(
      decodeGgnome(encodeGgnome(locked)).layers[propertyId]!.locked,
      isTrue,
    );
  });

  test('a circular boundary survives a save and reopen', () {
    var (doc, property) = GardenDocument(
      id: 'doc-2',
    ).addLayer(LayerKind.property, newId: newId);
    doc = doc.withGeometry(
      doc
          .geometryOf(property)
          .edit((e) => e.addCircle(e.addPoint(const Vec(3, 4)), 2.5)),
    );
    final reopened = decodeGgnome(encodeGgnome(doc));
    final geometry = reopened.geometryOf(property);
    expect(geometry.boundaryCircle!.radius, 2.5);
    expect(reopened.isActive(property), isTrue);
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

  test('files from another schema version are refused', () {
    final json = documentToJson(sampleDocument())..['schema_version'] = 0;
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(
        isA<DocumentFormatError>().having(
          (e) => e.message,
          'message',
          contains('unsupported schema version'),
        ),
      ),
    );
  });

  test('a missing setting is damage, not filled in with a default', () {
    final json = documentToJson(sampleDocument());
    final layer = (json['layers'] as Map).values.first as Map;
    layer.remove('locked');
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(
        isA<DocumentFormatError>().having(
          (e) => e.message,
          'message',
          contains('layer lock'),
        ),
      ),
    );
  });

  test('planting sizes on a property are refused', () {
    final json = documentToJson(sampleDocument());
    final zone = (json['geometries'] as Map).values.last as Map;
    final property = (json['geometries'] as Map).values.first as Map;
    property['dimensions'] = zone['dimensions'];
    expect(
      () => decodeGgnome(zipWith(json)),
      throwsA(
        isA<DocumentFormatError>().having(
          (e) => e.message,
          'message',
          contains('planting sizes'),
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

  test('overlapping properties open and are shown invalid', () {
    var doc = sampleDocument();
    final (withSecond, second) = doc.addLayer(LayerKind.property, newId: newId);
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
