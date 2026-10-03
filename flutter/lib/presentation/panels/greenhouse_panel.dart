import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting.dart';
import '../garden/start_tray_dialog.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/panel.dart';

/// Plant mode's greenhouse list: every flat and pot growing on this farm,
/// with how many plants each gives and when it is due out, and a button
/// to start more.
class GreenhouseBody extends StatelessWidget {
  const GreenhouseBody({super.key, required this.garden});

  final GardenController? garden;

  @override
  Widget build(BuildContext context) {
    final garden = this.garden;
    if (garden == null) return const EmptyPanelText('No Seed Vault.');
    return ListenableBuilder(
      listenable: garden,
      builder: (context, _) {
        final growing = garden.schedules(PlantingStage.greenhouse);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (growing.isEmpty)
              const EmptyPanelText('Nothing growing.')
            else
              for (final s in growing) _TrayTile(garden: garden, schedule: s),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: garden.profiles.isEmpty
                  ? null
                  : () => showStartTrayDialog(context, garden),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Flats or pots'),
            ),
          ],
        );
      },
    );
  }
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({required this.garden, required this.schedule});

  final GardenController garden;
  final PlantingSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final p = schedule.planting;
    final out = schedule.plantOut;
    final today = garden.today;
    final due = today.isBefore(out.start)
        ? 'out ${formatDay(out.start)}'
        : !today.isAfter(out.end)
        ? 'ready'
        : 'overdue';
    final plants = p.plants;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            p.container == GrowContainer.pot
                ? Icons.local_florist_outlined
                : Icons.grid_on,
            size: 15,
            color: Palette.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  schedule.profile.variety.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5),
                ),
                Text(
                  [
                    if (trayDescription(p) case final t when t.isNotEmpty) t,
                    due,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ],
            ),
          ),
          if (plants != null)
            Tooltip(
              message: 'Plants available',
              child: Text(
                '$plants',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Palette.ink,
                ),
              ),
            ),
          IconAction(
            iconData: Icons.delete_outline,
            label: 'Remove ${schedule.profile.variety.name}',
            size: 24,
            onPressed: () => garden.removePlanting(p.id),
          ),
        ],
      ),
    );
  }
}
