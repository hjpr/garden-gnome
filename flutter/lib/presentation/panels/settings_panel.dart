import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/workspace_settings.dart';
import '../../domain/units.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/property_controls.dart';

/// The Controls panel: view, units, snapping and guides. Changes apply at
/// once and are not part of the drawing's Undo history.
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
          title: 'VIEW',
          children: [
            _ViewModeSwitch(value: s.viewMode, onChanged: editor.setViewMode),
          ],
        ),
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

/// Wireframe or Render, as two halves of one segmented button, styled like
/// the tool buttons: the chosen half raised on white.
class _ViewModeSwitch extends StatelessWidget {
  const _ViewModeSwitch({required this.value, required this.onChanged});

  final ViewMode value;
  final ValueChanged<ViewMode> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius + 2),
    ),
    child: Row(
      children: [
        for (final mode in ViewMode.values) ...[
          if (mode.index > 0) const SizedBox(width: 3),
          Expanded(
            child: _ViewModeButton(
              mode: mode,
              selected: mode == value,
              onTap: () => onChanged(mode),
            ),
          ),
        ],
      ],
    ),
  );
}

class _ViewModeButton extends StatelessWidget {
  const _ViewModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final ViewMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? Palette.accent : Palette.ink;
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: selected ? Palette.paper : Palette.paper.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(Metrics.radius),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: selected ? Palette.paper : Palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(mode.icon, size: 15, color: colour),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: colour,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
