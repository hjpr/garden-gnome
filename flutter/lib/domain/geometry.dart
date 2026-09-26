import 'curve_edge.dart';
import 'planar.dart';
import 'region.dart';
import 'vec.dart';

/// An editable straight or circular connection between two owned points.
class LineSegment {
  const LineSegment(this.id, this.start, this.end, {this.bulge = 0});

  final String id;
  final String start;
  final String end;

  /// tan(signed sweep / 4); zero keeps existing straight segments unchanged.
  final double bulge;

  CurveEdge curve(Map<String, Vec> points) =>
      CurveEdge(points[start]!, points[end]!, bulge: bulge);

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
  const ClosedShape(
    this.id,
    this.segments, {
    this.holes = const [],
    this.label,
  });

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

/// Row and mound settings stored with an area's geometry.
///
/// Planting layout controls arrive in a later milestone; the values are kept
/// so saved drawings round-trip without loss.
class AreaDimensions {
  const AreaDimensions({
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
/// Instances are immutable: use [edit] to produce a changed copy.
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
  final AreaDimensions? dimensions;

  bool get isEmpty => points.isEmpty;

  /// Every shape and circle on the layer, bottom first. A shape higher in
  /// the stack cuts the shapes below it when used with Subtract.
  late final List<String> stack = _stack();

  /// The shapes and circles that are closed and enclose land, bottom first.
  late final List<String> closedIds = [
    for (final id in stack)
      if (regionOf(id) != null) id,
  ];

  /// All of the layer's land: every closed shape and circle together, or
  /// null while there is none.
  late final Region? region = _region();

  /// Whether the layer has any closed land yet.
  bool get isClosed => region != null;

  /// Total land area in square metres: the sum of every closed shape, or
  /// null while there is none. Overlapping shapes (an invalid layer) are
  /// counted once each, so the figure stays predictable.
  double? get area => closedIds.isEmpty
      ? null
      : closedIds.fold<double>(0, (sum, id) => sum + regionOf(id)!.area);

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

  Geometry edit(void Function(GeometryEditor editor) change) {
    final editor = GeometryEditor(this);
    change(editor);
    return editor.build();
  }

  Geometry copyWith({IdCounters? counters, AreaDimensions? dimensions}) =>
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

  Region? _region() {
    final ids = closedIds;
    if (ids.isEmpty) return null;
    if (ids.length == 1) return regionOf(ids.single);
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
      // An invalid layer: still show and test its land as the union, so
      // an overlap does not read as a hole.
      try {
        Region merged = regions.first;
        for (final next in regions.skip(1)) {
          merged = merged.combine(next, BooleanOperation.union);
        }
        return merged;
      } on StateError {
        // Fall through to the gathered pieces below.
      }
    }
    // Separate pieces can simply be gathered; nesting sorts out islands
    // inside another shape's hole.
    return CurveRegion([for (final region in regions) ...region.contours]);
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
      if (_closedRingCorners(ring).isEmpty) return null;
      final edges = _ringEdges(ring);
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
      contours.add(_oriented(nonzero, positive: i == 0));
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

  List<CurveEdge> _ringEdges(List<SegmentRef> ring) => [
    for (final ref in ring)
      if (ref.reversed)
        lines[ref.segmentId]!.curve(points).reversed()
      else
        lines[ref.segmentId]!.curve(points),
  ];

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

/// Thrown when an edit would break a geometry rule. The message is shown
/// to the user.
class GeometryRuleError implements Exception {
  const GeometryRuleError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A working copy of a [Geometry] used to make one set of changes.
///
/// Boundary membership is kept up to date after each structural change.
class GeometryEditor {
  GeometryEditor(Geometry source)
    : _source = source,
      _points = Map.of(source.points),
      _lines = Map.of(source.lines),
      _circles = Map.of(source.circles),
      _shapes = Map.of(source.shapes),
      _order = List.of(source.stack),
      _counters = source.counters.atLeast(
        IdCounters(
          points: _highestItemNumber(source.points.keys),
          lines: _highestItemNumber(source.lines.keys),
          circles: _highestItemNumber(source.circles.keys),
          shapes: _highestItemNumber(source.shapes.keys),
        ),
      );

  final Geometry _source;
  final Map<String, Vec> _points;
  final Map<String, LineSegment> _lines;
  final Map<String, Circle> _circles;
  final Map<String, ClosedShape> _shapes;
  final List<String> _order;
  IdCounters _counters;

  Map<String, Vec> get points => _points;
  Map<String, LineSegment> get lines => _lines;

  String addPoint(Vec position) {
    if (!position.isFinite) {
      throw const GeometryRuleError('Point coordinates must be finite');
    }
    _counters = IdCounters(
      points: _counters.points + 1,
      lines: _counters.lines,
      circles: _counters.circles,
      shapes: _counters.shapes,
    );
    final id = 'point-${_counters.points}';
    _points[id] = position;
    return id;
  }

  void movePoint(String id, Vec position) {
    if (!_points.containsKey(id)) return;
    _points[id] = position;
  }

  /// Joins two points with a straight segment or circular arc.
  String connect(String a, String b, {double bulge = 0}) {
    if (a == b || !_points.containsKey(a) || !_points.containsKey(b)) {
      throw const GeometryRuleError('Choose two different points');
    }
    if (!bulge.isFinite) {
      throw const GeometryRuleError('An arc must have a finite sweep');
    }
    if (_lines.values.any(
      (line) =>
          line.connects(a, b) &&
          (line.start == a ? line.bulge : -line.bulge) == bulge,
    )) {
      throw const GeometryRuleError('These points are already joined');
    }
    if (_degree(a) >= 2 || _degree(b) >= 2) {
      throw const GeometryRuleError(
        'A point can join at most two lines, so boundaries cannot branch',
      );
    }
    final id = _nextLineId();
    _lines[id] = LineSegment(id, a, b, bulge: bulge);
    _refreshBoundary();
    return id;
  }

  /// Draws a circle on top of the layer's other shapes.
  String addCircle(String centerId, double radius) {
    if (!_points.containsKey(centerId)) {
      throw const GeometryRuleError('That center point no longer exists');
    }
    if (!radius.isFinite || radius <= tolerance) {
      throw const GeometryRuleError('A circle must have size');
    }
    _counters = IdCounters(
      points: _counters.points,
      lines: _counters.lines,
      circles: _counters.circles + 1,
      shapes: _counters.shapes,
    );
    final id = 'circle-${_counters.circles}';
    _circles[id] = Circle(id, centerId, radius);
    _order.add(id);
    return id;
  }

  /// Names a shape or circle; null restores the automatic name.
  void setLabel(String itemId, String? label) {
    final circle = _circles[itemId];
    if (circle != null) {
      _circles[itemId] = Circle(
        circle.id,
        circle.center,
        circle.radius,
        label: label,
      );
      return;
    }
    final shape = _shapes[itemId];
    if (shape == null) {
      throw const GeometryRuleError('That shape no longer exists');
    }
    _shapes[itemId] = ClosedShape(
      shape.id,
      shape.segments,
      holes: shape.holes,
      label: label,
    );
  }

  /// Moves a shape or circle to [index] in the stack (0 is the bottom).
  void moveInStack(String itemId, int index) {
    if (!_order.remove(itemId)) {
      throw const GeometryRuleError('That shape no longer exists');
    }
    _order.insert(index.clamp(0, _order.length), itemId);
  }

  /// Changes a circle's size; its centre stays put.
  void resizeCircle(String circleId, double radius) {
    final circle = _circles[circleId];
    if (circle == null) return;
    if (!radius.isFinite || radius <= tolerance) {
      throw const GeometryRuleError('A circle must have size');
    }
    _circles[circleId] = circle.withRadius(radius);
  }

  /// Places a projected point on an edge without changing its curve.
  String insertPoint(String lineId, Vec position) {
    final original = _lines[lineId];
    if (original == null) {
      throw const GeometryRuleError('That line no longer exists');
    }
    if (!position.isFinite) {
      throw const GeometryRuleError('Point coordinates must be finite');
    }
    final curve = original.curve(_points);
    final projected = curve.closestPoint(position);
    if (projected.distanceTo(curve.start) <= tolerance ||
        projected.distanceTo(curve.end) <= tolerance) {
      throw const GeometryRuleError('Choose a point between the edge ends');
    }
    final t = curve.parameterOf(projected).clamp(0.0, 1.0);
    final pointId = addPoint(projected);
    final first = _nextLineId();
    final second = _nextLineId();
    _lines.remove(lineId);
    _lines[first] = LineSegment(
      first,
      original.start,
      pointId,
      bulge: curve.portion(0, t).bulge,
    );
    _lines[second] = LineSegment(
      second,
      pointId,
      original.end,
      bulge: curve.portion(t, 1).bulge,
    );
    for (final shape in _shapes.values.toList()) {
      final rings = [
        for (final ring in shape.rings)
          <SegmentRef>[
            for (final ref in ring)
              if (ref.segmentId != lineId)
                ref
              else if (ref.reversed) ...[
                SegmentRef(second, reversed: true),
                SegmentRef(first, reversed: true),
              ] else ...[
                SegmentRef(first),
                SegmentRef(second),
              ],
          ],
      ];
      _shapes[shape.id] = ClosedShape(
        shape.id,
        rings.first,
        holes: rings.skip(1).toList(),
        label: shape.label,
      );
    }
    return pointId;
  }

  /// Removes the items and anything that depends on them.
  ///
  /// Deleting a point removes its lines and any circle drawn around it;
  /// deleting a shape removes its lines. Deleting a circle keeps its
  /// centre point. Neighbouring points are never reconnected.
  void delete(Iterable<String> itemIds) {
    final linesToRemove = <String>{};
    final pointsToRemove = <String>{};
    final circlesToRemove = <String>{};
    for (final id in itemIds) {
      if (_points.containsKey(id)) {
        pointsToRemove.add(id);
        linesToRemove.addAll(
          _lines.values.where((l) => l.touches(id)).map((l) => l.id),
        );
        circlesToRemove.addAll(
          _circles.values.where((c) => c.center == id).map((c) => c.id),
        );
      }
      if (_circles.containsKey(id)) circlesToRemove.add(id);
      if (_lines.containsKey(id)) linesToRemove.add(id);
      final shape = _shapes[id];
      if (shape != null) {
        linesToRemove.addAll(
          shape.rings.expand((ring) => ring).map((ref) => ref.segmentId),
        );
        // Deleting the whole object discards its holes as well as its rim.
        _shapes.remove(id);
        _order.remove(id);
      }
    }
    for (final id in linesToRemove) {
      _lines.remove(id);
    }
    for (final id in pointsToRemove) {
      _points.remove(id);
    }
    for (final id in circlesToRemove) {
      _circles.remove(id);
      _order.remove(id);
    }
    _refreshBoundary();
  }

  /// Whether [other] takes part in a Boolean with [selected]. Shapes that
  /// overlap always do. Union also merges shapes that share an edge (such
  /// as a disc that exactly fills a hole), but not ones touching at a point.
  static bool _joins(
    Region other,
    Region selected,
    BooleanOperation operation,
  ) {
    if (other.overlaps(selected)) return true;
    if (operation != BooleanOperation.union) return false;
    try {
      final merged = selected.combine(other, operation);
      final pieces =
          CurveRegion(selected.contours).outerCount +
          CurveRegion(other.contours).outerCount;
      return merged.outerCount < pieces;
    } on StateError {
      return false;
    }
  }

  /// Combines the clicked shape with others on this layer and returns the
  /// IDs of the resulting shapes, bottom first.
  ///
  /// Union merges the shape with every shape it overlaps. Subtract uses the
  /// shape as a cutter: it cuts every shape below it in the stack that it
  /// overlaps, and is then removed. Cut shapes may split into pieces or
  /// disappear. All checks happen on a detached copy, so a refusal leaves
  /// this editor unchanged.
  List<String> boolean(String operandId, BooleanOperation operation) {
    final before = build();
    final selectedId = before.shapeIdFor(operandId);
    if (selectedId == null) {
      throw const GeometryRuleError('Choose a closed shape or circle');
    }
    final selected = _operandRegion(before, selectedId);
    final position = before.stack.indexOf(selectedId);
    final partners = [
      for (final (index, id) in before.stack.indexed)
        if (id != selectedId &&
            (operation == BooleanOperation.union || index < position) &&
            before.regionOf(id) != null &&
            _joins(_operandRegion(before, id), selected, operation))
          id,
    ];
    if (partners.isEmpty) {
      throw GeometryRuleError(
        operation == BooleanOperation.union
            ? 'This shape does not overlap another shape on this layer'
            : 'Nothing below this shape overlaps it. Move it above the shape '
                  'it should cut',
      );
    }
    return _applyBoolean(before, selectedId, selected, partners, operation);
  }

  /// Combines exactly the chosen shapes and returns the IDs of the
  /// resulting shapes, bottom first. This is what the Operations panel
  /// runs on the selection.
  ///
  /// [itemIds] may name shapes, circles, or any outline, corner, or centre
  /// of one; each resolves to its shape. At least two shapes are needed.
  /// Union merges them all; each must overlap or share an edge with
  /// another chosen shape. Subtract uses the chosen shape highest in the
  /// stack as the cutter: it cuts every other chosen shape, each of which
  /// it must overlap, and is then removed. All checks happen on a detached
  /// copy, so a refusal leaves this editor unchanged.
  List<String> booleanOf(Iterable<String> itemIds, BooleanOperation operation) {
    final before = build();
    final chosen = <String>{};
    for (final itemId in itemIds) {
      final id = before.shapeIdFor(itemId);
      if (id == null || before.regionOf(id) == null) {
        throw const GeometryRuleError(
          'Select only closed shapes and circles for a Boolean',
        );
      }
      chosen.add(id);
    }
    if (chosen.length < 2) {
      throw const GeometryRuleError('Select at least two shapes on one layer');
    }
    // Bottom first, so the last one is the top of the stack.
    final ordered = [
      for (final id in before.stack)
        if (chosen.contains(id)) id,
    ];
    final regions = {for (final id in ordered) id: _operandRegion(before, id)};
    final selectedId = ordered.last;
    final partners = ordered.sublist(0, ordered.length - 1);

    if (operation == BooleanOperation.union) {
      for (final id in ordered) {
        final joined = ordered.any(
          (other) =>
              other != id && _joins(regions[other]!, regions[id]!, operation),
        );
        if (!joined) {
          throw GeometryRuleError(
            '${before.labelOf(id)} does not overlap or share an edge with '
            'another selected shape',
          );
        }
      }
    } else {
      for (final id in partners) {
        if (!_joins(regions[id]!, regions[selectedId]!, operation)) {
          throw GeometryRuleError(
            '${before.labelOf(selectedId)} is on top, so it is the cutter, '
            'but it does not overlap ${before.labelOf(id)}',
          );
        }
      }
    }
    return _applyBoolean(
      before,
      selectedId,
      regions[selectedId]!,
      partners,
      operation,
    );
  }

  /// Replaces [selectedId] and its [partners] with the Boolean result and
  /// returns the new shape IDs, bottom first. For Subtract, [selectedId]
  /// is the cutter and the partners are the shapes it cuts.
  List<String> _applyBoolean(
    Geometry before,
    String selectedId,
    Region selected,
    List<String> partners,
    BooleanOperation operation,
  ) {
    final working = GeometryEditor(before);
    final results = <String>[];
    if (operation == BooleanOperation.union) {
      CurveRegion? merged;
      for (final id in partners) {
        merged = _combineOrRefuse(
          merged ?? selected,
          _operandRegion(before, id),
          operation,
        );
      }
      final lowest = before.stack.firstWhere(
        (id) => id == selectedId || partners.contains(id),
      );
      final label =
          before.shapes[lowest]?.label ?? before.circles[lowest]?.label;
      final index = before.stack.indexOf(lowest);
      working._consume({selectedId, ...partners});
      final at = index.clamp(0, working._order.length);
      results.addAll(working._storeRegion(merged!, label: label, at: at));
    } else {
      final cuts = <String, CurveRegion>{
        for (final id in partners)
          id: _combineOrRefuse(_operandRegion(before, id), selected, operation),
      };
      final positions = {
        for (final id in partners) id: before.stack.indexOf(id),
      };
      final labels = {
        for (final id in partners)
          id: before.shapes[id]?.label ?? before.circles[id]?.label,
      };
      for (final id in partners) {
        final cut = cuts[id]!;
        if (cut.contours.isEmpty || cut.area <= tolerance * cut.perimeter) {
          throw GeometryRuleError(
            'Subtract would remove all of ${before.labelOf(id)}. '
            'Delete it instead',
          );
        }
      }
      working._consume({selectedId, ...partners});
      // Re-insert from the top down so earlier indexes stay correct.
      for (final id in partners.reversed) {
        final at = positions[id]!.clamp(0, working._order.length);
        results.insertAll(
          0,
          working._storeRegion(cuts[id]!, label: labels[id], at: at),
        );
      }
    }
    for (final id in results) {
      final problem = geometryProblem(_onlyShape(working.build(), id));
      if (problem != null) {
        throw GeometryRuleError(
          'The operation would create an invalid shape: $problem',
        );
      }
    }
    _points
      ..clear()
      ..addAll(working._points);
    _lines
      ..clear()
      ..addAll(working._lines);
    _circles
      ..clear()
      ..addAll(working._circles);
    _shapes
      ..clear()
      ..addAll(working._shapes);
    _order
      ..clear()
      ..addAll(working._order);
    _counters = working._counters;
    return results;
  }

  static Region _operandRegion(Geometry geometry, String id) {
    final problem = geometryProblem(_onlyShape(geometry, id));
    if (problem != null) {
      throw GeometryRuleError(
        'Cannot combine ${geometry.labelOf(id)}: $problem',
      );
    }
    final region = geometry.regionOf(id);
    if (region == null) {
      throw GeometryRuleError('Close ${geometry.labelOf(id)} first');
    }
    return region;
  }

  static CurveRegion _combineOrRefuse(
    Region a,
    Region b,
    BooleanOperation operation,
  ) {
    try {
      return a.combine(b, operation);
    } on StateError catch (error) {
      throw GeometryRuleError('Cannot resolve the operation: ${error.message}');
    }
  }

  /// Stores each separate piece of [region] as its own shape at [at] in
  /// the stack, with its holes. The first piece keeps [label]; later
  /// pieces are numbered after it. Slivers with no real area are dropped.
  List<String> _storeRegion(CurveRegion region, {String? label, int at = 0}) {
    final outers = [
      for (final ring in region.contours)
        if (_signedArea(ring) > 0) ring,
    ];
    final holesOf = {for (final outer in outers) outer: <List<CurveEdge>>[]};
    for (final ring in region.contours) {
      if (_signedArea(ring) > 0) continue;
      // A hole belongs to the smallest piece around it.
      List<CurveEdge>? owner;
      for (final outer in outers) {
        final probe = ring.first.pointAt(0.5);
        if (CurveRegion([outer]).locate(probe) == PointLocation.outside) {
          continue;
        }
        if (owner == null ||
            _signedArea(outer).abs() < _signedArea(owner).abs()) {
          owner = outer;
        }
      }
      if (owner != null) holesOf[owner]!.add(ring);
    }
    final ids = <String>[];
    for (final outer in outers) {
      final piece = CurveRegion([outer, ...holesOf[outer]!]);
      if (piece.area <= tolerance * piece.perimeter) continue;
      final id = _nextShapeId();
      _shapes[id] = ClosedShape(
        id,
        _storeRing(outer),
        holes: [for (final hole in holesOf[outer]!) _storeRing(hole)],
        label: label == null || ids.isEmpty
            ? label
            : '$label ${ids.length + 1}',
      );
      _order.insert((at + ids.length).clamp(0, _order.length), id);
      ids.add(id);
    }
    return ids;
  }

  /// Deletes only the operands' records and their now-unreferenced anchors.
  void _consume(Set<String> ids) {
    final before = build();
    final candidates = before.definingPoints(ids);
    final segments = <String>{
      for (final id in ids)
        for (final ring in _shapes[id]?.rings ?? <List<SegmentRef>>[])
          for (final ref in ring) ref.segmentId,
    };
    for (final id in ids) {
      _shapes.remove(id);
      _circles.remove(id);
      _order.remove(id);
    }
    final retained = {
      for (final shape in _shapes.values)
        for (final ring in shape.rings)
          for (final ref in ring) ref.segmentId,
    };
    for (final id in segments.difference(retained)) {
      _lines.remove(id);
    }
    for (final id in candidates) {
      if (!_lines.values.any((line) => line.touches(id)) &&
          !_circles.values.any((circle) => circle.center == id)) {
        _points.remove(id);
      }
    }
  }

  List<SegmentRef> _storeRing(List<CurveEdge> ring) {
    final corners = [for (final edge in ring) addPoint(edge.start)];
    return [
      for (var i = 0; i < ring.length; i++)
        _storeEdge(corners[i], corners[(i + 1) % ring.length], ring[i].bulge),
    ];
  }

  SegmentRef _storeEdge(String start, String end, double bulge) {
    final id = _nextLineId();
    _lines[id] = LineSegment(id, start, end, bulge: bulge);
    return SegmentRef(id);
  }

  Geometry build() => Geometry(
    id: _source.id,
    ownerLayerId: _source.ownerLayerId,
    points: _points,
    lines: _lines,
    circles: _circles,
    shapes: _shapes,
    order: _order,
    counters: _counters,
    dimensions: _source.dimensions,
  );

  int _degree(String pointId) =>
      _lines.values.where((line) => line.touches(pointId)).length;

  String _nextLineId() {
    _counters = IdCounters(
      points: _counters.points,
      lines: _counters.lines + 1,
      circles: _counters.circles,
      shapes: _counters.shapes,
    );
    return 'line-${_counters.lines}';
  }

  String _nextShapeId() {
    _counters = IdCounters(
      points: _counters.points,
      lines: _counters.lines,
      circles: _counters.circles,
      shapes: _counters.shapes + 1,
    );
    return 'shape-${_counters.shapes}';
  }

  /// Repairs each existing ring from its surviving connected segments.
  /// A shape with nothing left is removed; a new closed loop becomes a new
  /// shape on top of the stack.
  void _refreshBoundary() {
    final chains = _chains();
    final claimed = <_Chain>{};
    for (final shape in _shapes.values.toList()) {
      final rings = <List<SegmentRef>>[];
      for (final ring in shape.rings) {
        final survivors = ring.map((ref) => ref.segmentId).toSet();
        final members = chains.where(
          (chain) => chain.segments.any(survivors.contains),
        );
        final refs = <SegmentRef>[];
        for (final chain in members) {
          claimed.add(chain);
          refs.addAll(chain.refs);
        }
        rings.add(refs);
      }
      if (rings.every((ring) => ring.isEmpty)) {
        _shapes.remove(shape.id);
        _order.remove(shape.id);
        continue;
      }
      _shapes[shape.id] = ClosedShape(
        shape.id,
        rings.first,
        holes: rings.skip(1).toList(),
        label: shape.label,
      );
    }

    for (final loop in chains.where((chain) => chain.closed)) {
      if (claimed.contains(loop)) continue;
      final id = _nextShapeId();
      _shapes[id] = ClosedShape(id, loop.refs);
      _order.add(id);
    }
  }

  /// Splits the lines into connected chains. Because no point has more than
  /// two lines, each chain is either an open path or a closed loop.
  List<_Chain> _chains() {
    final visited = <String>{};
    final chains = <_Chain>[];
    final byPoint = <String, List<LineSegment>>{};
    for (final line in _lines.values) {
      byPoint.putIfAbsent(line.start, () => []).add(line);
      byPoint.putIfAbsent(line.end, () => []).add(line);
    }
    final sortedLines = _lines.values.toList()
      ..sort((a, b) => compareItemIds(a.id, b.id));

    String startOf(LineSegment seed) {
      var point = seed.start;
      var via = seed;
      final seen = <String>{seed.id};
      while (true) {
        final next = byPoint[point]!.where((l) => l != via).firstOrNull;
        if (next == null || !seen.add(next.id)) return point;
        point = next.otherEnd(point);
        via = next;
      }
    }

    for (final seed in sortedLines) {
      if (visited.contains(seed.id)) continue;
      final origin = startOf(seed);
      final refs = <SegmentRef>[];
      var point = origin;
      LineSegment? line = byPoint[origin]!
          .where((l) => !visited.contains(l.id))
          .firstOrNull;
      while (line != null && visited.add(line.id)) {
        final reversed = line.end == point;
        refs.add(SegmentRef(line.id, reversed: reversed));
        point = line.otherEnd(point);
        line = byPoint[point]!
            .where((l) => !visited.contains(l.id))
            .firstOrNull;
      }
      chains.add(_Chain(refs, closed: point == origin && refs.length >= 2));
    }
    return chains;
  }
}

class _Chain {
  _Chain(this.refs, {required this.closed});

  final List<SegmentRef> refs;
  final bool closed;

  Iterable<String> get segments => refs.map((ref) => ref.segmentId);
}

/// Orders IDs such as point-2 and point-10 by their number.
int compareItemIds(String a, String b) {
  final numberA = int.tryParse(a.substring(a.lastIndexOf('-') + 1)) ?? 0;
  final numberB = int.tryParse(b.substring(b.lastIndexOf('-') + 1)) ?? 0;
  return numberA != numberB ? numberA.compareTo(numberB) : a.compareTo(b);
}

/// Checks topology within each object, not intersections between operands.
/// Ordinary edits retain invalid drawings; Boolean operations use the same
/// rules on each operand separately before consuming anything.
String? geometryProblem(Geometry geometry) {
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

  final owners = _ownersOf(geometry);
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
    final edge = line.curve(geometry.points);
    for (final entry in points) {
      if (line.touches(entry.key) || separate(line.id, entry.key)) continue;
      if (edge.distanceTo(entry.value) <= tolerance) {
        return 'A point cannot rest on an edge it is not part of';
      }
    }
    for (var j = 0; j < i; j++) {
      final other = lines[j];
      if (separate(line.id, other.id)) continue;
      final otherEdge = other.curve(geometry.points);
      final shared = {
        line.start,
        line.end,
      }.intersection({other.start, other.end});
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

  for (final circle in geometry.circles.values) {
    final disc = DiscRegion(geometry.points[circle.center]!, circle.radius);
    for (final line in lines) {
      if (separate(line.id, circle.id)) continue;
      if (disc.contours
          .expand((ring) => ring)
          .any(
            (edge) =>
                intersections(edge, line.curve(geometry.points)).isNotEmpty,
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
    if (geometry._closedRingCorners(ring).isEmpty) {
      regions.add(null);
      continue;
    }
    final edges = geometry._ringEdges(ring);
    final region = CurveRegion([_oriented(edges, positive: true)]);
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

Map<String, Set<String>> _ownersOf(Geometry geometry) {
  final owners = <String, Set<String>>{};
  void add(String item, String shape) =>
      owners.putIfAbsent(item, () => {}).add(shape);
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

/// Isolating one shape lets it be checked on its own, without mistaking an
/// overlap with another shape for a self-crossing outline.
Geometry _onlyShape(Geometry geometry, String id) {
  final points = geometry.definingPoints([id]);
  final shape = geometry.shapes[id];
  final circle = geometry.circles[id];
  return Geometry(
    id: geometry.id,
    ownerLayerId: geometry.ownerLayerId,
    points: {for (final point in points) point: ?geometry.points[point]},
    lines: {
      if (shape != null)
        for (final ring in shape.rings)
          for (final ref in ring) ref.segmentId: ?geometry.lines[ref.segmentId],
    },
    circles: {id: ?circle},
    shapes: {id: ?shape},
    order: [id],
    counters: geometry.counters,
  );
}

double _signedArea(List<CurveEdge> ring) {
  if (ring.isEmpty) return 0;
  final origin = ring.first.start;
  return ring.fold(
    0.0,
    (area, edge) =>
        area +
        CurveEdge(
          edge.start - origin,
          edge.end - origin,
          bulge: edge.bulge,
        ).signedArea,
  );
}

int _highestItemNumber(Iterable<String> ids) => ids.fold(0, (highest, id) {
  final number = int.tryParse(id.substring(id.lastIndexOf('-') + 1)) ?? 0;
  return number > highest ? number : highest;
});

List<CurveEdge> _oriented(List<CurveEdge> ring, {required bool positive}) =>
    (_signedArea(ring) >= 0) == positive
    ? ring
    : [for (final edge in ring.reversed) edge.reversed()];
