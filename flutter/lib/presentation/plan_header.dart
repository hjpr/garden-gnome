import 'package:flutter/material.dart';

import '../application/app_tools.dart';
import '../application/editor_controller.dart';
import '../application/workspace_settings.dart';
import 'tool_switcher.dart';
import 'theme.dart';
import 'widgets/drawing_title.dart';
import 'widgets/mode_switch.dart';

class PlanHeader extends StatelessWidget {
  const PlanHeader({
    super.key,
    required this.title,
    required this.dirty,
    required this.editor,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onSaveAs,
    required this.onExport,
    required this.onClose,
    required this.onPreferences,
    this.navigator,
  });

  final AppNavigator? navigator;
  final String title;
  final bool dirty;
  final EditorController editor;
  final VoidCallback onNew, onOpen, onSave, onSaveAs, onExport, onClose;
  final VoidCallback onPreferences;

  @override
  Widget build(BuildContext context) {
    MenuItemButton item(
      String label,
      VoidCallback? onPressed, {
      String? shortcut,
      IconData? icon,
    }) => MenuItemButton(
      onPressed: onPressed,
      leadingIcon: SizedBox(
        width: 18,
        child: icon == null ? null : Icon(icon, size: 16, color: Palette.muted),
      ),
      trailingIcon: shortcut == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                shortcut,
                style: const TextStyle(fontSize: 12, color: Palette.faint),
              ),
            ),
      child: Text(label),
    );

    final docks = editor.settings.docks;
    return Container(
      height: Metrics.headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: Palette.paper,
        border: Border(bottom: BorderSide(color: Palette.panelBorder)),
      ),
      child: Row(
        children: [
          if (navigator case final navigator?)
            ToolSwitcher(navigator: navigator)
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.eco, size: 20, color: Palette.accent),
            ),
          MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(Colors.transparent),
              elevation: WidgetStatePropertyAll(0),
              padding: WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              SubmenuButton(
                menuChildren: [
                  item(
                    'New',
                    onNew,
                    shortcut: 'Ctrl+N',
                    icon: Icons.note_add_outlined,
                  ),
                  item(
                    'Open…',
                    onOpen,
                    shortcut: 'Ctrl+O',
                    icon: Icons.folder_open_outlined,
                  ),
                  const Divider(),
                  item(
                    'Save',
                    onSave,
                    shortcut: 'Ctrl+S',
                    icon: Icons.save_outlined,
                  ),
                  item('Save as…', onSaveAs, shortcut: 'Ctrl+Shift+S'),
                  const Divider(),
                  item(
                    'Export .ggnome file',
                    onExport,
                    icon: Icons.download_outlined,
                  ),
                  const Divider(),
                  item('Close drawing', onClose, icon: Icons.close),
                ],
                child: const Text('File'),
              ),
              SubmenuButton(
                menuChildren: [
                  item(
                    editor.undoLabel == null
                        ? 'Undo'
                        : 'Undo ${editor.undoLabel}',
                    editor.canUndo ? editor.undo : null,
                    shortcut: 'Ctrl+Z',
                    icon: Icons.undo,
                  ),
                  item(
                    editor.redoLabel == null
                        ? 'Redo'
                        : 'Redo ${editor.redoLabel}',
                    editor.canRedo ? editor.redo : null,
                    shortcut: 'Ctrl+Shift+Z',
                    icon: Icons.redo,
                  ),
                  const Divider(),
                  item(
                    'Delete',
                    editor.canDeleteSelection ? editor.deleteSelection : null,
                    shortcut: 'Del',
                    icon: Icons.delete_outline,
                  ),
                  const Divider(),
                  item(
                    'Preferences…',
                    onPreferences,
                    icon: Icons.settings_outlined,
                  ),
                ],
                child: const Text('Edit'),
              ),
              SubmenuButton(
                menuChildren: [
                  for (final side in DockSide.values)
                    CheckboxMenuButton(
                      value: docks.isOpen(side),
                      onChanged: (v) => editor.setDockOpen(side, v ?? true),
                      child: Text(
                        side == DockSide.left ? 'Left panels' : 'Right panels',
                      ),
                    ),
                  const Divider(),
                  for (final id in PanelId.values)
                    if (id.availableIn(editor.mode))
                      CheckboxMenuButton(
                        value: !editor.settings.hiddenPanels.contains(id),
                        onChanged: (v) => editor.setPanelVisible(id, v ?? true),
                        child: Text(id.label),
                      ),
                  const Divider(),
                  item(
                    'Fit drawing',
                    editor.fitDrawing,
                    icon: Icons.fit_screen_outlined,
                  ),
                  item(
                    'Reset view',
                    editor.resetView,
                    icon: Icons.center_focus_strong_outlined,
                  ),
                ],
                child: const Text('View'),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Center(
              child: DrawingTitle(
                title: title,
                dirty: dirty,
                onRename: editor.renameDrawing,
              ),
            ),
          ),
          ModeSwitch(editor: editor),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
