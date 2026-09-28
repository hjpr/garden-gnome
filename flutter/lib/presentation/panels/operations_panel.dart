import 'package:flutter/material.dart';

import '../../application/alignment.dart';
import '../../application/editor_controller.dart';
import '../../domain/region.dart';
import '../theme.dart';
import '../widgets/button_grid.dart';
import '../widgets/panel.dart';

/// One-shot actions on the selected shapes. Unlike the drawing tools,
/// these do not wait for canvas clicks: select the shapes first (Select
/// with Shift-click, or Shift-click in Layers), then press a button.
class OperationsBody extends StatelessWidget {
  const OperationsBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final canBoolean = editor.booleanBlocker == null;
    final canAlign = editor.alignBlocker == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyGroup(
          title: 'BOOLEAN',
          children: [
            ButtonGrid(
              children: [
                for (final operation in BooleanOperation.values)
                  _OperationButton(
                    label: operation == BooleanOperation.union
                        ? 'Union'
                        : 'Subtract',
                    icon: operation == BooleanOperation.union
                        ? 'union.svg'
                        : 'subtract.svg',
                    enabled: canBoolean,
                    onHover: (on) =>
                        editor.previewBoolean(on ? operation : null),
                    onTap: () => editor.runBoolean(operation),
                  ),
              ],
            ),
          ],
        ),
        PropertyGroup(
          title: 'ALIGN',
          children: [
            // Three to a row, like Drawing tools: Left Right Top, then
            // Bottom Center.
            ButtonGrid(
              children: [
                for (final edge in AlignEdge.values)
                  _OperationButton(
                    label: edge.label,
                    icon: edge.icon,
                    enabled: canAlign,
                    onHover: (on) => editor.previewAlign(on ? edge : null),
                    onTap: () => editor.runAlign(edge),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// One operation button. Hovering previews the result on the canvas;
/// pressing commits it as one Undo step.
class _OperationButton extends StatelessWidget {
  const _OperationButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onHover,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool enabled;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = enabled ? Palette.ink : Palette.faint;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) {
          if (enabled) onHover(true);
        },
        onExit: (_) => onHover(false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                children: [
                  AppIcon(icon, size: 18, color: colour),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colour),
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
