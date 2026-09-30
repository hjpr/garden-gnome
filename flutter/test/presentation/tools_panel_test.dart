import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/canvas/drawing_canvas.dart';
import 'package:garden_gnome/presentation/panels/tools_panel.dart';

import '../support/editor_workbench.dart';
import '../support/widget_harness.dart';

void main() {
  testWidgets('tools are laid out Select to Reference, three to a row', (
    tester,
  ) async {
    await setTestViewport(tester);
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    await tester.pumpWidget(editorWorkbench(editor));
    await tester.pumpAndSettle();
    // Rows: Select Point Line / Arc Circle Polygon / Ground Feature
    // Reference.
    Offset centre(String label) => tester.getCenter(
      find.descendant(of: find.byType(ToolsBody), matching: find.text(label)),
    );
    for (final (label, column) in [
      ('Arc', 'Select'),
      ('Circle', 'Point'),
      ('Polygon', 'Line'),
      ('Ground', 'Select'),
      ('Feature', 'Point'),
      ('Reference', 'Line'),
    ]) {
      expect(centre(label).dx, centre(column).dx, reason: label);
    }
    expect(centre('Point').dy, centre('Select').dy);
    expect(centre('Line').dy, centre('Select').dy);
    expect(centre('Arc').dy, greaterThan(centre('Select').dy));
    expect(centre('Circle').dy, centre('Arc').dy);
    expect(centre('Polygon').dy, centre('Arc').dy);
    expect(centre('Ground').dy, greaterThan(centre('Arc').dy));
    expect(centre('Feature').dy, centre('Ground').dy);
    expect(find.text('Pattern'), findsNothing, reason: 'Pattern was removed');
    expect(find.text('Boolean'), findsNothing, reason: 'now in Operations');

    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    expect(editor.function, ToolFunction.draw);
    expect(find.text('LINE FUNCTIONS'), findsOneWidget);
    expect(find.text('Straight'), findsOneWidget);
    expect(find.text('Join'), findsNothing);
    await tester.tap(find.text('Curve'));
    await tester.pumpAndSettle();
    expect(editor.function, ToolFunction.curve);
    expect(
      find.text('Arc'),
      findsOneWidget,
      reason: 'Arc is its own tool, not a Line function',
    );

    await tester.tap(find.text('Arc'));
    await tester.pumpAndSettle();
    expect(editor.tool, Tool.arc);
    expect(editor.function, ToolFunction.threePointArc);
    expect(find.text('ARC FUNCTIONS'), findsOneWidget);
    expect(find.text('3-point'), findsOneWidget);
    await tester.tap(find.text('Start-end'));
    await tester.pumpAndSettle();
    expect(editor.function, ToolFunction.startEndArc);

    await tester.tap(find.text('Polygon'));
    await tester.pumpAndSettle();
    expect(find.text('Regular'), findsOneWidget);
    expect(find.text('Rectangle'), findsOneWidget);
    expect(find.text('Sides'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('More sides'));
    await tester.pumpAndSettle();
    expect(editor.polygonSides, 7);
    await tester.tap(find.text('Rectangle'));
    await tester.pumpAndSettle();
    expect(find.text('Sides'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'three canvas clicks create Arc from the visible function button',
    (tester) async {
      await setTestViewport(tester);
      final editor = EditorController()..addLayer(LayerKind.property);
      addTearDown(editor.dispose);
      final layer = editor.selectedLayerId!;
      await tester.pumpWidget(editorWorkbench(editor));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Arc'));
      await tester.pumpAndSettle();
      final origin = tester.getTopLeft(find.byType(DrawingCanvas));
      for (final point in [const Vec(2, 8), const Vec(6, 4)]) {
        await tester.tapAt(origin + editor.camera.toScreen(point));
        await tester.pump();
      }
      expect(editor.document.geometryOf(layer).points, isEmpty);
      expect(editor.arcPoints, hasLength(2));
      await tester.tapAt(origin + editor.camera.toScreen(const Vec(10, 8)));
      await tester.pumpAndSettle();
      expect(
        editor.document.geometryOf(layer).lines.values.single.bulge,
        closeTo(1, 1e-8),
      );
      expect(editor.arcPoints, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  test('tool labels and bundled icons; Boolean is not a tool', () {
    expect(Tool.values.map((t) => t.label), [
      'Select',
      'Point',
      'Line',
      'Arc',
      'Circle',
      'Polygon',
      'Ground',
      'Feature',
      'Reference',
    ]);
    expect(Tool.ground.functions.map((f) => f.label), [
      'Zone',
      'Flat',
      'Row',
      'Grow',
    ]);
    expect(Tool.feature.functions.map((f) => f.label), [
      'Raised bed',
      'Greenhouse',
      'High tunnel',
    ]);
    expect(Tool.line.functions.map((f) => f.label), isNot(contains('Arc')));
    expect(Tool.arc.functions, [
      ToolFunction.threePointArc,
      ToolFunction.startEndArc,
    ]);
    expect(Tool.polygon.functions.map((f) => f.label), [
      'Regular',
      'Rectangle',
    ]);
    // Only Select shows an arrow; tools that add or remove geometry show a
    // crosshair.
    expect(Tool.values.where((t) => t.usesArrowCursor), [Tool.select]);
    for (final tool in Tool.values) {
      for (final icon in [tool.icon, ...tool.functions.map((f) => f.icon)]) {
        expect(File('assets/icons/$icon').existsSync(), isTrue, reason: icon);
      }
    }
    // CanvasInput is also constructed by DrawingCanvas, not a widget-only stub.
    final editor = EditorController();
    expect(CanvasInput(editor).editor, same(editor));
    editor.dispose();
  });
}
