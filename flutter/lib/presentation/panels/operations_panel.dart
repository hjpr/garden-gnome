import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../domain/region.dart';
import '../theme.dart';
import '../widgets/panel.dart';

/// One-shot actions on the selected shapes. Unlike the drawing tools,
/// these do not wait for canvas clicks: select the shapes first (Select
/// with Shift-click, or Shift-click in Layers), then press a button.
class OperationsBody extends StatelessWidget {
  const OperationsBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final blocker = editor.booleanBlocker;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PropertyGroup(
          title: 'BOOLEAN',
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Palette.field,
                borderRadius: BorderRadius.circular(Metrics.radius + 2),
              ),
              child: Row(
                children: [
                  for (final (i, operation)
                      in BooleanOperation.values.indexed) ...[
                    if (i > 0) const SizedBox(width: 3),
                    Expanded(
                      child: _OperationButton(
                        editor: editor,
                        operation: operation,
                        enabled: blocker == null,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A Union or Subtract button. Hovering previews the result on the
/// canvas; pressing commits it as one Undo step.
class _OperationButton extends StatelessWidget {
  const _OperationButton({
    required this.editor,
    required this.operation,
    required this.enabled,
  });

  final EditorController editor;
  final BooleanOperation operation;
  final bool enabled;

  String get _label =>
      operation == BooleanOperation.union ? 'Union' : 'Subtract';

  String get _icon =>
      operation == BooleanOperation.union ? 'union.svg' : 'subtract.svg';

  @override
  Widget build(BuildContext context) {
    final colour = enabled ? Palette.ink : Palette.faint;
    return Semantics(
      button: true,
      enabled: enabled,
      label: _label,
      excludeSemantics: true,
      child: MouseRegion(
        onEnter: (_) {
          if (enabled) editor.previewBoolean(operation);
        },
        onExit: (_) => editor.previewBoolean(null),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? () => editor.runBoolean(operation) : null,
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                children: [
                  AppIcon(_icon, size: 18, color: colour),
                  const SizedBox(height: 3),
                  Text(
                    _label,
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
