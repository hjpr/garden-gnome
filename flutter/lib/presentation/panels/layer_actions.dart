import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../application/tools.dart';
import '../../domain/layer.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import 'reference_upload.dart';

/// The Add layer button under the layer tree. It opens a menu of layer
/// kinds; a kind that cannot be added yet is greyed out, with the reason
/// as its tooltip.
class LayerActions extends StatelessWidget {
  const LayerActions({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    if (editor.mode == EditMode.plant) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: MenuAnchor(
        menuChildren: [
          _AddLayerItem(
            icon: 'add-plot.svg',
            label: 'Property layer',
            blocker: editor.addLayerBlocker(LayerKind.property),
            onPressed: () => editor.addLayer(LayerKind.property),
          ),
          for (final role in const [LayerRole.bed, LayerRole.planting])
            _AddLayerItem(
              icon: role == LayerRole.bed
                  ? 'ground-flat.svg'
                  : 'ground-grow.svg',
              label: '${role.label} layer',
              blocker: editor.addLayerBlocker(LayerKind.zone, role: role),
              onPressed: () => editor.addLayer(LayerKind.zone, role: role),
            ),
          _AddLayerItem(
            icon: 'add-reference.svg',
            label: 'Reference layer',
            blocker: editor.addReferenceBlocker,
            onPressed: () async {
              final problem = await uploadReferenceImage(editor);
              if (problem != null) editor.showNotice(problem);
            },
          ),
        ],
        builder: (context, menu, _) => Semantics(
          button: true,
          label: 'Add layer',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => menu.isOpen ? menu.close() : menu.open(),
            borderRadius: BorderRadius.circular(Metrics.radius),
            hoverColor: Palette.hover,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 14, color: Palette.ink),
                  SizedBox(width: 4),
                  Text(
                    'Add layer',
                    style: TextStyle(fontSize: 12, color: Palette.ink),
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

class _AddLayerItem extends StatelessWidget {
  const _AddLayerItem({
    required this.icon,
    required this.label,
    required this.blocker,
    required this.onPressed,
  });

  final String icon;
  final String label;
  final String? blocker;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = blocker == null;
    final item = MenuItemButton(
      leadingIcon: AppIcon(
        icon,
        size: 16,
        color: enabled ? Palette.ink : Palette.faint,
      ),
      onPressed: enabled ? onPressed : null,
      child: Text(label),
    );
    return enabled ? item : Tooltip(message: blocker, child: item);
  }
}
