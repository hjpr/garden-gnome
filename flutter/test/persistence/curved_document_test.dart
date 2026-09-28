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
  final (doc, property) = GardenDocument(
    id: 'curved-document',
  ).addLayer(LayerKind.property, newId: newId);
  return doc.withGeometry(
    doc.geometryOf(property).edit((e) {
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
  final property = doc.propertyIds.single;
  return doc.withGeometry(
    doc.geometryOf(property).edit((e) {
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
    final geometry = opened.geometryOf(opened.propertyIds.single);

    expect(documentToJson(opened)['schema_version'], schemaVersion);
    expect(geometry.boundary!.holes, hasLength(1));
    expect(geometry.lines.values.any((edge) => edge.bulge != 0), isTrue);
    expect(geometry.region!.area, closeTo(100 - math.pi * 4, 1e-8));
    expect(geometry.region!.locate(const Vec(5, 5)), PointLocation.outside);
    expect(opened.isActive(opened.propertyIds.single), isTrue);
    expect(
      jsonEncode(documentToJson(opened)),
      jsonEncode(documentToJson(original)),
    );
  });

  test('a circular notch round-trips as arc edges, not chords', () {
    final original = cutCircle(squareDocument(), const Vec(10, 5), 2);
    final opened = decodeGgnome(encodeGgnome(original));
    final region = opened.geometryOf(opened.propertyIds.single).region!;
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
    final property = doc.propertyIds.single;
    final boundary = doc.geometryOf(property).boundaryId;
    doc = doc.withGeometry(
      doc.geometryOf(property).edit((e) {
        e.addCircle(e.addPoint(const Vec(20, 5)), 2);
        final small = e.addCircle(e.addPoint(const Vec(30, 3)), 1);
        e.setLabel(small, 'Tomatoes');
        e.moveInStack(small, 0);
      }),
    );
    final geometry = decodeGgnome(encodeGgnome(doc)).geometryOf(property);
    expect(geometry.stack, ['circle-2', boundary, 'circle-1']);
    expect(geometry.labelOf('circle-2'), 'Tomatoes');
    expect(geometry.area, closeTo(100 + math.pi * 5, 1e-8));
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
      // A second property spilling out of the first one's round hole.
      var doc = cutCircle(squareDocument(), const Vec(5, 5), 2);
      final property = doc.propertyIds.single;
      final (withSecond, second) = doc.addLayer(
        LayerKind.property,
        newId: newId,
      );
      doc = withSecond.withGeometry(
        withSecond.geometryOf(second).edit((e) {
          e.addCircle(e.addPoint(const Vec(5, 5)), 3);
        }),
      );
      final opened = decodeGgnome(encodeGgnome(doc));
      expect(opened.problemOf(property), contains('Overlaps'));
      expect(opened.problemOf(second), contains('Overlaps'));
      expect(opened.isActive(second), isFalse);
      expect(
        jsonEncode(documentToJson(opened)),
        jsonEncode(documentToJson(doc)),
      );
    },
  );
}
