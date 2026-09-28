import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/presentation/panels/layers_panel.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/theme.dart';

Widget panels(EditorController editor) => MaterialApp(
  // The plain ripple needs no shader, so taps work on test machines that
  // cannot load the default sparkle.
  theme: buildTheme().copyWith(splashFactory: InkRipple.splashFactory),
  home: Scaffold(
    body: SizedBox(
      width: 264,
      child: ListenableBuilder(
        listenable: editor,
        builder: (context, _) => SingleChildScrollView(
          child: Column(
            children: [
              LayerActions(editor: editor),
              LayersBody(editor: editor),
              PropertiesBody(editor: editor),
            ],
          ),
        ),
      ),
    ),
  ),
);

/// Draws a 10 m square on [layerId] as one undoable step.
void drawSquare(EditorController editor, String layerId) {
  final (next, _) = editor.tryGeometryEdit(layerId, (e) {
    final ids = [
      for (final p in const [Vec(0, 0), Vec(10, 0), Vec(10, 10), Vec(0, 10)])
        e.addPoint(p),
    ];
    for (var i = 0; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
  });
  editor.commit('Square', next!);
}

void main() {
  testWidgets('Layers adds a property, then zones under it', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(panels(editor));
    expect(find.text('Add a property to start.'), findsOneWidget);
    expect(
      find.byTooltip('Select a property to add a zone'),
      findsOneWidget,
      reason: 'Zone is greyed out with nothing selected',
    );

    await tester.tap(find.bySemanticsLabel('Add property'));
    await tester.pumpAndSettle();
    final property = editor.selectedLayerId!;
    expect(editor.document.layers[property]!.name, 'Property 1');
    expect(
      find.byTooltip('Complete Property 1 before adding a zone'),
      findsOneWidget,
    );
    drawSquare(editor, property);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Add zone'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Add zone'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Add zone'));
    await tester.pumpAndSettle();
    final zones = editor.document.layers[property]!.children;
    expect(zones.map((id) => editor.document.layers[id]!.name), [
      'Zone 1',
      'Zone 2',
    ]);
    expect(find.bySemanticsLabel(RegExp(r'^Zone 2, Zone, ')), findsOneWidget);
  });

  testWidgets('a zone has Color, Ground and Crop in Properties', (
    tester,
  ) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    drawSquare(editor, editor.selectedLayerId!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    await tester.pumpWidget(panels(editor));
    expect(find.text('Soil drainage'), findsNothing);
    for (final label in ['Color', 'Ground', 'Crop']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }

    final crop = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'e.g. tomatoes',
    );
    await tester.enterText(crop, 'Tomatoes');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final properties = editor.document.layers[zone]!.properties;
    expect((properties as ZoneProperties).crop, 'Tomatoes');
    expect(properties.color, OutlineColor.sage);
  });

  testWidgets('Layers marks a zone shape outside its property', (tester) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    drawSquare(editor, editor.selectedLayerId!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    final (next, _) = editor.tryGeometryEdit(zone, (e) {
      e.addCircle(e.addPoint(const Vec(5, 5)), 2);
      e.addCircle(e.addPoint(const Vec(30, 5)), 2);
    });
    editor.commit('Two circles', next!);
    await tester.pumpWidget(panels(editor));
    await tester.tap(find.bySemanticsLabel('Show shapes of Zone 1'));
    await tester.pumpAndSettle();
    expect(find.text('Circle 2  outside Property 1'), findsOneWidget);
    expect(find.text('Circle 1'), findsOneWidget, reason: 'inside: no note');
    expect(find.text('Invalid: Circle 2 is not inside Property 1'), findsOne);
  });
}
