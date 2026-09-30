import 'curve_contour.dart';
import 'curve_edge.dart';
import 'geometry.dart';
import 'planar.dart';
import 'region.dart';

/// Checks topology within each object, not intersections between operands.
/// Ordinary edits retain invalid drawings; Boolean operations use the same
/// rules on each operand separately before consuming anything.
///
/// Separate shapes may already cross and touch. With [shapesMayMeet], as in
/// a zone, so may unfinished drawing: each connected run of lines is
/// checked only against itself, so a new outline can be drawn across an
/// existing shape. Without it, loose lines and points may not meet
/// anything.
String? geometryProblem(Geometry geometry, {bool shapesMayMeet = false}) {
  for (final p in geometry.points.values) {
    if (!p.isFinite) return 'Point coordinates must be finite';
  }
  final lines = geometry.lines.values.toList();
  for (final line in lines) {
    final a = geometry.points[line.start];
    final b = geometry.points[line.end];
    if (a == null || b == null) return 'A line is missing an end point';
    if (a.distanceTo(b) <= tolerance) return 'A line must have length';
    if (!line.bulge.isFinite) return 'An arc must have a finite sweep';
    if (line.bezier(geometry.points) case final bezier?) {
      if (!bezier.isFinite) return 'A curve handle must be finite';
      final pieces = line.edges(geometry.points);
      for (var i = 0; i < pieces.length; i++) {
        for (var j = 0; j < i - 1; j++) {
          if (intersections(pieces[i], pieces[j]).isNotEmpty) {
            return 'A curve cannot cross itself';
          }
        }
      }
      continue;
    }
    final curve = line.curve(geometry.points);
    if (!curve.length.isFinite || !curve.signedArea.isFinite) {
      return 'An arc must have a finite size';
    }
  }
  for (final pointId in geometry.points.keys) {
    if (geometry.degreeOf(pointId) > 2) {
      return 'A point can join at most two lines, so boundaries cannot branch';
    }
  }
  for (final circle in geometry.circles.values) {
    if (!geometry.points.containsKey(circle.center)) {
      return 'A circle is missing its center';
    }
    if (!circle.radius.isFinite || circle.radius <= tolerance) {
      return 'A circle must have size';
    }
  }
  final referenced = <String>{};
  for (final shape in geometry.shapes.values) {
    for (final ring in shape.rings) {
      for (final ref in ring) {
        if (!geometry.lines.containsKey(ref.segmentId)) {
          return 'A shape is missing an edge';
        }
        if (!referenced.add(ref.segmentId)) {
          return 'Boundary rings cannot share an edge';
        }
      }
    }
  }

  final owners = _ownersOf(geometry, byRun: shapesMayMeet);
  bool separate(String a, String b) {
    final first = owners[a];
    final second = owners[b];
    return first != null &&
        second != null &&
        first.intersection(second).isEmpty;
  }

  final points = geometry.points.entries.toList();
  for (var i = 0; i < points.length; i++) {
    for (var j = 0; j < i; j++) {
      if (!separate(points[i].key, points[j].key) &&
          points[i].value.distanceTo(points[j].value) <= tolerance) {
        return 'Two points cannot occupy the same spot';
      }
    }
  }
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final pieces = line.edges(geometry.points);
    for (final entry in points) {
      if (line.touches(entry.key) || separate(line.id, entry.key)) continue;
      if (pieces.any((edge) => edge.distanceTo(entry.value) <= tolerance)) {
        return 'A point cannot rest on an edge it is not part of';
      }
    }
    for (var j = 0; j < i; j++) {
      final other = lines[j];
      if (separate(line.id, other.id)) continue;
      final shared = {
        line.start,
        line.end,
      }.intersection({other.start, other.end});
      for (final edge in pieces) {
        for (final otherEdge in other.edges(geometry.points)) {
          final meetings = intersections(edge, otherEdge);
          if (meetings.any(
            (p) => !shared.any(
              (id) => geometry.points[id]!.distanceTo(p) <= tolerance,
            ),
          )) {
            return 'Edges cannot cross or touch except at shared points';
          }
          if (meetings.isNotEmpty &&
              (edge.distanceTo(otherEdge.pointAt(0.5)) <= tolerance ||
                  otherEdge.distanceTo(edge.pointAt(0.5)) <= tolerance)) {
            return 'Edges cannot double back over each other';
          }
        }
      }
    }
  }

  for (final circle in geometry.circles.values) {
    final disc = DiscRegion(geometry.points[circle.center]!, circle.radius);
    for (final line in lines) {
      if (separate(line.id, circle.id)) continue;
      if (disc.contours
          .expand((ring) => ring)
          .any(
            (edge) => line
                .edges(geometry.points)
                .any((piece) => intersections(edge, piece).isNotEmpty),
          )) {
        return 'Edges cannot cross or touch the circle';
      }
    }
  }
  for (final shape in geometry.shapes.values) {
    final problem = _shapeProblem(geometry, shape);
    if (problem != null) return problem;
  }
  return null;
}

String? _shapeProblem(Geometry geometry, ClosedShape shape) {
  final regions = <Region?>[];
  for (final ring in shape.rings) {
    final edges = geometry.contourOf(ring);
    if (edges == null) {
      regions.add(null);
      continue;
    }
    final region = CurveRegion([orientContour(edges, positive: true)]);
    if (region.area <= tolerance * region.perimeter) {
      return 'A boundary ring must enclose some land';
    }
    regions.add(region);
  }
  final outer = regions.first;
  final holes = regions.skip(1).whereType<Region>().toList();
  for (var i = 0; i < holes.length; i++) {
    if (outer != null && !outer.contains(holes[i])) {
      return 'A hole must stay inside its outer boundary';
    }
    for (var j = 0; j < i; j++) {
      if (holes[i].overlaps(holes[j])) return 'Holes cannot overlap or nest';
    }
  }
  final region = geometry.regionOf(shape.id);
  if (region != null && region.area <= tolerance * region.perimeter) {
    return 'A boundary must enclose some land';
  }
  return null;
}

/// The shapes and circles each item belongs to. With [byRun], every point
/// and line also belongs to its connected run of lines, so loose drawing
/// has an owner too. A shape's holes are runs of their own, but still share
/// the shape with its outline.
Map<String, Set<String>> _ownersOf(Geometry geometry, {bool byRun = false}) {
  final owners = <String, Set<String>>{};
  void add(String item, String shape) =>
      owners.putIfAbsent(item, () => {}).add(shape);
  if (byRun) {
    final roots = {for (final id in geometry.points.keys) id: id};
    String root(String id) {
      while (roots[id] != id) {
        id = roots[id] = roots[roots[id]!]!;
      }
      return id;
    }

    for (final line in geometry.lines.values) {
      roots[root(line.start)] = root(line.end);
    }
    for (final id in geometry.points.keys) {
      add(id, 'run:${root(id)}');
    }
    for (final line in geometry.lines.values) {
      add(line.id, 'run:${root(line.start)}');
    }
  }
  for (final shape in geometry.shapes.values) {
    for (final ring in shape.rings) {
      for (final ref in ring) {
        add(ref.segmentId, shape.id);
        final line = geometry.lines[ref.segmentId];
        if (line != null) {
          add(line.start, shape.id);
          add(line.end, shape.id);
        }
      }
    }
  }
  for (final circle in geometry.circles.values) {
    add(circle.id, circle.id);
    add(circle.center, circle.id);
  }
  return owners;
}
