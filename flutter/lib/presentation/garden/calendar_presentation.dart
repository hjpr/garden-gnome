import 'package:flutter/material.dart';

import '../../domain/grow/day.dart';
import '../../domain/grow/planting_windows.dart';
import '../theme.dart';

/// How far either side of today the growing calendars look.
const calendarReachDays = 61;

/// The span the growing calendars show around [today].
DayWindow calendarRange(DateTime today) => DayWindow(
  addDays(today, -calendarReachDays),
  addDays(today, calendarReachDays),
);

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

/// A key for the calendar colours.
class CalendarLegend extends StatelessWidget {
  const CalendarLegend(this.items, {super.key});

  final List<(String, Color)> items;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 14,
    runSpacing: 4,
    children: [
      for (final (label, color) in items)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
        ),
    ],
  );
}
