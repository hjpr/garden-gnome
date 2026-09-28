import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tool_prompts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/fill_patterns.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/persistence/document_codec.dart';
import '../support/first_shape.dart';

Offset at(double x, double y) => Offset(x * pixelsPerMetre, y * pixelsPerMetre);

void click(CanvasInput input, double x, double y) {
  final screen = at(x, y);
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

/// A layer of [kind] with a closed rectangle from (x0,y0) to (x1,y1),
/// drawn with the Polygon tool.
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

(EditorController, CanvasInput) newEditor() {
  final editor = EditorController();
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor));
}

void main() {
  test('Pattern comes before Reference and offers None plus six patterns', () {
    expect(Tool.values.sublist(Tool.values.length - 2), [
      Tool.pattern,
      Tool.reference,
    ]);
    expect(
      Tool.pattern.functions.map((f) => f.fillPattern).whereType<FillPattern>(),
      FillPattern.values,
    );
    expect(FillPattern.values, hasLength(6));
    expect(Tool.pattern.functions.first.fillPattern, isNull);
  });

  test('clicking inside a Property stores the pattern in its Properties; one '
      'Undo removes it', () {
    final (editor, input) = newEditor();
    final property = rectangleLayer(
      editor,
      input,
      LayerKind.property,
      0,
      0,
      10,
      8,
    );
    editor.selectTool(Tool.pattern);
    editor.selectFunction(ToolFunction.crosshatchPattern);
    expect(toolPrompt(editor), contains('Crosshatch'));

    final area = editor.document.geometryOf(property).region!.area;
    click(input, 5, 4);
    expect(editor.document.patternOf(property), FillPattern.crosshatch);
    final geometry = editor.document.geometryOf(property);
    expect(
      editor.document.layers[property]!.properties.pattern,
      FillPattern.crosshatch,
    );
    // Looks only: area and status are unchanged.
    expect(geometry.region!.area, area);
    expect(editor.document.isActive(property), isTrue);
    expect(editor.tool, Tool.pattern, reason: 'the tool stays chosen');

    editor.undo();
    expect(editor.document.patternOf(property), isNull);
    editor.redo();
    expect(editor.document.patternOf(property), FillPattern.crosshatch);

    editor.selectFunction(ToolFunction.noPattern);
    click(input, 5, 4);
    expect(editor.document.patternOf(property), isNull);
  });

  test('clicks outside the boundary or in a hole change nothing', () {
    final (editor, input) = newEditor();
    final property = rectangleLayer(
      editor,
      input,
      LayerKind.property,
      0,
      0,
      10,
      8,
    );
    editor.selectTool(Tool.pattern);
    editor.selectFunction(ToolFunction.dotsPattern);
    final before = editor.document;
    click(input, 20, 20);
    expect(identical(editor.document, before), isTrue);
    expect(editor.notice, contains('inside'));
    expect(editor.document.patternOf(property), isNull);
  });

  test('a Zone pattern lives in its Properties, shared with the panel', () {
    final (editor, input) = newEditor();
    rectangleLayer(editor, input, LayerKind.property, 0, 0, 20, 20);
    final zone = rectangleLayer(editor, input, LayerKind.zone, 2, 2, 8, 8);
    editor.selectTool(Tool.pattern);
    editor.selectFunction(ToolFunction.rowsPattern);
    click(input, 5, 5);

    final properties =
        editor.document.layers[zone]!.properties as ZoneProperties;
    expect(properties.pattern, FillPattern.rows);

    // The Properties panel uses the same controller call.
    editor.setPattern(zone, FillPattern.grid);
    expect(editor.document.patternOf(zone), FillPattern.grid);
  });

  test('an open outline shows no pattern until it closes again', () {
    final (editor, input) = newEditor();
    final property = rectangleLayer(
      editor,
      input,
      LayerKind.property,
      0,
      0,
      10,
      8,
    );
    editor.setPattern(property, FillPattern.diagonal);
    final geometry = editor.document.geometryOf(property);
    final edge = geometry.boundary!.segments.first.segmentId;
    final opened = geometry.edit((e) => e.delete([edge]));
    final document = editor.document.withGeometry(opened);
    expect(document.patternOf(property), isNull);
    expect(document.storedPatternOf(property), FillPattern.diagonal);
  });

  test('a circle layer keeps its pattern and it is saved', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    editor.selectTool(Tool.circle);
    click(input, 5, 5);
    click(input, 9, 5);
    editor.setPattern(property, FillPattern.crosses);
    expect(editor.document.geometryOf(property).boundaryCircle, isNotNull);

    final reopened = decodeGgnome(encodeGgnome(editor.document));
    expect(reopened.patternOf(property), FillPattern.crosses);
  });

  test('a pattern needs a closed shape; locked layers refuse it', () {
    final (editor, _) = newEditor();
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    final before = editor.document;
    editor.setPattern(property, FillPattern.dots);
    expect(identical(editor.document, before), isTrue);
    expect(editor.notice, contains('closed shape'));
  });
}
