import 'package:flutter_test/flutter_test.dart';
import 'package:garden_gnome/application/editor_controller.dart';
import 'package:garden_gnome/application/workspace_settings.dart';
import 'package:garden_gnome/domain/layer.dart';

void main() {
  test('the right dock starts with Properties above Layers, both open', () {
    const layout = DockLayout();
    expect(layout.right, [PanelId.properties, PanelId.layers]);
    expect(layout.left, [
      PanelId.tools,
      PanelId.seeds,
      PanelId.operations,
      PanelId.settings,
    ]);
    expect(layout.isOpen(DockSide.left), isTrue);
    expect(layout.isOpen(DockSide.right), isTrue);
  });

  test('dragging a panel down moves it below the next one', () {
    const layout = DockLayout();
    // A reorderable list reports "insert before position 2" for a drag
    // from the top to the bottom of two items.
    final moved = layout.moved(DockSide.right, layout.right, 0, 2);
    expect(moved.right, [PanelId.layers, PanelId.properties]);
    expect(moved.left, layout.left, reason: 'the other dock is untouched');
    expect(moved.moved(DockSide.right, moved.right, 1, 0).right, layout.right);
  });

  test('hidden panels keep their place when the others are reordered', () {
    const layout = DockLayout(left: [PanelId.tools, PanelId.settings]);
    // Only Settings is visible, so there is nothing to reorder.
    expect(
      layout.moved(DockSide.left, [PanelId.settings], 0, 1).left,
      layout.left,
    );
  });

  test('a layout saved before Operations existed shows it after tools', () {
    final restored = DockLayout.restore(left: ['tools', 'settings']);
    expect(restored.left, [
      PanelId.tools,
      PanelId.seeds,
      PanelId.operations,
      PanelId.settings,
    ]);
  });

  test('a saved layout is restored, repairing unknown or missing panels', () {
    final restored = DockLayout.restore(
      left: ['settings', 'tools'],
      right: ['layers', 'unknown', 'tools'],
      folded: ['right'],
    );
    expect(restored.left, [
      PanelId.settings,
      PanelId.tools,
      PanelId.seeds,
      PanelId.operations,
    ]);
    expect(restored.right, [PanelId.layers, PanelId.properties]);
    expect(restored.isOpen(DockSide.right), isFalse);
  });

  test(
    'folding and reordering go through the editor and do not touch history',
    () {
      final editor = EditorController();
      editor.setDockOpen(DockSide.left, false);
      expect(editor.settings.docks.isOpen(DockSide.left), isFalse);
      editor.movePanel(DockSide.right, editor.settings.docks.right, 1, 0);
      expect(editor.settings.docks.right.first, PanelId.layers);
      expect(editor.canUndo, isFalse);
    },
  );

  test('selecting a layer expands a minimized Properties panel', () {
    final editor = EditorController();
    editor.setPanelMinimized(PanelId.properties, true);
    expect(editor.propertiesOpen, isFalse);
    editor.selectLayer(null);
    expect(
      editor.propertiesOpen,
      isFalse,
      reason: 'clearing the layer does not',
    );
    editor.addLayer(LayerKind.property);
    expect(editor.propertiesOpen, isTrue);
  });

  test('dock widths are clamped, kept while folded, and restored', () {
    final editor = EditorController();
    addTearDown(editor.dispose);
    expect(editor.settings.docks.widthOf(DockSide.left), 232);
    editor.setDockWidth(DockSide.left, 300);
    editor.setDockWidth(DockSide.right, 5000);
    expect(editor.settings.docks.widthOf(DockSide.right), DockLayout.maxWidth);
    editor.setDockOpen(DockSide.left, false);
    editor.setDockOpen(DockSide.left, true);
    expect(editor.settings.docks.widthOf(DockSide.left), 300);
    expect(editor.canUndo, isFalse);
    final restored = DockLayout.restore(widths: {'left': 300, 'right': 10});
    expect(restored.widthOf(DockSide.left), 300);
    expect(restored.widthOf(DockSide.right), DockLayout.minWidth);
  });
}
