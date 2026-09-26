import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/workspace_settings.dart';
import '../../domain/units.dart';
import '../widgets/panel.dart';

/// Units, snapping, and menu size. Changes apply immediately and are not
/// part of the drawing's Undo history.
class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final s = editor.settings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyGroup(
          title: 'MEASURE',
          children: [
            PropertyRow(
              label: 'Units',
              child: CompactDropdown<Units>(
                label: 'Units',
                value: s.units,
                items: {for (final u in Units.values) u: u.symbol},
                onChanged: (u) => editor.updateSettings(s.copyWith(units: u)),
              ),
            ),
          ],
        ),
        PropertyGroup(
          title: 'SNAPPING',
          children: [
            PropertyRow(
              label: 'Enabled',
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: 0.75,
                  alignment: Alignment.centerLeft,
                  child: Switch(
                    value: s.snappingEnabled,
                    onChanged: (v) =>
                        editor.updateSettings(s.copyWith(snappingEnabled: v)),
                  ),
                ),
              ),
            ),
            PropertyRow(
              label: 'Snap to',
              child: CompactDropdown<SnapMode>(
                label: 'Snap to',
                value: s.snapMode,
                items: {for (final m in SnapMode.values) m: m.label},
                onChanged: (m) =>
                    editor.updateSettings(s.copyWith(snapMode: m)),
              ),
            ),
          ],
        ),
        PropertyGroup(
          title: 'VIEWPORT',
          children: [
            PropertyRow(
              label: 'Menu size',
              child: CompactDropdown<MenuScale>(
                label: 'Menu size',
                value: s.menuScale,
                items: {for (final m in MenuScale.values) m: m.label},
                onChanged: (m) =>
                    editor.updateSettings(s.copyWith(menuScale: m)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
