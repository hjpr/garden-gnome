import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';

import 'editor_input.dart';

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

/// A seed with round sizes and gaps, so plant counts are easy to check.
ZoneSeed seed({double size = 0.5, double spacing = 0.25}) => ZoneSeed(
  varietyId: 'variety-1',
  name: 'Test · Crop',
  size: size,
  spacing: spacing,
);

/// A 0–20 m property with a soil zone and a grow zone over part of it.
/// Returns the editor, input, soil zone and grow zone.
(EditorController, CanvasInput, String, String) garden(GroundType soil) {
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
  final soilZone = rectangleLayer(editor, input, LayerKind.zone, 2, 2, 12, 12);
  editor.setGround(soilZone, soil);
  editor.selectLayer(property);
  final grow = rectangleLayer(editor, input, LayerKind.zone, 4, 4, 8, 10);
  editor.setGround(grow, GroundType.grow);
  editor.selectTool(Tool.select);
  return (editor, input, soilZone, grow);
}
