import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/tools.dart';
import '../../domain/layer.dart';
import '../theme.dart';

/// Add property / zone buttons shown under the layer tree.
class LayerActions extends StatelessWidget {
  const LayerActions({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    if (editor.mode == EditMode.plant) return const SizedBox.shrink();

    Widget add(LayerKind kind) {
      final blocker = editor.addLayerBlocker(kind);
      final name = kind.label;
      final enabled = blocker == null;
      final colour = enabled ? Palette.ink : Palette.faint;
      return Expanded(
        child: Tooltip(
          message: blocker ?? 'Add ${name.toLowerCase()}',
          child: Semantics(
            button: true,
            enabled: enabled,
            label: 'Add ${name.toLowerCase()}',
            excludeSemantics: true,
            child: InkWell(
              onTap: enabled ? () => editor.addLayer(kind) : null,
              borderRadius: BorderRadius.circular(Metrics.radius),
              hoverColor: Palette.hover,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add, size: 14, color: colour),
                    const SizedBox(width: 4),
                    Text(name, style: TextStyle(fontSize: 12, color: colour)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(children: [add(LayerKind.property), add(LayerKind.zone)]),
    );
  }
}
