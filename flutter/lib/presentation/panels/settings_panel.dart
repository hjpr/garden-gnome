import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../domain/units.dart';
import '../widgets/panel.dart';

/// The Controls panel: units, snapping and guides. Changes apply at once
/// and are not part of the drawing's Undo history.
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
          title: 'UNITS',
          children: [
            PropertyRow(
              label: 'Dimensions',
              child: CompactDropdown<Units>(
                label: 'Dimensions',
                value: s.units,
                items: {for (final u in Units.values) u: u.symbol},
                onChanged: (u) => editor.updateSettings(s.copyWith(units: u)),
              ),
            ),
            PropertyRow(
              label: 'Area',
              child: CompactDropdown<AreaUnits>(
                label: 'Area',
                value: s.areaUnits,
                items: {for (final u in AreaUnits.values) u: u.symbol},
                onChanged: (u) =>
                    editor.updateSettings(s.copyWith(areaUnits: u)),
              ),
            ),
          ],
        ),
        PropertyGroup(
          title: 'SNAPPING',
          children: [
            _SwitchRow(
              label: 'Enabled',
              value: s.snappingEnabled,
              onChanged: (v) =>
                  editor.updateSettings(s.copyWith(snappingEnabled: v)),
            ),
          ],
        ),
        PropertyGroup(
          title: 'GUIDES',
          children: [
            _SwitchRow(
              label: 'Enabled',
              value: s.guidesEnabled,
              onChanged: (v) =>
                  editor.updateSettings(s.copyWith(guidesEnabled: v)),
            ),
          ],
        ),
      ],
    );
  }
}

/// A labelled on/off switch sized to sit in a property row.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => PropertyRow(
    label: label,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Transform.scale(
        scale: 0.75,
        alignment: Alignment.centerLeft,
        child: Switch(value: value, onChanged: onChanged),
      ),
    ),
  );
}
