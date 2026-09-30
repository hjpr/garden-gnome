import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/previews.dart';
import '../../application/selection_box.dart';
import '../theme.dart';

/// The status bar's reading of the selection box: its width and height in
/// the user's units, and the angle while a rotation is dragged. Values
/// follow a scale or rotate drag live. Empty when there is no box.
class SelectionReadout extends StatelessWidget {
  const SelectionReadout({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    // Drag previews arrive on viewChanges, which does not rebuild the
    // screen, so the readout listens for it itself.
    return ListenableBuilder(
      listenable: editor.viewChanges,
      builder: (context, _) {
        final box = selectionBoxOf(editor);
        if (box == null) return const SizedBox.shrink();
        final units = editor.settings.units;
        final preview = editor.preview;
        final angle = preview is MovePreview ? preview.box?.angle : null;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Value(label: 'W', value: units.format(box.width)),
            const SizedBox(width: 12),
            _Value(label: 'H', value: units.format(box.height)),
            if (angle != null) ...[
              const SizedBox(width: 12),
              _Value(
                label: '∠',
                value: '${(angle * 180 / math.pi).toStringAsFixed(1)}°',
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A small caps label followed by its value, like the zoom readout.
class _Value extends StatelessWidget {
  const _Value({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: sectionTitleStyle),
      const SizedBox(width: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 12,
          color: Palette.ink,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}
