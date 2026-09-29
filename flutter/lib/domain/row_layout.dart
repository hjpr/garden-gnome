import 'curve_edge.dart';
import 'ground.dart';
import 'planar.dart';
import 'region.dart';
import 'vec.dart';

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
/// Rows are laid across the land edge to edge: the first row's side sits
/// on the land's outermost edge across the rows, and each next row is one
/// [RowSpec.pitch] further on. Each row is cut to the zone's land.
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

    // How far the land reaches along and across the rows.
    var lowAcross = double.infinity, highAcross = double.negativeInfinity;
    var lowAlong = double.infinity, highAlong = double.negativeInfinity;
    for (final edge in contours.expand((c) => c)) {
      for (final p in _extremes(edge)) {
        final a = p.dot(across), b = p.dot(along);
        if (a < lowAcross) lowAcross = a;
        if (a > highAcross) highAcross = a;
        if (b < lowAlong) lowAlong = b;
        if (b > highAlong) highAlong = b;
      }
    }
    final span = highAcross - lowAcross;
    if (!(span > 0)) return RowLayout._(spec, const [], 0);
    final count = ((span - spec.width) / spec.pitch).floor() + 1;
    if (count > maxRows) return RowLayout._(spec, const [], 0);

    final runs = <RowRun>[];
    var rowsWithLand = 0;
    for (var i = 0; i < count; i++) {
      final offset = lowAcross + spec.width / 2 + i * spec.pitch;
      final from = across * offset + along * (lowAlong - 1);
      final to = across * offset + along * (highAlong + 1);
      final found = _clip(region, from, to);
      if (found.isNotEmpty) rowsWithLand++;
      runs.addAll(found);
    }
    return RowLayout._(spec, List.unmodifiable(runs), rowsWithLand);
  }

  /// Rows for each separate piece of land, laid out on its own, so every
  /// piece starts with a whole row at its edge.
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

/// Points that bound an edge: its ends and, for an arc, the arc's
/// outermost points in eight directions, which cover every heading of
/// the rows closely enough to size the layout.
Iterable<Vec> _extremes(CurveEdge edge) sync* {
  yield edge.start;
  yield edge.end;
  if (!edge.isArc) return;
  for (var i = 1; i < 16; i++) {
    yield edge.pointAt(i / 16);
  }
}

/// The parts of segment [from]–[to] that lie inside [region].
List<RowRun> _clip(Region region, Vec from, Vec to) {
  final line = CurveEdge(from, to);
  final direction = to - from;
  final lengthSquared = direction.dot(direction);
  final cuts = <double>[0, 1];
  for (final edge in region.contours.expand((c) => c)) {
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
    if (b - a < 1e-9) continue;
    final middle = from + direction * ((a + b) / 2);
    final inside = region.locate(middle) == PointLocation.inside;
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
  return runs;
}
