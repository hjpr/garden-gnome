import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../domain/layer.dart';

/// Draws a decorative [pattern] inside [area].
///
/// Spacing is in screen pixels so the pattern stays readable at any zoom.
/// [anchor] is the screen position of the world origin: tying the pattern
/// to it keeps the marks still while the view pans.
///
/// Only the part of [area] that is on screen gets marks. Zoomed in, a
/// shape can be far larger than the view, and marking all of it made the
/// work grow with the square of the zoom.
void paintFillPattern(
  Canvas canvas,
  Path area,
  FillPattern pattern,
  Color color,
  Offset anchor,
) {
  final bounds = area.getBounds();
  if (bounds.isEmpty) return;
  canvas.save();
  canvas.clipPath(area);
  final visible = visibleRect(canvas, bounds);
  if (visible != null) _paintMarks(canvas, visible, pattern, color, anchor);
  canvas.restore();
}

/// The part of [bounds] inside the canvas clip, grown a little so marks
/// that only just reach the clip edge still draw their anti-aliased edge.
/// Null when nothing of [bounds] is visible.
Rect? visibleRect(Canvas canvas, Rect bounds) {
  final clip = canvas.getLocalClipBounds();
  if (!clip.overlaps(bounds)) return null;
  return clip.intersect(bounds).inflate(2);
}

void _paintMarks(
  Canvas canvas,
  Rect bounds,
  FillPattern pattern,
  Color color,
  Offset anchor,
) {
  final lines = Paint()
    ..color = color
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;
  final segments = LineBatch();
  switch (pattern) {
    case FillPattern.diagonal:
      _diagonals(segments, bounds, anchor, 10, rising: true);
    case FillPattern.rows:
      _horizontals(segments, bounds, anchor, 9);
    case FillPattern.crosshatch:
      _diagonals(segments, bounds, anchor, 12, rising: true);
      _diagonals(segments, bounds, anchor, 12, rising: false);
    case FillPattern.grid:
      _horizontals(segments, bounds, anchor, 12);
      _verticals(segments, bounds, anchor, 12);
    case FillPattern.dots:
      // Round points as wide as a dot draw the same discs as drawCircle,
      // in one call instead of one per dot.
      final dots = <double>[];
      _eachCell(
        bounds,
        anchor,
        10,
        (c) => dots
          ..add(c.dx)
          ..add(c.dy),
      );
      canvas.drawRawPoints(
        PointMode.points,
        Float32List.fromList(dots),
        Paint()
          ..color = color
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round,
      );
    case FillPattern.crosses:
      _eachCell(bounds, anchor, 14, (c) {
        segments.add(c - const Offset(3, 0), c + const Offset(3, 0));
        segments.add(c - const Offset(0, 3), c + const Offset(0, 3));
      });
  }
  segments.draw(canvas, lines);
}

/// Straight line pieces collected so they are drawn in one call. Each
/// piece is still drawn on its own, so crossings look exactly as they did
/// with one drawLine per piece.
class LineBatch {
  final List<double> _coordinates = [];

  bool get isEmpty => _coordinates.isEmpty;

  void add(Offset from, Offset to) =>
      _coordinates.addAll([from.dx, from.dy, to.dx, to.dy]);

  void draw(Canvas canvas, Paint paint) {
    if (isEmpty) return;
    canvas.drawRawPoints(
      PointMode.lines,
      Float32List.fromList(_coordinates),
      paint,
    );
  }
}

/// The first multiple of [step] (offset by [phase]) at or below [value].
double patternStart(double value, double phase, double step) =>
    ((value - phase) / step).floorToDouble() * step + phase;

void _horizontals(LineBatch out, Rect bounds, Offset anchor, double step) {
  for (
    var y = patternStart(bounds.top, anchor.dy, step);
    y <= bounds.bottom;
    y += step
  ) {
    out.add(Offset(bounds.left, y), Offset(bounds.right, y));
  }
}

void _verticals(LineBatch out, Rect bounds, Offset anchor, double step) {
  for (
    var x = patternStart(bounds.left, anchor.dx, step);
    x <= bounds.right;
    x += step
  ) {
    out.add(Offset(x, bounds.top), Offset(x, bounds.bottom));
  }
}

/// 45° lines [spacing] apart. A rising line keeps x + y constant; a
/// falling one x − y.
void _diagonals(
  LineBatch out,
  Rect bounds,
  Offset anchor,
  double spacing, {
  required bool rising,
}) {
  // Lines [spacing] apart measured across them are step apart along x.
  final step = spacing * math.sqrt2;
  if (rising) {
    risingDiagonals(out, bounds, anchor.dx + anchor.dy, step);
    return;
  }
  final h = bounds.height;
  for (
    var k = patternStart(
      bounds.left - bounds.bottom,
      anchor.dx - anchor.dy,
      step,
    );
    k <= bounds.right - bounds.top;
    k += step
  ) {
    // x − y = k.
    out.add(
      Offset(k + bounds.top, bounds.top),
      Offset(k + bounds.top + h, bounds.bottom),
    );
  }
}

/// Lines where x + y = [phase] + n·[step], across [bounds] from its top
/// edge to its bottom edge.
void risingDiagonals(LineBatch out, Rect bounds, double phase, double step) {
  final h = bounds.height;
  for (
    var k = patternStart(bounds.left + bounds.top, phase, step);
    k <= bounds.right + bounds.bottom;
    k += step
  ) {
    out.add(
      Offset(k - bounds.top, bounds.top),
      Offset(k - bounds.top - h, bounds.bottom),
    );
  }
}

/// Calls [draw] at the centre of every [step]-sized cell covering bounds.
void _eachCell(
  Rect bounds,
  Offset anchor,
  double step,
  void Function(Offset centre) draw,
) {
  final half = step / 2;
  for (
    var y = patternStart(bounds.top - half, anchor.dy, step);
    y <= bounds.bottom + half;
    y += step
  ) {
    for (
      var x = patternStart(bounds.left - half, anchor.dx, step);
      x <= bounds.right + half;
      x += step
    ) {
      draw(Offset(x + half, y + half));
    }
  }
}
