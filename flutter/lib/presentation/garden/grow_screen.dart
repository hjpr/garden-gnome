import 'package:flutter/material.dart';

import '../../application/garden_controller.dart';
import '../../domain/grow/planting_windows.dart';
import '../theme.dart';
import '../widgets/icon_controls.dart';
import 'calendar_presentation.dart';
import 'climate_bar.dart';
import 'garden_card.dart';
import 'start_tray_dialog.dart';
import 'status_chip.dart';
import 'timeline.dart';

/// Grow: what to sow in the ground or start in the greenhouse within two
/// months of today, as a list in order of urgency and a calendar.
class GrowBody extends StatefulWidget {
  const GrowBody({super.key, required this.garden});

  final GardenController garden;

  @override
  State<GrowBody> createState() => _GrowBodyState();
}

class _GrowBodyState extends State<GrowBody> {
  /// Which windows to list. Plant-out is followed in Greenhouse, per
  /// planting, so Grow lists the two ways of sowing.
  Set<WindowKind> _kinds = {WindowKind.directSow, WindowKind.greenhouseSow};
  bool _showPassed = false;

  GardenController get _garden => widget.garden;

  @override
  Widget build(BuildContext context) {
    final today = _garden.today;
    final all = _garden.recommendations(kinds: _kinds);
    final shown = [
      for (final r in all)
        if (_showPassed || r.timing != Timing.passed) r,
    ];
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClimateBar(garden: _garden),
          const SizedBox(height: 10),
          Expanded(
            child: GardenCard(
              title: 'Planting calendar',
              padding: EdgeInsets.zero,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final kind in [
                    WindowKind.directSow,
                    WindowKind.greenhouseSow,
                  ])
                    _KindToggle(
                      kind: kind,
                      on: _kinds.contains(kind),
                      onChanged: (on) => setState(
                        () => _kinds = on
                            ? {..._kinds, kind}
                            : ({..._kinds}..remove(kind)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  _KindToggle.plain(
                    label: 'Closed',
                    on: _showPassed,
                    onChanged: (on) => setState(() => _showPassed = on),
                  ),
                ],
              ),
              child: Timeline(
                range: calendarRange(today),
                today: today,
                labelWidth: 330,
                emptyText: _garden.record.varieties.isEmpty
                    ? 'Add varieties in the Seed Vault to see what to plant.'
                    : 'Nothing to plant within two months.',
                rows: [
                  for (final r in shown)
                    TimelineRow(
                      title: r.profile.displayName,
                      subtitle:
                          '${r.window.kind.label} · ${r.window.season.label}'
                          ' · ${timingDetail(r)}',
                      trailing: _RowActions(garden: _garden, recommendation: r),
                      bars: [
                        TimelineBar(
                          span: r.window.span,
                          ideal: r.window.ideal,
                          color: windowColor(r.window.kind),
                          label:
                              '${r.window.kind.label}: ${r.window.span}'
                              '\nIdeal: ${r.window.ideal}',
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A timing chip and the button that records the sowing.
class _RowActions extends StatelessWidget {
  const _RowActions({required this.garden, required this.recommendation});

  final GardenController garden;
  final Recommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final r = recommendation;
    final indoors = r.window.kind == WindowKind.greenhouseSow;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        StatusChip(r.timing.label, color: timingColor(r.timing)),
        const SizedBox(width: 4),
        IconAction(
          iconData: indoors ? Icons.move_to_inbox_outlined : Icons.grass,
          label: indoors ? 'Start in greenhouse' : 'Sow today',
          size: 26,
          onPressed: !r.timing.isOpen
              ? null
              : indoors
              ? () => showStartTrayDialog(
                  context,
                  garden,
                  varietyId: r.profile.id,
                )
              : () => garden.sow(r.profile.id, indoors: false),
        ),
      ],
    );
  }
}

class _KindToggle extends StatelessWidget {
  const _KindToggle({
    required WindowKind this.kind,
    required this.on,
    required this.onChanged,
  }) : label = null;

  const _KindToggle.plain({
    required String this.label,
    required this.on,
    required this.onChanged,
  }) : kind = null;

  final WindowKind? kind;
  final String? label;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = kind == null ? Palette.muted : windowColor(kind!);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: FilterChip(
        avatar: kind == null
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: on ? color : color.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
        label: Text(label ?? kind!.label, style: const TextStyle(fontSize: 12)),
        selected: on,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        selectedColor: Palette.wash,
        side: BorderSide(color: on ? Palette.accent : Palette.panelBorder),
        onSelected: onChanged,
      ),
    );
  }
}
