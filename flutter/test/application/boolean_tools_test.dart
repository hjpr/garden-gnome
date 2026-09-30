import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/document_content.dart';
import 'package:garden_gnome/application/hit_testing.dart';
import 'package:garden_gnome/application/previews.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/land_rules.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/region.dart';
import 'package:garden_gnome/domain/vec.dart';
import '../support/editor_input.dart';
import '../support/first_shape.dart';

void main() {
  group('Boolean operations', () {
    test('Union merges the selected shapes, one Undo/Redo', () {
      final (editor, input, layer) = property();
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
      final (editor, input, layer) = property();
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
      final (editor, input, layer) = property();
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
        final (editor, input, layer) = property();
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
        final (editor, input, layer) = property();
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
      final (editor, input, _) = property();
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
      final (editor, input, _) = property();
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
      final (editor, input, layer) = property();
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

    test('preview is red when Subtract cuts land from under a zone', () {
      final (editor, input, propertyId) = property();
      rectangle(input, 0, 0, 20, 20);
      editor.addLayer(LayerKind.zone);
      final zoneId = editor.selectedLayerId!;
      circle(input, 10, 10, 3);
      editor.selectLayer(propertyId);
      circle(input, 10, 10, 2);
      selectShapes(input, [const Vec(1, 1), const Vec(10, 10)]);
      editor.previewBoolean(BooleanOperation.subtract);
      final preview = editor.preview as BooleanPreview;
      expect(preview.document, isNotNull);
      expect(preview.valid, isFalse);
      editor.runBoolean(BooleanOperation.subtract);
      expect(
        editor.document.geometryOf(propertyId).boundary!.holes,
        hasLength(1),
      );
      expect(editor.document.problemOf(zoneId), contains('not inside'));
      editor.undo();
      expect(editor.document.ruleProblemOf(zoneId), isNull);
    });

    test('moving one shape carries only the land inside that shape', () {
      final (editor, input, propertyId) = property();
      rectangle(input, 0, 0, 20, 20);
      editor.addLayer(LayerKind.zone);
      final child = editor.selectedLayerId!;
      rectangle(input, 2, 2, 3, 3);
      final childBefore = editor.document.geometryOf(child);
      editor.selectLayer(propertyId);
      rectangle(input, 12, 12, 4, 4);
      final before = editor.document.geometryOf(propertyId);
      editor.selectTool(Tool.select);
      input.press(at(14, 14), shift: false);
      input.move(at(15, 14));
      input.release(at(15, 14));
      expect(editor.selection.single, isNot(before.boundaryId));
      expect(
        editor.document.geometryOf(propertyId).region!.area,
        closeTo(400, 1e-8),
      );
      expect(editor.document.geometryOf(child).points, childBefore.points);
    });
  });
}
