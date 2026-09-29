import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tool_prompts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/row_layout.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

Offset at(double x, double y) => Offset(x * pixelsPerMetre, y * pixelsPerMetre);

void click(CanvasInput input, double x, double y) {
  final screen = at(x, y);
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

(EditorController, CanvasInput) newEditor() {
  final editor = EditorController();
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor));
}

/// A layer of [kind] with a closed rectangle, drawn with the Polygon tool.
String rectangleLayer(
  EditorController editor,
  CanvasInput input,
  LayerKind kind,
  double x0,
  double y0,
  double x1,
  double y1,
) {
  editor.addLayer(kind);
  final id = editor.selectedLayerId!;
  editor.selectTool(Tool.polygon);
  editor.selectFunction(ToolFunction.rectangle);
  click(input, x0, y0);
  click(input, x1, y1);
  expect(editor.document.geometryOf(id).isClosed, isTrue);
  return id;
}

/// A property 0–20 m square with a zone 2–12 × 2–8 m inside it.
(EditorController, CanvasInput, String, String) farm() {
  final (editor, input) = newEditor();
  final property = rectangleLayer(
    editor,
    input,
    LayerKind.property,
    0,
    0,
    20,
    20,
  );
  final zone = rectangleLayer(editor, input, LayerKind.zone, 2, 2, 12, 8);
  return (editor, input, property, zone);
}

void main() {
  group('Ground tool', () {
    test('clicking inside a zone sets its ground as one Undo step', () {
      final (editor, input, _, zone) = farm();
      editor.selectTool(Tool.ground);
      expect(editor.function, ToolFunction.flatGround);
      click(input, 5, 5);
      expect(editor.document.storedGroundOf(zone), GroundType.flat);
      expect(editor.undoLabel, 'Flat ground');

      editor.selectFunction(ToolFunction.rowGround);
      click(input, 5, 5);
      expect(editor.document.storedGroundOf(zone), GroundType.row);
      editor.undo();
      expect(editor.document.storedGroundOf(zone), GroundType.flat);
      expect(editor.tool, Tool.ground, reason: 'the tool stays chosen');
    });

    test('outside the zone, or on a property, nothing changes', () {
      final (editor, input, property, zone) = farm();
      editor.selectTool(Tool.ground);
      click(input, 15, 15);
      expect(editor.document.storedGroundOf(zone), isNull);
      expect(editor.notice, contains('Click inside'));

      editor.selectLayer(property);
      expect(toolPrompt(editor), 'Ground is set on zones. Select a zone');
      click(input, 15, 15);
      expect(editor.notice, CanvasInput.groundNeedsZone);
    });

    test('Properties and the tool share one value; rows keep their sizes', () {
      final (editor, _, _, zone) = farm();
      editor.setGround(zone, GroundType.row);
      editor.setRows(
        zone,
        const RowSpec(width: 1, spacing: 0.5, direction: 90),
      );
      editor.setGround(zone, GroundType.flat);
      editor.setGround(zone, GroundType.row);
      expect(
        editor.document.rowsOf(zone),
        const RowSpec(width: 1, spacing: 0.5, direction: 90),
      );
      expect(RowSpec.normalDirection(-30), 150);
      expect(RowSpec.normalDirection(270), 90);
    });

    test('row sizes that cannot work are refused with a reason', () {
      final (editor, _, _, zone) = farm();
      final before = editor.document;
      editor.setRows(zone, const RowSpec(width: 0));
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, 'Row width must be above 0');
    });
  });

  group('Row layout', () {
    const square = PolygonRegion([
      Vec(0, 0),
      Vec(10, 0),
      Vec(10, 6),
      Vec(0, 6),
    ]);

    test('north–south rows fill the width edge to edge', () {
      // 10 m wide, 1 m rows with 1 m paths: rows at 0.5, 2.5 … 8.5.
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 1, spacing: 1, direction: 0),
      );
      expect(layout.rowCount, 5);
      expect(layout.totalLength, closeTo(30, 1e-6));
      expect(layout.bedArea, closeTo(30, 1e-6));
      expect(layout.runs.first.start.x, closeTo(0.5, 1e-9));
    });

    test('east–west rows run along the other side', () {
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 1, spacing: 1, direction: 90),
      );
      expect(layout.rowCount, 3);
      expect(layout.totalLength, closeTo(30, 1e-6));
    });

    test('a hole splits a row into two runs', () {
      final holed = CurveRegion([
        const PolygonRegion([
          Vec(0, 0),
          Vec(10, 0),
          Vec(10, 10),
          Vec(0, 10),
        ]).contours.first,
        const PolygonRegion([
          Vec(4, 4),
          Vec(6, 4),
          Vec(6, 6),
          Vec(4, 6),
        ]).contours.first,
      ]);
      final layout = RowLayout.of(
        holed,
        const RowSpec(width: 1, spacing: 1, direction: 90),
      );
      // Rows at y = 0.5, 2.5, 4.5, 6.5, 8.5; the one at 4.5 is cut in two.
      expect(layout.rowCount, 5);
      expect(layout.runs, hasLength(6));
      expect(layout.totalLength, closeTo(48, 1e-6));
    });

    test('each piece of a zone starts with a whole row at its edge', () {
      final (editor, input, _, zone) = farm();
      editor.selectTool(Tool.polygon);
      editor.selectFunction(ToolFunction.rectangle);
      // A second piece, 3.3 m to the right: not on the first piece's pitch.
      click(input, 15.3, 10);
      click(input, 18.3, 16);
      editor.setGround(zone, GroundType.row);
      editor.setRows(zone, const RowSpec(width: 1, spacing: 1));
      final layout = editor.document.rowLayoutOf(zone)!;
      // 10 m wide piece: 5 rows; 3 m wide piece: 2 rows.
      expect(layout.rowCount, 7);
      expect(
        layout.runs.map((r) => r.start.x).toSet(),
        containsAll([2.5, 15.8]),
      );
    });

    test('far too many rows lays out none rather than freezing', () {
      final layout = RowLayout.of(
        square,
        const RowSpec(width: 0.0001, spacing: 0),
      );
      expect(layout.runs, isEmpty);
    });
  });

  group('Feature tool', () {
    test('a click places a feature at its usual size and selects it', () {
      final (editor, input) = newEditor();
      editor.selectTool(Tool.feature);
      editor.selectFunction(ToolFunction.greenhouse);
      click(input, 10, 10);
      final feature = editor.document.features.single;
      expect(feature.kind, FeatureKind.greenhouse);
      expect(feature.centre, const Vec(10, 10));
      expect(feature.length, FeatureKind.greenhouse.defaultLength);
      expect(feature.displayName, 'Greenhouse 1');
      expect(editor.selectedFeature, feature);
      expect(editor.showsFeature, isTrue);
      editor.undo();
      expect(editor.document.features, isEmpty);
      expect(editor.selectedFeature, isNull);
    });

    test('Select picks a feature over land and drags it', () {
      final (editor, input, property, _) = farm();
      editor.addFeature(FeatureKind.raisedBed, const Vec(15, 15));
      editor.selectLayer(property);
      editor.selectTool(Tool.select);
      click(input, 15, 15);
      expect(editor.selectedFeature?.kind, FeatureKind.raisedBed);

      input.press(at(15, 15), shift: false);
      input.move(at(16, 15));
      input.move(at(17, 16));
      input.release(at(17, 16));
      expect(editor.selectedFeature!.centre, const Vec(17, 16));
      expect(editor.undoLabel, 'Move Raised bed 1');
    });

    test('sizes, rotation and name change as Undo steps; Delete removes', () {
      final (editor, _) = newEditor();
      editor.addFeature(FeatureKind.highTunnel, Vec.zero);
      final feature = editor.selectedFeature!;
      editor.updateFeature(
        'Change length',
        feature.copyWith(length: 20, rotation: -90, label: () => 'Tomatoes'),
      );
      final changed = editor.selectedFeature!;
      expect(changed.length, 20);
      expect(changed.rotation, 270);
      expect(changed.displayName, 'Tomatoes');
      editor.updateFeature('Change width', changed.copyWith(width: 0));
      expect(editor.notice, 'Width must be above 0');
      expect(editor.selectedFeature!.width, feature.width);
      editor.deleteSelection();
      expect(editor.document.features, isEmpty);
      editor.undo();
      expect(editor.document.features.single.displayName, 'Tomatoes');
    });

    test('a rotated feature contains points along its turned length', () {
      final f = Feature.placed(
        'feature-1',
        FeatureKind.raisedBed,
        Vec.zero,
      ).copyWith(rotation: 90);
      expect(f.contains(Vec(0, f.length / 2 - 0.01)), isTrue);
      expect(f.contains(Vec(f.length / 2 - 0.01, 0)), isFalse);
    });

    test('a tunnel is drawn in whole 5 ft sections, ends included', () {
      const foot = 0.3048;
      expect(tunnelSections(79 * foot), 16, reason: '79 ft shows as 80 ft');
      expect(tunnelSections(77 * foot), 15, reason: '77 ft shows as 75 ft');
      expect(tunnelSections(30 * foot), 6);
      expect(tunnelSections(3 * foot), 2, reason: 'never fewer than 2 ends');
    });

    test('feature IDs are never reused after Undo', () {
      final (editor, _) = newEditor();
      editor.addFeature(FeatureKind.raisedBed, Vec.zero);
      editor.undo();
      editor.addFeature(FeatureKind.raisedBed, Vec.zero);
      expect(editor.document.features.single.id, 'feature-2');
    });
  });

  group('View mode', () {
    test('Render is a workspace choice, not an Undo step', () {
      final (editor, _) = newEditor();
      expect(editor.settings.viewMode, ViewMode.wireframe);
      editor.setViewMode(ViewMode.render);
      expect(editor.settings.viewMode, ViewMode.render);
      expect(editor.canUndo, isFalse);
      expect(editor.isDirty, isFalse);
    });
  });

  group('Saving', () {
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
}
