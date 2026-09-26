import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/camera.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/persistence/document_codec.dart';

Offset at(double x, double y) => Offset(x * pixelsPerMetre, y * pixelsPerMetre);

void click(CanvasInput input, double x, double y) {
  final screen = at(x, y);
  input.hover(screen);
  input.press(screen, shift: false);
  input.release(screen);
}

(EditorController, CanvasInput, String) field() {
  final editor = EditorController()..addLayer(LayerKind.field);
  addTearDown(editor.dispose);
  return (editor, CanvasInput(editor), editor.selectedLayerId!);
}

void main() {
  group('soil sample', () {
    test('each value can be set or cleared, one Undo step each, and saved', () {
      final (editor, _, layer) = field();
      var p = editor.document.layers[layer]!.properties as FieldProperties;
      editor.updateProperties(
        layer,
        p.copyWith(soil: p.soil.withValue('ph', 6.4)),
      );
      p = editor.document.layers[layer]!.properties as FieldProperties;
      editor.updateProperties(
        layer,
        p.copyWith(soil: p.soil.withValue('organicMatter', 3.2)),
      );
      p = editor.document.layers[layer]!.properties as FieldProperties;
      expect(p.soil.ph, 6.4);
      expect(p.soil.organicMatter, 3.2);
      expect(p.soil.potassium, isNull);

      final reopened = decodeGgnome(encodeGgnome(editor.document));
      final saved = reopened.layers[layer]!.properties as FieldProperties;
      expect(saved.soil.ph, 6.4);
      expect(saved.soil.organicMatter, 3.2);

      editor.undo();
      p = editor.document.layers[layer]!.properties as FieldProperties;
      expect(p.soil.organicMatter, isNull);
      expect(p.soil.ph, 6.4);
      expect(
        p.soil.withValue('ph', null).ph,
        isNull,
        reason: 'blank clears a value',
      );
    });

    test('every listed field reads and writes its own value', () {
      var soil = const SoilSample();
      for (final (i, (field, _)) in SoilSample.fields.indexed) {
        soil = soil.withValue(field, i + 1.0);
      }
      for (final (i, (field, _)) in SoilSample.fields.indexed) {
        expect(soil.valueOf(field), i + 1.0, reason: field);
      }
    });
  });

  group('point spacing', () {
    test('a new point too close to another is refused with a reason', () {
      final (editor, input, layer) = field();
      editor.selectTool(Tool.point);
      click(input, 5, 5);
      final before = editor.document;
      // Less than one 6 px marker away.
      final nudge = editor.camera.metres(3);
      click(input, 5 + nudge, 5);
      expect(identical(editor.document, before), isTrue);
      expect(editor.notice, contains('Too close'));
      click(input, 6, 5);
      expect(editor.document.geometryOf(layer).points, hasLength(2));
    });
  });
}
