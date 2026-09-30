import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import 'calendar_presentation.dart';
import 'garden_card.dart';
import 'timeline.dart';

/// Harvest: when each crop in the ground comes ready and how long it
/// keeps picking. Greenhouse trays are included, faded, at their
/// expected dates, so the whole season is visible.
class HarvestBody extends StatelessWidget {
  const HarvestBody({super.key, required this.garden});

  final GardenController garden;

  @override
  Widget build(BuildContext context) {
    final today = garden.today;
    final inGround = garden.schedules(PlantingStage.inGround)
      ..sort((a, b) => a.harvest.start.compareTo(b.harvest.start));
    final trays = garden.schedules(PlantingStage.greenhouse)
      ..sort((a, b) => a.harvest.start.compareTo(b.harvest.start));
    final picking = inGround.where((s) => s.harvest.contains(today)).length;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: GardenCard(
        title: 'Harvest calendar',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$picking picking now',
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
            const SizedBox(width: 16),
            CalendarLegend([
              ('In ground', Palette.harvest),
              ('In greenhouse', Palette.harvest.withValues(alpha: 0.28)),
            ]),
          ],
        ),
        padding: EdgeInsets.zero,
        child: Timeline(
          range: calendarRange(today),
          today: today,
          labelWidth: 400,
          emptyText: 'Nothing planted yet.',
          rows: [
            for (final s in inGround) _row(s, today, inGround: true),
            for (final s in trays) _row(s, today, inGround: false),
          ],
        ),
      ),
    );
  }

  TimelineRow _row(
    PlantingSchedule s,
    DateTime today, {
    required bool inGround,
  }) {
    final h = s.harvest;
    final p = s.planting;
    final String status;
    if (today.isBefore(h.start)) {
      status =
          'ready ${formatDay(h.start)} (${daysBetween(today, h.start)} days)';
    } else if (!today.isAfter(h.end)) {
      status = 'picking until ${formatDay(h.end)}';
    } else {
      status = 'past since ${formatDay(h.end)}';
    }
    return TimelineRow(
      title: s.profile.displayName,
      subtitle: [
        inGround
            ? (p.startedIndoors
                  ? 'Planted out ${formatDay(p.plantedOutOn!)}'
                  : 'Sown ${formatDay(p.sownOn)}')
            : 'In greenhouse',
        if (p.location.isNotEmpty) p.location,
        status,
      ].join(' · '),
      trailing: inGround
          ? IconAction(
              iconData: Icons.done_all,
              label: 'Harvest finished',
              size: 26,
              onPressed: () => garden.finish(p.id),
            )
          : null,
      bars: [
        // Solid once in the ground; faded while still a guess in trays,
        // matching the legend.
        TimelineBar(
          span: h,
          ideal: inGround ? h : null,
          color: Palette.harvest,
          label: 'Harvest: $h',
        ),
      ],
    );
  }
}
