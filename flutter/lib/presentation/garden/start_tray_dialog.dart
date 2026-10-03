import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/planting.dart';
import '../../domain/grow/variety.dart';
import '../theme.dart';

/// Asks what a variety is started in (flats with so many cells each, or
/// pots of one plant) and starts it in the greenhouse today. With no
/// [varietyId], the variety is picked in the dialog too.
Future<void> showStartTrayDialog(
  BuildContext context,
  GardenController garden, {
  String? varietyId,
}) => showDialog<void>(
  context: context,
  builder: (context) => _StartTrayDialog(garden: garden, varietyId: varietyId),
);

class _StartTrayDialog extends StatefulWidget {
  const _StartTrayDialog({required this.garden, this.varietyId});

  final GardenController garden;
  final String? varietyId;

  @override
  State<_StartTrayDialog> createState() => _StartTrayDialogState();
}

class _StartTrayDialogState extends State<_StartTrayDialog> {
  late String? _variety = widget.varietyId;
  GrowContainer _container = GrowContainer.flat;
  final _count = TextEditingController(text: '1');
  final _cells = TextEditingController(text: '72');

  int? _read(TextEditingController c) {
    final n = int.tryParse(c.text.trim());
    return n != null && n >= 1 ? n : null;
  }

  int? get _plants {
    final count = _read(_count);
    if (count == null) return null;
    if (_container == GrowContainer.pot) return count;
    final cells = _read(_cells);
    return cells == null ? null : count * cells;
  }

  @override
  void dispose() {
    _count.dispose();
    _cells.dispose();
    super.dispose();
  }

  void _start() {
    final variety = _variety;
    final count = _read(_count);
    if (variety == null || count == null || _plants == null) return;
    widget.garden.startInGreenhouse(
      variety,
      container: _container,
      containers: count,
      cellsPerFlat: _container == GrowContainer.flat ? _read(_cells)! : 1,
    );
    Navigator.pop(context);
  }

  Widget _number(String label, TextEditingController controller) => SizedBox(
    width: 120,
    child: TextField(
      key: ValueKey('tray-$label'),
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _start(),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profiles = widget.garden.profiles;
    final VarietyProfile? chosen = _variety == null
        ? null
        : widget.garden.profileOf(_variety!);
    final plants = _plants;
    final flat = _container == GrowContainer.flat;
    return AlertDialog(
      title: Text(
        chosen == null ? 'Start in greenhouse' : 'Start ${chosen.displayName}',
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.varietyId == null) ...[
              DropdownButtonFormField<String>(
                initialValue: _variety,
                decoration: const InputDecoration(labelText: 'Seed'),
                items: [
                  for (final p in profiles)
                    DropdownMenuItem(value: p.id, child: Text(p.displayName)),
                ],
                onChanged: (id) => setState(() => _variety = id),
              ),
              const SizedBox(height: 12),
            ],
            SegmentedButton<GrowContainer>(
              segments: [
                for (final c in GrowContainer.values)
                  ButtonSegment(value: c, label: Text('${c.label}s')),
              ],
              selected: {_container},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _container = s.first),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _number(flat ? 'Flats' : 'Pots', _count),
                if (flat) ...[
                  const SizedBox(width: 10),
                  _number('Cells per flat', _cells),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              plants == null
                  ? 'Enter whole numbers of 1 or more'
                  : '$plants ${plants == 1 ? 'plant' : 'plants'} to plant out',
              key: const ValueKey('tray-plants'),
              style: TextStyle(
                fontSize: 12.5,
                color: plants == null ? Palette.invalid : Palette.muted,
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
          onPressed: _variety != null && plants != null ? _start : null,
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// "2 flats × 72 = 144 plants", "6 pots", or the older cell count.
String trayDescription(Planting p) => switch (p.container) {
  GrowContainer.flat =>
    '${p.containers} ${p.containers == 1 ? 'flat' : 'flats'} × '
        '${p.cellsPerFlat} = ${p.plants} plants',
  GrowContainer.pot => '${p.containers} ${p.containers == 1 ? 'pot' : 'pots'}',
  null => p.count == null ? '' : '${p.count} cells',
};
