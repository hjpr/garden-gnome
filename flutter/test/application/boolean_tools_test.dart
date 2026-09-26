import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/document.dart';
import 'package:garden_gnome/domain/geometry.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/first_shape.dart';

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

(EditorController, CanvasInput, String) field() {
  final editor = EditorController()..addLayer(LayerKind.field);
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor), editor.selectedLayerId!);
}

/// Selects the shapes under each world position, as Shift-click with
/// Select does, then runs [operation] from the Operations panel.
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

void arc(CanvasInput input) {
  input.editor.selectTool(Tool.arc);
  click(input, 2, 8);
  click(input, 6, 4);
  click(input, 10, 8);
}

void main() {
  group('Boolean operations', () {
    test('Union merges the selected shapes, one Undo/Redo', () {
      final (editor, input, layer) = field();
      rectangle(input, 0, 0, 10, 10);
      rectangle(input, 5, 0, 10, 10);
      final before = editor.document;
      final source = before.geometryOf(layer);
      expect(source.shapes, hasLength(2));
      expect(before.problemOf(layer), contains('overlaps'));

      expect(editor.booleanBlocker, isNotNull, reason: 'nothing selected');
      selectShapes(input, [const Vec(2, 5), const Vec(12, 5)]);
      expect(editor.booleanBlocker, isNull);
      editor.previewBoolean(BooleanOperation.union);
      final preview = editor.preview as BooleanPreview;
      expect(preview.valid, isTrue);
      expect(
        preview.document!.geometryOf(layer).region!.area,
        closeTo(15 * 10, 1e-8),
      );
      expect(identical(editor.document, before), isTrue);
      editor.runBoolean(BooleanOperation.union);
      final after = editor.document;
      final result = after.geometryOf(layer);
      expect(after.isValid(layer), isTrue);
      expect(result.shapes, hasLength(1));
      expect(result.region!.area, closeTo(15 * 10, 1e-8));
      expect(editor.selection, {result.boundaryId});
      expect(editor.preview, isNull);
      expect(editor.undoLabel, 'Union');
      editor.undo();
      expect(sameContent(editor.document, before), isTrue);
      editor.redo();
      expect(sameContent(editor.document, after), isTrue);
    });

    test('Union merges only the selected shapes', () {
      final (editor, input, layer) = field();
      rectangle(input, 0, 0, 10, 10);
      rectangle(input, 5, 0, 10, 10);
      rectangle(input, 12, 0, 10, 10);
      selectShapes(input, [const Vec(2, 5), const Vec(7, 5)]);
      editor.runBoolean(BooleanOperation.union);
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.shapes, hasLength(2));
      expect(
        geometry.regionOf(editor.selection.single)!.area,
        closeTo(150, 1e-8),
      );
    });

    test('Subtract cuts the top selected shape out of the others', () {
      final (editor, input, layer) = field();
      rectangle(input, 0, 0, 10, 10);
      circle(input, 5, 5, 2);
      final before = editor.document;
      selectShapes(input, [const Vec(1, 1), const Vec(5, 5)]);
      editor.previewBoolean(BooleanOperation.subtract);
      expect((editor.preview as BooleanPreview).valid, isTrue);
      editor.runBoolean(BooleanOperation.subtract);
      final after = editor.document;
      final geometry = after.geometryOf(layer);
      expect(geometry.boundary!.holes, hasLength(1));
      expect(geometry.circles, isEmpty);
      expect(geometry.region!.area, closeTo(100 - math.pi * 4, 1e-7));
      expect(
        geometry.lines.values.where((line) => line.bulge != 0),
        isNotEmpty,
      );
      expect(
        hitsAt(
          geometry,
          editor.camera,
          at(5, 5),
        ).where((h) => h.kind == HitKind.interior),
        isEmpty,
      );
      click(input, 5, 5);
      expect(editor.selection, isEmpty);
      expect(editor.undoLabel, 'Subtract');
      editor.undo();
      expect(sameContent(editor.document, before), isTrue);
      editor.redo();
      expect(sameContent(editor.document, after), isTrue);
    });

    test(
      'circle Union commits editable arcs rather than chord approximations',
      () {
        final (editor, input, layer) = field();
        circle(input, 5, 5, 4);
        circle(input, 9, 5, 4);
        selectShapes(input, [const Vec(2, 5), const Vec(12, 5)]);
        editor.runBoolean(BooleanOperation.union);
        final geometry = editor.document.geometryOf(layer);
        expect(geometry.circles, isEmpty);
        expect(geometry.boundary, isNotNull);
        expect(geometry.lines.values.every((edge) => edge.bulge != 0), isTrue);
        expect(geometry.region!.area, greaterThan(math.pi * 16));
        expect(editor.document.isActive(layer), isTrue);
      },
    );

    for (final operation in BooleanOperation.values) {
      test('${operation.name} refusal is atomic with a useful red preview', () {
        final (editor, input, layer) = field();
        rectangle(input, 0, 0, 10, 10);
        rectangle(input, 20, 0, 4, 4);
        final message = operation == BooleanOperation.union
            ? 'does not overlap'
            : 'does not overlap Shape';
        final before = editor.document;
        final history = editor.undoLabel;
        final counters = before.geometryOf(layer).counters;
        selectShapes(input, [const Vec(5, 5), const Vec(22, 2)]);
        editor.previewBoolean(operation);
        final preview = editor.preview as BooleanPreview;
        expect(preview.valid, isFalse);
        expect(preview.document, isNull);
        expect(preview.problem, contains(message));
        editor.previewBoolean(null);
        expect(editor.preview, isNull);
        editor.runBoolean(operation);
        expect(identical(editor.document, before), isTrue);
        expect(editor.undoLabel, history);
        expect(
          editor.document.geometryOf(layer).counters.sameAs(counters),
          isTrue,
        );
        expect(editor.notice, contains(message));
      });
    }

    test('one selected shape is not enough', () {
      final (editor, input, _) = field();
      rectangle(input, 0, 0, 10, 10);
      rectangle(input, 5, 0, 10, 10);
      selectShapes(input, [const Vec(2, 5)]);
      final before = editor.document;
      expect(editor.booleanBlocker, contains('two or more'));
      editor.runBoolean(BooleanOperation.union);
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('two or more'));
    });

    test('Subtract that would empty the land does not consume anything', () {
      final (editor, input, _) = field();
      rectangle(input, 0, 0, 10, 10);
      rectangle(input, -2, -2, 14, 14);
      final before = editor.document;
      // The big square is on top, so it would cut all of the small one.
      editor.selectTool(Tool.select);
      for (final id in before.geometryOf(editor.selectedLayerId!).stack) {
        editor.selectItem(id, toggle: true);
      }
      editor.runBoolean(BooleanOperation.subtract);
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('remove all'));
    });

    test('a locked layer refuses Boolean operations', () {
      final (editor, input, layer) = field();
      rectangle(input, 0, 0, 10, 10);
      circle(input, 5, 5, 1);
      selectShapes(input, [const Vec(1, 1), const Vec(5, 5)]);
      editor.setLayerLocked(layer, true);
      // Locking clears the selection; select the shapes again directly.
      final geometry = editor.document.geometryOf(layer);
      for (final id in geometry.stack) {
        editor.selectItem(id, toggle: true);
      }
      final locked = editor.document;
      expect(editor.booleanBlocker, contains('locked'));
      editor.runBoolean(BooleanOperation.subtract);
      expect(identical(editor.document, locked), isTrue);
      expect(editor.notice, contains('locked'));
    });

    test('preview is red when Subtract removes land underneath a child', () {
      final (editor, input, fieldId) = field();
      rectangle(input, 0, 0, 20, 20);
      editor.addLayer(LayerKind.plot);
      final plotId = editor.selectedLayerId!;
      circle(input, 10, 10, 3);
      editor.selectLayer(fieldId);
      circle(input, 10, 10, 2);
      selectShapes(input, [const Vec(1, 1), const Vec(10, 10)]);
      editor.previewBoolean(BooleanOperation.subtract);
      final preview = editor.preview as BooleanPreview;
      expect(preview.document, isNotNull);
      expect(preview.valid, isFalse);
      editor.runBoolean(BooleanOperation.subtract);
      expect(editor.document.geometryOf(fieldId).boundary!.holes, hasLength(1));
      expect(editor.document.problemOf(plotId), contains('not inside a field'));
      editor.undo();
      expect(editor.document.ruleProblemOf(plotId), isNull);
    });

    test('moving one shape carries only the land inside that shape', () {
      final (editor, input, fieldId) = field();
      rectangle(input, 0, 0, 20, 20);
      editor.addLayer(LayerKind.plot);
      final child = editor.selectedLayerId!;
      rectangle(input, 2, 2, 3, 3);
      final childBefore = editor.document.geometryOf(child);
      editor.selectLayer(fieldId);
      rectangle(input, 12, 12, 4, 4);
      final before = editor.document.geometryOf(fieldId);
      editor.selectTool(Tool.select);
      input.press(at(14, 14), shift: false);
      input.move(at(15, 14));
      input.release(at(15, 14));
      expect(editor.selection.single, isNot(before.boundaryId));
      expect(
        editor.document.geometryOf(fieldId).region!.area,
        closeTo(400, 1e-8),
      );
      expect(editor.document.geometryOf(child).points, childBefore.points);
    });
  });

  group('3-point Arc', () {
    test(
      'first two clicks are temporary, third commits one arc and one Undo',
      () {
        final (editor, input, layer) = field();
        editor.selectTool(Tool.arc);
        final before = editor.document;
        click(input, 2, 8);
        click(input, 6, 4);
        expect(identical(editor.document, before), isTrue);
        expect(editor.arcPoints, hasLength(2));
        input.hover(at(10, 8));
        final preview = editor.preview as ArcPreview;
        expect(preview.valid, isTrue);
        expect(
          preview.curve!.pointAt(0.5).distanceTo(const Vec(6, 4)),
          lessThan(1e-8),
        );
        click(input, 10, 8);
        final geometry = editor.document.geometryOf(layer);
        expect(
          geometry.points,
          hasLength(2),
          reason: 'through is not a document vertex',
        );
        expect(geometry.lines.values.single.bulge, closeTo(1, 1e-8));
        expect(editor.arcPoints, isEmpty);
        final after = editor.document;
        editor.undo();
        expect(sameContent(editor.document, before), isTrue);
        editor.redo();
        expect(sameContent(editor.document, after), isTrue);
        expect(editor.arcPoints, isEmpty);
      },
    );

    test(
      'arc hit testing and Point insertion use the curve, not its chord',
      () {
        final (editor, input, layer) = field();
        arc(input);
        final geometry = editor.document.geometryOf(layer);
        final original = geometry.lines.values.single;
        final length = original.curve(geometry.points).length;
        expect(lineAt(geometry, editor.camera, at(6, 4)), original.id);
        expect(lineAt(geometry, editor.camera, at(6, 8)), isNull);
        editor.selectTool(Tool.point);
        input.hover(at(6, 3.9));
        final preview = editor.preview as PointPreview;
        expect(preview.position.distanceTo(const Vec(6, 4)), lessThan(1e-8));
        expect(preview.lineId, original.id);
        click(input, 6, 3.9);
        final split = editor.document.geometryOf(layer);
        expect(split.lines, hasLength(2));
        expect(split.lines.values.every((edge) => edge.bulge != 0), isTrue);
        expect(
          split.lines.values.fold(
            0.0,
            (sum, edge) => sum + edge.curve(split.points).length,
          ),
          closeTo(length, 1e-8),
        );
        editor.undo();
        expect(editor.document.geometryOf(layer).lines.keys, [original.id]);
      },
    );

    test('Select moves the actual arc and keeps its bulge through Undo', () {
      final (editor, input, layer) = field();
      arc(input);
      final before = editor.document;
      final source = before.geometryOf(layer).lines.values.single;
      editor.selectTool(Tool.select);
      input.press(at(6, 4), shift: false);
      input.move(at(7, 5));
      final preview = editor.preview as MovePreview;
      final candidate = preview.document.geometryOf(layer);
      expect(candidate.lines[source.id]!.bulge, source.bulge);
      input.release(at(7, 5));
      final moved = editor.document.geometryOf(layer);
      expect(moved.points[source.start], const Vec(3, 9));
      expect(moved.points[source.end], const Vec(11, 9));
      editor.undo();
      expect(sameContent(editor.document, before), isTrue);
    });

    test(
      'existing endpoints can enclose a circular segment with a straight return',
      () {
        final (editor, input, layer) = field();
        arc(input);
        editor.selectTool(Tool.line);
        editor.selectFunction(ToolFunction.join);
        click(input, 10, 8);
        click(input, 2, 8);
        final geometry = editor.document.geometryOf(layer);
        expect(geometry.points, hasLength(2));
        expect(geometry.lines, hasLength(2));
        expect(geometry.isClosed, isTrue);
        expect(geometry.region!.area, closeTo(math.pi * 16 / 2, 1e-8));
        expect(editor.document.isActive(layer), isTrue);
      },
    );

    test('Arc reuses the open ends of an existing straight line', () {
      final (editor, input, layer) = field();
      editor.selectTool(Tool.line);
      click(input, 2, 8);
      click(input, 10, 8);
      editor.selectTool(Tool.arc);
      click(input, 2, 8);
      click(input, 6, 4);
      click(input, 10, 8);
      final geometry = editor.document.geometryOf(layer);
      expect(geometry.points, hasLength(2));
      expect(geometry.isClosed, isTrue);
      expect(editor.document.isActive(layer), isTrue);
    });

    test(
      'collinear Arc is refused without a partial commit, then can be retried',
      () {
        final (editor, input, layer) = field();
        editor.selectTool(Tool.arc);
        final before = editor.document;
        final history = editor.undoLabel;
        click(input, 2, 8);
        click(input, 6, 8);
        input.hover(at(10, 8));
        expect((editor.preview as ArcPreview).valid, isFalse);
        click(input, 10, 8);
        expect(identical(editor.document, before), isTrue);
        expect(editor.undoLabel, history);
        expect(editor.notice, contains('straight line'));
        expect(editor.arcPoints, hasLength(2));
        click(input, 10, 4);
        expect(editor.document.geometryOf(layer).lines, hasLength(1));
        expect(editor.arcPoints, isEmpty);
      },
    );

    for (final cancel in ['escape', 'tool', 'enter', 'layer', 'undo', 'lock']) {
      test('$cancel clears both temporary Arc clicks', () {
        final (editor, input, layer) = field();
        editor.selectTool(Tool.arc);
        click(input, 2, 8);
        click(input, 6, 4);
        switch (cancel) {
          case 'escape':
            editor.escape();
          case 'tool':
            editor.selectTool(Tool.point);
          case 'enter':
            editor.cancelOperation();
          case 'layer':
            editor.selectLayer(null);
          case 'undo':
            editor.undo();
          case 'lock':
            editor.setLayerLocked(layer, true);
        }
        expect(editor.arcPoints, isEmpty);
        expect(editor.preview, isNull);
        if (editor.document.layers.containsKey(layer)) {
          expect(editor.document.geometryOf(layer).lines, isEmpty);
        }
      });
    }

    test('locked layers refuse the first Arc and circle clicks', () {
      final (editor, input, layer) = field();
      editor.setLayerLocked(layer, true);
      final before = editor.document;
      editor.selectTool(Tool.arc);
      click(input, 2, 8);
      expect(editor.arcPoints, isEmpty);
      editor.selectTool(Tool.circle);
      click(input, 4, 4);
      expect(editor.circleStart, isNull);
      expect(editor.notice, contains('locked'));
      expect(identical(editor.document, before), isTrue);
    });

    test('Fit drawing includes arc extrema away from both endpoints', () {
      final (editor, input, _) = field();
      arc(input);
      editor.setViewportSize(const Size(600, 400));
      editor.fitDrawing();
      for (final p in [const Vec(2, 8), const Vec(6, 4), const Vec(10, 8)]) {
        final screen = editor.camera.toScreen(p);
        expect(screen.dx, inInclusiveRange(39.0, 561.0));
        expect(screen.dy, inInclusiveRange(39.0, 361.0));
      }
    });
  });

  test(
    'saved content comparison includes bulges, holes and shape/circle patterns',
    () {
      final (editor, input, layer) = field();
      rectangle(input, 0, 0, 10, 10);
      final before = editor.document;
      final geometry = before.geometryOf(layer);
      GardenDocument changed({
        Map<String, LineSegment>? lines,
        Map<String, ClosedShape>? shapes,
        Map<String, Circle>? circles,
      }) => before.withGeometry(
        Geometry(
          id: geometry.id,
          ownerLayerId: layer,
          points: geometry.points,
          lines: lines ?? geometry.lines,
          shapes: shapes ?? geometry.shapes,
          circles: circles ?? geometry.circles,
          order: geometry.order,
          counters: geometry.counters,
        ),
      );
      final line = geometry.lines.values.first;
      expect(
        sameContent(
          before,
          changed(
            lines: {
              ...geometry.lines,
              line.id: LineSegment(line.id, line.start, line.end, bulge: 0.1),
            },
          ),
        ),
        isFalse,
      );
      final shape = geometry.boundary!;
      expect(
        sameContent(
          before,
          changed(
            shapes: {
              shape.id: ClosedShape(shape.id, shape.segments, label: 'Beds'),
            },
          ),
        ),
        isFalse,
      );
      expect(
        sameContent(
          before,
          changed(
            shapes: {
              shape.id: ClosedShape(
                shape.id,
                shape.segments,
                holes: [shape.segments],
              ),
            },
          ),
        ),
        isFalse,
      );
      final first = changed(
        circles: {'circle-1': Circle('circle-1', line.start, 2)},
      );
      final second = changed(
        circles: {'circle-1': Circle('circle-1', line.start, 2, label: 'Beds')},
      );
      expect(sameContent(first, second), isFalse);
      expect(sameContent(before, changed()), isTrue);
    },
  );

  test('Net area uses squared unit conversion and a dash for open land', () {
    expect(AreaUnits.squareMetres.format(null), '—');
    expect(AreaUnits.squareMetres.format(12.5), '12.5 m²');
    expect(AreaUnits.squareFeet.format(0.3048 * 0.3048), '1 ft²');
    expect(AreaUnits.squareMetres.format(0), '0 m²');
    expect(AreaUnits.acres.format(4046.8564224), '1 acre');
    expect(AreaUnits.acres.format(100), '0.0247 acres');
  });
}
