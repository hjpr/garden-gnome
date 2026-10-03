import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/feature.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/domain/plant_layout.dart';
import 'package:garden_gnome/domain/units.dart';
import 'package:garden_gnome/domain/vec.dart';
import 'package:garden_gnome/domain/zone_ground.dart';
import 'package:garden_gnome/presentation/panels/layer_actions.dart';
import 'package:garden_gnome/presentation/panels/layers_panel.dart';
import 'package:garden_gnome/presentation/panels/layer_fields.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/widgets/property_controls.dart';
import '../support/ground_fixtures.dart';
import '../support/widget_harness.dart';

Widget panels(EditorController editor) => editorPanel(
  editor: editor,
  builder: (context) => Column(
    children: [
      LayerActions(editor: editor),
      LayersBody(editor: editor),
      PropertiesBody(editor: editor),
    ],
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
  testWidgets('Flat ground owns the planting direction; grow zones show none', (
    tester,
  ) async {
    final (editor, _, flat, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    editor.selectLayer(grow);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => PropertiesBody(editor: editor),
      ),
    );
    final direction = find.descendant(
      of: find.widgetWithText(PropertyRow, 'Direction (°)'),
      matching: find.byType(TextField),
    );
    expect(direction, findsNothing);

    editor.selectLayer(flat);
    await tester.pumpAndSettle();
    expect(find.text('GROUND'), findsOneWidget);
    expect(direction, findsOneWidget);
    await tester.enterText(direction, '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.document.rowsOf(flat)!.direction, 90);
    final line = editor.document.plantLayoutOf(grow)!.lines.first;
    expect(line.start.y, closeTo(line.end.y, 1e-9));
  });

  testWidgets('Plants sits under Seed; Sown and Transplanted are dates', (
    tester,
  ) async {
    final (editor, _, _, grow) = garden(GroundType.flat);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => PropertiesBody(editor: editor),
      ),
    );
    final sown = find.byKey(const ValueKey('day-Sown'));
    final transplanted = find.byKey(const ValueKey('day-Transplanted'));
    expect(tester.widget<InkWell>(sown).onTap, isNull, reason: 'no seed');

    editor.setSeed(grow, seed());
    await tester.pumpAndSettle();
    double top(String label) =>
        tester.getTopLeft(find.widgetWithText(PropertyRow, label)).dy;
    expect(top('Seed'), lessThan(top('Plants')));
    expect(top('Plants'), lessThan(top('Size (ft)')));
    expect(top('Spacing (ft)'), lessThan(top('Sown')));
    expect(top('Sown'), lessThan(top('Transplanted')));
    expect(
      tester.widget<InkWell>(transplanted).onTap,
      isNull,
      reason: 'needs a Sown date first',
    );

    await tester.tap(sown);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('10'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final sowing = editor.document.currentPlantingOf(grow)!;
    expect(sowing.sownOn, DateTime.utc(now.year, now.month, 10));
    expect(sowing.startedIndoors, isFalse, reason: 'sown in place');

    await tester.tap(transplanted);
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final out = editor.document.currentPlantingOf(grow)!;
    expect(out.plantedOutOn, DateTime.utc(now.year, now.month, 20));
    expect(out.startedIndoors, isTrue);

    await tester.tap(find.byTooltip('Clear Transplanted'));
    await tester.pumpAndSettle();
    expect(editor.document.currentPlantingOf(grow)!.plantedOutOn, isNull);
    expect(editor.document.currentPlantingOf(grow)!.startedIndoors, isFalse);

    editor.undo();
    editor.undo();
    editor.undo();
    await tester.pumpAndSettle();
    expect(editor.document.currentPlantingOf(grow), isNull);
  });

  testWidgets('typing plant spacing changes row layout and supports Undo', (
    tester,
  ) async {
    final (editor, _, soil, grow) = garden(GroundType.row);
    editor.setRows(soil, const RowSpec(width: 0.5, spacing: 0.5));
    editor.setSeed(
      grow,
      const ZoneSeed(
        varietyId: 'test',
        name: 'Test seed',
        size: 0.5,
        spacing: 0,
      ),
    );
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => PropertiesBody(editor: editor),
      ),
    );
    final spacing = find.descendant(
      of: find.widgetWithText(PropertyRow, 'Spacing (ft)'),
      matching: find.byType(TextField),
    );
    final before = editor.document.plantLayoutOf(grow)!;
    await tester.enterText(spacing, '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final after = editor.document.plantLayoutOf(grow)!;
    expect(after.seed.size, 0.5);
    expect(after.seed.spacing, closeTo(0.3048, 1e-9));
    expect(after.count, lessThan(before.count));
    expect(
      (after.positions[1].y - after.positions[0].y).abs(),
      closeTo(0.8048, 1e-9),
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('readout-Plants'))).data,
      '${after.count}',
    );
    editor.undo();
    await tester.pumpAndSettle();
    expect(editor.document.plantLayoutOf(grow)!.count, before.count);
    expect(tester.widget<TextField>(spacing).controller!.text, '0');
    editor.redo();
    await tester.pumpAndSettle();
    expect(editor.document.plantLayoutOf(grow)!.count, after.count);
    await tester.enterText(spacing, '-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      editor.document.plantLayoutOf(grow)!.seed.spacing,
      closeTo(0.3048, 1e-9),
    );
    await tester.enterText(spacing, '0');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.document.plantLayoutOf(grow)!.count, before.count);
  });

  testWidgets(
    'ground type bar spans the panel above the name and follows Undo',
    (tester) async {
      final (editor, _, property, zone) = farm();
      await tester.pumpWidget(
        editorPanel(
          editor: editor,
          builder: (_) => PropertiesBody(editor: editor),
        ),
      );
      final bar = find.byKey(const ValueKey('ground-type-bar'));
      for (final (ground, label, color) in [
        (null, 'Fallow bed', const Color(0xFF6B7280)),
        (GroundType.flat, 'Flat bed', const Color(0xFFBF5700)),
        (GroundType.row, 'Row bed', const Color(0xFF98DFC2)),
      ]) {
        editor.setGround(zone, ground);
        await tester.pumpAndSettle();
        expect(bar, findsOneWidget);
        expect(tester.widget<Container>(bar).color, color);
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
        );
        expect(
          tester.getSize(bar).width,
          tester.getSize(find.byType(PropertiesBody)).width,
        );
        expect(
          tester.getRect(bar).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(LayerNameEditor)).top),
        );
      }
      editor.undo();
      await tester.pumpAndSettle();
      expect(tester.widget<Container>(bar).color, const Color(0xFFBF5700));
      editor.selectLayer(property);
      await tester.pumpAndSettle();
      expect(bar, findsNothing);
    },
  );

  testWidgets('property options show only the colour', (tester) async {
    final (editor, _, property, _) = farm();
    editor.selectLayer(property);
    await tester.pumpWidget(panels(editor));
    expect(find.text('Color'), findsOneWidget);
    expect(find.text('Soil drainage'), findsNothing);
    expect(find.text('SOIL SAMPLE'), findsNothing);
  });

  testWidgets(
    'row dimensions use inches in feet drawings and metres otherwise',
    (tester) async {
      final (editor, _, _, zone) = farm();
      editor.setGround(zone, GroundType.row);
      editor.setRows(zone, const RowSpec(border: 1.524));
      await tester.pumpWidget(
        editorPanel(
          editor: editor,
          builder: (_) => PropertiesBody(editor: editor),
        ),
      );
      Finder field(String label) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.byType(TextField),
      );
      for (final (label, value, typed) in [
        ('Row width', '30', '25'),
        ('Spacing', '18', '10'),
        ('Border', '60', '50'),
      ]) {
        expect(find.text('$label (in)'), findsOneWidget);
        final box = field('$label (in)');
        expect(tester.widget<TextField>(box).controller!.text, value);
        await tester.ensureVisible(box);
        await tester.enterText(box, typed);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      final rows = editor.document.rowsOf(zone)!;
      expect(rows.width, closeTo(0.635, 1e-9));
      expect(rows.spacing, closeTo(0.254, 1e-9));
      expect(rows.border, closeTo(1.27, 1e-9));
      final document = editor.document;
      editor.updateSettings(editor.settings.copyWith(units: Units.metres));
      await tester.pumpAndSettle();
      for (final (label, value) in [
        ('Row width', '0.635'),
        ('Spacing', '0.254'),
        ('Border', '1.27'),
      ]) {
        expect(
          tester.widget<TextField>(field('$label (m)')).controller!.text,
          value,
        );
      }
      expect(editor.document, same(document));
      await tester.ensureVisible(field('Border (m)'));
      await tester.enterText(field('Border (m)'), '1.524');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.document.rowsOf(zone)!.border, closeTo(1.524, 1e-9));
      editor.updateSettings(editor.settings.copyWith(units: Units.feet));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('Border (in)')).controller!.text,
        '60',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('readout-Row length')))
            .data,
        endsWith(' ft'),
      );
    },
  );

  testWidgets('row border uses inches, recalculates rows and supports Undo', (
    tester,
  ) async {
    final (editor, _, _, zone) = farm();
    editor.setGround(zone, GroundType.row);
    editor.setRows(zone, const RowSpec(width: 1, spacing: 1));
    final geometry = editor.document.geometryOf(zone);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => PropertiesBody(editor: editor),
      ),
    );
    expect(find.text('Border (in)'), findsOneWidget);
    final border = find.descendant(
      of: find
          .ancestor(of: find.text('Border (in)'), matching: find.byType(Row))
          .first,
      matching: find.byType(TextField),
    );
    expect(border, findsOneWidget);
    await tester.ensureVisible(border);
    await tester.enterText(border, '60');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.document.rowsOf(zone)!.border, closeTo(1.524, 1e-9));
    expect(editor.document.rowLayoutOf(zone)!.rowCount, 3);
    expect(
      editor.document.rowLayoutOf(zone)!.totalLength,
      closeTo(8.856, 1e-8),
    );
    expect(identical(editor.document.geometryOf(zone), geometry), isTrue);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('readout-Rows'))).data,
      '3',
    );

    editor.undo();
    await tester.pumpAndSettle();
    expect(editor.document.rowsOf(zone)!.border, 0);
    expect(editor.document.rowLayoutOf(zone)!.rowCount, 5);
    editor.redo();
    await tester.pumpAndSettle();
    expect(editor.document.rowsOf(zone)!.border, closeTo(1.524, 1e-9));

    await tester.enterText(border, '-1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(editor.document.rowsOf(zone)!.border, closeTo(1.524, 1e-9));
    editor.setGround(zone, GroundType.flat);
    await tester.pumpAndSettle();
    expect(find.text('Border (in)'), findsNothing);
  });

  testWidgets('grow zones show only grow options in both modes', (
    tester,
  ) async {
    final (editor, _, _, grow) = garden(GroundType.flat);
    editor.setSeed(grow, seed());
    editor.setMode(EditMode.plant);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => PropertiesBody(editor: editor),
      ),
    );
    expect(find.byType(CompactDropdown<GroundType?>), findsNothing);
    expect(find.text('OPTIONS'), findsNothing);
    expect(find.text('GROUND'), findsNothing);
    expect(find.text('GROW'), findsOneWidget);
    expect(find.text('Spacing (ft)'), findsOneWidget);
    final spacing = find.descendant(
      of: find
          .ancestor(of: find.text('Size (ft)'), matching: find.byType(Row))
          .first,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(spacing).enabled, isTrue);
    await tester.enterText(spacing, '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      (editor.document.layers[grow]!.properties as ZoneProperties).seed!.size,
      closeTo(editor.settings.units.toMetres(2), 1e-9),
    );
    editor.setMode(EditMode.build);
    await tester.pumpAndSettle();
    expect(find.byType(CompactDropdown<GroundType?>), findsNothing);
    expect(find.text('OPTIONS'), findsNothing);
    expect(find.text('GROUND'), findsNothing);
    expect(find.text('GROW'), findsOneWidget);
  });

  testWidgets('Layers adds a property, then beds and plantings in groups', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(panels(editor));
    expect(find.text('Add a property to start.'), findsOneWidget);
    // With no property, only Property layer can be picked.
    final propertyItem = await openAddLayerItem(tester, 'Property layer');
    expect(menuItemEnabled(tester, propertyItem), isTrue);
    for (final label in ['Bed layer', 'Planting layer', 'Reference layer']) {
      final item = find.widgetWithText(MenuItemButton, label);
      expect(menuItemEnabled(tester, item), isFalse, reason: label);
    }
    expect(find.byTooltip('Add a property layer first'), findsNWidgets(3));

    await tester.tap(propertyItem);
    await tester.pumpAndSettle();
    final property = editor.selectedLayerId!;
    expect(editor.document.layers[property]!.name, 'Property 1');
    final bedItem = await openAddLayerItem(tester, 'Bed layer');
    expect(menuItemEnabled(tester, bedItem), isFalse);
    expect(
      find.byTooltip('Complete Property 1 before adding a bed'),
      findsOneWidget,
    );
    expect(
      menuItemEnabled(
        tester,
        find.widgetWithText(MenuItemButton, 'Reference layer'),
      ),
      isTrue,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    drawSquare(editor, property);
    await tester.pumpAndSettle();

    await addLayerFromMenu(tester, 'Bed layer');
    editor.selectLayer(property);
    await addLayerFromMenu(tester, 'Planting layer');
    editor.selectLayer(property);
    await addLayerFromMenu(tester, 'Bed layer');
    final zones = editor.document.layers[property]!.children;
    expect(zones.map((id) => editor.document.layers[id]!.name), [
      'Bed 1',
      'Planting 1',
      'Bed 2',
    ]);
    expect(
      editor.document.layers[zones.first]!.properties,
      isA<ZoneProperties>().having((p) => p.ground, 'ground', GroundType.flat),
      reason: 'a new bed is Flat, so plantings over it grow',
    );
    expect(editor.isGrowZone(zones[1]), isTrue);
    expect(find.bySemanticsLabel(RegExp(r'^Bed 2, Bed, ')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Planting 1, Planting, ')),
      findsOneWidget,
    );
    // Beds are listed together, then plantings, whatever order they came in.
    double top(String text) => tester
        .getTopLeft(
          find.descendant(
            of: find.byType(LayersBody),
            matching: find.text(text),
          ),
        )
        .dy;
    expect(top('BEDS'), lessThan(top('Bed 1')));
    expect(top('Bed 2'), lessThan(top('PLANTINGS')));
    expect(top('PLANTINGS'), lessThan(top('Planting 1')));
  });

  testWidgets('zone options follow the ground type without a Crop field', (
    tester,
  ) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    drawSquare(editor, editor.selectedLayerId!);
    editor.addLayer(LayerKind.zone);
    final zone = editor.selectedLayerId!;
    drawSquare(editor, zone);
    editor.updateProperties(zone, const ZoneProperties(crop: 'Tomatoes'));
    await tester.pumpWidget(panels(editor));
    expect(find.text('Soil drainage'), findsNothing);
    for (final ground in [null, GroundType.flat, GroundType.row]) {
      editor.setGround(zone, ground);
      await tester.pumpAndSettle();
      expect(find.text('Color'), findsOneWidget);
      // Ground is set with the Ground tool; Row and Flat have settings.
      expect(find.byType(CompactDropdown<GroundType?>), findsNothing);
      expect(
        find.text('GROUND'),
        ground == null ? findsNothing : findsOneWidget,
      );
      expect(
        find.text('Direction (°)'),
        ground == null ? findsNothing : findsOneWidget,
      );
      for (final label in ['Crop', 'GROW', 'Size (ft)']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      expect(
        find.text('Row width (in)'),
        ground == GroundType.row ? findsOneWidget : findsNothing,
      );
      expect(
        (editor.selectedLayer!.properties as ZoneProperties).crop,
        'Tomatoes',
      );
    }
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

  testWidgets('row boxes appear only when the ground is Row', (tester) async {
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
    expect(find.text('Row width (in)'), findsNothing);
    expect(find.text('GROW'), findsNothing);

    editor.setGround(zone, GroundType.row);
    await tester.pumpAndSettle();
    expect(box('Row width (in)').enabled, isTrue);
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

  testWidgets('open boundaries show a dash, not an invented area', (
    tester,
  ) async {
    final editor = EditorController()..addLayer(LayerKind.property);
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (context) => PropertiesBody(editor: editor),
      ),
    );
    expect(find.text('Net area'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('empty Properties and Layers say so in grey', (tester) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (context) => Column(
          children: [
            PropertiesBody(editor: editor),
            LayersBody(editor: editor),
          ],
        ),
      ),
    );
    expect(find.text('Nothing selected.'), findsOneWidget);
    expect(find.text('Add a property to start.'), findsOneWidget);
  });
}
