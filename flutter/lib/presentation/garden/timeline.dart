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

/// A calendar strip: month headings across the top, one row per item
/// with its windows as bars, and a line at today. Shared by Grow,
/// Greenhouse and Harvest so all three read the same way.
class Timeline extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
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
            SizedBox(
              height: 32,
              child: Row(
                children: [
                  SizedBox(width: labelWidth),
                  SizedBox(
                    width: chartWidth,
                    child: CustomPaint(
                      painter: _MonthsPainter(range, x, today),
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
                              _row(rows[i], chartWidth, x),
                        ),
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

  Widget _row(TimelineRow row, double chartWidth, double Function(DateTime) x) {
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
                  children: [for (final bar in row.bars) ..._bar(bar, x)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _bar(TimelineBar bar, double Function(DateTime) x) {
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
  _MonthsPainter(this.range, this.x, this.today);

  final DayWindow range;
  final double Function(DateTime) x;
  final DateTime today;

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
      old.range != range || old.today != today;
}
