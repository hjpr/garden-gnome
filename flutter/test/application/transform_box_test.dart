import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tool_prompts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/application/transform_box.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';

/// With the camera at its starting height over the origin, one metre is 30
/// pixels.
Offset at(double x, double y) => Offset(x * 30, y * 30);

/// The selection box pads the shape by this many metres at the starting
/// camera height.
const pad = BoxReach.padding / 30;

void click(CanvasInput input, Offset where) {
  input.hover(where);
  input.press(where, shift: false);
  input.release(where);
}

void drag(CanvasInput input, Offset from, Offset to, {bool shift = false}) {
  input.hover(from);
  input.press(from, shift: false);
  input.move(from + (to - from) / 10, shift: shift);
  input.move(to, shift: shift);
  input.release(to);
}

/// A property with one 4 × 2 m rectangle from (2, 2) to (6, 4), selected
/// with Select.
(EditorController, CanvasInput, String) selectedRectangle() {
  final editor = EditorController()..addLayer(LayerKind.property);
  addTearDown(editor.dispose);
  final input = CanvasInput(editor);
  final layer = editor.selectedLayerId!;
  editor.selectTool(Tool.polygon);
  editor.selectFunction(ToolFunction.rectangle);
  click(input, at(2, 2));
  click(input, at(6, 4));
  editor.selectTool(Tool.select);
  click(input, at(4, 3));
  return (editor, input, layer);
}

List<Vec> corners(EditorController editor, String layer) {
  final points = editor.document.geometryOf(layer).points.values.toList()
    ..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  return points;
}

void main() {
  test('a selected shape gets a box around it; a lone point does not', () {
    final (editor, input, layer) = selectedRectangle();
    final box = selectionBoxOf(editor)!;
    expect(box.centre, const Vec(4, 3));
    expect(box.width, closeTo(4, 1e-9));
    expect(box.height, closeTo(2, 1e-9));

    click(input, at(2, 2));
    expect(editor.selection.single, startsWith('point'));
    expect(selectionBoxOf(editor), isNull);

    editor.selectTool(Tool.line);
    expect(selectionBoxOf(editor), isNull, reason: 'only Select has a box');
    expect(layer, isNotNull);
  });

  test('hovering finds corner and edge handles, edges, and rotate zones', () {
    final (editor, input, _) = selectedRectangle();
    final box = selectionBoxOf(editor)!;
    final camera = editor.camera;
    expect(
      box.gripAt(camera, at(6 + pad, 4 + pad)),
      const BoxGrip(BoxHandle.bottomRight),
    );
    expect(
      box.gripAt(camera, at(4, 2 - pad)),
      const BoxGrip(BoxHandle.top),
      reason: 'the middle dot of the top edge',
    );
    expect(
      box.gripAt(camera, at(5, 2 - pad)),
      const BoxGrip(BoxHandle.top),
      reason: 'anywhere along the dashed top edge',
    );
    expect(box.gripAt(camera, at(2 - pad, 3.3)), const BoxGrip(BoxHandle.left));
    expect(
      box.gripAt(camera, at(6 + pad, 2 - pad) + const Offset(10, -10)),
      const BoxGrip(BoxHandle.topRight, rotate: true),
      reason: 'just outside a corner turns the shape',
    );
    expect(box.gripAt(camera, at(4, 3)), isNull, reason: 'the inside moves');
    expect(box.gripAt(camera, at(10, 10)), isNull);

    input.hover(at(6 + pad, 4 + pad));
    expect(input.activeGrip, const BoxGrip(BoxHandle.bottomRight));
    input.hover(at(4, 3));
    expect(input.activeGrip, isNull);
  });

  test('dragging a corner scales about the opposite corner, as one Undo', () {
    final (editor, input, layer) = selectedRectangle();
    final before = editor.document;
    // Pull the bottom-right handle 2 m right and 1 m down.
    drag(input, at(6 + pad, 4 + pad), at(8 + pad, 5 + pad));
    expect(corners(editor, layer), const [
      Vec(2, 2),
      Vec(2, 5),
      Vec(8, 2),
      Vec(8, 5),
    ]);
    expect(editor.undoLabel, 'Scale');
    expect(editor.selection, isNotEmpty, reason: 'selection is kept');
    editor.undo();
    expect(identical(editor.document, before), isTrue);
  });

  test('Shift keeps a corner scale in proportion', () {
    final (editor, input, layer) = selectedRectangle();
    drag(input, at(6 + pad, 4 + pad), at(10 + pad, 4 + pad), shift: true);
    final box = selectionBoxOf(editor)!;
    expect(box.width, closeTo(8, 1e-9));
    expect(box.height, closeTo(4, 1e-9));
    expect(corners(editor, layer).first, const Vec(2, 2));
  });

  test('an edge handle scales one way only', () {
    final (editor, input, layer) = selectedRectangle();
    drag(input, at(2 - pad, 3), at(1 - pad, 3.5));
    final box = selectionBoxOf(editor)!;
    expect(box.width, closeTo(5, 1e-9));
    expect(box.height, closeTo(2, 1e-9));
    expect(corners(editor, layer).last, const Vec(6, 4));
  });

  test('scaling cannot turn a shape inside out', () {
    final (editor, _, _) = selectedRectangle();
    final input = CanvasInput(editor);
    drag(input, at(6 + pad, 3), at(-4, 3));
    final box = selectionBoxOf(editor)!;
    expect(box.width, greaterThan(0));
    expect(box.centre.x, greaterThan(2));
  });

  test('a circle scales evenly and keeps being a circle', () {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final input = CanvasInput(editor);
    final layer = editor.selectedLayerId!;
    editor.selectTool(Tool.circle);
    click(input, at(5, 5));
    click(input, at(7, 5));
    editor.selectTool(Tool.select);
    click(input, at(5.5, 5.5));
    // Radius 2: the right edge pulled 2 m out makes the 4 m box 6 m wide,
    // and the height follows.
    drag(input, at(7 + pad, 5), at(9 + pad, 5));
    final geometry = editor.document.geometryOf(layer);
    final circle = geometry.circles.values.single;
    expect(circle.radius, closeTo(3, 1e-9));
    expect(geometry.points[circle.center], const Vec(6, 5));
  });

  test('dragging outside a corner rotates about the box centre', () {
    final (editor, input, layer) = selectedRectangle();
    final before = editor.document.geometryOf(layer).region!.area;
    // From beyond the top-right corner, turn a quarter turn clockwise on
    // screen: the pointer moves from up-right of the centre to down-right.
    final start = at(6 + pad, 2 - pad) + const Offset(8, -8);
    final centre = at(4, 3);
    final d = start - centre;
    final end = centre + Offset(-d.dy, d.dx);
    input.hover(start);
    input.press(start, shift: false);
    input.move(start + const Offset(0, 6));
    input.move(end);
    final preview = editor.preview! as MovePreview;
    expect(preview.box!.angle, closeTo(math.pi / 2, 1e-9));
    input.release(end);

    final box = selectionBoxOf(editor)!;
    expect(box.width, closeTo(2, 1e-9), reason: 'now tall, not wide');
    expect(box.height, closeTo(4, 1e-9));
    expect(box.centre.x, closeTo(4, 1e-9));
    expect(box.centre.y, closeTo(3, 1e-9));
    expect(
      editor.document.geometryOf(layer).region!.area,
      closeTo(before, 1e-9),
    );
    expect(editor.undoLabel, 'Rotate');
  });

  test('Shift turns in 15° steps', () {
    final (editor, input, _) = selectedRectangle();
    final start = at(6 + pad, 2 - pad) + const Offset(8, -8);
    final centre = at(4, 3);
    final d = start - centre;
    final turn = 0.3; // about 17°
    final end =
        centre +
        Offset(
          d.dx * math.cos(turn) - d.dy * math.sin(turn),
          d.dx * math.sin(turn) + d.dy * math.cos(turn),
        );
    input.hover(start);
    input.press(start, shift: false);
    input.move(end, shift: true);
    final preview = editor.preview! as MovePreview;
    expect(preview.box!.angle, closeTo(math.pi / 12, 1e-9));
    input.cancel();
  });

  test('rotating a property carries the zone inside it', () {
    final (editor, input, property) = selectedRectangle();
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    editor.selectTool(Tool.polygon);
    editor.selectFunction(ToolFunction.rectangle);
    click(input, at(2.5, 2.5));
    click(input, at(3.5, 3.5));
    editor.selectTool(Tool.select);
    // Pick the property by its edge-free inside, away from the zone.
    click(input, at(5, 3));
    expect(editor.selectedLayerId, property);
    final start = at(6 + pad, 2 - pad) + const Offset(8, -8);
    final centre = at(4, 3);
    final d = start - centre;
    final end = centre - d; // half a turn
    input.hover(start);
    input.press(start, shift: false);
    input.move(start + const Offset(0, 6));
    input.move(end);
    input.release(end);
    final zoneBox = editor.document.geometryOf(zone).region!.bounds;
    expect(zoneBox.$1.x, closeTo(4.5, 1e-9));
    expect(zoneBox.$1.y, closeTo(2.5, 1e-9));
    expect(editor.document.isActive(zone), isTrue);
  });

  test('a click on a handle is not an edit', () {
    final (editor, input, _) = selectedRectangle();
    final selected = editor.selection;
    final label = editor.undoLabel;
    click(input, at(4, 2 - pad));
    expect(editor.selection, selected);
    expect(editor.undoLabel, label);
  });

  test('a locked layer shows no box', () {
    final (editor, _, layer) = selectedRectangle();
    editor.setLayerLocked(layer, true);
    expect(selectionBoxOf(editor), isNull);
  });

  test('Select has no status-bar sentence', () {
    final (editor, _, _) = selectedRectangle();
    expect(toolPrompt(editor), isEmpty);
  });
}
