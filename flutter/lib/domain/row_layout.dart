import 'curve_edge.dart';
import 'ground.dart';
import 'planar.dart';
import 'region.dart';
import 'vec.dart';

part 'row_border.dart';

/// One straight run of a planting row inside a zone: the row's centre
/// line from [start] to [end], in world metres. A row that crosses a hole
/// or a notch in the zone is split into several runs.
class RowRun {
  const RowRun(this.start, this.end);

  final Vec start;
  final Vec end;

  double get length => start.distanceTo(end);
}

/// Where a zone's rows fall, and how much row there is to plant.
///
/// Rows are [RowSpec.pitch] apart. With no border they start at the land's
/// outermost edge. Bordered rows are centred across the usable span so
/// leftover space is shared equally, with at least [RowSpec.border] clear
/// around the whole strip, including its ends and hole rims.
class RowLayout {
  RowLayout._(this.spec, this.runs, this.rowCount);

  /// The largest number of rows laid out. A row width typed in the wrong
  /// units could otherwise ask for millions.
  static const maxRows = 4000;

  /// Rows for [spec] across [region]. Returns an empty layout when the
  /// region is empty or would need more than [maxRows] rows.
  factory RowLayout.of(Region region, RowSpec spec) {
    final contours = region.contours;
    if (contours.isEmpty || spec.problem != null) {
      return RowLayout._(spec, const [], 0);
    }
    final (ax, ay) = spec.along;
    final along = Vec(ax, ay);
    final across = Vec(-ay, ax);
    final exactAxes = spec.border > 0 ? [along, across] : null;

    // How far the land reaches along and across the rows.
    var lowAcross = double.infinity, highAcross = double.negativeInfinity;
    var lowAlong = double.infinity, highAlong = double.negativeInfinity;
    for (final edge in contours.expand((c) => c)) {
      for (final p in _extremes(edge, axes: exactAxes)) {
        final a = p.dot(across), b = p.dot(along);
        if (a < lowAcross) lowAcross = a;
        if (a > highAcross) highAcross = a;
        if (b < lowAlong) lowAlong = b;
        if (b > highAlong) highAlong = b;
      }
    }
    lowAcross += spec.border;
    highAcross -= spec.border;
    lowAlong += spec.border;
    highAlong -= spec.border;
    if (highAlong <= lowAlong) return RowLayout._(spec, const [], 0);
    final span = highAcross - lowAcross;
    if (!(span > 0)) return RowLayout._(spec, const [], 0);
    final count = ((span - spec.width) / spec.pitch).floor() + 1;
    if (count <= 0 || count > maxRows) return RowLayout._(spec, const [], 0);

    final usedSpan = spec.width + (count - 1) * spec.pitch;
    final margin = spec.border > 0 ? (span - usedSpan) / 2 : 0.0;
    final border = spec.border > 0
        ? _RowBorder(region, spec.border, across * (spec.width / 2))
        : null;
    final runs = <RowRun>[];
    var rowsWithLand = 0;
    for (var i = 0; i < count; i++) {
      final offset = lowAcross + margin + spec.width / 2 + i * spec.pitch;
      final from = across * offset + along * (lowAlong - 1);
      final to = across * offset + along * (highAlong + 1);
      final found = _clip(region, from, to, border: border);
      if (found.isNotEmpty) rowsWithLand++;
      runs.addAll(found);
    }
    return RowLayout._(spec, List.unmodifiable(runs), rowsWithLand);
  }

  /// Rows for each separate piece of land, laid out on its own.
  factory RowLayout.ofPieces(Iterable<Region> pieces, RowSpec spec) {
    final runs = <RowRun>[];
    var rows = 0;
    for (final piece in pieces) {
      final layout = RowLayout.of(piece, spec);
      runs.addAll(layout.runs);
      rows += layout.rowCount;
    }
    return RowLayout._(spec, List.unmodifiable(runs), rows);
  }

  final RowSpec spec;

  /// Every piece of row centre line inside the land.
  final List<RowRun> runs;

  /// Rows that reach the land at least once.
  final int rowCount;

  /// Total length of row to plant along, in metres.
  double get totalLength => runs.fold(0.0, (sum, run) => sum + run.length);

  /// The planted strips' area, in square metres: row length × row width.
  double get bedArea => totalLength * spec.width;
}

/// Exact extrema on [axes], or the legacy arc samples when omitted.
/// Bordered strips need exact bounds so a near-tangent row does not
/// appear or disappear merely because the row direction changes.
Iterable<Vec> _extremes(CurveEdge edge, {List<Vec>? axes}) sync* {
  yield edge.start;
  yield edge.end;
  if (!edge.isArc) return;
  if (axes != null) {
    for (final axis in axes) {
      for (final sign in [-1.0, 1.0]) {
        final point = edge.centre + axis * (sign * edge.radius);
        if (edge.parameterOf(point) <= 1) yield point;
      }
    }
    return;
  }
  for (var i = 1; i < 16; i++) {
    yield edge.pointAt(i / 16);
  }
}

/// How far [region] reaches along [axis] (a unit vector): the lowest and
/// highest value of `point · axis` over its outline. Arcs are sampled, as
/// for sizing a row layout.
(double, double) extentAlong(Region region, Vec axis) {
  var low = double.infinity, high = double.negativeInfinity;
  for (final edge in region.contours.expand((c) => c)) {
    for (final p in _extremes(edge)) {
      final d = p.dot(axis);
      if (d < low) low = d;
      if (d > high) high = d;
    }
  }
  return (low, high);
}

/// The parts of segment [from]–[to] that lie inside [region].
List<RowRun> clipToRegion(Region region, Vec from, Vec to) =>
    _clip(region, from, to);

/// The parts of segment [from]–[to] that lie inside [region].
List<RowRun> _clip(Region region, Vec from, Vec to, {_RowBorder? border}) {
  final line = CurveEdge(from, to);
  final direction = to - from;
  final lengthSquared = direction.dot(direction);
  final cuts = <double>[0, 1];
  for (final edge in border?.cuts ?? region.contours.expand((c) => c)) {
    for (final p in intersections(line, edge)) {
      cuts.add((p - from).dot(direction) / lengthSquared);
    }
  }
  cuts.sort();
  final runs = <RowRun>[];
  Vec? open;
  var lastEnd = from;
  for (var i = 0; i + 1 < cuts.length; i++) {
    final a = cuts[i], b = cuts[i + 1];
    if (b <= a) continue;
    // A tiny parameter interval can still be real excluded land on a
    // long row. Bordered layouts classify every gap before joining runs.
    if (border == null && b - a < 1e-9) continue;
    final middle = from + direction * ((a + b) / 2);
    final inside =
        border?.contains(middle) ??
        (region.locate(middle) == PointLocation.inside);
    final start = from + direction * a;
    final end = from + direction * b;
    if (inside) {
      open ??= start;
      lastEnd = end;
    } else if (open != null) {
      runs.add(RowRun(open, lastEnd));
      open = null;
    }
  }
  if (open != null) runs.add(RowRun(open, lastEnd));
  if (border != null) runs.removeWhere((run) => run.length <= tolerance);
  return runs;
}
