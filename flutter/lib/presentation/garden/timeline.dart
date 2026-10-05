import 'package:flutter/foundation.dart';
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
    this.outlined = false,
  });

  final DayWindow span;
  final DayWindow? ideal;
  final Color color;

  /// Tooltip text.
  final String? label;

  /// Drawn as an outline over a light hatch: an alternate window that
  /// needs protection, rather than the usual open-field one.
  final bool outlined;
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

/// A titled group of rows in a [Timeline]. An [inactive] section's titles
/// and bars are drawn fainter, so what is growing stands out above what
/// is only planned.
class TimelineSection {
  const TimelineSection({
    required this.title,
    required this.rows,
    required this.emptyText,
    this.inactive = false,
  });

  final String title;
  final List<TimelineRow> rows;

  /// Shown in place of rows when there are none.
  final String emptyText;
  final bool inactive;
}

/// What one line of the row list holds.
sealed class _Line {
  const _Line();
}

class _HeaderLine extends _Line {
  const _HeaderLine(this.title, this.count);
  final String title;
  final int count;
}

class _EmptyLine extends _Line {
  const _EmptyLine(this.text);
  final String text;
}

class _RowLine extends _Line {
  const _RowLine(this.row, this.inactive);
  final TimelineRow row;
  final bool inactive;
}

/// A calendar strip: today's date, month headings, one row per item with
/// its windows as bars over week (major) and day (minor) lines, and a
/// line at today. Over the chart the mouse wheel zooms around the
/// pointer; a drag moves through time sideways and through the rows up
/// and down, like a map. Today brings the view back.
/// Shared by Grow's Sow and Transplant views so both read the same way.
class Timeline extends StatefulWidget {
  const Timeline({
    super.key,
    required this.range,
    required this.today,
    this.rows = const [],
    this.sections,
    this.seasons = const [],
    this.labelWidth = 220,
    this.emptyText = 'Nothing to show.',
  });

  /// The view shown at first and after Today.
  final DayWindow range;
  final DateTime today;
  final List<TimelineRow> rows;

  /// When given, rows are shown in these titled groups instead of [rows],
  /// each group always present (with its empty text when it has none).
  final List<TimelineSection>? sections;

  /// Stretches shaded behind every row, e.g. last frost to first frost.
  final List<DayWindow> seasons;
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

  /// The row list's scroller, so a drag can move it up and down.
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

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
    final Offset(:dx, :dy) = details.delta;
    // Dragging right pulls earlier days into view and dragging down
    // earlier rows, like a map.
    if (dy != 0 && _scroll.hasClients) {
      final p = _scroll.position;
      p.jumpTo((p.pixels - dy).clamp(p.minScrollExtent, p.maxScrollExtent));
    }
    if (dx != 0) setState(() => _moved = _view.panned(-dx / _chartWidth));
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
  /// drag there moves through time and the rows.
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
            // A pan, not a horizontal drag, so the hand moves the rows
            // up and down too. Touch still scrolls the list on its own:
            // its vertical drag wins before the pan's larger slop.
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: _onDrag,
            onPanEnd: (_) => setState(() => _dragging = false),
            onPanCancel: () => setState(() => _dragging = false),
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
                              painter: _MonthsPainter(
                                scale,
                                today,
                                showsToday,
                                widget.seasons,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: lines.isEmpty
                      ? Center(child: _EmptyText(widget.emptyText))
                      : Stack(
                          children: [
                            ListView.builder(
                              controller: _scroll,
                              itemCount: lines.length,
                              // Each line listens too: it sits inside the
                              // list's scroller, so it claims the wheel
                              // over the chart before the list can scroll.
                              // Over the names it lets the list have it.
                              itemBuilder: (context, i) => Listener(
                                onPointerSignal: _onSignal,
                                child: switch (lines[i]) {
                                  _HeaderLine(:final title, :final count) =>
                                    _sectionHeader(title, count),
                                  _EmptyLine(:final text) => SizedBox(
                                    height: rowHeight,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 12),
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: _EmptyText(text),
                                      ),
                                    ),
                                  ),
                                  _RowLine(:final row, :final inactive) => _row(
                                    row,
                                    scale,
                                    inactive: inactive,
                                  ),
                                },
                              ),
                            ),
                            // Where each frost-free season starts and
                            // ends, under the today line.
                            for (final at in _seasonEdges(widget.seasons))
                              if (scale.shows(at))
                                Positioned(
                                  left: labelWidth + scale.x(at) - 1,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 2,
                                      color: Palette.seasonMark,
                                    ),
                                  ),
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

  /// The rows as list lines: plain rows, or each section's header then its
  /// rows (or its empty text).
  List<_Line> get lines {
    final sections = widget.sections;
    if (sections == null) return [for (final r in rows) _RowLine(r, false)];
    return [
      for (final s in sections) ...[
        _HeaderLine(s.title, s.rows.length),
        if (s.rows.isEmpty)
          _EmptyLine(s.emptyText)
        else
          for (final r in s.rows) _RowLine(r, s.inactive),
      ],
    ];
  }

  /// A section title band across the list, on the chrome grey.
  Widget _sectionHeader(String title, int count) => Container(
    height: 26,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    alignment: Alignment.centerLeft,
    decoration: const BoxDecoration(
      color: Palette.chrome,
      border: Border(bottom: BorderSide(color: Palette.rule)),
    ),
    child: Text('${title.toUpperCase()}  $count', style: sectionTitleStyle),
  );

  Widget _row(TimelineRow row, _Scale scale, {bool inactive = false}) {
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
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: inactive ? Palette.muted : Palette.ink,
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
                          child: CustomPaint(
                            painter: _DayLinesPainter(scale, widget.seasons),
                          ),
                        ),
                        // Not planted yet: windows show, but faded.
                        Positioned.fill(
                          child: Opacity(
                            opacity: inactive ? 0.45 : 1,
                            child: Stack(
                              children: [
                                for (final bar in row.bars) ..._bar(bar, scale),
                              ],
                            ),
                          ),
                        ),
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
          child: bar.outlined
              ? CustomPaint(painter: _HatchPainter(bar.color))
              : Container(
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
      if (bar.ideal case final ideal? when !bar.outlined)
        piece(ideal, 0.95, 14),
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

/// Where frost-free seasons start and end: the lines and badges sit on
/// the edges of the band, so the end is the day after its last day.
List<DateTime> _seasonEdges(List<DayWindow> seasons) => [
  for (final s in seasons) ...[s.start, _dayAfter(s.end)],
];

DateTime _dayAfter(DateTime day) => addDays(day, 1);

/// Month names and ticks across the top of the timeline, day numbers
/// when zoomed in far enough, LAST FROST and FIRST FROST badges at each
/// frost-free season's edges, and the TODAY badge.
class _MonthsPainter extends CustomPainter {
  _MonthsPainter(this.scale, this.today, this.showsToday, this.seasons);

  final _Scale scale;
  final DateTime today;
  final bool showsToday;
  final List<DayWindow> seasons;

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
        if (_seasonEdges(seasons).contains(d)) continue;
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
    // TODAY is placed first and never moves; the frost badges slide
    // aside rather than cover it or each other. Their lines stay on the
    // true dates.
    final placed = <Rect>[];
    final todayBadge = showsToday
        ? _place(size, 'TODAY', scale.x(today), placed)
        : null;
    // The season runs from the last spring frost to the first fall one.
    for (final s in seasons) {
      for (final (text, at) in [
        ('LAST FROST', s.start),
        ('FIRST FROST', _dayAfter(s.end)),
      ]) {
        if (scale.shows(at)) {
          final badge = _place(size, text, scale.x(at), placed);
          _draw(canvas, badge, Palette.seasonMark);
        }
      }
    }
    if (todayBadge != null) _draw(canvas, todayBadge, Palette.ink);
  }

  static const _badgeStyle = TextStyle(
    fontSize: 9.5,
    fontWeight: FontWeight.w700,
    color: Colors.white,
    letterSpacing: 0.5,
  );

  /// Where a badge reading [text] goes: centred on [x] in the bottom half,
  /// kept inside the chart, and slid clear of the badges in [placed],
  /// away from the one it meets. Adds itself to [placed].
  (TextPainter, Rect) _place(
    Size size,
    String text,
    double x,
    List<Rect> placed,
  ) {
    final label = _text(text, _badgeStyle);
    var box = Rect.fromCenter(
      center: Offset(x, size.height - 8),
      width: label.width + 8,
      height: 14,
    );
    Rect inside(Rect r) => r.shift(
      Offset(
        r.left < 0
            ? -r.left
            : r.right > size.width
            ? size.width - r.right
            : 0,
        0,
      ),
    );
    box = inside(box);
    for (final other in placed) {
      if (!box.overlaps(other.inflate(2))) continue;
      final right = box.center.dx >= other.center.dx;
      box = inside(
        box.shift(
          Offset(
            right ? other.right + 3 - box.left : other.left - 3 - box.right,
            0,
          ),
        ),
      );
    }
    placed.add(box);
    return (label, box);
  }

  void _draw(Canvas canvas, (TextPainter, Rect) badge, Color color) {
    final (label, box) = badge;
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(3)),
      Paint()..color = color,
    );
    label.paint(canvas, Offset(box.left + 4, box.top + 1));
    label.dispose();
  }

  @override
  bool shouldRepaint(_MonthsPainter old) =>
      old.scale != scale ||
      old.today != today ||
      old.showsToday != showsToday ||
      !listEquals(old.seasons, seasons);
}

/// A faint line at every day and a stronger one at the start of every
/// week (Monday), so where a window starts and ends reads at a glance.
/// Zoomed out, day lines are left out, then week lines give way to one
/// line at the start of each month.
class _DayLinesPainter extends CustomPainter {
  _DayLinesPainter(this.scale, this.seasons);

  final _Scale scale;

  /// Shaded first, under the lines: the frost-free growing seasons.
  final List<DayWindow> seasons;

  /// Day lines need at least this many pixels per day, week lines this
  /// many per week.
  static const _minDayPixels = 4.0;
  static const _minWeekPixels = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final band = Paint()..color = Palette.season;
    for (final s in seasons) {
      final left = scale.clampedX(s.start);
      final right = scale.clampedX(addDays(s.end, 1));
      if (right > left) {
        canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), band);
      }
    }
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
  bool shouldRepaint(_DayLinesPainter old) =>
      old.scale != scale || !listEquals(old.seasons, seasons);
}

/// An alternate window: a thin outline in [color] over light diagonal
/// hatching, so it reads as possible but not the usual way.
class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final box = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.save();
    canvas.clipRRect(box);
    canvas.drawRRect(box, Paint()..color = color.withValues(alpha: 0.10));
    final hatch = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(
        Offset(x, size.height),
        Offset(x + size.height, 0),
        hatch,
      );
    }
    canvas.restore();
    canvas.drawRRect(
      box.deflate(0.75),
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}
