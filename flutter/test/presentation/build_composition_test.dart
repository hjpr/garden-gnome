import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/domain/layer.dart';
import 'package:garden_gnome/presentation/build_header.dart';
import 'package:garden_gnome/presentation/build_status_bar.dart';
import 'package:garden_gnome/presentation/panels/layer_actions.dart';
import 'package:garden_gnome/presentation/panels/layer_fields.dart';
import 'package:garden_gnome/presentation/panels/properties_panel.dart';
import 'package:garden_gnome/presentation/panels/property_options.dart';
import 'package:garden_gnome/presentation/widgets/drawing_title.dart';
import 'package:garden_gnome/presentation/widgets/mode_switch.dart';

import '../support/widget_harness.dart';

void main() {
  testWidgets(
    'BuildHeader places the mode switch on the right without history buttons',
    (tester) async {
      await setTestViewport(tester, size: const Size(800, 600));
      final editor = EditorController();
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        testApp(
          child: ListenableBuilder(
            listenable: editor,
            builder: (context, _) => BuildHeader(
              title: editor.title,
              dirty: false,
              editor: editor,
              onNew: () {},
              onOpen: () {},
              onSave: () {},
              onSaveAs: () {},
              onExport: () {},
              onClose: () {},
              onPreferences: () {},
            ),
          ),
        ),
      );

      final modeSwitch = find.byType(ModeSwitch);
      expect(modeSwitch, findsOneWidget);
      expect(
        tester.getRect(modeSwitch).left,
        greaterThan(tester.getRect(find.byType(DrawingTitle)).right),
      );
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.redo), findsNothing);

      await tester.tap(find.text('Plant'));
      await tester.pumpAndSettle();
      expect(editor.mode, EditMode.plant);
      await tester.tap(find.text('Build'));
      await tester.pumpAndSettle();
      expect(editor.mode, EditMode.build);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('BuildHeader delegates file commands without owning a session', (
    tester,
  ) async {
    await setTestViewport(tester);
    final editor = EditorController();
    addTearDown(editor.dispose);
    final commands = <String>[];
    await tester.pumpWidget(
      testApp(
        child: BuildHeader(
          title: editor.title,
          dirty: false,
          editor: editor,
          onNew: () => commands.add('New'),
          onOpen: () => commands.add('Open…'),
          onSave: () => commands.add('Save'),
          onSaveAs: () => commands.add('Save as…'),
          onExport: () => commands.add('Export .ggnome file'),
          onClose: () => commands.add('Close drawing'),
          onPreferences: () => commands.add('Preferences…'),
        ),
      ),
    );
    const fileCommands = [
      'New',
      'Open…',
      'Save',
      'Save as…',
      'Export .ggnome file',
      'Close drawing',
    ];
    for (final label in fileCommands) {
      await tester.tap(find.text('File'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(commands.last, label);
    }
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferences…'));
    await tester.pumpAndSettle();
    expect(commands, [...fileCommands, 'Preferences…']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BuildStatusBar follows view changes without a screen rebuild', (
    tester,
  ) async {
    await setTestViewport(tester);
    final editor = EditorController()..setViewportSize(const Size(600, 600));
    addTearDown(editor.dispose);
    var parentBuilds = 0;
    await tester.pumpWidget(
      testApp(
        child: Builder(
          builder: (context) {
            parentBuilds++;
            return BuildStatusBar(editor: editor);
          },
        ),
      ),
    );
    expect(find.text('100 ft'), findsOneWidget);
    editor.zoomAt(const Offset(300, 300), 4);
    await tester.pump();
    expect(find.text('50 ft'), findsOneWidget);
    expect(find.text('100 ft'), findsNothing);
    expect(parentBuilds, 1);
    expect(
      find.byTooltip('Camera height. Click to fit drawing'),
      findsOneWidget,
    );
  });

  testWidgets(
    'LayerActions can add a property without mounting the layer tree',
    (tester) async {
      final editor = EditorController();
      addTearDown(editor.dispose);
      await tester.pumpWidget(
        editorPanel(
          editor: editor,
          builder: (context) => LayerActions(editor: editor),
        ),
      );
      await addLayerFromMenu(tester, 'Property layer');
      expect(editor.selectedLayer!.kind, LayerKind.property);
      expect(editor.document.layers.length, 1);
    },
  );

  testWidgets(
    'extracted layer name keeps explicit commit, cancellation and undo',
    (tester) async {
      final editor = EditorController()..addLayer(LayerKind.property);
      addTearDown(editor.dispose);
      final id = editor.selectedLayerId!;
      await tester.pumpWidget(
        editorPanel(
          editor: editor,
          width: 264,
          builder: (context) => PropertiesBody(editor: editor),
        ),
      );
      expect(find.byType(LayerNameEditor), findsOneWidget);
      expect(find.byType(PropertyOptions), findsOneWidget);
      final name = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Layer name',
      );
      await tester.tap(find.byTooltip('Rename layer'));
      await tester.pumpAndSettle();
      await tester.enterText(name, 'North property');
      expect(editor.document.layers[id]!.name, 'Property 1');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(editor.document.layers[id]!.name, 'North property');
      expect(name, findsNothing);

      await tester.tap(find.byTooltip('Rename layer'));
      await tester.pumpAndSettle();
      await tester.enterText(name, 'Discarded name');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(editor.document.layers[id]!.name, 'North property');
      expect(editor.drafts['rename'], isNull);
      editor.undo();
      await tester.pumpAndSettle();
      expect(find.text('Property 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
