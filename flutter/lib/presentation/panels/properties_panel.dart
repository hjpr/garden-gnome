import 'package:flutter/material.dart';

import '../../application/editor_controller.dart';
import '../../domain/land_rules.dart';
import '../../domain/layer.dart';
import '../theme.dart';
import '../widgets/panel.dart';
import '../widgets/property_controls.dart';
import 'feature_properties.dart';
import 'reference_properties.dart';
import 'layer_fields.dart';
import 'property_options.dart';
import 'zone_options.dart';

/// Settings for the selected layer: its name, status, and options.
class PropertiesBody extends StatelessWidget {
  const PropertiesBody({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    if (editor.showsFeature) {
      return FeatureProperties(
        key: ValueKey(('feature-properties', editor.selectedFeature!.id)),
        editor: editor,
        feature: editor.selectedFeature!,
      );
    }
    if (editor.showsReference) {
      return ReferenceProperties(
        key: const ValueKey('reference-properties'),
        editor: editor,
      );
    }
    final layer = editor.selectedLayer;
    if (layer == null) {
      return const EmptyPanelText('Nothing selected.');
    }
    final document = editor.document;
    final invalid = !document.isValid(layer.id);
    final reason = document.inactiveReason(layer.id);
    final status = invalid
        ? 'Invalid: $reason'
        : (reason == null ? 'Active' : 'Inactive: $reason');
    // A locked layer's details are shown read-only.
    final lockNotice = editor.lockNotice(layer.id);
    final editable = lockNotice == null;
    return Column(
      key: ValueKey(layer.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (layer.properties case ZoneProperties(:final ground))
          _GroundTypeBar(ground: ground),
        LayerNameEditor(editor: editor, layer: layer, editable: editable),
        _StatusBadge(
          text: status,
          colour: invalid
              ? Palette.invalid
              : (reason == null ? Palette.valid : Palette.muted),
        ),
        PropertyRow(
          label: 'Net area',
          child: Text(
            editor.settings.areaUnits.format(document.netAreaOf(layer.id)),
            key: const ValueKey('net-area'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (lockNotice != null)
          _LockedNote(
            text: lockNotice,
            onUnlock: layer.locked
                ? () => editor.setLayerLocked(layer.id, false)
                : null,
          ),
        switch (layer.properties) {
          PropertyProperties p => PropertyOptions(
            editor: editor,
            layer: layer,
            properties: p,
            editable: editable,
          ),
          ZoneProperties p => ZoneOptions(
            editor: editor,
            layer: layer,
            properties: p,
            editable: editable,
          ),
        },
      ],
    );
  }
}

class _GroundTypeBar extends StatelessWidget {
  const _GroundTypeBar({required this.ground});

  final GroundType? ground;

  @override
  Widget build(BuildContext context) {
    final color = switch (ground) {
      null => Palette.groundZone,
      GroundType.flat => Palette.groundFlat,
      GroundType.row => Palette.groundRow,
      GroundType.grow => Palette.groundGrow,
    };
    final label = ground?.label ?? 'Zone';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: 'Ground type: $label',
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('ground-type-bar'),
          color: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            label,
            style: TextStyle(
              color: ground == GroundType.row ? Palette.ink : Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small dot and label showing whether the layer counts as land.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.text, required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, right: 6),
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        ),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: colour)),
        ),
      ],
    ),
  );
}

/// A quiet note that the layer is locked, with a shortcut to unlock it
/// when the lock is on this layer (not on one around it).
class _LockedNote extends StatelessWidget {
  const _LockedNote({required this.text, this.onUnlock});

  final String text;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 4, bottom: 2),
    padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
    decoration: BoxDecoration(
      color: Palette.field,
      borderRadius: BorderRadius.circular(Metrics.radius),
    ),
    child: Row(
      children: [
        const Icon(Icons.lock_outline, size: 14, color: Palette.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            onUnlock == null ? text : 'Locked. Changes are turned off',
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
        ),
        if (onUnlock != null)
          TextButton(onPressed: onUnlock, child: const Text('Unlock')),
      ],
    ),
  );
}
