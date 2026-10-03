import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting.dart';
import '../../domain/grow/planting_windows.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/panel.dart' show EmptyPanelText;
import 'calendar_presentation.dart';
import 'garden_card.dart';
import 'start_tray_dialog.dart';
import 'status_chip.dart';
import 'timeline.dart';

/// Greenhouse: every tray growing now and when it comes due to plant
/// out, beside the queue of what to start next (from Grow's greenhouse
/// windows).
class GreenhouseBody extends StatelessWidget {
  const GreenhouseBody({super.key, required this.garden});

  final GardenController garden;

  @override
  Widget build(BuildContext context) {
    final today = garden.today;
    final growing = garden.inGreenhouse();
    final queue = [
      for (final r in garden.recommendations(
        kinds: const {WindowKind.greenhouseSow},
      ))
        if (r.timing != Timing.passed) r,
    ];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GardenCard(
              title: 'Growing now',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CalendarLegend([
                    ('Germinating', Palette.muted),
                    ('Plant out', Palette.plantOut),
                  ]),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: garden.profiles.isEmpty
                        ? null
                        : () => showStartTrayDialog(context, garden),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Flats or pots'),
                  ),
                ],
              ),
              padding: EdgeInsets.zero,
              child: Timeline(
                range: calendarRange(today),
                today: today,
                labelWidth: 400,
                emptyText: 'Nothing in the greenhouse.',
                rows: [for (final s in growing) _row(s, today)],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 320,
            child: GardenCard(
              title: 'Start next',
              padding: EdgeInsets.zero,
              child: queue.isEmpty
                  ? const EmptyPanelText('Nothing to start within two months.')
                  : ListView(
                      children: [
                        for (final r in queue)
                          _QueueTile(garden: garden, recommendation: r),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  TimelineRow _row(PlantingSchedule s, DateTime today) {
    final out = s.plantOut;
    final String status;
    final Color color;
    if (today.isBefore(out.start)) {
      status =
          'due ${formatDay(out.start)}'
          ' (${daysBetween(today, out.start)} days)';
      color = Palette.muted;
    } else if (!today.isAfter(out.end)) {
      status = 'ready to plant out';
      color = Palette.valid;
    } else {
      status = 'overdue since ${formatDay(out.end)}';
      color = Palette.invalid;
    }
    final p = s.planting;
    return TimelineRow(
      title: s.profile.displayName,
      subtitle: [
        'Sown ${formatDay(p.sownOn)}',
        if (trayDescription(p) case final tray when tray.isNotEmpty) tray,
        status,
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            color == Palette.muted
                ? 'Growing'
                : color == Palette.valid
                ? 'Ready'
                : 'Overdue',
            color: color,
          ),
          const SizedBox(width: 4),
          IconAction(
            iconData: Icons.south_east,
            label: 'Planted out today',
            size: 26,
            onPressed: () => garden.plantOut(p.id),
          ),
          IconAction(
            iconData: Icons.delete_outline,
            label: 'Remove planting',
            size: 26,
            onPressed: () => garden.removePlanting(p.id),
          ),
        ],
      ),
      bars: [
        if (s.germination case final g?)
          TimelineBar(
            span: DayWindow(p.sownOn, g.end),
            ideal: g,
            color: Palette.muted,
            label: 'Sown ${formatDay(p.sownOn)}\nUp by $g',
          ),
        TimelineBar(
          span: out,
          ideal: out,
          color: Palette.plantOut,
          label: 'Plant out: $out',
        ),
      ],
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({required this.garden, required this.recommendation});

  final GardenController garden;
  final Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final r = recommendation;
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.rule)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.profile.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${r.window.season.label} · ${timingDetail(r)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(r.timing.label, color: timingColor(r.timing)),
            IconAction(
              iconData: Icons.move_to_inbox_outlined,
              label: 'Start in greenhouse today',
              size: 26,
              onPressed: r.timing.isOpen
                  ? () => showStartTrayDialog(
                      context,
                      garden,
                      varietyId: r.profile.id,
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
