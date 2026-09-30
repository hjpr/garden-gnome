import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/canvas/drawing_canvas.dart';
import '../support/first_shape.dart';
import '../support/editor_workbench.dart';
import '../support/widget_harness.dart';

void main() {
  testWidgets(
    'Subtract UI displays net area, leaves a hole and updates through Undo',
    (tester) async {
      await setTestViewport(tester);
      final editor = EditorController()..addLayer(LayerKind.property);
      addTearDown(editor.dispose);
      final layer = editor.selectedLayerId!;
      final (next, _) = editor.tryGeometryEdit(layer, (e) {
        final ids = [
          for (final p in [
            const Vec(1, 1),
            const Vec(11, 1),
            const Vec(11, 11),
            const Vec(1, 11),
          ])
            e.addPoint(p),
        ];
        for (var i = 0; i < ids.length; i++) {
          e.connect(ids[i], ids[(i + 1) % ids.length]);
        }
        e.addCircle(e.addPoint(const Vec(6, 6)), 2);
      });
      editor.commit('Two shapes', next!);
      editor.updateSettings(
        editor.settings.copyWith(areaUnits: AreaUnits.squareMetres),
      );
      await tester.pumpWidget(editorWorkbench(editor));
      await tester.pumpAndSettle();
      expect(find.text('Net area'), findsOneWidget);
      // Two overlapping shapes: each counts until they are combined.
      // 100 m² square plus a radius-2 m circle: 100 + 4π m².
      expect(find.text('112.57 m²'), findsOneWidget);
      final origin = tester.getTopLeft(find.byType(DrawingCanvas));
      // Buttons stay disabled until two shapes are selected.
      await tester.tap(find.text('Subtract'));
      await tester.pumpAndSettle();
      expect(editor.document.geometryOf(layer).shapes, hasLength(1));
      await tester.tapAt(origin + editor.camera.toScreen(const Vec(2, 2)));
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.tapAt(origin + editor.camera.toScreen(const Vec(6, 6)));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(editor.selection, hasLength(2));
      await tester.tap(find.text('Subtract'));
      await tester.pumpAndSettle();
      // Cut out the circle: 100 − 4π m².
      expect(find.text('87.43 m²'), findsOneWidget);
      expect(editor.document.geometryOf(layer).boundary!.holes, hasLength(1));
      editor.updateSettings(
        editor.settings.copyWith(areaUnits: AreaUnits.squareFeet),
      );
      await tester.pumpAndSettle();
      expect(find.text('941.13 ft²'), findsOneWidget);
      editor.undo();
      await tester.pumpAndSettle();
      expect(find.text('1211.65 ft²'), findsOneWidget);
      editor.redo();
      await tester.pumpAndSettle();
      expect(find.text('941.13 ft²'), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + editor.camera.toScreen(const Vec(6, 6)));
      await tester.pumpAndSettle();
      expect(editor.selection, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
