import 'dart:math' as math;

import 'bezier.dart';
import 'curve_contour.dart';
import 'curve_edge.dart';
import 'region.dart';
import 'vec.dart';

/// An editable connection between two owned points: straight, a circular
/// arc ([bulge]), or a cubic Bézier curve ([startHandle], [endHandle]).
class LineSegment {
  const LineSegment(
    this.id,
    this.start,
    this.end, {
    this.bulge = 0,
    this.startHandle,
    this.endHandle,
  });

  final String id;
  final String start;
  final String end;

  /// tan(signed sweep / 4); zero keeps existing straight segments unchanged.
  final double bulge;

  /// Bézier control points, each stored as an offset from its own end
  /// point so it moves with that point. Both null for a straight line or
  /// an arc.
  final Vec? startHandle;
  final Vec? endHandle;

  bool get isBezier => startHandle != null || endHandle != null;
  bool get isStraight => bulge == 0 && !isBezier;

  /// The same line with new Bézier handles.
  LineSegment withHandles(Vec startHandle, Vec endHandle) => LineSegment(
    id,
    start,
    end,
    startHandle: startHandle,
    endHandle: endHandle,
  );

  /// The handle offset at [pointId], one of this line's ends.
  Vec? handleAt(String pointId) => pointId == start ? startHandle : endHandle;

  /// The single straight or arc edge. Bézier lines have no single edge:
  /// use [edges], [bezier] or the measuring helpers below instead.
  CurveEdge curve(Map<String, Vec> points) {
    if (isBezier) {
      throw StateError('A Bézier line is not a single straight or arc edge.');
    }
    return CurveEdge(points[start]!, points[end]!, bulge: bulge);
  }

  /// The Bézier curve in world metres, or null for a straight line or arc.
  CubicBezier? bezier(Map<String, Vec> points) {
    if (!isBezier) return null;
    final a = points[start]!;
    final b = points[end]!;
    return CubicBezier(
      a,
      a + (startHandle ?? Vec.zero),
      b + (endHandle ?? Vec.zero),
      b,
    );
  }

  /// Straight and arc edges tracing this line end to end. A Bézier line
  /// gives the arcs standing in for it; see [bezierTolerance].
  List<CurveEdge> edges(Map<String, Vec> points) {
    final curve = bezier(points);
    if (curve == null) return [this.curve(points)];
    final cached = _fits[this];
    if (cached != null && cached.$1.sameAs(curve)) return cached.$2;
    final fitted = List<CurveEdge>.unmodifiable(curve.toEdges());
    _fits[this] = (curve, fitted);
    return fitted;
  }

  static final _fits = Expando<(CubicBezier, List<CurveEdge>)>('bezier fits');

  double distanceTo(Map<String, Vec> points, Vec p) =>
      closestPoint(points, p).distanceTo(p);

  /// Nearest point to [p]; Bézier projection uses numerical refinement.
  Vec closestPoint(Map<String, Vec> points, Vec p) {
    final curve = bezier(points);
    if (curve == null) return this.curve(points).closestPoint(p);
    return curve.pointAt(curve.closestParameter(p));
  }

  /// The point halfway along the curve's parameter.
  Vec midpoint(Map<String, Vec> points) =>
      bezier(points)?.pointAt(0.5) ?? curve(points).pointAt(0.5);

  (Vec, Vec) bounds(Map<String, Vec> points) {
    var low = const Vec(double.infinity, double.infinity);
    var high = const Vec(double.negativeInfinity, double.negativeInfinity);
    for (final edge in edges(points)) {
      final (a, b) = edge.bounds;
      low = Vec(math.min(low.x, a.x), math.min(low.y, a.y));
      high = Vec(math.max(high.x, b.x), math.max(high.y, b.y));
    }
    return (low, high);
  }

  /// Whether [other] draws the same curve between the same two points,
  /// in either direction.
  bool sameCurveAs(LineSegment other) {
    if (other.start == start && other.end == end) {
      return other.bulge == bulge &&
          other.startHandle == startHandle &&
          other.endHandle == endHandle;
    }
    return other.start == end &&
        other.end == start &&
        other.bulge == -bulge &&
        other.startHandle == endHandle &&
        other.endHandle == startHandle;
  }

  bool touches(String pointId) => start == pointId || end == pointId;
  String otherEnd(String pointId) => start == pointId ? end : start;
  bool connects(String a, String b) =>
      (start == a && end == b) || (start == b && end == a);
}

/// One segment's place in a boundary's traversal order.
class SegmentRef {
  const SegmentRef(this.segmentId, {this.reversed = false});

  final String segmentId;
  final bool reversed;
}

/// The segments that make up one shape on a layer, in traversal order.
///
/// The record keeps its identity while the shape is open, so repairing the
/// gap restores the same shape (and its label) rather than creating a new
/// one.
class ClosedShape {
  ClosedShape(
    this.id,
    List<SegmentRef> segments, {
    List<List<SegmentRef>> holes = const [],
    this.label,
  }) : segments = List.unmodifiable(segments),
       holes = List.unmodifiable([
         for (final hole in holes) List<SegmentRef>.unmodifiable(hole),
       ]);

  final String id;
  final List<SegmentRef> segments;
  final List<List<SegmentRef>> holes;

  /// The name the user gave this shape, or null for the automatic name.
  final String? label;

  List<List<SegmentRef>> get rings => [segments, ...holes];
}

/// A circle drawn around one of the layer's points.
///
/// The centre point owns the position, so moving that point moves the
/// circle. Both circle tools produce this same record.
class Circle {
  const Circle(this.id, this.center, this.radius, {this.label});

  final String id;

  /// The ID of the centre point.
  final String center;

  /// Radius in metres; finite and above zero.
  final double radius;

  /// The name the user gave this circle, or null for the automatic name.
  final String? label;

  Circle withRadius(double radius) => Circle(id, center, radius, label: label);
}

/// Mound settings stored with a zone's geometry, kept for the planting
/// layouts to come. Row sizes moved to the zone's properties ([RowSpec]);
/// the row fields here are only read from older files.
class PlantingDimensions {
  const PlantingDimensions({
    this.rowWidth,
    this.rowSpacing,
    this.rowDirection,
    this.moundDiameter,
    this.moundSpacing,
  });

  final double? rowWidth;
  final double? rowSpacing;
  final double? rowDirection;
  final double? moundDiameter;
  final double? moundSpacing;
}

/// Highest identifier number issued for each kind of geometry item.
///
/// Numbers are never reused, even after deletion or Undo.
class IdCounters {
  const IdCounters({
    this.points = 0,
    this.lines = 0,
    this.circles = 0,
    this.shapes = 0,
  });

  final int points;
  final int lines;
  final int circles;
  final int shapes;

  IdCounters atLeast(IdCounters other) => IdCounters(
    points: points > other.points ? points : other.points,
    lines: lines > other.lines ? lines : other.lines,
    circles: circles > other.circles ? circles : other.circles,
    shapes: shapes > other.shapes ? shapes : other.shapes,
  );

  bool sameAs(IdCounters other) =>
      points == other.points &&
      lines == other.lines &&
      circles == other.circles &&
      shapes == other.shapes;
}

/// Every point, line, circle, and shape drawn on one layer.
///
/// Points own coordinates; lines, circles, and shapes refer to points by
/// ID. A layer is a group: every closed shape and circle on it is part of
/// the layer's land, and [stack] orders them from bottom to top.
/// Instances are immutable; editing produces a changed copy.
class Geometry {
  Geometry({
    required this.id,
    required this.ownerLayerId,
    Map<String, Vec> points = const {},
    Map<String, LineSegment> lines = const {},
    Map<String, Circle> circles = const {},
    Map<String, ClosedShape> shapes = const {},
    List<String> order = const [],
    this.counters = const IdCounters(),
    this.dimensions,
  }) : points = Map.unmodifiable(points),
       lines = Map.unmodifiable(lines),
       circles = Map.unmodifiable(circles),
       shapes = Map.unmodifiable(shapes),
       order = List.unmodifiable(order);

  final String id;
  final String ownerLayerId;
  final Map<String, Vec> points;
  final Map<String, LineSegment> lines;
  final Map<String, Circle> circles;
  final Map<String, ClosedShape> shapes;

  /// Shape and circle IDs as saved, bottom first. Use [stack], which also
  /// covers any object missing from this list.
  final List<String> order;
  final IdCounters counters;
  final PlantingDimensions? dimensions;

  bool get isEmpty => points.isEmpty;

  /// Every shape and circle on the layer, bottom first. A shape higher in
  /// the stack cuts the shapes below it when used with Subtract.
  late final List<String> stack = List.unmodifiable(_stack());

  /// The shapes and circles that are closed and enclose land, bottom first.
  late final List<String> closedIds = List.unmodifiable([
    for (final id in stack)
      if (regionOf(id) != null) id,
  ]);

  /// All of the layer's land: every closed shape and circle together, or
  /// null while there is none.
  Region? get region => _land.$1;

  /// Whether the layer has any closed land yet.
  bool get isClosed => region != null;

  /// Total land area in square metres: the sum of every closed shape, or
  /// null while there is none. Overlapping shapes are counted once each,
  /// so the figure stays predictable. See [coveredArea].
  double? get area => closedIds.isEmpty
      ? null
      : closedIds.fold<double>(0, (sum, id) => sum + regionOf(id)!.area);

  /// The ground the layer covers in square metres, or null while there is
  /// none. Where shapes overlap, the shared land is counted once.
  double? get coveredArea => _land.merged ? region!.area : area;

  /// The land, and whether overlapping shapes were merged to make it.
  late final (Region?, {bool merged}) _land = _region();

  /// The shape's own name, or an automatic one such as "Shape 2".
  String labelOf(String id) {
    final custom = shapes[id]?.label ?? circles[id]?.label;
    if (custom != null) return custom;
    final number = id.substring(id.lastIndexOf('-') + 1);
    return circles.containsKey(id) ? 'Circle $number' : 'Shape $number';
  }

  /// Corner IDs of a closed shape's outer ring in traversal order, or empty
  /// when it is open, is a circle, or does not exist.
  List<String> cornersOf(String shapeId) {
    final shape = shapes[shapeId];
    if (shape == null ||
        shape.rings.any((ring) => _closedRingCorners(ring).isEmpty)) {
      return const [];
    }
    return _closedRingCorners(shape.segments);
  }

  /// Why the layer has unfinished drawing, or null when every line and
  /// point belongs to a closed shape or circle. Unfinished drawing makes
  /// the whole layer invalid.
  late final String? unfinishedReason = _unfinished();

  Iterable<LineSegment> linesAt(String pointId) =>
      lines.values.where((line) => line.touches(pointId));

  int degreeOf(String pointId) => linesAt(pointId).length;

  bool contains(String itemId) =>
      points.containsKey(itemId) ||
      lines.containsKey(itemId) ||
      circles.containsKey(itemId) ||
      shapes.containsKey(itemId);

  /// The distinct points that define the given items.
  Set<String> definingPoints(Iterable<String> itemIds) {
    final result = <String>{};
    for (final id in itemIds) {
      if (points.containsKey(id)) result.add(id);
      final line = lines[id];
      if (line != null) result.addAll([line.start, line.end]);
      final circle = circles[id];
      if (circle != null) result.add(circle.center);
      final shape = shapes[id];
      if (shape != null) {
        for (final ring in shape.rings) {
          for (final ref in ring) {
            final member = lines[ref.segmentId];
            if (member != null) result.addAll([member.start, member.end]);
          }
        }
      }
    }
    return result;
  }

  Geometry copyWith({IdCounters? counters, PlantingDimensions? dimensions}) =>
      Geometry(
        id: id,
        ownerLayerId: ownerLayerId,
        points: points,
        lines: lines,
        circles: circles,
        shapes: shapes,
        order: order,
        counters: counters ?? this.counters,
        dimensions: dimensions ?? this.dimensions,
      );

  List<String> _stack() {
    final known = {...shapes.keys, ...circles.keys};
    final listed = [
      for (final id in order.toSet())
        if (known.contains(id)) id,
    ];
    final missing = known.difference(listed.toSet()).toList()
      ..sort(compareItemIds);
    return [...listed, ...missing];
  }

  (Region?, {bool merged}) _region() {
    final ids = closedIds;
    if (ids.isEmpty) return (null, merged: false);
    if (ids.length == 1) return (regionOf(ids.single), merged: false);
    final regions = [for (final id in ids) regionOf(id)!];
    var overlapping = false;
    for (var i = 0; i < regions.length && !overlapping; i++) {
      for (var j = 0; j < i; j++) {
        if (regions[i].overlaps(regions[j])) {
          overlapping = true;
          break;
        }
      }
    }
    if (overlapping) {
      // Show and test overlapping land (a zone's, or an invalid property's)
      // as the union, so an overlap does not read as a hole.
      try {
        Region merged = regions.first;
        for (final next in regions.skip(1)) {
          merged = merged.combine(next, BooleanOperation.union);
        }
        return (merged, merged: true);
      } on StateError {
        // Fall through to the gathered pieces below.
      }
    }
    // Separate pieces can simply be gathered; nesting sorts out islands
    // inside another shape's hole.
    return (
      CurveRegion([for (final region in regions) ...region.contours]),
      merged: false,
    );
  }

  String? _unfinished() {
    final used = <String>{};
    for (final shape in shapes.values) {
      if (regionOf(shape.id) == null) {
        return '${labelOf(shape.id)} is not closed';
      }
      for (final ring in shape.rings) {
        for (final ref in ring) {
          used.add(ref.segmentId);
        }
      }
    }
    if (lines.keys.any((id) => !used.contains(id))) {
      return 'Some lines are not part of a closed shape';
    }
    final anchored = {
      for (final line in lines.values) ...[line.start, line.end],
      for (final circle in circles.values) circle.center,
    };
    if (points.keys.any((id) => !anchored.contains(id))) {
      return 'A point is not part of a shape';
    }
    return null;
  }

  /// Resolves an outline, corner, or centre click to its owning shape.
  /// Loose construction has no shape to use as a Boolean operand.
  String? shapeIdFor(String itemId) {
    if (shapes.containsKey(itemId) || circles.containsKey(itemId)) {
      return itemId;
    }
    for (final id in stack) {
      if (circles[id]?.center == itemId) return id;
      final shape = shapes[id];
      if (shape == null) continue;
      for (final ring in shape.rings) {
        for (final ref in ring) {
          if (ref.segmentId == itemId ||
              (lines[ref.segmentId]?.touches(itemId) ?? false)) {
            return id;
          }
        }
      }
    }
    return null;
  }

  /// The complete filled region of one closed shape or circle, including
  /// its holes, or null while it is open.
  Region? regionOf(String itemId) {
    final id = shapeIdFor(itemId);
    if (id == null) return null;
    return (_regions[id] ??= (_regionFor(id),)).$1;
  }

  final Map<String, (Region?,)> _regions = {};

  Region? _regionFor(String id) {
    final circle = circles[id];
    if (circle != null) {
      final centre = points[circle.center];
      return centre == null ? null : DiscRegion(centre, circle.radius);
    }
    final shape = shapes[id];
    if (shape == null) return null;
    final contours = <List<CurveEdge>>[];
    for (var i = 0; i < shape.rings.length; i++) {
      final ring = shape.rings[i];
      final edges = contourOf(ring);
      if (edges == null) return null;
      if (edges.any(
        (edge) =>
            !edge.start.isFinite ||
            !edge.end.isFinite ||
            !edge.bulge.isFinite ||
            !edge.length.isFinite,
      )) {
        return null;
      }
      // A coincident-point edit stays visible and invalid, rather than
      // crashing region queries while the user moves the point back.
      final nonzero = edges.where((edge) => edge.length > 0).toList();
      if (nonzero.length < 2) return null;
      contours.add(orientContour(nonzero, positive: i == 0));
    }
    return CurveRegion(contours);
  }

  List<String> _closedRingCorners(List<SegmentRef> ring) {
    // Two distinct arcs, or an arc and its chord, can enclose land.
    if (ring.length < 2) return const [];
    final corners = <String>[];
    for (var i = 0; i < ring.length; i++) {
      final current = _directed(ring[i]);
      final next = _directed(ring[(i + 1) % ring.length]);
      if (current == null || next == null || current.$2 != next.$1) {
        return const [];
      }
      corners.add(current.$1);
    }
    return corners.toSet().length == corners.length ? corners : const [];
  }

  /// A closed ring's edges in traversal order, or null if its references
  /// do not close. Bézier lines use their fitted arcs. Closure follows point
  /// IDs, not validity: self-crossing and collapsed drafts remain queryable.
  List<CurveEdge>? contourOf(List<SegmentRef> ring) {
    if (_closedRingCorners(ring).isEmpty) return null;
    return [
      for (final ref in ring)
        if (ref.reversed)
          for (final edge in lines[ref.segmentId]!.edges(points).reversed)
            edge.reversed()
        else
          ...lines[ref.segmentId]!.edges(points),
    ];
  }

  (String, String)? _directed(SegmentRef ref) {
    final line = lines[ref.segmentId];
    if (line == null ||
        !points.containsKey(line.start) ||
        !points.containsKey(line.end)) {
      return null;
    }
    return ref.reversed ? (line.end, line.start) : (line.start, line.end);
  }
}

/// Orders IDs such as point-2 and point-10 by their number.
int compareItemIds(String a, String b) {
  final numberA = int.tryParse(a.substring(a.lastIndexOf('-') + 1)) ?? 0;
  final numberB = int.tryParse(b.substring(b.lastIndexOf('-') + 1)) ?? 0;
  return numberA != numberB ? numberA.compareTo(numberB) : a.compareTo(b);
}
