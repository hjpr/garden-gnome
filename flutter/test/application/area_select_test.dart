import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';

/// At 100% zoom with the camera at the origin, one metre is 30 pixels.
Offset at(double x, double y) => Offset(x * 30, y * 30);

void click(CanvasInput input, Offset where) {
  input.hover(where);
  input.press(where, shift: false);
  input.release(where);
}

/// Presses at the first position, moves through the rest, and lets go at
/// the last.
void dragThrough(CanvasInput input, List<Offset> path, {bool shift = false}) {
  input.hover(path.first);
  input.press(path.first, shift: shift);
  for (final p in path.skip(1)) {
    input.move(p);
  }
  input.release(path.last);
}

/// A field with two 2 × 2 m rectangles, at (2, 2)–(4, 4) and
/// (8, 2)–(10, 4), and the Select tool chosen.
(EditorController, CanvasInput, String) twoRectangles() {
  final editor = EditorController()..addLayer(LayerKind.field);
  addTearDown(editor.dispose);
  final input = CanvasInput(editor);
  final layer = editor.selectedLayerId!;
  editor.selectTool(Tool.polygon);
  editor.selectFunction(ToolFunction.rectangle);
  click(input, at(2, 2));
  click(input, at(4, 4));
  click(input, at(8, 2));
  click(input, at(10, 4));
  editor.selectTool(Tool.select);
  editor.selectItem(null);
  return (editor, input, layer);
}

Set<String> shapes(EditorController editor, String layer) =>
    editor.document.geometryOf(layer).shapes.keys.toSet();

void main() {
  test('Select offers Marquee then Lasso, and starts on Marquee', () {
    expect(Tool.select.functions, [ToolFunction.marquee, ToolFunction.lasso]);
    final editor = EditorController();
    addTearDown(editor.dispose);
    expect(editor.function, ToolFunction.marquee);
    editor.selectFunction(ToolFunction.lasso);
    editor.selectTool(Tool.line);
    editor.selectTool(Tool.select);
    expect(editor.function, ToolFunction.lasso);
  });

  test('a marquee selects a shape it only partly covers', () {
    final (editor, input, layer) = twoRectangles();
    final first = editor.document.geometryOf(layer).stack.first;
    // Covers only the top-left corner of the first rectangle.
    dragThrough(input, [at(0, 0), at(1, 1), at(3, 3)]);
    expect(editor.selection, {first});
    expect(editor.preview, isNot(isA<AreaSelectPreview>()));
  });

  test('a marquee over both shapes selects both, in any direction', () {
    final (editor, input, layer) = twoRectangles();
    dragThrough(input, [at(11, 5), at(10, 4), at(3, 3.5)]);
    expect(editor.selection, shapes(editor, layer));
  });

  test('a marquee drawn inside a shape without its edge selects it', () {
    final (editor, input, layer) = twoRectangles();
    // Starting inside a shape moves it, so start outside on the left and
    // stop inside, the edge crossed on the way.
    dragThrough(input, [at(1, 2.5), at(1.5, 3), at(3, 3.5)]);
    expect(editor.selection, {editor.document.geometryOf(layer).stack.first});
  });

  test('a marquee over empty ground clears the selection', () {
    final (editor, input, layer) = twoRectangles();
    editor.selectItems(layer, shapes(editor, layer));
    dragThrough(input, [at(5, 6), at(5.5, 7), at(7, 9)]);
    expect(editor.selection, isEmpty);
  });

  test('Shift adds a marquee to the selection', () {
    final (editor, input, layer) = twoRectangles();
    final [first, second] = editor.document.geometryOf(layer).stack;
    click(input, at(3, 3));
    expect(editor.selection, {first});
    dragThrough(input, [at(7, 1), at(8, 2), at(9, 3)], shift: true);
    expect(editor.selection, {first, second});
  });

  test('pressing on a shape still moves it rather than drawing a box', () {
    final (editor, input, layer) = twoRectangles();
    final before = editor.document;
    dragThrough(input, [at(3, 3), at(3.5, 3), at(4, 3)]);
    expect(editor.document, isNot(same(before)));
    expect(
      editor.document.geometryOf(layer).points.values.map((p) => p.x),
      contains(closeTo(3, 1e-9)),
    );
  });

  test('the marquee shows while dragging with what it would pick', () {
    final (editor, input, layer) = twoRectangles();
    input.hover(at(7, 1));
    input.press(at(7, 1), shift: false);
    input.move(at(7.5, 1.5));
    input.move(at(9, 3));
    final preview = editor.preview;
    expect(preview, isA<AreaSelectPreview>());
    preview as AreaSelectPreview;
    expect(preview.lasso, isFalse);
    expect(preview.outline, hasLength(4));
    expect(preview.layerId, layer);
    expect(preview.items, {editor.document.geometryOf(layer).stack.last});
    input.release(at(9, 3));
  });

  test('a lasso selects what its drawn loop touches', () {
    final (editor, input, layer) = twoRectangles();
    editor.selectFunction(ToolFunction.lasso);
    // A loop around the second rectangle only, well clear of the first.
    dragThrough(input, [at(7, 1), at(11, 1), at(11, 5), at(7, 5), at(7, 1.2)]);
    expect(editor.selection, {editor.document.geometryOf(layer).stack.last});
  });

  test('a lasso that only nicks a shape still selects it', () {
    final (editor, input, layer) = twoRectangles();
    editor.selectFunction(ToolFunction.lasso);
    // A thin loop crossing the first rectangle's right edge.
    dragThrough(input, [at(3.5, 0), at(3.8, 0), at(3.8, 6), at(3.5, 6)]);
    expect(editor.selection, {editor.document.geometryOf(layer).stack.first});
  });

  test('a marquee picks loose points and lines, not the corners of shapes', () {
    final editor = EditorController()..addLayer(LayerKind.field);
    addTearDown(editor.dispose);
    final input = CanvasInput(editor);
    final layer = editor.selectedLayerId!;
    editor.selectTool(Tool.point);
    click(input, at(2, 2));
    editor.selectTool(Tool.line);
    click(input, at(5, 2));
    click(input, at(7, 2));
    editor.escape();
    editor.selectTool(Tool.select);
    dragThrough(input, [at(1, 1), at(2, 1.5), at(6, 3)]);
    final geometry = editor.document.geometryOf(layer);
    expect(editor.selection, {
      geometry.points.entries.firstWhere((e) => e.value.x == 2).key,
      geometry.lines.keys.single,
    });
  });

  test('on nested land the innermost layer is picked', () {
    final (editor, input, field) = twoRectangles();
    editor.addLayer(LayerKind.plot);
    final plot = editor.selectedLayerId!;
    expect(plot, isNot(field));
    editor.selectTool(Tool.polygon);
    editor.selectFunction(ToolFunction.rectangle);
    click(input, at(2.5, 2.5));
    click(input, at(3.5, 3.5));
    editor.selectTool(Tool.select);
    editor.selectLayer(null);
    dragThrough(input, [at(0, 0), at(1, 1), at(3, 3)]);
    expect(editor.selectedLayerId, plot);
    expect(editor.selection, shapes(editor, plot));
    // With the field chosen first, the marquee picks from the field.
    editor.selectLayer(field);
    dragThrough(input, [at(0, 0), at(1, 1), at(3, 3)]);
    expect(editor.selectedLayerId, field);
    expect(editor.selection, {editor.document.geometryOf(field).stack.first});
  });
}
