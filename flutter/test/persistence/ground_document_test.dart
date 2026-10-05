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

  test('a planting layer\'s sowing is saved with its layer', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    editor.setSeed(grow, seed());
    editor.setSownOn(grow, DateTime.utc(2027, 3, 1));
    editor.setTransplantedOn(grow, DateTime.utc(2027, 4, 15));
    final opened = decodeGgnome(encodeGgnome(editor.document));
    final sowing = opened.currentPlantingOf(grow)!;
    expect(sowing.layerId, grow);
    expect(sowing.sownOn, DateTime.utc(2027, 3, 1));
    expect(sowing.plantedOutOn, DateTime.utc(2027, 4, 15));
    expect(sowing.startedIndoors, isTrue);
  });

  test('a version 7 Plant on date opens as a sowing in place', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    editor.setSeed(grow, seed());
    final json = documentToJson(editor.document);
    json['schema_version'] = 7;
    for (final key in ['climate', 'planting_counter', 'plantings']) {
      json.remove(key);
    }
    final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
    // Version 7 seeds held a size and an empty gap.
    props['seed'] = <String, Object?>{
      'variety_id': seed().varietyId,
      'name': seed().name,
      'size': 0.5,
      'spacing': 0.25,
      'plant_on': '2027-04-15',
    };
    final opened = documentFromJson(json);
    final sowing = opened.plantings.values.single;
    expect(sowing.layerId, grow);
    expect(sowing.sownOn, DateTime.utc(2027, 4, 15));
    expect(sowing.startedIndoors, isFalse);
    expect(opened.plantingCounter, 1);
  });

  test('seed centre distances round-trip explicitly', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    for (final between in [0.5, 1.25]) {
      final planted = seed(inRow: 0.3, betweenRows: between);
      editor.setSeed(grow, planted);
      final json = documentToJson(editor.document);
      expect(json['schema_version'], schemaVersion);
      final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
      expect(props['seed'], {
        'variety_id': planted.varietyId,
        'name': planted.name,
        'in_row': 0.3,
        'between_rows': between,
      });
      final opened = decodeGgnome(encodeGgnome(editor.document));
      expect((opened.layers[grow]!.properties as ZoneProperties).seed, planted);
    }
  });

  test('schema 4-12 size and gap open as one centre distance both ways', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    final json = documentToJson(editor.document)..['schema_version'] = 12;
    final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
    props['seed'] = {
      'variety_id': 'old',
      'name': 'Old',
      'size': 0.5,
      'spacing': 0.25,
    };
    final planted =
        (documentFromJson(json).layers[grow]!.properties as ZoneProperties)
            .seed!;
    expect(planted.inRow, 0.75);
    expect(planted.betweenRows, 0.75);
    for (final (field, value) in [('size', 0), ('spacing', -1)]) {
      (props['seed'] as Map)[field] = value;
      expect(() => documentFromJson(json), throwsA(isA<DocumentFormatError>()));
      (props['seed'] as Map)['size'] = 0.5;
      (props['seed'] as Map)['spacing'] = 0.25;
    }
    (props['seed'] as Map)['spacing'] = 0;
    final touching =
        (documentFromJson(json).layers[grow]!.properties as ZoneProperties)
            .seed!;
    expect(touching.inRow, 0.5);
  });

  test('schema 3 centre distances open as they were', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    final json = documentToJson(editor.document)..['schema_version'] = 3;
    final props = ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
    props['seed'] = {
      'variety_id': 'legacy',
      'name': 'Legacy',
      'in_row': 0.5,
      'between_rows': 1.25,
    };
    final opened = documentFromJson(json);
    final planted = (opened.layers[grow]!.properties as ZoneProperties).seed!;
    expect(planted.inRow, 0.5);
    expect(planted.betweenRows, 1.25);
    final reopened = decodeGgnome(encodeGgnome(opened));
    expect((reopened.layers[grow]!.properties as ZoneProperties).seed, planted);
  });

  test('legacy damaged distances are refused', () {
    final (editor, _, _, grow) = garden(GroundType.row);
    for (final field in ['in_row', 'between_rows']) {
      for (final value in [0, -1, double.nan, double.infinity, '1', null]) {
        final json = documentToJson(editor.document)..['schema_version'] = 3;
        final props =
            ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
        props['seed'] = <String, Object?>{
          'variety_id': 'v',
          'name': 'Legacy',
          'in_row': 0.5,
          'between_rows': 1.0,
          field: value,
        };
        expect(
          () => documentFromJson(json),
          throwsA(isA<DocumentFormatError>()),
        );
      }
    }
  });

  test('invalid or missing seed spacings are refused', () {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    for (final field in ['in_row', 'between_rows']) {
      for (final value in [0, -1, double.nan, double.infinity, '5', null]) {
        final json =
            jsonDecode(jsonEncode(documentToJson(editor.document)))
                as Map<String, Object?>;
        final props =
            ((json['layers'] as Map)[grow] as Map)['properties'] as Map;
        (props['seed'] as Map)[field] = value;
        expect(
          () => documentFromJson(json),
          throwsA(isA<DocumentFormatError>()),
          reason: '$field=$value',
        );
      }
    }
  });
}
