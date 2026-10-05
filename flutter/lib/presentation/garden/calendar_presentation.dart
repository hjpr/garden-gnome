import 'package:flutter/material.dart';

import '../../domain/grow/climate.dart';
import '../../domain/grow/day.dart';
import '../../domain/grow/planting_windows.dart';
import '../theme.dart';
import 'timeline.dart';

/// How far either side of today the growing calendars look.
const calendarReachDays = 61;

/// The span the growing calendars show around [today].
DayWindow calendarRange(DateTime today) => DayWindow(
  addDays(today, -calendarReachDays),
  addDays(today, calendarReachDays),
);

/// Calendar sections list soonest first, so the order alone says what
/// comes next even when the dates are off screen. Recommendations go by
/// when their best time starts.
int bySoonestWindow(Recommendation a, Recommendation b) {
  final ideal = a.window.ideal.start.compareTo(b.window.ideal.start);
  return ideal != 0
      ? ideal
      : a.window.span.start.compareTo(b.window.span.start);
}

/// [sorted] windows grouped one list per variety, so a variety with
/// several windows in reach (spring and fall, this year and next) is one
/// row. Groups keep the order of each variety's first window, so sorting
/// with [bySoonestWindow] first gives soonest variety first.
List<List<Recommendation>> byVariety(List<Recommendation> sorted) {
  final groups = <String, List<Recommendation>>{};
  for (final r in sorted) {
    (groups[r.profile.id] ??= []).add(r);
  }
  return groups.values.toList();
}

/// The frost-free seasons (last spring frost to first fall frost) from
/// the year before [today] to two years after, for the calendar's band.
List<DayWindow> frostFreeSeasons(Climate climate, DateTime today) => [
  for (var year = today.year - 1; year <= today.year + 2; year++)
    if (climate.fallFrost.inYear(year) case final fall
        when fall.isAfter(climate.springFrost.inYear(year)))
      DayWindow(climate.springFrost.inYear(year), fall),
];

/// One window as a calendar bar in [color]: solid with its best part
/// darker, or outlined and hatched when it needs a tunnel.
TimelineBar windowBar(Recommendation r, Color color) {
  final w = r.window;
  return TimelineBar(
    span: w.span,
    ideal: w.ideal,
    color: color,
    outlined: w.isAlternate,
    label: [
      '${w.kind.label} · ${w.label}',
      w.isAlternate ? 'Sow: ${w.span}' : '${w.span}\nIdeal: ${w.ideal}',
      if (w.winter?.tierLabel case final tier?) "Johnny's: $tier",
    ].join('\n'),
  );
}

/// "Spring · ideal until Oct 12", or "Winter harvest · needs high tunnel
/// · opens Aug 2": what the window is and where it stands.
String windowSummary(Recommendation r) =>
    '${r.window.label} · ${timingDetail(r)}';

Color windowColor(WindowKind kind) => switch (kind) {
  WindowKind.directSow => Palette.directSow,
  WindowKind.greenhouseSow => Palette.greenhouse,
  WindowKind.plantOut => Palette.plantOut,
};

Color timingColor(Timing t) => switch (t) {
  Timing.ideal => Palette.valid,
  Timing.early || Timing.late => Palette.caution,
  Timing.upcoming => Palette.muted,
  Timing.passed => Palette.faint,
};

/// "until Oct 12", "ideal from Oct 3" and so on: what a timing means for
/// this window, in a few words.
String timingDetail(Recommendation r) {
  final w = r.window;
  return switch (r.timing) {
    Timing.ideal => 'ideal until ${formatDay(w.ideal.end)}',
    Timing.early => 'ideal from ${formatDay(w.ideal.start)}',
    Timing.late => 'closes ${formatDay(w.span.end)}',
    Timing.upcoming => 'opens ${formatDay(w.span.start)}',
    Timing.passed => 'closed ${formatDay(w.span.end)}',
  };
}

/// A key for the calendar colours. [alternates] adds the outlined style
/// of windows that need a tunnel.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend(this.items, {super.key, this.alternates = false});

  final List<(String, Color)> items;
  final bool alternates;

  static Widget _entry(Widget swatch, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      swatch,
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
    ],
  );

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final (label, color) in items)
        _entry(
          Container(
            width: 12,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          label,
        ),
      if (alternates)
        _entry(
          Container(
            width: 12,
            height: 8,
            decoration: BoxDecoration(
              border: Border.all(color: Palette.muted, width: 1.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          'Needs tunnel',
        ),
    ],
  );
}
