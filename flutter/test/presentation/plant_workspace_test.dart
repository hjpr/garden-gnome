import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/tools.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/presentation/build_header.dart';
import 'package:garden_gnome/presentation/panels/layer_actions.dart';
import 'package:garden_gnome/presentation/panels/tools_panel.dart';
import 'package:garden_gnome/presentation/widgets/dock.dart';
import 'package:garden_gnome/presentation/widgets/panel.dart';

import '../support/widget_harness.dart';

Widget workspaceFor(EditorController editor) => testApp(
  child: ListenableBuilder(
    listenable: editor,
    builder: (context, _) => Column(
      children: [
        BuildHeader(
          title: 'Plant workspace',
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
        Expanded(
          child: Row(
            children: [
              for (final side in DockSide.values)
                Dock(
                  side: side,
                  editor: editor,
                  width: 260,
                  buildPanel: (id, index) => DockPanel(
                    index: index,
                    title: id.label,
                    expanded: !editor.settings.minimizedPanels.contains(id),
                    onExpandedChanged: (open) =>
                        editor.setPanelMinimized(id, !open),
                    child: SizedBox(height: 40, child: Text('${id.name} body')),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  ),
);

List<String> dockTitles(WidgetTester tester, DockSide side) => tester
    .widgetList<DockPanel>(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is Dock && w.side == side),
        matching: find.byType(DockPanel),
      ),
    )
    .map((panel) => panel.title)
    .toList();

Future<void> expectViewPanels(
  WidgetTester tester,
  List<PanelId> expected,
) async {
  await tester.tap(find.text('View'));
  await tester.pumpAndSettle();
  for (final id in PanelId.values) {
    expect(
      find.widgetWithText(CheckboxMenuButton, id.label),
      expected.contains(id) ? findsOneWidget : findsNothing,
      reason: '${id.label} availability in View',
    );
  }
  await tester.tap(find.text('View'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mode filtering preserves saved panel and dock preferences', (
    tester,
  ) async {
    await setTestViewport(tester);
    const settings = WorkspaceSettings(
      hiddenPanels: {PanelId.settings, PanelId.properties},
      minimizedPanels: {PanelId.tools, PanelId.operations},
      docks: DockLayout(
        left: [
          PanelId.settings,
          PanelId.seeds,
          PanelId.operations,
          PanelId.tools,
        ],
        right: [PanelId.layers, PanelId.properties],
        folded: {DockSide.right},
        widths: {DockSide.left: 300, DockSide.right: 280},
      ),
    );
    final editor = EditorController(settings: settings);
    addTearDown(editor.dispose);
    await tester.pumpWidget(workspaceFor(editor));
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), ['Operations', 'Drawing tools']);

    editor.setMode(EditMode.plant);
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), ['Seeds', 'Drawing tools']);
    expect(dockTitles(tester, DockSide.right), ['Layers']);
    expect(find.text('tools body'), findsNothing);
    expect(find.text('seeds body'), findsOneWidget);
    expect(find.text('LAYERS').hitTestable(), findsNothing);
    expect(find.byTooltip('Operations'), findsNothing);
    expect(find.byTooltip('Controls'), findsNothing);
    expect(editor.settings, same(settings));

    editor.setMode(EditMode.build);
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), ['Operations', 'Drawing tools']);
    expect(dockTitles(tester, DockSide.right), ['Layers']);
    expect(find.text('operations body'), findsNothing);
    expect(find.text('tools body'), findsNothing);
    expect(find.text('LAYERS').hitTestable(), findsNothing);
    expect(editor.settings, same(settings));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plant View can restore a user-hidden Seeds panel', (
    tester,
  ) async {
    await setTestViewport(tester);
    final editor = EditorController(
      settings: const WorkspaceSettings(hiddenPanels: {PanelId.seeds}),
    )..setMode(EditMode.plant);
    addTearDown(editor.dispose);
    await tester.pumpWidget(workspaceFor(editor));
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), ['Drawing tools']);
    expect(find.byTooltip('Seeds'), findsNothing);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    final seeds = find.widgetWithText(CheckboxMenuButton, 'Seeds');
    expect(tester.widget<CheckboxMenuButton>(seeds).value, isFalse);
    await tester.tap(seeds);
    await tester.pumpAndSettle();
    expect(editor.settings.hiddenPanels, isNot(contains(PanelId.seeds)));
    expect(dockTitles(tester, DockSide.left), ['Drawing tools', 'Seeds']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plant hides layer creation footer content until Build returns', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        width: 400,
        builder: (_) => LayerActions(editor: editor),
      ),
    );
    expect(find.text('Add layer'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);

    editor.setMode(EditMode.plant);
    await tester.pumpAndSettle();
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(tester.getSize(find.byType(LayerActions)).height, 0);

    editor.setMode(EditMode.build);
    await tester.pumpAndSettle();
    expect(find.text('Add layer'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plant tools show only Select and explain the Build boundary', (
    tester,
  ) async {
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(
      editorPanel(
        editor: editor,
        builder: (_) => ToolsBody(editor: editor),
      ),
    );
    for (final tool in Tool.values) {
      expect(find.text(tool.label), findsOneWidget);
    }
    expect(find.text('Marquee'), findsOneWidget);
    expect(find.text('Lasso'), findsOneWidget);

    editor.setMode(EditMode.plant);
    await tester.pumpAndSettle();
    expect(find.text('Select'), findsOneWidget);
    for (final tool in Tool.values.where((tool) => tool != Tool.select)) {
      expect(find.text(tool.label), findsNothing, reason: tool.label);
    }
    expect(find.text('SELECT FUNCTIONS'), findsNothing);
    expect(find.text('Marquee'), findsNothing);
    expect(find.text('Lasso'), findsNothing);
    expect(
      find.text(
        'Select plantings to plant seeds. Edit geometry in Build mode.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(editor.tool, Tool.select);

    editor.setMode(EditMode.build);
    await tester.pumpAndSettle();
    for (final tool in Tool.values) {
      expect(find.text(tool.label), findsOneWidget);
    }
    expect(find.text('Marquee'), findsOneWidget);
    expect(find.text('Lasso'), findsOneWidget);
    expect(find.textContaining('Edit geometry in Build'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Plant focuses docks and View menu, then restores Build', (
    tester,
  ) async {
    await setTestViewport(tester);
    final editor = EditorController();
    addTearDown(editor.dispose);
    await tester.pumpWidget(workspaceFor(editor));
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), [
      'Drawing tools',
      'Operations',
      'Controls',
    ]);

    editor.setMode(EditMode.plant);
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), ['Drawing tools', 'Seeds']);
    expect(dockTitles(tester, DockSide.right), ['Properties', 'Layers']);
    await expectViewPanels(tester, [
      PanelId.tools,
      PanelId.seeds,
      PanelId.properties,
      PanelId.layers,
    ]);

    editor.setMode(EditMode.build);
    await tester.pumpAndSettle();
    expect(dockTitles(tester, DockSide.left), [
      'Drawing tools',
      'Operations',
      'Controls',
    ]);
    expect(dockTitles(tester, DockSide.right), ['Properties', 'Layers']);
    await expectViewPanels(tester, [
      PanelId.tools,
      PanelId.operations,
      PanelId.settings,
      PanelId.properties,
      PanelId.layers,
    ]);
    expect(tester.takeException(), isNull);
  });
}
