import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';

// World coordinates with the camera at its default height and origin.
Offset at(double x, double y) => Offset(x * pixelsPerMetre, y * pixelsPerMetre);

void click(CanvasInput input, double x, double y) {
  final screen = at(x, y);
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

void rectangle(CanvasInput input, double x, double y, double w, double h) {
  input.editor.selectTool(Tool.line);
  input.editor.selectFunction(ToolFunction.draw);
  input.editor.cancelOperation();
  for (final corner in [
    Vec(x, y),
    Vec(x + w, y),
    Vec(x + w, y + h),
    Vec(x, y + h),
    Vec(x, y),
  ]) {
    click(input, corner.x, corner.y);
  }
}

void circle(CanvasInput input, double x, double y, double radius) {
  input.editor.selectTool(Tool.circle);
  input.editor.selectFunction(ToolFunction.centerCircle);
  click(input, x, y);
  click(input, x + radius, y);
}

(EditorController, CanvasInput, String) property() {
  final editor = EditorController()..addLayer(LayerKind.property);
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor), editor.selectedLayerId!);
}

/// Selects closed shapes at world positions in the supplied order.
void selectShapes(CanvasInput input, List<Vec> at) {
  final editor = input.editor;
  editor.selectTool(Tool.select);
  editor.selectItem(null);
  final geometry = editor.document.geometryOf(editor.selectedLayerId!);
  for (final p in at) {
    final id = geometry.closedIds.reversed.firstWhere(
      (id) => geometry.regionOf(id)!.contains(DiscRegion(p, 1e-3)),
    );
    editor.selectItem(id, toggle: true);
  }
}

(EditorController, CanvasInput) newEditor() {
  final editor = EditorController();
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor));
}

/// A layer of [kind] with a closed rectangle, drawn with the Polygon tool.
/// [role] adds it as a bed or planting, as Layers > Add layer does.
String rectangleLayer(
  EditorController editor,
  CanvasInput input,
  LayerKind kind,
  double x0,
  double y0,
  double x1,
  double y1, {
  LayerRole? role,
}) {
  editor.addLayer(kind, role: role);
  final id = editor.selectedLayerId!;
  editor.selectTool(Tool.polygon);
  editor.selectFunction(ToolFunction.rectangle);
  click(input, x0, y0);
  click(input, x1, y1);
  expect(editor.document.geometryOf(id).isClosed, isTrue);
  return id;
}
