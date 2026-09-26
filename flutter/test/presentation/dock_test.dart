import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/presentation/widgets/dock.dart';
import 'package:garden_gnome/presentation/widgets/panel.dart';

/// A right dock whose panels are plain boxes of a known height.
Widget dockFor(EditorController editor) => MaterialApp(
  home: Scaffold(
    body: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ListenableBuilder(
          listenable: editor,
          builder: (context, _) => Dock(
            side: DockSide.right,
            editor: editor,
            width: 260,
            buildPanel: (id, index) => DockPanel(
              index: index,
              title: id.label,
              expanded: !editor.settings.minimizedPanels.contains(id),
              onExpandedChanged: (open) => editor.setPanelMinimized(id, !open),
              child: const SizedBox(height: 80),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('dragging a panel by its grip reorders the dock', (tester) async {
    final editor = EditorController();
    await tester.pumpWidget(dockFor(editor));
    expect(editor.settings.docks.right, [PanelId.properties, PanelId.layers]);

    final grip = find.byIcon(Icons.drag_indicator).last;
    final gesture = await tester.startGesture(
      tester.getCenter(grip),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(editor.settings.docks.right, [PanelId.layers, PanelId.properties]);
  });

  testWidgets('clicking the rail folds the dock and clicking again opens it', (
    tester,
  ) async {
    final editor = EditorController();
    await tester.pumpWidget(dockFor(editor));
    await tester.tap(find.byIcon(Icons.keyboard_double_arrow_right));
    await tester.pumpAndSettle();
    expect(editor.settings.docks.isOpen(DockSide.right), isFalse);
    expect(
      find.text('LAYERS').hitTestable(),
      findsNothing,
      reason: 'folded panels cannot be clicked',
    );

    await tester.tap(find.byIcon(Icons.layers_outlined));
    await tester.pumpAndSettle();
    expect(editor.settings.docks.isOpen(DockSide.right), isTrue);
  });

  testWidgets('clicking a panel heading collapses it to the heading', (
    tester,
  ) async {
    final editor = EditorController();
    await tester.pumpWidget(dockFor(editor));
    await tester.tap(find.text('LAYERS'));
    await tester.pumpAndSettle();
    expect(editor.settings.minimizedPanels, {PanelId.layers});
  });
}
