import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../panels/day_field.dart';
import '../theme.dart';

/// Asks which planned planting to sow and when (today unless changed),
/// then records the sowing on that planting layer. Only plantings with a
/// seed and nothing sown yet are offered: planning on the map comes
/// first. [choices] narrows the list, e.g. to the plantings of one
/// recommended variety; with a single choice it is fixed.
Future<void> showSowDialog(
  BuildContext context,
  GardenController garden, {
  List<PlannedSowing>? choices,
}) => showDialog<void>(
  context: context,
  builder: (context) =>
      _SowDialog(garden: garden, choices: choices ?? garden.plannedSowings()),
);

class _SowDialog extends StatefulWidget {
  const _SowDialog({required this.garden, required this.choices});

  final GardenController garden;
  final List<PlannedSowing> choices;

  @override
  State<_SowDialog> createState() => _SowDialogState();
}

class _SowDialogState extends State<_SowDialog> {
  late String? _layer = widget.choices.length == 1
      ? widget.choices.single.layerId
      : null;
  late DateTime _on = widget.garden.today;

  PlannedSowing? get _chosen {
    for (final c in widget.choices) {
      if (c.layerId == _layer) return c;
    }
    return null;
  }

  void _sow() {
    final layer = _layer;
    if (layer == null) return;
    widget.garden.sowPlanting(layer, on: _on);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final chosen = _chosen;
    final fixed = widget.choices.length == 1;
    final plants = chosen?.plants;
    return AlertDialog(
      title: Text(
        fixed && chosen != null
            ? 'Sow ${chosen.profile.displayName}'
            : 'Sow a planting',
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fixed)
              Text(
                chosen!.layerName,
                key: const ValueKey('sow-planting'),
                style: const TextStyle(fontSize: 13, color: Palette.muted),
              )
            else
              DropdownButtonFormField<String>(
                initialValue: _layer,
                decoration: const InputDecoration(labelText: 'Planting'),
                items: [
                  for (final c in widget.choices)
                    DropdownMenuItem(
                      value: c.layerId,
                      child: Text(
                        '${c.layerName} · ${c.profile.displayName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) => setState(() => _layer = id),
              ),
            const SizedBox(height: 12),
            Text('Sown', style: sectionTitleStyle),
            const SizedBox(height: 4),
            DayField(
              label: 'Sown',
              day: _on,
              enabled: true,
              onChanged: (day) => setState(() => _on = day),
            ),
            const SizedBox(height: 12),
            // Worked out from the planting's spacing and lines; change
            // those in Plan to change it.
            Text(
              chosen == null
                  ? '—'
                  : plants == null || plants == 0
                  ? 'No plants fit this planting yet'
                  : '$plants ${plants == 1 ? 'plant' : 'plants'}',
              key: const ValueKey('sow-plants'),
              style: TextStyle(
                fontSize: 12.5,
                color: chosen != null && (plants ?? 0) == 0
                    ? Palette.invalid
                    : Palette.muted,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: chosen != null ? _sow : null,
          child: const Text('Sow'),
        ),
      ],
    );
  }
}
