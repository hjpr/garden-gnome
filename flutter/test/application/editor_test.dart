import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/drafts.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

/// With the camera at its starting height over the origin, one metre is 30
/// pixels.
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
  test('W01: drawing a property boundary closes it and makes it active', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    expect(editor.selectedLayer!.name, 'Property 1');
    expect(editor.propertiesOpen, isTrue);
    expect(editor.tool, Tool.select, reason: 'Select is the starting tool');

    drawLoop(input, [at(1, 1), at(11, 1), at(11, 11), at(1, 11)]);
    final geometry = editor.document.geometryOf(property);
    expect(geometry.points, hasLength(4));
    expect(geometry.lines, hasLength(4));
    expect(editor.document.isActive(property), isTrue);
    expect(editor.lineAnchor, isNull, reason: 'closing ends the drawing');
    expect(editor.addLayerBlocker(LayerKind.zone), isNull);
  });

  test('each Draw click is its own undo step and Undo resumes the preview', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
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
    editor.addLayer(LayerKind.property);
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
    editor.addLayer(LayerKind.property);
    final layer = editor.selectedLayerId!;
    editor.selectTool(Tool.line);
    click(input, at(0, 0));
    click(input, at(10, 10));
    editor.cancelOperation();

    click(input, at(0, 10));
    click(input, at(10, 0));
    expect(editor.document.geometryOf(layer).lines, hasLength(2));
    expect(editor.document.isValid(layer), isFalse);
    expect(editor.notice, contains('Property 1 is invalid'));
    expect(editor.lineAnchor, 'point-4', reason: 'the drawing can continue');

    editor.undo();
    // No broken rule remains; the open line is still unfinished drawing.
    expect(editor.document.ruleProblemOf(layer), isNull);
    expect(editor.document.isValid(layer), isFalse);
  });

  test('a point cannot join a third line; that is still refused', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
    editor.selectTool(Tool.line);
    click(input, at(0, 0));
    click(input, at(5, 0));
    click(input, at(5, 5));
    editor.cancelOperation();
    final before = editor.document;
    click(input, at(5, 0));
    expect(identical(editor.document, before), isTrue);
  });

  test(
    'Straight joins existing points in a run until Esc or the loop closes',
    () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      editor.selectTool(Tool.point);
      for (final p in [at(0, 0), at(5, 0), at(5, 5), at(0, 5)]) {
        click(input, p);
      }
      editor.selectTool(Tool.line);
      final ids = editor.document.geometryOf(property).points.keys.toList();

      click(input, at(0, 0));
      click(input, at(5, 0));
      expect(editor.lineAnchor, ids[1], reason: 'the next line starts here');
      click(input, at(5, 5));
      click(input, at(0, 5));
      click(input, at(0, 0));
      final geometry = editor.document.geometryOf(property);
      expect(geometry.points, hasLength(4), reason: 'no new points');
      expect(geometry.lines, hasLength(4));
      expect(geometry.isClosed, isTrue);
      expect(
        editor.lineAnchor,
        isNull,
        reason: 'a closed loop has no open point left to carry on from',
      );

      // Esc ends a run early, keeping the lines already drawn.
      editor.selectTool(Tool.point);
      click(input, at(8, 0));
      click(input, at(8, 5));
      click(input, at(8, 8));
      editor.selectTool(Tool.line);
      click(input, at(8, 0));
      click(input, at(8, 5));
      expect(editor.lineAnchor, isNotNull);
      editor.escape();
      expect(editor.lineAnchor, isNull);
      expect(editor.document.geometryOf(property).lines, hasLength(5));
    },
  );

  test('W02: zones stay inside their property and may overlap and touch', () {
    final (editor, input) = newEditor();
    expect(
      editor.addLayerBlocker(LayerKind.zone),
      'Select a property to add a zone',
    );
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    expect(
      editor.addLayerBlocker(LayerKind.zone),
      'Complete Property 1 before adding a zone',
    );
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    expect(editor.addLayerBlocker(LayerKind.zone), isNull);

    editor.addLayer(LayerKind.zone);
    final beds = editor.selectedLayerId!;
    expect(editor.document.layers[beds]!.parentId, property);
    // With a zone selected, a new zone goes under the same property.
    editor.addLayer(LayerKind.zone);
    final orchard = editor.selectedLayerId!;
    expect(editor.document.layers[orchard]!.name, 'Zone 2');
    expect(editor.document.layers[orchard]!.parentId, property);
    expect(editor.document.layers[property]!.children, [beds, orchard]);

    editor.selectLayer(beds);
    drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);
    // A second shape across the first, and a third starting on its corner
    // and resting on the property line.
    drawLoop(input, [at(4, 4), at(8, 4), at(8, 8), at(4, 8)]);
    drawLoop(input, [at(6, 2), at(10, 1), at(10, 3)]);
    final geometry = editor.document.geometryOf(beds);
    expect(geometry.stack, hasLength(3));
    expect(geometry.lines, hasLength(11));
    expect(editor.document.problemOf(beds), isNull);
    expect(editor.document.isActive(beds), isTrue);
    expect(editor.notice, isNull);

    editor.selectLayer(orchard);
    drawLoop(input, [at(1, 1), at(7, 1), at(7, 7), at(1, 7)]);
    expect(editor.document.problemOf(orchard), isNull);
    expect(editor.document.problemOf(property), isNull);

    // A stroke past the property line is kept but flagged at once.
    editor.selectTool(Tool.line);
    click(input, at(8, 8));
    click(input, at(14, 8));
    expect(
      editor.document.problemOf(orchard),
      'Drawing is not inside Property 1',
    );
    expect(editor.notice, contains('Zone 2 is invalid'));

    // A property's shapes still may not touch: the corner is refused.
    editor.selectLayer(property);
    editor.selectTool(Tool.line);
    click(input, at(10, 10));
    expect(editor.notice, CanvasInput.tooClose);
  });

  test('moving a point commits on release, even into an invalid shape', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
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
    editor.addLayer(LayerKind.property);
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
      editor.addLayer(LayerKind.property);
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

  test('deleting a property boundary line deactivates its zones', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);
    expect(editor.document.isActive(zone), isTrue);

    editor.selectLayer(property);
    editor.selectTool(Tool.select);
    click(input, at(5, 0));
    editor.deleteSelection();
    expect(editor.document.isActive(property), isFalse);
    expect(editor.document.isActive(zone), isFalse);
  });

  test('deleting a layer removes its subtree in one undoable step', () {
    final (editor, input) = newEditor();
    editor.addLayer(LayerKind.property);
    final property = editor.selectedLayerId!;
    drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
    editor.addLayer(LayerKind.zone);
    editor.deleteLayer(property);
    expect(editor.document.layers, isEmpty);
    expect(editor.selectedLayerId, isNull);
    editor.undo();
    expect(editor.document.layers, hasLength(2));
  });

  test('undoing back to the saved drawing clears the unsaved marker', () {
    final (editor, _) = newEditor();
    editor.addLayer(LayerKind.property);
    editor.markSaved(editor.document);
    expect(editor.isDirty, isFalse);
    editor.renameLayer(editor.selectedLayerId!, 'North');
    expect(editor.isDirty, isTrue);
    editor.undo();
    expect(editor.isDirty, isFalse);
  });

  group('Select tool', () {
    /// A property with a zone inside it, and a second zone drawn over
    /// the first.
    (EditorController, CanvasInput, String, String, String) stacked() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(20, 0), at(20, 20), at(0, 20)]);
      editor.addLayer(LayerKind.zone);
      final zone = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(12, 2), at(12, 12), at(2, 12)]);
      editor.addLayer(LayerKind.zone);
      final inner = editor.selectedLayerId!;
      drawLoop(input, [at(4, 4), at(8, 4), at(8, 8), at(4, 8)]);
      editor.selectTool(Tool.select);
      return (editor, input, property, zone, inner);
    }

    test('it is the first tool and has a black arrow icon', () {
      expect(Tool.values.first, Tool.select);
      expect(Tool.select.icon, 'select.svg');
      // Its functions are Marquee and Lasso.
      expect(Tool.select.hasFunctionChoice, isTrue);
    });

    test('clicking stacked land picks the zone on top', () {
      final (editor, input, property, zone, inner) = stacked();
      click(input, at(6, 6));
      expect(editor.selectedLayerId, inner);
      click(input, at(10, 10));
      expect(editor.selectedLayerId, zone);
      click(input, at(16, 16));
      expect(editor.selectedLayerId, property);
      expect(
        editor.selection.single,
        editor.document.geometryOf(property).boundaryId,
        reason: 'the inside selects the whole shape',
      );
    });

    test('points beat lines, and lines beat insides, on any layer', () {
      final (editor, input, property, zone, _) = stacked();
      click(input, at(20, 10));
      expect(editor.selectedLayerId, property);
      expect(
        editor.document
            .geometryOf(property)
            .lines
            .containsKey(editor.selection.single),
        isTrue,
      );
      click(input, at(2, 2));
      expect(editor.selectedLayerId, zone);
      expect(editor.selection.single, 'point-1');
    });

    test('clicking empty ground clears the selection and the layer', () {
      final (editor, input, _, _, _) = stacked();
      click(input, at(6, 6));
      expect(editor.selectedLayerId, isNotNull);
      click(input, at(30, 30));
      expect(editor.selection, isEmpty);
      expect(editor.selectedLayerId, isNull);
    });

    test('Shift-clicking empty ground keeps the selection', () {
      final (editor, input, _, _, _) = stacked();
      click(input, at(6, 6));
      final layer = editor.selectedLayerId;
      final items = {...editor.selection};
      input
        ..hover(at(30, 30))
        ..press(at(30, 30), shift: true)
        ..release(at(30, 30));
      expect(editor.selectedLayerId, layer);
      expect(editor.selection, items);
    });

    test('dragging a point, a line, or a whole shape moves it', () {
      final (editor, input, _, zone, inner) = stacked();
      drag(input, at(12, 12), at(13, 13));
      expect(
        editor.document.geometryOf(zone).points['point-3']!.x,
        closeTo(13, 1e-9),
      );

      drag(input, at(12.5, 7), at(14.5, 7));
      final points = editor.document.geometryOf(zone).points;
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

      final innerBefore = editor.document.geometryOf(inner).points['point-1']!;
      drag(input, at(10, 3), at(11, 4));
      expect(editor.selectedLayerId, zone);
      expect(
        editor.document.geometryOf(zone).points['point-1']!.x,
        closeTo(3, 1e-9),
      );
      expect(
        editor.document.geometryOf(inner).points['point-1']!,
        innerBefore,
        reason: 'a zone over another zone stays put',
      );
      expect(editor.document.isActive(inner), isTrue);

      final property = editor.document.propertyIds.single;
      drag(input, at(18, 18), at(19, 19));
      expect(editor.selectedLayerId, property);
      expect(
        editor.document.geometryOf(inner).points['point-1']!.x,
        closeTo(innerBefore.x + 1, 1e-9),
        reason: 'zones inside a moved property shape move with it',
      );
    });

    test('a zone moved out of its property is kept but marked invalid', () {
      final (editor, input, _, zone, inner) = stacked();
      drag(input, at(10, 10), at(30, 10));
      expect(
        editor.document.geometryOf(zone).points['point-1']!.x,
        closeTo(22, 1e-9),
      );
      expect(
        editor.document.problemOf(zone),
        'Shape 1 is not inside Property 1',
      );
      expect(editor.document.isActive(zone), isFalse);
      expect(
        editor.document.isActive(inner),
        isTrue,
        reason: 'the zone it overlapped stays behind',
      );
      expect(editor.notice, contains('Zone 1 is invalid'));

      drag(input, at(30, 10), at(10, 10));
      expect(
        editor.document.isActive(zone),
        isTrue,
        reason: 'moving it back fixes it',
      );
    });

    test('holding still lists everything underneath, top first', () {
      final (editor, input, property, zone, inner) = stacked();
      input.press(at(6, 6), shift: false);
      final choices = input.takeHoldChoices();
      expect(choices.map((c) => c.layerId), [inner, zone, property]);
      expect(choices.every((c) => c.kind == HitKind.interior), isTrue);
      expect(input.describe(choices[1]), 'Zone 1 · Whole shape');

      input.choose(choices.last);
      expect(editor.selectedLayerId, property);
      input.release(at(6, 6));
      expect(
        editor.selectedLayerId,
        property,
        reason: 'the held press does not also click',
      );
    });

    test('a press that became a drag offers no list', () {
      final (_, input, _, _, _) = stacked();
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
        final p = editor.document.layers[layerId]!.properties as ZoneProperties;
        editor.updateProperties(layerId, p.copyWith(crop: () => t));
      },
    );

    (EditorController, String, String) twoZones() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      final property = editor.selectedLayerId!;
      editor.addLayer(LayerKind.zone);
      final first = editor.selectedLayerId!;
      editor.selectLayer(property);
      editor.addLayer(LayerKind.zone);
      return (editor, first, editor.selectedLayerId!);
    }

    test('unapplied text disables drawing Undo', () {
      final (editor, first, _) = twoZones();
      expect(editor.canUndo, isTrue);
      editor.drafts.update('ground', groundDraft(editor, first, 'beds'));
      expect(editor.canUndo, isFalse);
    });

    test(
      'switching layers applies valid text to the layer it was typed for',
      () {
        final (editor, first, second) = twoZones();
        editor.selectLayer(first);
        editor.drafts.update('ground', groundDraft(editor, first, 'beds'));
        editor.selectLayer(second);
        String? ground(String id) =>
            (editor.document.layers[id]!.properties as ZoneProperties).crop;
        expect(ground(first), 'beds');
        expect(ground(second), isNull);
      },
    );

    test('Save waits for invalid text and changes nothing', () {
      final (editor, first, _) = twoZones();
      editor.drafts.update('ground', groundDraft(editor, first, 'beds!'));
      final before = editor.document;
      expect(editor.drafts.settleForSave(), isNotNull);
      expect(identical(editor.document, before), isTrue);
      expect(editor.drafts['ground'], isNotNull);
    });
  });

  test('Point and Line have no Move function; Select moves things', () {
    expect(Tool.point.functions, [ToolFunction.place, ToolFunction.delete]);
    expect(Tool.line.functions, [ToolFunction.draw, ToolFunction.curve]);
    expect(Tool.circle.functions, [
      ToolFunction.centerCircle,
      ToolFunction.twoPointCircle,
    ]);
  });

  group('Circle tool', () {
    test('center circle: click the centre, then the edge', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(10, 10));
      expect(
        editor.document.geometryOf(property).points,
        isEmpty,
        reason: 'the first click is not added to the drawing',
      );
      expect(editor.circleStart, isNotNull);
      click(input, at(14, 10));

      final geometry = editor.document.geometryOf(property);
      final circle = geometry.circles.values.single;
      expect(circle.radius, closeTo(4, 1e-9));
      expect(geometry.points[circle.center]!.x, closeTo(10, 1e-9));
      expect(geometry.boundaryId, circle.id);
      expect(editor.document.isActive(property), isTrue);
      expect(editor.selection, {circle.id});

      editor.undo();
      expect(
        editor.document.geometryOf(property).points,
        isEmpty,
        reason: 'circle and centre are one undo step',
      );
    });

    test('2-point circle: the clicks are opposite sides', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      editor.selectFunction(ToolFunction.twoPointCircle);
      click(input, at(2, 5));
      click(input, at(12, 5));
      final geometry = editor.document.geometryOf(property);
      final circle = geometry.circles.values.single;
      expect(circle.radius, closeTo(5, 1e-9));
      expect(geometry.points[circle.center]!.x, closeTo(7, 1e-9));
      expect(geometry.points, hasLength(1), reason: 'only the centre is kept');
    });

    test('Esc forgets the first click', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      editor.selectTool(Tool.circle);
      click(input, at(10, 10));
      editor.escape();
      expect(editor.circleStart, isNull);
    });

    test('a further closed shape joins the layer on top of the stack', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      final boundaryId = editor.document.geometryOf(property).boundaryId;
      editor.selectTool(Tool.circle);
      final before = editor.document;
      click(input, at(20, 20));
      expect(editor.circleStart, isNotNull);
      expect(identical(editor.document, before), isTrue);
      click(input, at(22, 20));
      final geometry = editor.document.geometryOf(property);
      expect(geometry.circles, hasLength(1));
      expect(geometry.boundaryId, boundaryId);
      expect(geometry.stack.last, geometry.circles.keys.single);
      expect(geometry.area, closeTo(100 + 4 * 3.141592653589793, 1e-6));
      expect(editor.notice, isNull);
      editor.undo();
      expect(editor.document.geometryOf(property).circles, isEmpty);
    });

    test('a circular zone is checked against its property', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.zone);
      final zone = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(5, 5));
      click(input, at(8, 5));
      expect(editor.document.isActive(zone), isTrue);

      editor.selectTool(Tool.select);
      drag(input, at(8, 5), at(12, 5));
      final circle = editor.document.geometryOf(zone).circles.values.single;
      expect(
        circle.radius,
        closeTo(7, 1e-9),
        reason: 'dragging the edge resizes',
      );
      expect(
        editor.document.problemOf(zone),
        'Circle 1 is not inside Property 1',
      );

      editor.undo();
      drag(input, at(5, 6), at(4, 6));
      final moved = editor.document.geometryOf(zone);
      expect(
        moved.points[moved.circles.values.single.center]!.x,
        closeTo(4, 1e-9),
        reason: 'dragging the inside moves the circle',
      );
      expect(editor.document.isActive(zone), isTrue);
    });

    test('deleting the centre point deletes the circle', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(5, 5));
      click(input, at(8, 5));
      editor.selectTool(Tool.point);
      editor.selectFunction(ToolFunction.delete);
      click(input, at(5, 5));
      final geometry = editor.document.geometryOf(property);
      expect(geometry.circles, isEmpty);
      expect(geometry.boundaryId, isNull);
    });

    test('deleting a circle takes its centre point too', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      editor.selectTool(Tool.circle);
      click(input, at(5, 5));
      click(input, at(8, 5));
      editor.deleteSelection();
      final geometry = editor.document.geometryOf(property);
      expect(geometry.circles, isEmpty);
      expect(geometry.points, isEmpty, reason: 'no stray centre is left');
      expect(editor.document.problemOf(property), isNull);
      editor.undo();
      expect(editor.document.geometryOf(property).points, hasLength(1));
    });

    test('deleting a shape keeps points another shape still uses', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      // A circle centred on a corner of the square shares that point.
      editor.selectTool(Tool.circle);
      click(input, at(10, 10));
      click(input, at(12, 10));
      final geometry = editor.document.geometryOf(property);
      final (next, _) = editor.tryGeometryEdit(
        property,
        (e) => e.delete([geometry.boundaryId!]),
      );
      expect(next!.geometryOf(property).points.values, [const Vec(10, 10)]);
      expect(next.geometryOf(property).circles, hasLength(1));
    });

    test('deleting a line still keeps its points', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      final geometry = editor.document.geometryOf(property);
      final (next, _) = editor.tryGeometryEdit(
        property,
        (e) => e.delete([geometry.lines.keys.first]),
      );
      expect(next!.geometryOf(property).points, hasLength(4));
    });
  });

  group('locked layers', () {
    (EditorController, CanvasInput, String) lockedProperty() {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.setLayerLocked(property, true);
      return (editor, input, property);
    }

    test('refuse drawing, moving, renaming, properties and delete', () {
      final (editor, input, property) = lockedProperty();
      final before = editor.document;

      editor.selectTool(Tool.point);
      click(input, at(5, 5));
      expect(editor.notice, contains('Property 1 is locked'));

      editor.selectTool(Tool.select);
      drag(input, at(10, 10), at(12, 12));
      drag(input, at(5, 5), at(6, 6));

      editor.renameLayer(property, 'Renamed');
      editor.updateProperties(
        property,
        const PropertyProperties(color: OutlineColor.sage),
      );
      editor.deleteLayer(property);
      expect(identical(editor.document, before), isTrue);
      expect(editor.deleteLayerBlocker(property), isNotNull);
    });

    test('Select clicks pass through a locked layer', () {
      final (editor, input, _) = lockedProperty();
      editor.selectLayer(null);
      editor.selectTool(Tool.select);
      click(input, at(5, 5));
      expect(editor.selectedLayerId, isNull);
      expect(editor.preview, isNull);
    });

    test('a lock covers the layers inside and is undoable', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      final property = editor.selectedLayerId!;
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.zone);
      final zone = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);

      editor.setLayerLocked(property, true);
      expect(editor.document.lockedBy(zone)?.id, property);
      expect(
        editor.lockNotice(zone),
        'Zone 1 is inside Property 1, which is locked',
      );
      expect(editor.addLayerBlocker(LayerKind.zone), isNotNull);

      editor.undo();
      expect(editor.document.isLocked(zone), isFalse);
      expect(editor.addLayerBlocker(LayerKind.zone), isNull);
    });

    test('a locked zone stops its property being moved as a whole', () {
      final (editor, input) = newEditor();
      editor.addLayer(LayerKind.property);
      drawLoop(input, [at(0, 0), at(10, 0), at(10, 10), at(0, 10)]);
      editor.addLayer(LayerKind.zone);
      final zone = editor.selectedLayerId!;
      drawLoop(input, [at(2, 2), at(6, 2), at(6, 6), at(2, 6)]);
      editor.setLayerLocked(zone, true);

      final before = editor.document;
      editor.selectTool(Tool.select);
      drag(input, at(8, 8), at(9, 9));
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('Zone 1 is locked'));
    });
  });
}
