import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/domain/feature.dart';
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

  testWidgets('row boxes are greyed until the ground is Row', (tester) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    drawSquare(editor, editor.selectedLayerId!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    drawSquare(editor, zone);
    await tester.pumpWidget(panels(editor));
    TextField box(String label) => tester.widget<TextField>(
      find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField),
      ),
    );
    expect(box('Row width (ft)').enabled, isFalse);
    expect(find.text('—'), findsNWidgets(2), reason: 'Rows and Row length');

    editor.setGround(zone, GroundType.row);
    await tester.pumpAndSettle();
    expect(box('Row width (ft)').enabled, isTrue);
    expect(find.byKey(const ValueKey('readout-Rows')), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find
            .ancestor(
              of: find.text('Direction (°)'),
              matching: find.byType(Row),
            )
            .first,
        matching: find.byType(TextField),
      ),
      '90',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final p = editor.document.layers[zone]!.properties as ZoneProperties;
    expect(p.rows.direction, 90);
  });

  testWidgets('a selected feature shows its name and sizes', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    editor.addFeature(FeatureKind.raisedBed, const Vec(1, 1));
    await tester.pumpWidget(panels(editor));
    expect(find.text('Raised bed 1'), findsOneWidget);
    for (final label in ['Length (ft)', 'Width (ft)', 'Height (ft)']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('8'), findsOneWidget, reason: '8 ft long');
    await tester.tap(find.bySemanticsLabel('Delete Raised bed 1'));
    await tester.pumpAndSettle();
    expect(editor.document.features, isEmpty);
    expect(find.text('Nothing selected.'), findsOneWidget);
  });

  testWidgets('Direction has up and down arrows inside its box', (
    tester,
  ) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    drawSquare(editor, editor.selectedLayerId!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    drawSquare(editor, zone);
    editor.setGround(zone, GroundType.row);
    editor.setRows(zone, const RowSpec(direction: 178));
    await tester.pumpWidget(panels(editor));
    double direction() =>
        (editor.document.layers[zone]!.properties as ZoneProperties)
            .rows
            .direction;

    final up = find.bySemanticsLabel('Increase Direction');
    final down = find.bySemanticsLabel('Decrease Direction');
    expect(up, findsOneWidget);
    // The arrows sit inside the box, at its right edge.
    final box = tester.getRect(
      find.ancestor(of: up, matching: find.byType(TextField)).first,
    );
    expect(tester.getCenter(up).dx, greaterThan(box.right - 24));

    await tester.tap(up);
    await tester.pumpAndSettle();
    expect(direction(), 179);
    await tester.tap(up);
    await tester.pumpAndSettle();
    expect(direction(), 0, reason: '180° wraps to 0°');
    await tester.tap(down);
    await tester.pumpAndSettle();
    expect(direction(), 179);
    expect(find.text('179'), findsOneWidget);
  });
}
