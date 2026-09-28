import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/panels/layers_panel.dart';

void main() {
  testWidgets('a layer expands to list its shapes, top first', (tester) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    final layer = editor.selectedLayerId!;
    final (next, _) = editor.tryGeometryEdit(layer, (e) {
      final ids = [
        for (final p in const [Vec(0, 0), Vec(10, 0), Vec(10, 10), Vec(0, 10)])
          e.addPoint(p),
      ];
      for (var i = 0; i < ids.length; i++) {
        e.connect(ids[i], ids[(i + 1) % ids.length]);
      }
      e.addCircle(e.addPoint(const Vec(30, 5)), 2);
    });
    editor.commit('Two shapes', next!);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 264,
            child: ListenableBuilder(
              listenable: editor,
              builder: (context, _) => LayersBody(editor: editor),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Shape 1'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Show shapes of Property 1'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shape 1'), findsOneWidget);
    expect(find.textContaining('Circle 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.textContaining('Circle 1')).dy,
      lessThan(tester.getTopLeft(find.textContaining('Shape 1')).dy),
      reason: 'the top of the stack is listed first',
    );

    await tester.tap(find.textContaining('Shape 1'));
    await tester.pumpAndSettle();
    expect(editor.selection, contains('shape-1'));
    // Shape 1 is at the bottom, so it can move up but not down.
    editor.moveShape(layer, 'shape-1', up: true);
    await tester.pumpAndSettle();
    expect(editor.document.geometryOf(layer).stack.last, 'shape-1');
    editor.renameShape(layer, 'circle-1', 'Well');
    await tester.pumpAndSettle();
    expect(find.textContaining('Well'), findsOneWidget);
    editor.undo();
    await tester.pumpAndSettle();
    expect(find.textContaining('Circle 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
