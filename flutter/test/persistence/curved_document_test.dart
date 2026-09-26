import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/planar.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import '../support/first_shape.dart';

int _next = 0;
String newId() => 'curved-${_next++}';

GardenDocument squareDocument() {
  final (doc, field) = GardenDocument(
    id: 'curved-document',
  ).addLayer(LayerKind.field, newId: newId);
  return doc.withGeometry(
    doc.geometryOf(field).edit((e) {
      final ids = [
        e.addPoint(const Vec(0, 0)),
        e.addPoint(const Vec(10, 0)),
        e.addPoint(const Vec(10, 10)),
        e.addPoint(const Vec(0, 10)),
      ];
      for (var i = 0; i < ids.length; i++) {
        e.connect(ids[i], ids[(i + 1) % ids.length]);
      }
    }),
  );
}

GardenDocument cutCircle(GardenDocument doc, Vec centre, double radius) {
  final field = doc.fields.single;
  return doc.withGeometry(
    doc.geometryOf(field).edit((e) {
      final circle = e.addCircle(e.addPoint(centre), radius);
      e.boolean(circle, BooleanOperation.subtract);
    }),
  );
}

Map<String, Object?> firstGeometry(Map<String, Object?> json) =>
    (json['geometries'] as Map).values.first as Map<String, Object?>;

void main() {
  test('editable circular holes and their net area survive saving', () {
    final original = cutCircle(squareDocument(), const Vec(5, 5), 2);
    final opened = decodeGgnome(encodeGgnome(original));
    final geometry = opened.geometryOf(opened.fields.single);

    expect(documentToJson(opened)['schema_version'], schemaVersion);
    expect(geometry.boundary!.holes, hasLength(1));
    expect(geometry.lines.values.any((edge) => edge.bulge != 0), isTrue);
    expect(geometry.region!.area, closeTo(100 - math.pi * 4, 1e-8));
    expect(geometry.region!.locate(const Vec(5, 5)), PointLocation.outside);
    expect(opened.isActive(opened.fields.single), isTrue);
    expect(
      jsonEncode(documentToJson(opened)),
      jsonEncode(documentToJson(original)),
    );
  });

  test('a circular notch round-trips as arc edges, not chords', () {
    final original = cutCircle(squareDocument(), const Vec(10, 5), 2);
    final opened = decodeGgnome(encodeGgnome(original));
    final region = opened.geometryOf(opened.fields.single).region!;
    expect(region.area, closeTo(100 - math.pi * 2, 1e-8));
    expect(region.locate(const Vec(9, 5)), PointLocation.outside);
    expect(region.locate(const Vec(7, 5)), PointLocation.inside);
    expect(
      jsonEncode(documentToJson(opened)),
      jsonEncode(documentToJson(original)),
    );
  });

  test('several shapes, their order and labels survive saving', () {
    var doc = squareDocument();
    final field = doc.fields.single;
    final boundary = doc.geometryOf(field).boundaryId;
    doc = doc.withGeometry(
      doc.geometryOf(field).edit((e) {
        e.addCircle(e.addPoint(const Vec(20, 5)), 2);
        final small = e.addCircle(e.addPoint(const Vec(30, 3)), 1);
        e.setLabel(small, 'Tomatoes');
        e.moveInStack(small, 0);
      }),
    );
    final geometry = decodeGgnome(encodeGgnome(doc)).geometryOf(field);
    expect(geometry.stack, ['circle-2', boundary, 'circle-1']);
    expect(geometry.labelOf('circle-2'), 'Tomatoes');
    expect(geometry.area, closeTo(100 + math.pi * 5, 1e-8));
  });

  test('a schema 2 boundary becomes the bottom shape; operands sit above', () {
    final doc = squareDocument();
    final field = doc.fields.single;
    final staged = doc.withGeometry(
      doc
          .geometryOf(field)
          .edit((e) => e.addCircle(e.addPoint(const Vec(30, 5)), 2)),
    );
    final json = documentToJson(staged)..['schema_version'] = 2;
    final source = firstGeometry(json);
    final bottom = (source['order'] as List).first as String;
    source
      ..remove('order')
      ..['boundary'] = {'kind': 'shape', 'id': bottom};
    final opened = documentFromJson(json).geometryOf(field);
    expect(opened.stack, [bottom, 'circle-1']);
    expect(opened.area, closeTo(100 + math.pi * 4, 1e-8));
  });

  test('legacy schema 1 lines and shapes default to straight and no holes', () {
    final json = documentToJson(squareDocument())..['schema_version'] = 1;
    final source = firstGeometry(json);
    for (final line in (source['lines'] as Map).values) {
      (line as Map).remove('bulge');
    }
    for (final shape in (source['shapes'] as Map).values) {
      (shape as Map).remove('holes');
    }
    final doc = documentFromJson(json);
    final geometry = doc.geometryOf(doc.fields.single);
    expect(geometry.lines.values.every((edge) => edge.bulge == 0), isTrue);
    expect(geometry.boundary!.holes, isEmpty);
    expect(geometry.region!.area, closeTo(100, 1e-8));
    expect(doc.isActive(doc.fields.single), isTrue);
  });

  test('missing hole edges are damage, not silently filled-in holes', () {
    final json = documentToJson(
      cutCircle(squareDocument(), const Vec(5, 5), 2),
    );
    final geometry = firstGeometry(json);
    final shape = (geometry['shapes'] as Map).values.single as Map;
    final hole = (shape['holes'] as List).single as List;
    (hole.first as Map)['segment_id'] = 'line-999999';
    expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
  });

  test('a segment cannot be owned by both the outer and a hole ring', () {
    final json = documentToJson(squareDocument());
    final shape = (firstGeometry(json)['shapes'] as Map).values.single as Map;
    shape['holes'] = [shape['segments']];
    expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
  });

  test('malformed hole lists and direction flags are refused', () {
    final json = documentToJson(squareDocument());
    final shape = (firstGeometry(json)['shapes'] as Map).values.single as Map;
    shape['holes'] = 'not a list';
    expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
    shape['holes'] = <Object?>[];
    ((shape['segments'] as List).first as Map)['reversed'] = 'true';
    expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
  });

  test('nonfinite or nonnumeric arc values are refused', () {
    for (final value in [double.nan, double.infinity, 'arc']) {
      final json = documentToJson(squareDocument());
      final line = (firstGeometry(json)['lines'] as Map).values.first as Map;
      line['bulge'] = value;
      expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
    }
  });

  test(
    'opening invalid curved land preserves the drawing and invalid status',
    () {
      var doc = cutCircle(squareDocument(), const Vec(5, 5), 2);
      final field = doc.fields.single;
      final (withPlot, plot) = doc.addLayer(
        LayerKind.plot,
        parentId: field,
        newId: newId,
      );
      doc = withPlot.withGeometry(
        withPlot.geometryOf(plot).edit((e) {
          e.addCircle(e.addPoint(const Vec(5, 5)), 1);
        }),
      );
      final opened = decodeGgnome(encodeGgnome(doc));
      expect(opened.isActive(field), isTrue);
      expect(opened.problemOf(plot), contains('inside'));
      expect(opened.isActive(plot), isFalse);
      expect(
        jsonEncode(documentToJson(opened)),
        jsonEncode(documentToJson(doc)),
      );
    },
  );
}
