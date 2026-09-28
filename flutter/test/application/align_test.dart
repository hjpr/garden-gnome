import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/alignment.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/vec.dart';

import 'boolean_tools_test.dart' show circle, property, rectangle, selectShapes;

void main() {
  group('Align', () {
    /// A 10 m square at the origin (the anchor) and a radius-2 circle far
    /// off at (30, 30) (the one to move), selected in that order.
    (EditorController, String) setUp() {
      final (editor, input, layer) = property();
      rectangle(input, 0, 0, 10, 10);
      circle(input, 30, 30, 2);
      selectShapes(input, [const Vec(5, 5), const Vec(30, 30)]);
      return (editor, layer);
    }

    Vec circleCentre(EditorController editor, String layer) {
      final geometry = editor.document.geometryOf(layer);
      final c = geometry.circles.values.single;
      return geometry.points[c.center]!;
    }

    for (final (edge, expected) in [
      (AlignEdge.left, const Vec(2, 30)),
      (AlignEdge.right, const Vec(8, 30)),
      (AlignEdge.top, const Vec(30, 2)),
      (AlignEdge.bottom, const Vec(30, 8)),
      (AlignEdge.center, const Vec(5, 5)),
    ]) {
      test('${edge.label} moves the second item, not the first', () {
        final (editor, layer) = setUp();
        final square = editor.document.geometryOf(layer).points;
        editor.runAlign(edge);
        final centre = circleCentre(editor, layer);
        expect(centre.x, closeTo(expected.x, 1e-9));
        expect(centre.y, closeTo(expected.y, 1e-9));
        final geometry = editor.document.geometryOf(layer);
        for (final id in geometry.shapes.values.single.rings.first) {
          final line = geometry.lines[id.segmentId]!;
          expect(geometry.points[line.start], square[line.start]);
        }
        expect(editor.undoLabel, 'Align ${edge.label.toLowerCase()}');
      });
    }

    test('selection order decides which item moves', () {
      final (editor, input, layer) = property();
      rectangle(input, 0, 0, 10, 10);
      circle(input, 30, 30, 2);
      selectShapes(input, [const Vec(30, 30), const Vec(5, 5)]);
      editor.runAlign(AlignEdge.left);
      expect(circleCentre(editor, layer), const Vec(30, 30));
      final geometry = editor.document.geometryOf(layer);
      final square = boundsOfItem(geometry, geometry.shapes.keys.single)!;
      expect(square.$1.x, closeTo(28, 1e-9), reason: 'square moved left');
    });

    test('hover previews without changing the drawing; one Undo', () {
      final (editor, layer) = setUp();
      final before = editor.document;
      editor.previewAlign(AlignEdge.center);
      expect(editor.preview, isA<MovePreview>());
      expect(identical(editor.document, before), isTrue);
      editor.previewAlign(null);
      expect(editor.preview, isNull);
      editor.runAlign(AlignEdge.center);
      editor.undo();
      expect(sameContent(editor.document, before), isTrue);
      expect(circleCentre(editor, layer), const Vec(30, 30));
    });

    test('needs exactly two selected items', () {
      final (editor, input, _) = property();
      rectangle(input, 0, 0, 10, 10);
      circle(input, 30, 30, 2);
      circle(input, 50, 50, 2);
      expect(editor.alignBlocker, isNotNull);
      selectShapes(input, [const Vec(5, 5)]);
      expect(editor.alignBlocker, isNotNull);
      selectShapes(input, [
        const Vec(5, 5),
        const Vec(30, 30),
        const Vec(50, 50),
      ]);
      expect(editor.alignBlocker, isNotNull);
      final before = editor.document;
      editor.runAlign(AlignEdge.left);
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, isNotNull);
    });

    test('a move that overlaps is kept and flagged, not refused', () {
      final (editor, layer) = setUp();
      editor.runAlign(AlignEdge.center);
      expect(editor.document.problemOf(layer), contains('overlaps'));
      expect(circleCentre(editor, layer), const Vec(5, 5));
    });
  });
}
