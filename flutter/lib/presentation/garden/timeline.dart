import 'package:flutter/material.dart';

import '../../domain/grow/day.dart';
import '../theme.dart';

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

/// A calendar strip: today's date with arrows to move the view, month
/// headings, one row per item with its windows as bars over week (major)
/// and day (minor) lines, and a line at today. Shared by Grow,
/// Greenhouse and Harvest so all three read the same way.
class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.range,
    required this.today,
    required this.rows,
    this.labelWidth = 220,
    this.emptyText = 'Nothing to show.',
  });

  final DayWindow range;
  final DateTime today;
  final List<TimelineRow> rows;
  final double labelWidth;
  final String emptyText;

  static const rowHeight = 40.0;

  /// How far one arrow click moves the view.
  static const stepMonths = 2;

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  /// Steps of [Timeline.stepMonths] from [Timeline.range]; 0 is the view
  /// around today.
  int _offset = 0;

  DayWindow get range {
    if (_offset == 0) return widget.range;
    DateTime shift(DateTime d) =>
        DateTime.utc(d.year, d.month + _offset * Timeline.stepMonths, d.day);
    return DayWindow(shift(widget.range.start), shift(widget.range.end));
  }

  DateTime get today => widget.today;
  List<TimelineRow> get rows => widget.rows;
  double get labelWidth => widget.labelWidth;
  String get emptyText => widget.emptyText;
  static const rowHeight = Timeline.rowHeight;

  Widget _navigator() {
    final weekday = const [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
      'Friday', 'Saturday', 'Sunday',
    ][today.weekday - 1];
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: labelWidth),
          IconButton(
            tooltip: 'Earlier',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => setState(() => _offset--),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '$weekday, ${formatDay(today)}, ${today.year}',
              key: const ValueKey('calendar-today'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          if (_offset != 0)
            TextButton(
              onPressed: () => setState(() => _offset = 0),
              child: const Text('Today'),
            ),
          IconButton(
            tooltip: 'Later',
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () => setState(() => _offset++),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final range = this.range;
    final showsToday = range.contains(today);
    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = (constraints.maxWidth - labelWidth).clamp(
          120.0,
          double.infinity,
        );
        final days = daysBetween(range.start, range.end) + 1;
        double x(DateTime d) =>
            (daysBetween(range.start, d) / days * chartWidth).clamp(
              0.0,
              chartWidth,
            );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _navigator(),
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  SizedBox(width: labelWidth),
                  SizedBox(
                    width: chartWidth,
                    child: CustomPaint(
                      painter: _MonthsPainter(range, x, today, showsToday),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: rows.isEmpty
                  ? Center(child: _EmptyText(emptyText))
                  : Stack(
                      children: [
                        ListView.builder(
                          itemCount: rows.length,
                          itemExtent: rowHeight,
                          itemBuilder: (context, i) =>
                              _row(rows[i], range, chartWidth, x),
                        ),
                        if (showsToday)
                          Positioned(
                            left: labelWidth + x(today) - 1,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(width: 2, color: Palette.ink),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _row(
    TimelineRow row,
    DayWindow range,
    double chartWidth,
    double Function(DateTime) x,
  ) {
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
              SizedBox(
                width: chartWidth,
                height: rowHeight,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: CustomPaint(painter: _DayLinesPainter(range, x)),
                    ),
                    for (final bar in row.bars) ..._bar(bar, range, x),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bar(
    TimelineBar bar,
    DayWindow range,
    double Function(DateTime) x,
  ) {
    if (bar.span.end.isBefore(range.start) ||
        bar.span.start.isAfter(range.end)) {
      return const [];
    }
    Widget piece(DayWindow w, double alpha, double height) {
      final left = x(w.start);
      final width = (x(addDays(w.end, 1)) - left).clamp(3.0, double.infinity);
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

/// Month names and ticks across the top of the timeline.
class _MonthsPainter extends CustomPainter {
  _MonthsPainter(this.range, this.x, this.today, this.showsToday);

  final DayWindow range;
  final double Function(DateTime) x;
  final DateTime today;
  final bool showsToday;

  @override
  void paint(Canvas canvas, Size size) {
    final tick = Paint()
      ..color = Palette.panelBorder
      ..strokeWidth = 1;
    var month = DateTime.utc(range.start.year, range.start.month);
    while (!month.isAfter(range.end)) {
      final next = DateTime.utc(month.year, month.month + 1);
      final left = x(month.isBefore(range.start) ? range.start : month);
      final right = x(next.isAfter(range.end) ? addDays(range.end, 1) : next);
      if (!month.isBefore(range.start)) {
        canvas.drawLine(Offset(left, 0), Offset(left, size.height), tick);
      }
      final label = TextPainter(
        text: TextSpan(
          text: month.month == 1
              ? '${monthName(month.month)} ${month.year}'
              : monthName(month.month),
          style: sectionTitleStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (right - left > label.width + 8) {
        // Top half: the TODAY badge takes the bottom half, so the two
        // never collide.
        label.paint(canvas, Offset(left + 6, 1));
      }
      label.dispose();
      month = next;
    }
    if (!showsToday) return;
    final t = x(today);
    final todayLabel = TextPainter(
      text: const TextSpan(
        text: 'TODAY',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
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
      old.range != range || old.today != today || old.showsToday != showsToday;
}

/// A faint line at every day and a stronger one at the start of every
/// week (Monday), so where a window starts and ends reads at a glance.
/// Day lines are left out when days are too narrow to tell apart.
class _DayLinesPainter extends CustomPainter {
  _DayLinesPainter(this.range, this.x);

  final DayWindow range;
  final double Function(DateTime) x;

  /// Day lines need at least this many pixels per day.
  static const _minDayPixels = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final week = Paint()
      ..color = Palette.muted.withValues(alpha: 0.55)
      ..strokeWidth = 1.5;
    final day = Paint()
      ..color = Palette.rule.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    final dayPixels = x(addDays(range.start, 1)) - x(range.start);
    for (var d = range.start; !d.isAfter(range.end); d = addDays(d, 1)) {
      final monday = d.weekday == DateTime.monday;
      if (!monday && dayPixels < _minDayPixels) continue;
      final at = x(d).roundToDouble() + 0.5;
      canvas.drawLine(
        Offset(at, 0),
        Offset(at, size.height),
        monday ? week : day,
      );
    }
  }

  @override
  bool shouldRepaint(_DayLinesPainter old) => old.range != range;
}
