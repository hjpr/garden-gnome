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
/// Grow > Sow: the same layout as Transplant, for direct sowing; seed
/// started in trays is in Transplant.
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
    ]..sort(bySoonestWindow);
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
    // Both sections run soonest first. Sown crops go by when picking
    // starts; upcoming ones by when their best sowing time starts, planned
    // and unplanned together so the order is the order of the season. A
    // planned planting with no window in reach sorts as due now.
    // Cover crops sit with them, by when they are next due: terminated,
    // or sown when no end is set.
    final growing = <(DateTime, TimelineRow)>[
      for (final s in garden.inGround()) (s.harvest.start, _sownRow(s)),
      for (final c in garden.coverBeds())
        (c.cover.terminatedOn ?? c.cover.sownOn!, _coverRow(c)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    final upcoming = <(DateTime, TimelineRow)>[
      for (final p in planned)
        if (windowsOf(p.profile) case final w)
          (
            w.isEmpty ? today : w.first.window.ideal.start,
            _plannedRow(context, p, w),
          ),
      // One row per variety; its later windows are more bars.
      for (final w in byVariety(unplanned))
        (w.first.window.ideal.start, _unplannedRow(w)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));
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
                    title: 'Calendar',
                    trailing: CalendarLegend([
                      // In the order a crop goes through them.
                      ('Not planned', Palette.faint),
                      ('Sow window', Palette.directSow),
                      ('Germinating', Palette.muted),
                      ('Harvest', Palette.harvest),
                      ('Cover crop', Palette.groundCover),
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
                          emptyText: 'Nothing sown.',
                          rows: [for (final (_, row) in growing) row],
                        ),
                        TimelineSection(
                          title: 'Upcoming',
                          emptyText: garden.record.varieties.isEmpty
                              ? 'Add varieties in the Seed Vault to see '
                                    'what to plant.'
                              : 'Nothing to sow within a year.',
                          inactive: true,
                          rows: [for (final (_, row) in upcoming) row],
                        ),
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
        if (p.startedIndoors && p.plantedOutOn != null)
          'Planted out ${formatDay(p.plantedOutOn!)}'
        else
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
            iconData: Icons.done_all,
            label: 'Harvest finished',
            size: 26,
            onPressed: () => garden.finish(p.id),
          ),
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

  /// A Cover bed's cover crop, from Sown to Terminated (to today while
  /// no end is set: Johnny's gives no length to invent one from).
  TimelineRow _coverRow(CoverBed c) {
    final sown = c.cover.sownOn!;
    final end = c.cover.terminatedOn;
    final today = garden.today;
    return TimelineRow(
      title: c.cover.name,
      subtitle: [
        'Sown ${formatDay(sown)}',
        c.layerName,
        if (end != null) 'terminate ${formatDay(end)}',
      ].join(' · '),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StatusChip(
            today.isBefore(sown) ? 'Planned' : 'Cover',
            color: Palette.groundCover,
          ),
          const SizedBox(width: 4),
          IconAction(
            iconData: Icons.content_cut,
            label: 'Terminated today',
            size: 26,
            onPressed: () => garden.terminateCover(c.layerId),
          ),
        ],
      ),
      bars: [
        TimelineBar(
          span: DayWindow(sown, end ?? (today.isAfter(sown) ? today : sown)),
          color: Palette.groundCover,
          label: end == null
              ? 'Cover crop sown ${formatDay(sown)}'
              : 'Cover crop ${formatDay(sown)} – ${formatDay(end)}',
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
        if (windows.isNotEmpty) windowSummary(windows.first),
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
      bars: [for (final r in windows) windowBar(r, Palette.directSow)],
    );
  }

  TimelineRow _unplannedRow(List<Recommendation> windows) => TimelineRow(
    title: windows.first.profile.displayName,
    subtitle: '${windowSummary(windows.first)} · not planned',
    trailing: const IconAction(
      iconData: Icons.grass,
      label: 'Sow',
      tooltip: planFirst,
      size: 26,
      onPressed: null,
    ),
    bars: [for (final r in windows) windowBar(r, Palette.faint)],
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
                ? const EmptyPanelText('Nothing to sow within a year.')
                : ListView(
                    children: [
                      // One tile per variety, at its soonest window.
                      for (final w in byVariety(windows))
                        _QueueTile(
                          garden: garden,
                          recommendation: w.first,
                          planned: [
                            for (final p in planned)
                              if (p.profile.id == w.first.profile.id) p,
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
                      windowSummary(r),
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
