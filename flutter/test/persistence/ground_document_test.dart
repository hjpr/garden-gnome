import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

import '../support/ground_fixtures.dart';

void main() {
  group('Saving', () {
    test('older row settings without a border open with zero clearance', () {
      final (editor, _, _, zone) = farm();
      final json = documentToJson(editor.document);
      final properties =
          ((json['layers'] as Map)[zone] as Map)['properties'] as Map;
      (properties['rows'] as Map).remove('border');
      expect(documentFromJson(json).rowsOf(zone)!.border, 0);
    });

    test('damaged border values are refused', () {
      final (editor, _, _, zone) = farm();
      for (final value in [-1, double.nan, double.infinity, '5', null]) {
        final json =
            jsonDecode(jsonEncode(documentToJson(editor.document)))
                as Map<String, Object?>;
        final properties =
            ((json['layers'] as Map)[zone] as Map)['properties'] as Map;
        (properties['rows'] as Map)['border'] = value;
        expect(
          () => documentFromJson(json),
          throwsA(isA<DocumentFormatError>()),
        );
      }
    });

    test('row border survives loading and saving', () {
      final (editor, _, _, zone) = farm();
      final json = documentToJson(editor.document);
      final properties =
          ((json['layers'] as Map)[zone] as Map)['properties'] as Map;
      (properties['rows'] as Map)['border'] = 1.524;

      final opened = documentFromJson(json);
      final saved = documentToJson(decodeGgnome(encodeGgnome(opened)));
      final savedProperties =
          ((saved['layers'] as Map)[zone] as Map)['properties'] as Map;
      expect((savedProperties['rows'] as Map)['border'], 1.524);
      expect(opened.rowsOf(zone), isNot(editor.document.rowsOf(zone)));
    });

    test('ground, rows and features round-trip', () {
      final (editor, _, _, zone) = farm();
      editor.setGround(zone, GroundType.row);
      editor.setRows(
        zone,
        const RowSpec(width: 1.2, spacing: 0.3, direction: 45),
      );
      editor.addFeature(FeatureKind.greenhouse, const Vec(3, 4));
      final opened = decodeGgnome(encodeGgnome(editor.document));
      expect(opened.storedGroundOf(zone), GroundType.row);
      expect(
        opened.rowsOf(zone),
        const RowSpec(width: 1.2, spacing: 0.3, direction: 45),
      );
      expect(opened.features, editor.document.features);
      expect(opened.featureCounter, 1);
    });

    test('a version 1 file opens: patterns dropped, rows carried over', () {
      final (editor, _, _, zone) = farm();
      final json = documentToJson(editor.document)
        ..['schema_version'] = 1
        ..remove('features')
        ..remove('feature_counter');
      final layers = json['layers'] as Map<String, Object?>;
      for (final layer in layers.values.cast<Map<String, Object?>>()) {
        final props = layer['properties'] as Map<String, Object?>;
        props['pattern'] = 'dots';
        if (layer['kind'] == 'zone') {
          props
            ..remove('rows')
            ..['ground'] = 'raised beds'
            ..['planting_type'] = 'row';
        }
      }
      final zoneGeometry =
          (json['geometries'] as Map)[editor.document.layers[zone]!.geometryId]
              as Map<String, Object?>;
      zoneGeometry['dimensions'] = {
        'row_width': 2.0,
        'row_spacing': 1.0,
        'row_direction': 200.0,
        'mound_diameter': null,
        'mound_spacing': null,
      };
      final bytes = ZipEncoder().encodeBytes(
        Archive()..add(
          ArchiveFile.bytes(documentEntry, utf8.encode(jsonEncode(json))),
        ),
      );
      final opened = decodeGgnome(Uint8List.fromList(bytes));
      expect(opened.storedGroundOf(zone), isNull);
      expect(
        opened.rowsOf(zone),
        const RowSpec(width: 2, spacing: 1, direction: 20),
      );
      expect(opened.features, isEmpty);
    });

    test('damaged feature or row values are refused', () {
      final (editor, _, _, zone) = farm();
      editor.setGround(zone, GroundType.row);
      editor.addFeature(FeatureKind.raisedBed, Vec.zero);
      Map<String, Object?> fresh() =>
          jsonDecode(jsonEncode(documentToJson(editor.document)))
              as Map<String, Object?>;
      final json = fresh();
      ((json['features'] as List).single as Map)['length'] = -1;
      expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
      final again = fresh();
      final zoneJson = (again['layers'] as Map)[zone] as Map;
      ((zoneJson['properties'] as Map)['rows'] as Map)['width'] = 0;
      expect(
        () => documentFromJson(again),
        throwsA(isA<DocumentFormatError>()),
      );
    });
  });

  test('grow zones and seeds survive saving', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    editor.setSeed(grow, seed());
    final json = documentToJson(editor.document);
    expect(json['schema_version'], schemaVersion);
    final opened = documentFromJson(json);
    final p = opened.layers[grow]!.properties as ZoneProperties;
    expect(p.ground, GroundType.grow);
    expect(p.seed, seed());
  });

  test('seed diameter and empty gap round-trip explicitly in schema 4', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    for (final gap in [0.0, 0.75]) {
      final planted = seed(size: 0.5, spacing: gap);
      editor.setSeed(grow, planted);
      final json = documentToJson(editor.document);
      expect(json['schema_version'], 4);
      final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
      expect(props['seed'], {
        'variety_id': planted.varietyId,
        'name': planted.name,
        'size': 0.5,
        'spacing': gap,
      });
      final opened = decodeGgnome(encodeGgnome(editor.document));
      expect((opened.layers[grow]!.properties as ZoneProperties).seed, planted);
    }
  });

  test('legacy centre distances become diameter and nonnegative empty gap', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    for (final between in [0.25, 0.5, 1.25]) {
      final json = documentToJson(editor.document)..['schema_version'] = 3;
      final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
      props['seed'] = {
        'variety_id': 'legacy', 'name': 'Legacy',
        'in_row': 0.5, 'between_rows': between,
      };
      final opened = documentFromJson(json);
      final planted = (opened.layers[grow]!.properties as ZoneProperties).seed!;
      expect(planted.size, 0.5);
      expect(planted.spacing, between <= 0.5 ? 0 : 0.75);
      final reopened = decodeGgnome(encodeGgnome(opened));
      expect((reopened.layers[grow]!.properties as ZoneProperties).seed, planted);
    }
  });

  test('legacy damaged distances are rejected before gap conversion', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    for (final field in ['in_row', 'between_rows']) {
      for (final value in [0, -1, double.nan, double.infinity, '1', null]) {
        final json = documentToJson(editor.document)..['schema_version'] = 3;
        final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
        props['seed'] = <String, Object?>{
          'variety_id': 'v', 'name': 'Legacy',
          'in_row': 0.5, 'between_rows': 1.0, field: value,
        };
        expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
      }
    }
  });

  test('invalid or missing seed size and gap are refused', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    for (final field in ['size', 'spacing']) {
      for (final value in [-1, double.nan, double.infinity, '5', null]) {
        final json = jsonDecode(jsonEncode(documentToJson(editor.document)))
            as Map<String, Object?>;
        final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
        (props['seed'] as Map)[field] = value;
        expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()),
            reason: '$field=$value');
      }
    }
  });
}
