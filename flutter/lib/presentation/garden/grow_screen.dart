import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting.dart';
import '../../domain/grow/planting_windows.dart';
import '../../domain/grow/variety.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import '../widgets/panel.dart' show EmptyPanelText;
import 'calendar_presentation.dart';
import 'climate_bar.dart';
import 'garden_card.dart';
import 'sow_dialog.dart';
import 'status_chip.dart';
import 'timeline.dart';

/// Grow: what is sown in place, beside the queue of what to sow next.
/// The same layout as Greenhouse, for direct sowing; greenhouse starts
/// are recommended in Greenhouse.
///
/// Only planting layers on the map can be sown: planning comes first.
/// Varieties with a sowing window coming up but no planting yet are
/// shown greyed, as a prompt to plan them in Plan.
class GrowBody extends StatelessWidget {
  const GrowBody({super.key, required this.garden});

  final GardenController garden;

  /// Says why an unplanned variety cannot be sown from Grow.
  static const planFirst = 'Add it to a planting in Plan first';

  @override
  Widget build(BuildContext context) {
    final today = garden.today;
    final windows = [
      for (final r in garden.recommendations(
        kinds: const {WindowKind.directSow},
      ))
        if (r.timing != Timing.passed) r,
    ];
    final planned = garden.plannedSowings();
    final plannedVarieties = {for (final p in planned) p.profile.id};
    List<Recommendation> windowsOf(VarietyProfile profile) => [
      for (final r in windows)
        if (r.profile.id == profile.id) r,
    ];
    final unplanned = [
      for (final r in windows)
        if (!plannedVarieties.contains(r.profile.id)) r,
    ];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClimateBar(garden: garden),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: GardenCard(
                    title: 'Growing now',
                    trailing: CalendarLegend([
                      // In the order a crop goes through them.
                      ('Not planned', Palette.faint),
                      ('Sow window', Palette.directSow),
                      ('Germinating', Palette.muted),
                      ('Harvest', Palette.harvest),
                    ]),
                    padding: EdgeInsets.zero,
                    child: Timeline(
                      range: calendarRange(today),
                      today: today,
                      labelWidth: 400,
                      emptyText: garden.record.varieties.isEmpty
                          ? 'Add varieties in the Seed Vault to see what '
                                'to plant.'
                          : 'Nothing sown or planned.',
                      rows: [
                        for (final s in garden.directSowings()) _sownRow(s),
                        for (final p in planned)
                          _plannedRow(context, p, windowsOf(p.profile)),
                        // Below the real plantings, so the calendar
                        // reads plan first.
                        for (final r in unplanned) _unplannedRow(r),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 320,
                  child: _StartNext(
                    garden: garden,
                    windows: windows,
                    planned: planned,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TimelineRow _sownRow(PlantingSchedule s) {
    final p = s.planting;
    final harvest = s.harvest;
    final plants =
        p.plants ??
        (p.layerId == null ? null : garden.plannedPlantsOf(p.layerId!));
    return TimelineRow(
      title: s.profile.displayName,
      subtitle: [
        'Sown ${formatDay(p.sownOn)}',
        ?garden.layerNameOf(p),
        if (plants != null) '$plants plants',
        'harvest ${formatDay(harvest.start)}',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // A sowing dated ahead is planned, not yet in the ground.
          StatusChip(
            garden.today.isBefore(p.sownOn) ? 'Planned' : 'Sown',
            color: Palette.directSow,
          ),
          const SizedBox(width: 4),
          IconAction(
            iconData: Icons.delete_outline,
            label: 'Remove sowing',
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
          span: harvest,
          ideal: harvest,
          color: Palette.harvest,
          label: 'Harvest: $harvest',
        ),
      ],
    );
  }

  TimelineRow _plannedRow(
    BuildContext context,
    PlannedSowing p,
    List<Recommendation> windows,
  ) {
    return TimelineRow(
      title: p.profile.displayName,
      subtitle: [
        p.layerName,
        if (p.plants case final n?) '$n plants',
        if (windows.isNotEmpty) timingDetail(windows.first),
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (windows.isNotEmpty)
            StatusChip(
              windows.first.timing.label,
              color: timingColor(windows.first.timing),
            ),
          const SizedBox(width: 4),
          IconAction(
            iconData: Icons.grass,
            label: 'Sow ${p.layerName}',
            size: 26,
            onPressed: () => showSowDialog(context, garden, choices: [p]),
          ),
        ],
      ),
      bars: [for (final r in windows) _windowBar(r, Palette.directSow)],
    );
  }

  TimelineRow _unplannedRow(Recommendation r) => TimelineRow(
    title: r.profile.displayName,
    subtitle: '${r.window.season.label} · ${timingDetail(r)} · not planned',
    trailing: const IconAction(
      iconData: Icons.grass,
      label: 'Sow',
      tooltip: planFirst,
      size: 26,
      onPressed: null,
    ),
    bars: [_windowBar(r, Palette.faint)],
  );

  static TimelineBar _windowBar(Recommendation r, Color color) => TimelineBar(
    span: r.window.span,
    ideal: r.window.ideal,
    color: color,
    label:
        '${r.window.kind.label}: ${r.window.span}'
        '\nIdeal: ${r.window.ideal}',
  );
}

/// Add plant, then the direct-sow recommendations: planned ones sow
/// from here, unplanned ones are greyed until planned in Plan.
class _StartNext extends StatelessWidget {
  const _StartNext({
    required this.garden,
    required this.windows,
    required this.planned,
  });

  final GardenController garden;
  final List<Recommendation> windows;
  final List<PlannedSowing> planned;

  @override
  Widget build(BuildContext context) {
    return GardenCard(
      title: 'Start next',
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Tooltip(
              message: planned.isEmpty ? GrowBody.planFirst : '',
              child: OutlinedButton.icon(
                onPressed: planned.isEmpty
                    ? null
                    : () => showSowDialog(context, garden),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add plant'),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: windows.isEmpty
                ? const EmptyPanelText('Nothing to sow within two months.')
                : ListView(
                    children: [
                      for (final r in windows)
                        _QueueTile(
                          garden: garden,
                          recommendation: r,
                          planned: [
                            for (final p in planned)
                              if (p.profile.id == r.profile.id) p,
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile({
    required this.garden,
    required this.recommendation,
    required this.planned,
  });

  final GardenController garden;
  final Recommendation recommendation;

  /// This variety's plantings waiting to be sown.
  final List<PlannedSowing> planned;

  @override
  Widget build(BuildContext context) {
    final r = recommendation;
    final isPlanned = planned.isNotEmpty;
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
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isPlanned ? Palette.ink : Palette.faint,
                    ),
                  ),
                  Text(
                    [
                      r.window.season.label,
                      timingDetail(r),
                      if (isPlanned)
                        planned.map((p) => p.layerName).join(', ')
                      else
                        'not planned',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Palette.muted,
                    ),
                  ),
                ],
              ),
            ),
            StatusChip(
              r.timing.label,
              color: isPlanned ? timingColor(r.timing) : Palette.faint,
            ),
            IconAction(
              iconData: Icons.grass,
              label: 'Sow ${r.profile.variety.name}',
              tooltip: isPlanned ? null : GrowBody.planFirst,
              size: 26,
              onPressed: isPlanned
                  ? () => showSowDialog(context, garden, choices: planned)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
