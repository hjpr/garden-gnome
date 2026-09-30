import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/tools.dart';
import '../theme.dart';

/// Build | Plant, as a two-part switch in the header.
///
/// Build lays out the land. Plant locks everything except grow zones and
/// shows the Seeds panel, so seeds can be dragged onto them.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius + 1),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final mode in EditMode.values)
          _Segment(
            key: ValueKey(mode),
            label: mode.label,
            icon: mode == EditMode.build
                ? Icons.architecture_outlined
                : Icons.spa_outlined,
            selected: editor.mode == mode,
            onTap: () => editor.setMode(mode),
          ),
      ],
    ),
  );
}

class _Segment extends StatelessWidget {
  const _Segment({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? Palette.accent : Palette.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label mode',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          // See-through WHITE, not Colors.transparent (see-through black),
          // so the fade never passes through grey.
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: colour),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: colour,
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
