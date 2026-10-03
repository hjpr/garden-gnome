part of 'canvas_input.dart';

/// Multi-click construction. Builds through the controller so hover and
/// click share the commit rules.
extension _ConstructionInput on CanvasInput {
  /// Both Arc functions take three clicks; only their order differs.
  /// 3-point: start, a point on the curve, end. Start-end: start, end,
  /// then the arc's middle, which sets the bend.
  bool get _endSecond => editor.function == ToolFunction.startEndArc;

  void _arcClick(String layerId, Geometry geometry, Offset screen) {
    final points = editor.arcPoints;
    if (points.isEmpty) {
      editor.addArcPoint(_arcEndpointAt(geometry, screen));
      return editor.showNotice(null);
    }
    if (points.length == 1) {
      final second = _endSecond
          ? _arcEndpointAt(geometry, screen, from: points.first.pointId)
          : ArcPoint(_snapped(screen).position);
      if (second.position.distanceTo(points.first.position) <= tolerance) {
        return editor.showNotice(
          _endSecond
              ? 'Choose a different point for the end of the Arc'
              : 'Choose a different point for the Arc to pass through',
        );
      }
      editor.addArcPoint(second);
      return editor.showNotice(null);
    }
    final (end, curve) = _arcFromThirdClick(geometry, screen);
    if (curve == null) {
      return editor.showNotice(
        'An Arc needs three distinct points that are not on one straight line',
      );
    }
    late String lineId;
    final (next, problem) = editor.tryGeometryEdit(layerId, (e) {
      lineId = _addArc(e, points.first, end, curve);
    });
    if (next == null) return editor.showNotice(problem);
    editor.commit('Draw Arc', next);
    editor.selectItem(lineId);
  }

  /// The end and the curve given two clicks so far and the pointer as the
  /// third. The curve is null when the three points make no circle.
  (ArcPoint end, CurveEdge? curve) _arcFromThirdClick(
    Geometry geometry,
    Offset screen,
  ) {
    final points = editor.arcPoints;
    final start = points[0];
    if (_endSecond) {
      final end = points[1];
      final middle = _arcMiddle(start.position, end.position, screen);
      return (end, CurveEdge.through(start.position, middle, end.position));
    }
    final end = _arcEndpointAt(geometry, screen, from: start.pointId);
    return (
      end,
      CurveEdge.through(start.position, points[1].position, end.position),
    );
  }

  /// Start-end: the middle of the arc, kept on the line square to the
  /// chord through its centre so the arc stays symmetric. Only the
  /// pointer's distance from the chord counts; it sets the bend.
  Vec _arcMiddle(Vec start, Vec end, Offset screen) {
    final chord = end - start;
    final centre = (start + end) / 2;
    final square = Vec(-chord.y, chord.x) / chord.length;
    final height = (_snapped(screen).position - centre).dot(square);
    return centre + square * height;
  }

  /// Arc endpoints can close a two-edge circular segment. Unlike straight
  /// Draw, an existing straight connection does not rule out this endpoint.
  ArcPoint _arcEndpointAt(Geometry geometry, Offset screen, {String? from}) {
    final id = pointAt(
      geometry,
      editor.camera,
      screen,
      accept: (id) => id != from && geometry.degreeOf(id) < 2,
    );
    return id == null
        ? ArcPoint(_snapped(screen).position)
        : ArcPoint(geometry.points[id]!, pointId: id);
  }

  String _addArc(
    GeometryEditor e,
    ArcPoint start,
    ArcPoint end,
    CurveEdge curve,
  ) => e.connect(
    start.pointId ?? e.addPoint(start.position),
    end.pointId ?? e.addPoint(end.position),
    bulge: curve.bulge,
  );

  Preview? _arcPreview(String layerId, Geometry geometry, Offset screen) {
    final points = editor.arcPoints;
    if (points.isEmpty) {
      final start = _arcEndpointAt(geometry, screen);
      return start.pointId != null
          ? HoverPreview(start.pointId!, joinable: true)
          : PointPreview(start.position, valid: true);
    }
    final snap = _snapped(screen);
    if (points.length == 1) {
      if (!_endSecond) {
        return ArcPreview(
          start: points.first.position,
          through: snap.position,
          valid: true,
          guides: snap.guides,
        );
      }
      final end = _arcEndpointAt(geometry, screen, from: points.first.pointId);
      return ArcPreview(
        start: points.first.position,
        end: end.position,
        joinTarget: end.pointId,
        valid: end.position.distanceTo(points.first.position) > tolerance,
        guides: end.pointId == null ? snap.guides : SnapGuides.none,
      );
    }
    final (end, curve) = _arcFromThirdClick(geometry, screen);
    // Start-end's third click is a free point on the curve, never a join.
    final joins = !_endSecond && end.pointId != null;
    return ArcPreview(
      start: points[0].position,
      through: _endSecond
          ? _arcMiddle(points[0].position, end.position, screen)
          : points[1].position,
      end: end.position,
      curve: curve,
      joinTarget: _endSecond ? null : end.pointId,
      valid:
          curve != null &&
          _staysValid(layerId, (e) => _addArc(e, points.first, end, curve)),
      guides: joins ? SnapGuides.none : snap.guides,
    );
  }

  /// Polygon: the first click is kept aside like a circle's; the second
  /// adds every corner and edge as one undoable step.
  void _polygonClick(String layerId, Offset screen) {
    final start = editor.polygonStart;
    final position = _snapped(screen).position;
    if (start == null) {
      editor.setPolygonStart(position);
      return editor.showNotice(null);
    }
    final corners = _polygonCorners(start, position);
    if (corners == null) return;
    late String firstLineId;
    final (next, problem) = editor.tryGeometryEdit(
      layerId,
      (e) => firstLineId = _addPolygon(e, corners),
    );
    if (next == null) return editor.showNotice(problem);
    editor.commit(
      editor.function == ToolFunction.rectangle
          ? 'Draw rectangle'
          : 'Draw polygon',
      next,
    );
    editor.selectItem(
      editor.document.geometryOf(layerId).shapeIdFor(firstLineId) ??
          firstLineId,
    );
  }

  /// Corners for the current Polygon function, or null while the two
  /// clicks are too close together.
  List<Vec>? _polygonCorners(Vec start, Vec pointer) =>
      editor.function == ToolFunction.rectangle
      ? rectangleCorners(start, pointer)
      : regularPolygonCorners(start, pointer, editor.polygonSides);

  /// Adds the corners as points joined in a closed loop. Returns the first
  /// edge, whose closed shape becomes the selection.
  String _addPolygon(GeometryEditor e, List<Vec> corners) {
    final ids = [for (final corner in corners) e.addPoint(corner)];
    final first = e.connect(ids.first, ids[1]);
    for (var i = 1; i < ids.length; i++) {
      e.connect(ids[i], ids[(i + 1) % ids.length]);
    }
    return first;
  }

  Preview _polygonPreview(String layerId, Offset screen) {
    final snap = _snapped(screen);
    final start = editor.polygonStart;
    if (start == null) {
      return PointPreview(snap.position, valid: true, guides: snap.guides);
    }
    final corners = _polygonCorners(start, snap.position);
    return PolygonPreview(
      start: start,
      corners: corners ?? const [],
      valid:
          corners != null &&
          _staysValid(layerId, (e) => _addPolygon(e, corners)),
      guides: snap.guides,
    );
  }

  /// Ground: only a click inside one of the selected zone's closed
  /// shapes counts. Holes are outside. Returns that shape's ID.
  String? _shapeUnder(Geometry geometry, Offset screen) {
    final world = editor.camera.toWorld(screen);
    for (final id in geometry.closedIds.reversed) {
      if (geometry.regionOf(id)!.locate(world) == PointLocation.inside) {
        return id;
      }
    }
    return null;
  }

  HoverPreview? _groundHover(String layerId, Geometry geometry, Offset screen) {
    if (editor.document.layers[layerId]?.role != LayerRole.bed) return null;
    final id = _shapeUnder(geometry, screen);
    return id == null ? null : HoverPreview(id);
  }

  void _groundClick(String layerId, Geometry geometry, Offset screen) {
    if (editor.document.layers[layerId]?.role != LayerRole.bed) {
      return editor.showNotice(CanvasInput.groundNeedsBed);
    }
    if (geometry.region == null) {
      return editor.showNotice('Close a shape before setting its ground');
    }
    if (_shapeUnder(geometry, screen) == null) {
      return editor.showNotice('Click inside one of this bed\'s shapes');
    }
    editor.showNotice(null);
    editor.setGround(layerId, editor.function.groundType);
  }
}
