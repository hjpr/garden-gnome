import 'dart:math' as math;

import '../../domain/grow/day.dart';

/// Which stretch of days a [Timeline] shows: where the view starts and
/// how many days it spans, both in fractional days so a drag moves it
/// smoothly. Counted from the calendar's home range start.
class TimelineView {
  const TimelineView({required this.start, required this.days});

  /// Days from the home range start to the left edge.
  final double start;

  /// Days across the chart.
  final double days;

  /// Narrowest and widest spans the wheel zooms to.
  static const minDays = 14.0;
  static const maxDays = 1100.0;

  /// How much one wheel notch zooms.
  static const zoomStep = 1.2;

  /// [days] zoomed by [factor] (above 1 shows more days) keeping the day
  /// at [anchor] (0 = left edge, 1 = right edge) where it is.
  TimelineView zoomed(double factor, double anchor) {
    final next = (days * factor).clamp(minDays, maxDays);
    final pinned = start + anchor * days;
    return TimelineView(start: pinned - anchor * next, days: next);
  }

  /// Moved by [fraction] of the chart width; positive moves later.
  TimelineView panned(double fraction) =>
      TimelineView(start: start + fraction * days, days: days);

  /// The whole days at least partly on screen.
  DayWindow window(DateTime home) => DayWindow(
    addDays(home, start.floor()),
    addDays(home, math.max(start.floor(), (start + days).ceil() - 1)),
  );

  @override
  bool operator ==(Object other) =>
      other is TimelineView && other.start == start && other.days == days;

  @override
  int get hashCode => Object.hash(start, days);
}
