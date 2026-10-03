import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../application/planting.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting.dart';
import '../garden/start_tray_dialog.dart';
import '../garden/status_chip.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/panel.dart';

/// Plant mode's greenhouse list: every flat and pot growing on this farm,
/// ready or not, with how many plants each gives and when it is due out.
/// Each one drags onto a planting to plan where it goes. Flats and pots
/// are started in the Greenhouse tool.
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
        final growing = garden.inGreenhouse();
        if (growing.isEmpty) return const EmptyPanelText('Nothing growing.');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final s in growing)
              _TrayTile(
                key: ValueKey(s.planting.id),
                garden: garden,
                schedule: s,
              ),
          ],
        );
      },
    );
  }
}

/// Where a greenhouse sowing stands today.
enum TrayStatus {
  growing('Growing', Palette.muted),
  ready('Ready', Palette.valid),
  overdue('Overdue', Palette.invalid);

  const TrayStatus(this.label, this.color);

  final String label;
  final Color color;

  static TrayStatus of(PlantingSchedule s, DateTime today) {
    final out = s.plantOut;
    if (today.isBefore(out.start)) return growing;
    if (!today.isAfter(out.end)) return ready;
    return overdue;
  }
}

class _TrayTile extends StatelessWidget {
  const _TrayTile({super.key, required this.garden, required this.schedule});

  final GardenController garden;
  final PlantingSchedule schedule;

  @override
  Widget build(BuildContext context) {
    final p = schedule.planting;
    final out = schedule.plantOut;
    final today = garden.today;
    final status = TrayStatus.of(schedule, today);
    final planned = p.plantedOutOn;
    final place = garden.layerNameOf(p);
    final when = planned != null
        ? '${place ?? 'out'} ${formatDay(planned)}'
        : status == TrayStatus.growing
        ? 'ready ${formatDay(out.start)}'
        : null;
    // The dock is narrow: the plant count here, the flats breakdown in
    // the tooltip.
    final plants = p.plants;
    final tile = _TrayLabel(
      schedule: schedule,
      detail: [
        if (plants != null) '$plants ${plants == 1 ? 'plant' : 'plants'}',
        ?when,
      ].join(' · '),
      status: status,
    );
    final tray = trayDescription(p);
    return Draggable<TrayDrag>(
      data: TrayDrag(
        plantingId: p.id,
        profile: schedule.profile,
        outOn: out.start.isBefore(today) ? today : out.start,
      ),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        elevation: 6,
        color: Palette.paper,
        borderRadius: BorderRadius.circular(Metrics.radius),
        child: SizedBox(width: 220, child: tile),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: tile),
      child: Tooltip(
        message: [if (tray.isNotEmpty) tray, 'Drag onto a planting'].join('\n'),
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          cursor: SystemMouseCursors.grab,
          child: Row(
            children: [
              Expanded(child: tile),
              IconAction(
                iconData: Icons.delete_outline,
                label: 'Remove ${schedule.profile.variety.name}',
                size: 24,
                onPressed: () => garden.removePlanting(p.id),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrayLabel extends StatelessWidget {
  const _TrayLabel({
    required this.schedule,
    required this.detail,
    required this.status,
  });

  final PlantingSchedule schedule;
  final String detail;
  final TrayStatus status;

  @override
  Widget build(BuildContext context) {
    final p = schedule.planting;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        schedule.profile.variety.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Palette.ink,
                        ),
                      ),
                    ),
                    StatusChip(status.label, color: status.color),
                  ],
                ),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
