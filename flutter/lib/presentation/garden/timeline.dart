import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/grow/day.dart';
import '../theme.dart';
import 'timeline_view.dart';

/// One coloured stretch on a [Timeline] row. [ideal], when given, is
/// drawn solid and the rest of [span] lighter.
class TimelineBar {
  const TimelineBar({
    required this.span,
    required this.color,
    this.ideal,
    this.label,
  });

  final DayWindow span;
  final DayWindow? ideal;
  final Color color;

  /// Tooltip text.
  final String? label;
}

class TimelineRow {
  const TimelineRow({
    required this.title,
    required this.bars,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.selected = false,
  });

  final String title;
  final String? subtitle;
  final List<TimelineBar> bars;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool selected;
}

/// A calendar strip: today's date, month headings, one row per item with
/// its windows as bars over week (major) and day (minor) lines, and a
/// line at today. Over the chart the mouse wheel zooms around the
/// pointer and a drag moves through time; Today brings the view back.
/// Shared by Grow, Greenhouse and Harvest so all three read the same way.
class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.range,
    required this.today,
    required this.rows,
    this.labelWidth = 220,
    this.emptyText = 'Nothing to show.',
  });

  /// The view shown at first and after Today.
  final DayWindow range;
  final DateTime today;
  final List<TimelineRow> rows;
  final double labelWidth;
  final String emptyText;

  static const rowHeight = 40.0;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  /// The zoomed or moved view; null shows [Timeline.range].
  TimelineView? _moved;
  bool _dragging = false;

  /// Width of the chart at the last layout, for turning drags into days.
  double _chartWidth = 1;

  DateTime get _home => widget.range.start;

  TimelineView get _view =>
      _moved ??
      TimelineView(
        start: 0,
        days: (daysBetween(widget.range.start, widget.range.end) + 1)
            .toDouble(),
      );

  DateTime get today => widget.today;
  List<TimelineRow> get rows => widget.rows;
  double get labelWidth => widget.labelWidth;
  static const rowHeight = Timeline.rowHeight;

  void _onSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final along = event.localPosition.dx - labelWidth;
    // Over the names the wheel scrolls the list as usual.
    if (along < 0) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final dy = event.scrollDelta.dy;
      if (dy == 0) return;
      final factor = dy > 0 ? TimelineView.zoomStep : 1 / TimelineView.zoomStep;
      final anchor = (along / _chartWidth).clamp(0.0, 1.0);
      setState(() => _moved = _view.zoomed(factor, anchor));
    });
  }

  void _onDrag(DragUpdateDetails details) {
    final dx = details.primaryDelta ?? 0;
    if (dx == 0) return;
    // Dragging right pulls earlier days into view, like a map.
    setState(() => _moved = _view.panned(-dx / _chartWidth));
  }

  Widget _header() {
    final weekday = const [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
      'Friday', 'Saturday', 'Sunday',
    ][today.weekday - 1];
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: labelWidth),
          Expanded(
            child: Text(
              '$weekday, ${formatDay(today)}, ${today.year}',
              key: const ValueKey('calendar-today'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          // Kept in the layout while hidden so the date never shifts.
          Visibility.maintain(
            visible: _moved != null,
            child: TextButton(
              onPressed: () => setState(() => _moved = null),
              child: const Text('Today'),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }

  /// The chart part of a row or the heading: shows a grab hand, since a
  /// drag there moves through time.
  Widget _chartCell(Widget child) => MouseRegion(
    cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = (constraints.maxWidth - labelWidth).clamp(
          120.0,
          double.infinity,
        );
        _chartWidth = chartWidth;
        final scale = _Scale(_home, _view, chartWidth);
        final showsToday = scale.shows(today);
        return Listener(
          onPointerSignal: _onSignal,
          child: GestureDetector(
            // Empty stretches of the chart drag too.
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: _onDrag,
            onHorizontalDragEnd: (_) => setState(() => _dragging = false),
            onHorizontalDragCancel: () => setState(() => _dragging = false),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                SizedBox(
                  height: 32,
                  child: Row(
                    children: [
                      SizedBox(width: labelWidth),
                      _chartCell(
                        SizedBox(
                          width: chartWidth,
                          height: 32,
                          child: ClipRect(
                            child: CustomPaint(
                              painter: _MonthsPainter(scale, today, showsToday),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: rows.isEmpty
                      ? Center(child: _EmptyText(widget.emptyText))
                      : Stack(
                          children: [
                            ListView.builder(
                              itemCount: rows.length,
                              itemExtent: rowHeight,
                              itemBuilder: (context, i) => _row(rows[i], scale),
                            ),
                            if (showsToday)
                              Positioned(
                                left: labelWidth + scale.x(today) - 1,
                                top: 0,
                                bottom: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    width: 2,
                                    color: Palette.ink,
                                  ),
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _row(TimelineRow row, _Scale scale) {
    return Material(
      color: row.selected ? Palette.wash : Palette.paper,
      child: InkWell(
        onTap: row.onTap,
        hoverColor: Palette.hover,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Palette.rule)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (row.subtitle != null)
                              Text(
                                row.subtitle!,
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
                      ?row.trailing,
                    ],
                  ),
                ),
              ),
              _chartCell(
                SizedBox(
                  width: scale.width,
                  height: rowHeight,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(painter: _DayLinesPainter(scale)),
                        ),
                        for (final bar in row.bars) ..._bar(bar, scale),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bar(TimelineBar bar, _Scale scale) {
    final shown = scale.window;
    if (bar.span.end.isBefore(shown.start) ||
        bar.span.start.isAfter(shown.end)) {
      return const [];
    }
    Widget piece(DayWindow w, double alpha, double height) {
      final left = scale.clampedX(w.start);
      final width = (scale.clampedX(addDays(w.end, 1)) - left).clamp(
        3.0,
        double.infinity,
      );
      return Positioned(
        left: left,
        width: width,
        top: (rowHeight - height) / 2,
        height: height,
        child: Tooltip(
          message: bar.label ?? w.toString(),
          child: Container(
            decoration: BoxDecoration(
              color: bar.color.withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
    }

    return [
      piece(bar.span, 0.28, 14),
      if (bar.ideal case final ideal?) piece(ideal, 0.95, 14),
    ];
  }
}

/// Turns days into chart pixels for one view and chart width.
class _Scale {
  _Scale(this.home, this.view, this.width);

  final DateTime home;
  final TimelineView view;
  final double width;

  late final DayWindow window = view.window(home);

  double get dayPixels => width / view.days;

  /// Where the start of [day] falls; may be off either edge.
  double x(DateTime day) =>
      (daysBetween(home, day) - view.start) / view.days * width;

  double clampedX(DateTime day) => x(day).clamp(0.0, width);

  bool shows(DateTime day) {
    final at = x(day);
    return at >= 0 && at <= width;
  }

  @override
  bool operator ==(Object other) =>
      other is _Scale &&
      other.home == home &&
      other.view == view &&
      other.width == width;

  @override
  int get hashCode => Object.hash(home, view, width);
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12.5,
      fontStyle: FontStyle.italic,
      color: Palette.faint,
    ),
  );
}

/// Month names and ticks across the top of the timeline, day numbers
/// when zoomed in far enough, and the TODAY badge.
class _MonthsPainter extends CustomPainter {
  _MonthsPainter(this.scale, this.today, this.showsToday);

  final _Scale scale;
  final DateTime today;
  final bool showsToday;

  /// Day numbers need at least this many pixels per day.
  static const _dayNumberPixels = 20.0;

  TextPainter _text(String text, TextStyle style) => TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void paint(Canvas canvas, Size size) {
    final range = scale.window;
    final tick = Paint()
      ..color = Palette.panelBorder
      ..strokeWidth = 1;
    var month = DateTime.utc(range.start.year, range.start.month);
    while (!month.isAfter(range.end)) {
      final next = DateTime.utc(month.year, month.month + 1);
      final start = scale.x(month);
      final left = start.clamp(0.0, size.width);
      final right = scale.clampedX(next);
      if (start >= 0) {
        canvas.drawLine(Offset(start, 0), Offset(start, size.height), tick);
      }
      // January always says which year starts there; zoomed far out,
      // where "Jan 2027" no longer fits, the year alone does.
      final names = month.month == 1
          ? ['${monthName(month.month)} ${month.year}', '${month.year}']
          : [monthName(month.month)];
      for (final name in names) {
        final label = _text(name, sectionTitleStyle);
        final fits = right - left > label.width + 8;
        // Top half: the TODAY badge and day numbers take the bottom half,
        // so they never collide.
        if (fits) label.paint(canvas, Offset(left + 6, 1));
        label.dispose();
        if (fits) break;
      }
      month = next;
    }
    if (scale.dayPixels >= _dayNumberPixels) {
      for (var d = range.start; !d.isAfter(range.end); d = addDays(d, 1)) {
        if (showsToday && d == today) continue;
        final number = _text(
          '${d.day}',
          const TextStyle(fontSize: 10, color: Palette.faint),
        );
        final centre = scale.x(d) + scale.dayPixels / 2;
        number.paint(
          canvas,
          Offset(centre - number.width / 2, size.height - number.height - 1),
        );
        number.dispose();
      }
    }
    if (!showsToday) return;
    final t = scale.x(today);
    final todayLabel = _text(
      'TODAY',
      const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 0.5,
      ),
    );
    final box = Rect.fromCenter(
      center: Offset(t, size.height - 8),
      width: todayLabel.width + 8,
      height: 14,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = Palette.ink,
    );
    todayLabel.paint(canvas, Offset(box.left + 4, box.top + 1));
    todayLabel.dispose();
  }

  @override
  bool shouldRepaint(_MonthsPainter old) =>
      old.scale != scale || old.today != today || old.showsToday != showsToday;
}

/// A faint line at every day and a stronger one at the start of every
/// week (Monday), so where a window starts and ends reads at a glance.
/// Zoomed out, day lines are left out, then week lines give way to one
/// line at the start of each month.
class _DayLinesPainter extends CustomPainter {
  _DayLinesPainter(this.scale);

  final _Scale scale;

  /// Day lines need at least this many pixels per day, week lines this
  /// many per week.
  static const _minDayPixels = 4.0;
  static const _minWeekPixels = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final major = Paint()
      ..color = Palette.muted.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    final minor = Paint()
      ..color = Palette.rule.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final dayPixels = scale.dayPixels;
    final weeks = dayPixels * 7 >= _minWeekPixels;
    final range = scale.window;
    for (var d = range.start; !d.isAfter(range.end); d = addDays(d, 1)) {
      final isMajor = weeks ? d.weekday == DateTime.monday : d.day == 1;
      if (!isMajor && dayPixels < _minDayPixels) continue;
      final at = scale.x(d).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(at, 0),
        Offset(at, size.height),
        isMajor ? major : minor,
      );
    }
  }

  @override
  bool shouldRepaint(_DayLinesPainter old) => old.scale != scale;
}
