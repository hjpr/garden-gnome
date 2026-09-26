import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/drafts.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import '../support/first_shape.dart';

/// At 100% zoom with the camera at the origin, one metre is 30 pixels.
Offset at(double x, double y) => Offset(x * 30, y * 30);

void click(CanvasInput input, Offset where, {bool shift = false}) {
  input.hover(where);
  input.press(where, shift: shift);
  input.release(where);
}

void drag(CanvasInput input, Offset from, Offset to) {
  input.press(from, shift: false);
  input.move(from + const Offset(5, 0));
  input.move(to);
  input.release(to);
}

/// Draws a closed loop with Line → Draw on the selected layer.
void drawLoop(CanvasInput input, List<Offset> corners) {
  final editor = input.editor;
  editor.selectTool(Tool.line);
  editor.selectFunction(ToolFunction.draw);
  for (final corner in corners) {
    click(input, corner);
  }
  click(input, corners.first);
}

(EditorController, CanvasInput) newEditor() {
  final editor = EditorController();
  return (editor, CanvasInput(editor));
}

void main() {
  test('W01: drawing a field boundary closes it and makes it active', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final field = editor.selectedLayerId!;
    expect(editor.selectedLayer!.name, 'Field 1');
    expect(editor.propertiesOpen, isTrue);
    expect(editor.tool, Tool.select, reason: 'Select is the starting tool');

    drawLoop(input, [at(1, 1), at(11, 1), at(11, 11), at(1, 11)]);
    final geometry = editor.document.geometryOf(field);
    expect(geometry.points, hasLength(4));
    expect(geometry.lines, hasLength(4));
    expect(editor.document.isActive(field), isTrue);
    expect(editor.lineAnchor, isNull, reason: 'closing ends the drawing');
    expect(editor.addLayerBlocker(LayerKind.plot), isNull);
  });

  test('each Draw click is its own undo step and Undo resumes the preview', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    editor.selectTool(Tool.line);
    click(input, at(1, 1));
    click(input, at(5, 1));
    click(input, at(5, 5));
    final layer = editor.selectedLayerId!;
    expect(editor.document.geometryOf(layer).lines, hasLength(2));

    editor.undo();
    expect(editor.document.geometryOf(layer).lines, hasLength(1));
    expect(editor.lineAnchor, 'point-2', reason: 'preview resumes from B');

    editor.redo();
    expect(editor.document.geometryOf(layer).lines, hasLength(2));
    expect(editor.lineAnchor, 'point-3');

    editor.selectTool(Tool.point);
    editor.selectTool(Tool.line);
    editor.undo();
    expect(
      editor.lineAnchor,
      isNull,
      reason: 'switching tools ends the operation',
    );
  });

  test('Undo never lets an ID number be issued again', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    editor.selectTool(Tool.point);
    editor.selectFunction(ToolFunction.place);
    click(input, at(1, 1));
    editor.undo();
    click(input, at(2, 2));
    final points = editor.document.geometryOf(editor.selectedLayerId!).points;
    expect(points.keys, ['point-2']);
  });

  test('a crossing line is placed and the layer is marked invalid', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final layer = editor.selectedLayerId!;
    editor.selectTool(Tool.line);
    click(input, at(0, 0));
    click(input, at(10, 10));
    editor.cancelOperation();

    click(input, at(0, 10));
    click(input, at(10, 0));
    expect(editor.document.geometryOf(layer).lines, hasLength(2));
    expect(editor.document.isValid(layer), isFalse);
    expect(editor.notice, contains('Field 1 is invalid'));
    expect(editor.lineAnchor, 'point-4', reason: 'the drawing can continue');

    editor.undo();
    // No broken rule remains; the open line is still unfinished drawing.
    expect(editor.document.ruleProblemOf(layer), isNull);
    expect(editor.document.isValid(layer), isFalse);
  });

  test('a point cannot join a third line; that is still refused', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    editor.selectTool(Tool.line);
    click(input, at(0, 0));
    click(input, at(5, 0));
    click(input, at(5, 5));
    editor.cancelOperation();
    editor.selectFunction(ToolFunction.join);
    final before = editor.document;
    click(input, at(5, 0));
    click(input, at(0, 5));
    expect(identical(editor.document, before), isTrue);
  });

  test(
    'Join chains from the point just joined until Esc or the loop closes',
    () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      editor.selectTool(Tool.point);
      for (final p in [at(0, 0), at(5, 0), at(5, 5), at(0, 5)]) {
        click(input, p);
      }
      editor.selectTool(Tool.line);
      editor.selectFunction(ToolFunction.join);
      final ids = editor.document.geometryOf(field).points.keys.toList();

      click(input, at(0, 0));
      click(input, at(5, 0));
      expect(editor.joinStart, ids[1], reason: 'the next join starts here');
      click(input, at(5, 5));
      click(input, at(0, 5));
      click(input, at(0, 0));
      final geometry = editor.document.geometryOf(field);
      expect(geometry.lines, hasLength(4));
      expect(geometry.isClosed, isTrue);
      expect(
        editor.joinStart,
        isNull,
        reason: 'a closed loop has no open point left to carry on from',
      );

      // Esc ends a chain early, keeping the lines already joined.
      editor.selectTool(Tool.point);
      click(input, at(8, 0));
      click(input, at(8, 5));
      click(input, at(8, 8));
      editor.selectTool(Tool.line);
      editor.selectFunction(ToolFunction.join);
      click(input, at(8, 0));
      click(input, at(8, 5));
      expect(editor.joinStart, isNotNull);
      editor.escape();
      expect(editor.joinStart, isNull);
      click(input, at(8, 8));
      expect(editor.joinStart, isNotNull, reason: 'a fresh first click');
      expect(editor.document.geometryOf(field).lines, hasLength(5));
    },
  );

  test('W02: plots must stay inside their field and need a complete field', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final field = editor.selectedLayerId!;
    expect(
      editor.addLayerBlocker(LayerKind.plot),
      'complete field before adding new plot',
    );

    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.addLayer(LayerKind.plot);
    final plot = editor.selectedLayerId!;
    expect(editor.document.layers[plot]!.parentId, field);

    editor.selectTool(Tool.line);
    editor.selectFunction(ToolFunction.draw);
    click(input, at(2, 2));
    click(input, at(14, 2));
    expect(editor.document.geometryOf(plot).lines, hasLength(1));
    expect(editor.document.problemOf(plot), contains('not inside a field'));
    expect(editor.notice, contains('Plot 1 is invalid'));
  });

  test('moving a point commits on release, even into an invalid shape', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final layer = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.selectTool(Tool.select);

    drag(input, at(10, 10), at(12, 12));
    expect(
      editor.document.geometryOf(layer).points['point-3']!.x,
      closeTo(12, 1e-9),
    );

    drag(input, at(12, 12), at(-5, 5));
    expect(
      editor.document.geometryOf(layer).points['point-3']!.x,
      closeTo(-5, 1e-9),
    );
    expect(
      editor.document.isValid(layer),
      isFalse,
      reason: 'self-crossing is kept, but flagged',
    );
    expect(editor.preview, isNull);
  });

  test('group move shifts shared points once', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final layer = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.selectTool(Tool.select);
    click(input, at(5, 0));
    click(input, at(10, 5), shift: true);
    expect(editor.selection, hasLength(2));
    drag(input, at(5, 0), at(6, 0));
    final points = editor.document.geometryOf(layer).points;
    expect(points['point-2']!.x, closeTo(11, 1e-9));
    expect(points['point-1']!.x, closeTo(1, 1e-9));
  });

  test(
    'Point → Place on a line splits it; Undo restores the original line',
    () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final layer = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.selectTool(Tool.point);
      editor.selectFunction(ToolFunction.place);
      click(input, at(5, 0.1));
      var geometry = editor.document.geometryOf(layer);
      expect(geometry.lines.containsKey('line-1'), isFalse);
      expect(geometry.boundaryCorners, hasLength(5));
      expect(geometry.points['point-5']!.y, closeTo(0, 1e-9));
      editor.undo();
      geometry = editor.document.geometryOf(layer);
      expect(geometry.lines.containsKey('line-1'), isTrue);
    },
  );

  test('deleting a field boundary line deactivates its plots', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final field = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.addLayer(LayerKind.plot);
    final plot = editor.selectedLayerId!;
    drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);
    expect(editor.document.isActive(plot), isTrue);

    editor.selectLayer(field);
    editor.selectFunction(ToolFunction.delete);
    click(input, at(5, 0));
    expect(editor.document.isActive(field), isFalse);
    expect(editor.document.isActive(plot), isFalse);
  });

  test('deleting a layer removes its subtree in one undoable step', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.field);
    final field = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.addLayer(LayerKind.plot);
    editor.deleteLayer(field);
    expect(editor.document.layers, isEmpty);
    expect(editor.selectedLayerId, isNull);
    editor.undo();
    expect(editor.document.layers, hasLength(2));
  });

  test('undoing back to the saved drawing clears the unsaved marker', () {
    final (editor, _) = newEditor();
    editor.addLayer(LayerKind.field);
    editor.markSaved(editor.document);
    expect(editor.isDirty, isFalse);
    editor.renameLayer(editor.selectedLayerId!, 'North');
    expect(editor.isDirty, isTrue);
    editor.undo();
    expect(editor.isDirty, isFalse);
  });

  group('Select tool', () {
    /// A field with a plot inside it, and an area inside the plot.
    (EditorController, CanvasInput, String, String, String) nested() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(20, 0), at(20, 20), at(0, 20)]);
      editor.addLayer(LayerKind.plot);
      final plot = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(12, 2), at(12, 12), at(2, 12)]);
      editor.addLayer(LayerKind.area);
      final area = editor.selectedLayerId!;
      drawLoop(input, [at(4, 4), at(8, 4), at(8, 8), at(4, 8)]);
      editor.selectTool(Tool.select);
      return (editor, input, field, plot, area);
    }

    test('it is the first tool and has a black arrow icon', () {
      expect(Tool.values.first, Tool.select);
      expect(Tool.select.icon, 'select.svg');
      expect(Tool.select.hasFunctionChoice, isFalse);
    });

    test('clicking nested land picks the innermost piece', () {
      final (editor, input, field, plot, area) = nested();
      click(input, at(6, 6));
      expect(editor.selectedLayerId, area);
      click(input, at(10, 10));
      expect(editor.selectedLayerId, plot);
      click(input, at(16, 16));
      expect(editor.selectedLayerId, field);
      expect(
        editor.selection.single,
        editor.document.geometryOf(field).boundaryId,
        reason: 'the inside selects the whole shape',
      );
    });

    test('points beat lines, and lines beat insides, on any layer', () {
      final (editor, input, field, plot, _) = nested();
      click(input, at(20, 10));
      expect(editor.selectedLayerId, field);
      expect(
        editor.document
            .geometryOf(field)
            .lines
            .containsKey(editor.selection.single),
        isTrue,
      );
      click(input, at(2, 2));
      expect(editor.selectedLayerId, plot);
      expect(editor.selection.single, 'point-1');
    });

    test('clicking empty ground clears the selection', () {
      final (editor, input, _, _, _) = nested();
      click(input, at(6, 6));
      click(input, at(30, 30));
      expect(editor.selection, isEmpty);
    });

    test('dragging a point, a line, or a whole shape moves it', () {
      final (editor, input, _, plot, area) = nested();
      drag(input, at(12, 12), at(13, 13));
      expect(
        editor.document.geometryOf(plot).points['point-3']!.x,
        closeTo(13, 1e-9),
      );

      drag(input, at(12.5, 7), at(14.5, 7));
      final points = editor.document.geometryOf(plot).points;
      expect(
        points['point-2']!.x,
        closeTo(14, 1e-9),
        reason: 'the right edge moved',
      );
      expect(
        points['point-1']!.x,
        closeTo(2, 1e-9),
        reason: 'the left edge stayed',
      );

      final areaBefore = editor.document.geometryOf(area).points['point-1']!;
      drag(input, at(10, 3), at(11, 4));
      expect(editor.selectedLayerId, plot);
      expect(
        editor.document.geometryOf(plot).points['point-1']!.x,
        closeTo(3, 1e-9),
      );
      expect(
        editor.document.geometryOf(area).points['point-1']!.x,
        closeTo(areaBefore.x + 1, 1e-9),
        reason: 'land inside a moved shape moves with it',
      );
      expect(editor.document.isActive(area), isTrue);
    });

    test('a plot moved out of its field is kept but marked inactive', () {
      final (editor, input, _, plot, area) = nested();
      drag(input, at(10, 10), at(30, 10));
      expect(
        editor.document.geometryOf(plot).points['point-1']!.x,
        closeTo(22, 1e-9),
      );
      expect(editor.document.problemOf(plot), contains('not inside a field'));
      expect(editor.document.isActive(plot), isFalse);
      expect(
        editor.document.isActive(area),
        isFalse,
        reason: 'its area goes with it',
      );
      expect(editor.notice, contains('Plot 1 is invalid'));

      drag(input, at(30, 10), at(10, 10));
      expect(
        editor.document.isActive(plot),
        isTrue,
        reason: 'moving it back fixes it',
      );
    });

    test('holding still lists everything underneath, innermost first', () {
      final (editor, input, field, plot, area) = nested();
      input.press(at(6, 6), shift: false);
      final choices = input.takeHoldChoices();
      expect(choices.map((c) => c.layerId), [area, plot, field]);
      expect(choices.every((c) => c.kind == HitKind.interior), isTrue);
      expect(input.describe(choices[1]), 'Plot 1 · Whole shape');

      input.choose(choices.last);
      expect(editor.selectedLayerId, field);
      input.release(at(6, 6));
      expect(
        editor.selectedLayerId,
        field,
        reason: 'the held press does not also click',
      );
    });

    test('a press that became a drag offers no list', () {
      final (_, input, _, _, _) = nested();
      input.press(at(6, 6), shift: false);
      input.move(at(9, 9));
      expect(input.takeHoldChoices(), isEmpty);
      input.release(at(9, 9));
    });
  });

  group('property drafts', () {
    PropertyDraft groundDraft(
      EditorController editor,
      String layerId,
      String text,
    ) => PropertyDraft(
      layerId: layerId,
      text: text,
      committedText: '',
      check: (t) => t.contains('!') ? 'No exclamation marks' : null,
      apply: (t) {
        final p = editor.document.layers[layerId]!.properties as PlotProperties;
        editor.updateProperties(layerId, p.copyWith(ground: () => t));
      },
    );

    (EditorController, String, String) twoPlots() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      final field = editor.selectedLayerId!;
      editor.addLayer(LayerKind.plot);
      final first = editor.selectedLayerId!;
      editor.selectLayer(field);
      editor.addLayer(LayerKind.plot);
      return (editor, first, editor.selectedLayerId!);
    }

    test('unapplied text disables drawing Undo', () {
      final (editor, first, _) = twoPlots();
      expect(editor.canUndo, isTrue);
      editor.drafts.update('ground', groundDraft(editor, first, 'beds'));
      expect(editor.canUndo, isFalse);
    });

    test(
      'switching layers applies valid text to the layer it was typed for',
      () {
        final (editor, first, second) = twoPlots();
        editor.selectLayer(first);
        editor.drafts.update('ground', groundDraft(editor, first, 'beds'));
        editor.selectLayer(second);
        String? ground(String id) =>
            (editor.document.layers[id]!.properties as PlotProperties).ground;
        expect(ground(first), 'beds');
        expect(ground(second), isNull);
      },
    );

    test('Save waits for invalid text and changes nothing', () {
      final (editor, first, _) = twoPlots();
      editor.drafts.update('ground', groundDraft(editor, first, 'beds!'));
      final before = editor.document;
      expect(editor.drafts.settleForSave(), isNotNull);
      expect(identical(editor.document, before), isTrue);
      expect(editor.drafts['ground'], isNotNull);
    });
  });

  test('Point and Line have no Move function; Select moves things', () {
    expect(Tool.point.functions, [ToolFunction.place, ToolFunction.delete]);
    expect(Tool.line.functions, [
      ToolFunction.draw,
      ToolFunction.join,
      ToolFunction.delete,
    ]);
    expect(Tool.circle.functions, [
      ToolFunction.centerCircle,
      ToolFunction.twoPointCircle,
    ]);
  });

  group('Circle tool', () {
    test('center circle: click the centre, then the edge', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(10, 10));
      expect(
        editor.document.geometryOf(field).points,
        isEmpty,
        reason: 'the first click is not added to the drawing',
      );
      expect(editor.circleStart, isNotNull);
      click(input, at(14, 10));

      final geometry = editor.document.geometryOf(field);
      final circle = geometry.circles.values.single;
      expect(circle.radius, closeTo(4, 1e-9));
      expect(geometry.points[circle.center]!.x, closeTo(10, 1e-9));
      expect(geometry.boundaryId, circle.id);
      expect(editor.document.isActive(field), isTrue);
      expect(editor.selection, {circle.id});

      editor.undo();
      expect(
        editor.document.geometryOf(field).points,
        isEmpty,
        reason: 'circle and centre are one undo step',
      );
    });

    test('2-point circle: the clicks are opposite sides', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      editor.selectFunction(ToolFunction.twoPointCircle);
      click(input, at(2, 5));
      click(input, at(12, 5));
      final geometry = editor.document.geometryOf(field);
      final circle = geometry.circles.values.single;
      expect(circle.radius, closeTo(5, 1e-9));
      expect(geometry.points[circle.center]!.x, closeTo(7, 1e-9));
      expect(geometry.points, hasLength(1), reason: 'only the centre is kept');
    });

    test('Esc forgets the first click', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      editor.selectTool(Tool.circle);
      click(input, at(10, 10));
      editor.escape();
      expect(editor.circleStart, isNull);
    });

    test('a further closed shape joins the layer on top of the stack', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      final boundaryId = editor.document.geometryOf(field).boundaryId;
      editor.selectTool(Tool.circle);
      final before = editor.document;
      click(input, at(20, 20));
      expect(editor.circleStart, isNotNull);
      expect(identical(editor.document, before), isTrue);
      click(input, at(22, 20));
      final geometry = editor.document.geometryOf(field);
      expect(geometry.circles, hasLength(1));
      expect(geometry.boundaryId, boundaryId);
      expect(geometry.stack.last, geometry.circles.keys.single);
      expect(geometry.area, closeTo(100 + 4 * 3.141592653589793, 1e-6));
      expect(editor.notice, isNull);
      editor.undo();
      expect(editor.document.geometryOf(field).circles, isEmpty);
    });

    test('a circular plot is checked against its field', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.plot);
      final plot = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(5, 5));
      click(input, at(8, 5));
      expect(editor.document.isActive(plot), isTrue);

      editor.selectTool(Tool.select);
      drag(input, at(8, 5), at(12, 5));
      final circle = editor.document.geometryOf(plot).circles.values.single;
      expect(
        circle.radius,
        closeTo(7, 1e-9),
        reason: 'dragging the edge resizes',
      );
      expect(editor.document.problemOf(plot), contains('not inside a field'));

      editor.undo();
      drag(input, at(5, 6), at(4, 6));
      final moved = editor.document.geometryOf(plot);
      expect(
        moved.points[moved.circles.values.single.center]!.x,
        closeTo(4, 1e-9),
        reason: 'dragging the inside moves the circle',
      );
      expect(editor.document.isActive(plot), isTrue);
    });

    test('deleting the centre point deletes the circle', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(5, 5));
      click(input, at(8, 5));
      editor.selectTool(Tool.point);
      editor.selectFunction(ToolFunction.delete);
      click(input, at(5, 5));
      final geometry = editor.document.geometryOf(field);
      expect(geometry.circles, isEmpty);
      expect(geometry.boundaryId, isNull);
    });
  });

  group('locked layers', () {
    (EditorController, CanvasInput, String) lockedField() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.setLayerLocked(field, true);
      return (editor, input, field);
    }

    test('refuse drawing, moving, renaming, properties and delete', () {
      final (editor, input, field) = lockedField();
      final before = editor.document;

      editor.selectTool(Tool.point);
      click(input, at(5, 5));
      expect(editor.notice, contains('Field 1 is locked'));

      editor.selectTool(Tool.select);
      drag(input, at(10, 10), at(12, 12));
      drag(input, at(5, 5), at(6, 6));

      editor.renameLayer(field, 'Renamed');
      editor.updateProperties(
        field,
        const FieldProperties(color: OutlineColor.sage),
      );
      editor.deleteLayer(field);
      expect(identical(editor.document, before), isTrue);
      expect(editor.deleteLayerBlocker(field), isNotNull);
    });

    test('Select clicks pass through a locked layer', () {
      final (editor, input, _) = lockedField();
      editor.selectLayer(null);
      editor.selectTool(Tool.select);
      click(input, at(5, 5));
      expect(editor.selectedLayerId, isNull);
      expect(editor.preview, isNull);
    });

    test('a lock covers the layers inside and is undoable', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      final field = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.plot);
      final plot = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);

      editor.setLayerLocked(field, true);
      expect(editor.document.lockedBy(plot)?.id, field);
      expect(
        editor.lockNotice(plot),
        'Plot 1 is inside Field 1, which is locked',
      );
      expect(editor.addLayerBlocker(LayerKind.area), isNotNull);

      editor.undo();
      expect(editor.document.isLocked(plot), isFalse);
      expect(editor.addLayerBlocker(LayerKind.area), isNull);
    });

    test('a locked plot stops its field being moved as a whole', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.field);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.plot);
      final plot = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);
      editor.setLayerLocked(plot, true);

      final before = editor.document;
      editor.selectTool(Tool.select);
      drag(input, at(8, 8), at(9, 9));
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('Plot 1 is locked'));
    });
  });
}
