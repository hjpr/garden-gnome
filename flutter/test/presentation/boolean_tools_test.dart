import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/canvas_input.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/canvas/drawing_canvas.dart';
import 'package:garden_gnome/presentation/panels/operations_panel.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/panels/tools_panel.dart';
import 'package:garden_gnome/presentation/theme.dart';
import '../support/first_shape.dart';

Widget workbench(EditorController editor) => MaterialApp(
  theme: buildTheme(),
  home: Scaffold(
    body: ListenableBuilder(
      listenable: editor,
      builder: (context, _) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 232,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ToolsBody(editor: editor),
                  OperationsBody(editor: editor),
                ],
              ),
            ),
          ),
          Expanded(child: DrawingCanvas(editor: editor)),
          SizedBox(
            width: 264,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: PropertiesBody(editor: editor),
            ),
          ),
        ],
      ),
    ),
  ),
);

void main() {
  testWidgets('tools are laid out Select to Pattern, three to a row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final editor = EditorController()..addLayer(LayerKind.field);
    addTearDown(editor.dispose);
    await tester.pumpWidget(workbench(editor));
    await tester.pumpAndSettle();
    // Rows: Select Point Line / Arc Circle Polygon / Pattern.
    Offset centre(String label) => tester.getCenter(
      find.descendant(of: find.byType(ToolsBody), matching: find.text(label)),
    );
    for (final (label, column) in [
      ('Arc', 'Select'),
      ('Circle', 'Point'),
      ('Polygon', 'Line'),
      ('Pattern', 'Select'),
    ]) {
      expect(centre(label).dx, centre(column).dx, reason: label);
    }
    expect(centre('Point').dy, centre('Select').dy);
    expect(centre('Line').dy, centre('Select').dy);
    expect(centre('Arc').dy, greaterThan(centre('Select').dy));
    expect(centre('Circle').dy, centre('Arc').dy);
    expect(centre('Polygon').dy, centre('Arc').dy);
    expect(centre('Pattern').dy, greaterThan(centre('Arc').dy));
    expect(find.text('Boolean'), findsNothing, reason: 'now in Operations');

    await tester.tap(find.text('Line'));
    await tester.pumpAndSettle();
    expect(find.text('Draw'), findsOneWidget);
    expect(
      find.text('Arc'),
      findsOneWidget,
      reason: 'Arc is its own tool, not a Line function',
    );

    await tester.tap(find.text('Arc'));
    await tester.pumpAndSettle();
    expect(editor.tool, Tool.arc);
    expect(editor.function, ToolFunction.arc);
    expect(find.text('ARC FUNCTIONS'), findsNothing);

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
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = EditorController()..addLayer(LayerKind.field);
      addTearDown(editor.dispose);
      final layer = editor.selectedLayerId!;
      await tester.pumpWidget(workbench(editor));
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

  testWidgets(
    'Subtract UI displays net area, leaves a hole and updates through Undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final editor = EditorController()..addLayer(LayerKind.field);
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
      await tester.pumpWidget(workbench(editor));
      await tester.pumpAndSettle();
      expect(find.text('Net area'), findsOneWidget);
      // Two overlapping shapes: each counts until they are combined.
      final both = 100 + math.pi * 4;
      expect(find.text(AreaUnits.squareMetres.format(both)), findsOneWidget);
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
      final area = 100 - math.pi * 4;
      expect(find.text(AreaUnits.squareMetres.format(area)), findsOneWidget);
      expect(editor.document.geometryOf(layer).boundary!.holes, hasLength(1));
      editor.updateSettings(
        editor.settings.copyWith(areaUnits: AreaUnits.squareFeet),
      );
      await tester.pumpAndSettle();
      expect(find.text(AreaUnits.squareFeet.format(area)), findsOneWidget);
      editor.undo();
      await tester.pumpAndSettle();
      expect(find.text(AreaUnits.squareFeet.format(both)), findsOneWidget);
      editor.redo();
      await tester.pumpAndSettle();
      expect(find.text(AreaUnits.squareFeet.format(area)), findsOneWidget);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      await tester.tapAt(origin + editor.camera.toScreen(const Vec(6, 6)));
      await tester.pumpAndSettle();
      expect(editor.selection, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('open boundaries show a dash, not an invented area', (
    tester,
  ) async {
    final editor = EditorController()..addLayer(LayerKind.field);
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The dock scrolls; the soil sample group makes the panel tall.
          body: SingleChildScrollView(
            child: SizedBox(width: 264, child: PropertiesBody(editor: editor)),
          ),
        ),
      ),
    );
    expect(find.text('Net area'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  test('tool labels and bundled icons; Boolean is not a tool', () {
    expect(Tool.values.map((t) => t.label), [
      'Select',
      'Point',
      'Line',
      'Arc',
      'Circle',
      'Polygon',
      'Pattern',
      'Reference',
    ]);
    expect(Tool.pattern.functions.map((f) => f.label), [
      'None',
      'Diagonal',
      'Rows',
      'Crosshatch',
      'Grid',
      'Dots',
      'Crosses',
    ]);
    expect(Tool.line.functions.map((f) => f.label), isNot(contains('Arc')));
    expect(Tool.arc.functions, [ToolFunction.arc]);
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
