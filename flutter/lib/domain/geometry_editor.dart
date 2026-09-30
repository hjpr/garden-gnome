import 'curve_contour.dart';
import 'curve_edge.dart';
import 'geometry.dart';
import 'geometry_rules.dart';
import 'planar.dart';
import 'region.dart';
import 'vec.dart';

extension GeometryEditing on Geometry {
  Geometry edit(void Function(GeometryEditor editor) change) {
    final editor = GeometryEditor(this);
    change(editor);
    return editor.build();
  }
}

/// An unrepresentable edit or a refused operation, with a user-facing reason.
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

  /// Joins two points with a straight segment, a circular arc ([bulge]),
  /// or a Bézier curve (handles as offsets from [a] and [b]). Zero-length
  /// handles on both ends make a straight line.
  String connect(
    String a,
    String b, {
    double bulge = 0,
    Vec? startHandle,
    Vec? endHandle,
  }) {
    if (a == b || !_points.containsKey(a) || !_points.containsKey(b)) {
      throw const GeometryRuleError('Choose two different points');
    }
    if (!bulge.isFinite) {
      throw const GeometryRuleError('An arc must have a finite sweep');
    }
    final curved =
        (startHandle != null && startHandle != Vec.zero) ||
        (endHandle != null && endHandle != Vec.zero);
    if (curved &&
        (!(startHandle ?? Vec.zero).isFinite ||
            !(endHandle ?? Vec.zero).isFinite)) {
      throw const GeometryRuleError('A curve handle must be finite');
    }
    final proposed = LineSegment(
      '',
      a,
      b,
      bulge: curved ? 0 : bulge,
      startHandle: curved ? startHandle ?? Vec.zero : null,
      endHandle: curved ? endHandle ?? Vec.zero : null,
    );
    if (_lines.values.any(proposed.sameCurveAs)) {
      throw const GeometryRuleError('These points are already joined');
    }
    if (_degree(a) >= 2 || _degree(b) >= 2) {
      throw const GeometryRuleError(
        'A point can join at most two lines, so boundaries cannot branch',
      );
    }
    final id = _nextLineId();
    _lines[id] = LineSegment(
      id,
      a,
      b,
      bulge: proposed.bulge,
      startHandle: proposed.startHandle,
      endHandle: proposed.endHandle,
    );
    _refreshBoundary();
    return id;
  }

  /// Sets a Bézier line's handle at [pointId], one of its ends, as an
  /// offset from that point.
  void setHandle(String lineId, String pointId, Vec offset) {
    final line = _lines[lineId];
    if (line == null || !line.isBezier || !line.touches(pointId)) return;
    if (!offset.isFinite) {
      throw const GeometryRuleError('A curve handle must be finite');
    }
    _lines[lineId] = pointId == line.start
        ? line.withHandles(offset, line.endHandle!)
        : line.withHandles(line.startHandle!, offset);
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
    final bezier = original.bezier(_points);
    final projected = original.closestPoint(_points, position);
    final startPoint = _points[original.start]!;
    final endPoint = _points[original.end]!;
    if (projected.distanceTo(startPoint) <= tolerance ||
        projected.distanceTo(endPoint) <= tolerance) {
      throw const GeometryRuleError('Choose a point between the edge ends');
    }
    final pointId = addPoint(projected);
    final first = _nextLineId();
    final second = _nextLineId();
    _lines.remove(lineId);
    if (bezier != null) {
      // Splitting a Bézier curve gives two that trace it exactly.
      final (a, b) = bezier.split(bezier.closestParameter(projected));
      _lines[first] = LineSegment(
        first,
        original.start,
        pointId,
        startHandle: a.p1 - a.p0,
        endHandle: a.p2 - projected,
      );
      _lines[second] = LineSegment(
        second,
        pointId,
        original.end,
        startHandle: b.p1 - projected,
        endHandle: b.p2 - b.p3,
      );
    } else {
      final curve = original.curve(_points);
      final t = curve.parameterOf(projected).clamp(0.0, 1.0);
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
    }
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
  /// Deleting a point removes its lines and any circle drawn around it.
  /// Deleting a shape or circle removes it whole: its lines, and its
  /// points unless another line or circle still uses them. Otherwise a
  /// left-behind point (a circle's centre, say) would leave the layer
  /// unfinished with nothing obvious to show why. Deleting a line keeps
  /// its points. Neighbouring points are never reconnected.
  void delete(Iterable<String> itemIds) {
    final linesToRemove = <String>{};
    final pointsToRemove = <String>{};
    final circlesToRemove = <String>{};
    // Points of deleted shapes and circles, dropped if nothing else uses
    // them once those are gone.
    final wholeShapePoints = <String>{};
    for (final id in itemIds) {
      if (_circles[id] case final circle?) {
        wholeShapePoints.add(circle.center);
      }
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
        final segments = shape.rings
            .expand((ring) => ring)
            .map((ref) => ref.segmentId);
        linesToRemove.addAll(segments);
        for (final segment in segments) {
          if (_lines[segment] case final line?) {
            wholeShapePoints.addAll([line.start, line.end]);
          }
        }
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
    for (final id in wholeShapePoints) {
      if (!_lines.values.any((line) => line.touches(id)) &&
          !_circles.values.any((circle) => circle.center == id)) {
        _points.remove(id);
      }
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
        if (signedContourArea(ring) > 0) ring,
    ];
    final holesOf = {for (final outer in outers) outer: <List<CurveEdge>>[]};
    for (final ring in region.contours) {
      if (signedContourArea(ring) > 0) continue;
      // A hole belongs to the smallest piece around it.
      List<CurveEdge>? owner;
      for (final outer in outers) {
        final probe = ring.first.pointAt(0.5);
        if (CurveRegion([outer]).locate(probe) == PointLocation.outside) {
          continue;
        }
        if (owner == null ||
            signedContourArea(outer).abs() < signedContourArea(owner).abs()) {
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

int _highestItemNumber(Iterable<String> ids) => ids.fold(0, (highest, id) {
  final number = int.tryParse(id.substring(id.lastIndexOf('-') + 1)) ?? 0;
  return number > highest ? number : highest;
});
