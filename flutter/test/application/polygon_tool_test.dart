import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tool_prompts.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/polygon_shapes.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

Offset at(double x, double y) => Offset(x * pixelsPerMetre, y * pixelsPerMetre);

void click(CanvasInput input, double x, double y) {
  final screen = at(x, y);
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

(EditorController, CanvasInput, String) property() {
  final editor = EditorController()..addLayer(LayerKind.property);
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor), editor.selectedLayerId!);
}

void main() {
  group('corner maths', () {
    test('a regular polygon puts its first corner on the second click', () {
      final corners = regularPolygonCorners(
        const Vec(5, 5),
        const Vec(9, 5),
        6,
      )!;
      expect(corners, hasLength(6));
      expect(corners.first, const Vec(9, 5));
      for (final c in corners) {
        expect(c.distanceTo(const Vec(5, 5)), closeTo(4, 1e-12));
      }
    });

    test('a rectangle uses the two clicks as opposite corners', () {
      expect(rectangleCorners(const Vec(1, 2), const Vec(4, 6)), const [
        Vec(1, 2),
        Vec(4, 2),
        Vec(4, 6),
        Vec(1, 6),
      ]);
    });

    test('clicks too close together make no shape', () {
      expect(regularPolygonCorners(Vec.zero, Vec.zero, 6), isNull);
      expect(rectangleCorners(const Vec(1, 1), const Vec(1, 5)), isNull);
    });
  });

  group('Polygon tool', () {
    test('Regular: first click is temporary, second adds a closed hexagon '
        'as one Undo step', () {
      final (editor, input, layer) = property();
      editor.selectTool(Tool.polygon);
      expect(editor.function, ToolFunction.regularPolygon);
      expect(toolPrompt(editor), contains('6-sided'));
      final before = editor.document;

      click(input, 5, 5);
      expect(identical(editor.document, before), isTrue);
      expect(editor.polygonStart, const Vec(5, 5));

      input.hover(at(9, 5));
      final preview = editor.preview as PolygonPreview;
      expect(preview.corners, hasLength(6));
      expect(preview.valid, isTrue);

      click(input, 9, 5);
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.points, hasLength(6));
      expect(geometry.lines, hasLength(6));
      expect(geometry.isClosed, isTrue);
      // A regular hexagon with circumradius r has area 3√3/2 · r².
      expect(geometry.region!.area, closeTo(3 * math.sqrt(3) / 2 * 16, 1e-9));
      expect(editor.polygonStart, isNull);
      expect(editor.document.isActive(layer), isTrue);
      expect(editor.selection, [geometry.boundaryId]);

      editor.undo();
      expect(editor.document.geometryOf(layer).points, isEmpty);
    });

    test('the number of sides is kept between uses and clamped', () {
      final (editor, input, layer) = property();
      editor.selectTool(Tool.polygon);
      editor.setPolygonSides(3);
      click(input, 5, 5);
      click(input, 9, 5);
      expect(editor.document.geometryOf(layer).lines, hasLength(3));

      editor.setPolygonSides(1);
      expect(editor.polygonSides, EditorController.minPolygonSides);
      editor.setPolygonSides(99);
      expect(editor.polygonSides, EditorController.maxPolygonSides);
    });

    test('Rectangle: two opposite corners', () {
      final (editor, input, layer) = property();
      editor.selectTool(Tool.polygon);
      editor.selectFunction(ToolFunction.rectangle);
      click(input, 1, 2);
      click(input, 5, 5);
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.points, hasLength(4));
      expect(geometry.isClosed, isTrue);
      expect(geometry.region!.area, closeTo(12, 1e-12));
      expect(editor.undoLabel, 'Draw rectangle');
    });

    test('a second polygon on the layer adds land and can cut the first', () {
      final (editor, input, layer) = property();
      editor.selectTool(Tool.polygon);
      editor.selectFunction(ToolFunction.rectangle);
      click(input, 0, 0);
      click(input, 10, 10);
      final boundary = editor.document.geometryOf(layer).boundaryId;
      click(input, 2, 2);
      click(input, 4, 4);
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.boundaryId, boundary);
      expect(geometry.stack, hasLength(2));
      expect(
        editor.document.problemOf(layer),
        contains('overlaps'),
        reason: 'overlapping shapes must be combined',
      );

      editor.selectItem(boundary);
      editor.selectItem(geometry.stack.last, toggle: true);
      editor.runBoolean(BooleanOperation.subtract);
      expect(editor.document.geometryOf(layer).region!.area, closeTo(96, 1e-9));
    });

    for (final cancel in ['escape', 'tool', 'function', 'undo']) {
      test('$cancel forgets the first Polygon click', () {
        final (editor, input, layer) = property();
        editor.selectTool(Tool.polygon);
        click(input, 5, 5);
        expect(editor.polygonStart, isNotNull);
        switch (cancel) {
          case 'escape':
            editor.escape();
          case 'tool':
            editor.selectTool(Tool.line);
          case 'function':
            editor.selectFunction(ToolFunction.rectangle);
          case 'undo':
            editor.undo();
        }
        expect(editor.polygonStart, isNull);
        // Undo with nothing drawn removes the new property itself.
        if (editor.document.layers.containsKey(layer)) {
          expect(editor.document.geometryOf(layer).points, isEmpty);
        }
      });
    }

    test('a locked layer refuses the first click', () {
      final (editor, input, layer) = property();
      editor.setLayerLocked(layer, true);
      editor.selectTool(Tool.polygon);
      click(input, 5, 5);
      expect(editor.polygonStart, isNull);
      expect(editor.notice, contains('locked'));
    });
  });
}
