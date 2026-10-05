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

/// Grow > Transplant: every tray growing now and when it comes due to plant
/// out, beside the queue of what to start next (from Grow's greenhouse
/// windows).
class GreenhouseBody extends StatelessWidget {
  const GreenhouseBody({super.key, required this.garden});

  final GardenController garden;

  @override
  Widget build(BuildContext context) {
    final today = garden.today;
    // Soonest out first.
    final growing = garden.inGreenhouse()
      ..sort((a, b) => a.plantOut.start.compareTo(b.plantOut.start));
    final queue = [
      for (final r in garden.recommendations(
        kinds: const {WindowKind.greenhouseSow},
      ))
        if (r.timing != Timing.passed) r,
    ]..sort(bySoonestWindow);
    // One row per variety, soonest first; its later windows are more bars.
    final varieties = byVariety(queue);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: GardenCard(
              title: 'Calendar',
              trailing: CalendarLegend([
                // In the order a tray goes through them.
                ('Start window', Palette.greenhouse),
                ('Germinating', Palette.muted),
                ('Plant out', Palette.plantOut),
              ], alternates: true),
              padding: EdgeInsets.zero,
              child: Timeline(
                range: calendarRange(today),
                today: today,
                labelWidth: 400,
                seasons: frostFreeSeasons(garden.climate, today),
                sections: [
                  TimelineSection(
                    title: 'Growing',
                    emptyText: 'Nothing in the greenhouse.',
                    rows: [for (final s in growing) _row(s, today)],
                  ),
                  TimelineSection(
                    title: 'Upcoming',
                    emptyText: 'Nothing to start within a year.',
                    inactive: true,
                    rows: [
                      for (final windows in varieties)
                        _upcomingRow(context, windows),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 320,
            child: GardenCard(
              title: 'Start next',
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Anything the recommendations do not list is started
                  // here, with the seed picked in the dialog.
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: OutlinedButton.icon(
                      onPressed: garden.profiles.isEmpty
                          ? null
                          : () => showStartTrayDialog(context, garden),
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add plant'),
                    ),
                  ),
                  const Divider(),
                  Expanded(
                    child: varieties.isEmpty
                        ? const EmptyPanelText(
                            'Nothing to start within a year.',
                          )
                        : ListView(
                            children: [
                              for (final windows in varieties)
                                _QueueTile(
                                  garden: garden,
                                  recommendation: windows.first,
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A variety's greenhouse sowing windows, not started yet. The chip
  /// and text describe the soonest; every window is a bar.
  TimelineRow _upcomingRow(BuildContext context, List<Recommendation> windows) {
    final r = windows.first;
    return TimelineRow(
      title: r.profile.displayName,
      subtitle: windowSummary(r),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(r.timing.label, color: timingColor(r.timing)),
          const SizedBox(width: 4),
          IconAction(
            iconData: Icons.move_to_inbox_outlined,
            label: 'Start ${r.profile.variety.name} in greenhouse',
            size: 26,
            onPressed: () =>
                showStartTrayDialog(context, garden, varietyId: r.profile.id),
          ),
        ],
      ),
      bars: [for (final w in windows) windowBar(w, Palette.greenhouse)],
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
                    windowSummary(r),
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
              // Upcoming ones too: the start date can be set ahead.
              label: 'Start in greenhouse',
              size: 26,
              onPressed: () =>
                  showStartTrayDialog(context, garden, varietyId: r.profile.id),
            ),
          ],
        ),
      ),
    );
  }
}
