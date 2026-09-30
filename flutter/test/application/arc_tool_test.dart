import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/document_content.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/vec.dart';

import '../support/editor_input.dart';

void arc(CanvasInput input) {
  input.editor.selectTool(Tool.arc);
  click(input, 2, 8);
  click(input, 6, 4);
  click(input, 10, 8);
}

void main() {
  group('3-point Arc', () {
    test(
      'first two clicks are temporary, third commits one arc and one Undo',
      () {
        final (editor, input, layer) = property();
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
        final (editor, input, layer) = property();
        arc(input);
        final geometry = editor.document.geometryOf(layer);
        final original = geometry.lines.values.single;
        final length = 4 * math.pi; // radius 4 m, half a circumference
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
      final (editor, input, layer) = property();
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
        final (editor, input, layer) = property();
        arc(input);
        editor.selectTool(Tool.line);
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
      final (editor, input, layer) = property();
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
        final (editor, input, layer) = property();
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

    group('Start-end', () {
      void startEnd(EditorController editor) {
        editor.selectTool(Tool.arc);
        editor.selectFunction(ToolFunction.startEndArc);
      }

      test('start, end, then the middle commits one arc', () {
        final (editor, input, layer) = property();
        startEnd(editor);
        final before = editor.document;
        click(input, 2, 8);
        click(input, 10, 8);
        expect(identical(editor.document, before), isTrue);
        expect(editor.arcPoints, hasLength(2));
        input.hover(at(6, 4));
        final preview = editor.preview as ArcPreview;
        expect(preview.valid, isTrue);
        expect(
          preview.curve!.pointAt(0.5).distanceTo(const Vec(6, 4)),
          lessThan(1e-8),
        );
        click(input, 6, 4);
        final geometry = editor.document.geometryOf(layer);
        expect(geometry.points, hasLength(2));
        expect(geometry.lines.values.single.bulge, closeTo(1, 1e-8));
        expect(editor.arcPoints, isEmpty);
      });

      test('the third click sets the bend and keeps the arc symmetric', () {
        final (editor, input, layer) = property();
        startEnd(editor);
        click(input, 2, 8);
        click(input, 10, 8);
        // Off to the side: only the distance from the chord counts.
        click(input, 9, 6);
        final geometry = editor.document.geometryOf(layer);
        final curve = geometry.lines.values.single.curve(geometry.points);
        expect(curve.pointAt(0.5).distanceTo(const Vec(6, 6)), lessThan(1e-8));
      });

      test('the end reuses an open end point', () {
        final (editor, input, layer) = property();
        editor.selectTool(Tool.line);
        click(input, 2, 8);
        click(input, 10, 8);
        startEnd(editor);
        click(input, 2, 8);
        click(input, 10, 8);
        click(input, 6, 4);
        final geometry = editor.document.geometryOf(layer);
        expect(geometry.points, hasLength(2));
        expect(geometry.isClosed, isTrue);
      });

      test('a middle on the chord is refused and can be retried', () {
        final (editor, input, layer) = property();
        startEnd(editor);
        click(input, 2, 8);
        click(input, 10, 8);
        input.hover(at(6, 8));
        expect((editor.preview as ArcPreview).valid, isFalse);
        click(input, 6, 8);
        expect(editor.notice, contains('straight line'));
        expect(editor.arcPoints, hasLength(2));
        click(input, 6, 12);
        expect(editor.document.geometryOf(layer).lines, hasLength(1));
      });

      test('an end on the start is refused', () {
        final (editor, input, _) = property();
        startEnd(editor);
        click(input, 2, 8);
        click(input, 2, 8);
        expect(editor.arcPoints, hasLength(1));
        expect(editor.notice, contains('end of the Arc'));
      });

      test('switching function clears the clicks', () {
        final (editor, input, _) = property();
        startEnd(editor);
        click(input, 2, 8);
        editor.selectFunction(ToolFunction.threePointArc);
        expect(editor.arcPoints, isEmpty);
      });
    });

    for (final cancel in ['escape', 'tool', 'enter', 'layer', 'undo', 'lock']) {
      test('$cancel clears both temporary Arc clicks', () {
        final (editor, input, layer) = property();
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
      final (editor, input, layer) = property();
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
  });
}
