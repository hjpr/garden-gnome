part of 'canvas_input.dart';

/// Line → Curve, drawn pen style. Each press places a point. Letting go
/// where you pressed makes a sharp corner; dragging first pulls out the
/// point's two handles, opposite each other, which bend the curve on both
/// sides of it. An existing point can be joined in the same way.
extension _CurveInput on CanvasInput {
  bool get _drawsCurve =>
      editor.tool == Tool.line && editor.function == ToolFunction.curve;

  /// Where a Curve press lands: an existing point to join, or a new spot.
  /// Like Arc, a curve may join two points that a straight line already
  /// joins, closing a shape between them.
  _CurveStop _curveStopAt(Geometry geometry, Offset screen) {
    final from = editor.lineAnchor;
    final target = pointAt(
      geometry,
      editor.camera,
      screen,
      accept: (id) => id != from && geometry.degreeOf(id) < 2,
    );
    return target == null
        ? _CurveStop(_snapped(screen).position)
        : _CurveStop(geometry.points[target]!, pointId: target);
  }

  /// The press's stop, when a Curve press may become a handle drag.
  _CurveStop? _curvePressStop(Offset screen) {
    final layerId = editor.selectedLayerId;
    if (!_drawsCurve || layerId == null || editor.lockNotice(layerId) != null) {
      return null;
    }
    return _curveStopAt(editor.document.geometryOf(layerId), screen);
  }

  /// The handle being pulled out: from the pressed point to the pointer.
  Vec _curveDrag(_CurveStop stop, Offset screen) =>
      editor.camera.toWorld(screen) - stop.position;

  void _updateCurveDrag(_CurveStop stop, Offset screen) {
    final layerId = editor.selectedLayerId!;
    editor.setPreview(
      _curvePreview(
        layerId,
        editor.document.geometryOf(layerId),
        stop,
        _curveDrag(stop, screen),
      ),
    );
  }

  void _finishCurveDrag(_CurveStop stop, Offset screen) {
    final layerId = editor.selectedLayerId!;
    _curvePlace(
      layerId,
      editor.document.geometryOf(layerId),
      stop,
      _curveDrag(stop, screen),
    );
  }

  /// Places the next point at [stop]. [drag] is its outgoing handle; the
  /// incoming one mirrors it. Zero on both ends of a piece gives a
  /// straight line.
  void _curvePlace(
    String layerId,
    Geometry geometry,
    _CurveStop stop,
    Vec drag,
  ) {
    final anchor = editor.lineAnchor;
    final target = stop.pointId;

    if (anchor == null) {
      if (target != null) {
        editor.startLineOperation();
        editor.setLineAnchor(target);
        editor.setCurveHandle(drag);
        return editor.showNotice(null);
      }
      if (_crowded(geometry, stop.position)) {
        return editor.showNotice(CanvasInput.tooClose);
      }
      late String pointId;
      final (next, problem) = editor.tryGeometryEdit(
        layerId,
        (e) => pointId = e.addPoint(stop.position),
      );
      if (next == null) return editor.showNotice(problem);
      final token = editor.lineToken ?? editor.startLineOperation();
      editor.commit(
        'Place point',
        next,
        lineContext: LineContext(operation: token, anchorAfter: pointId),
      );
      editor.setLineAnchor(pointId);
      editor.setCurveHandle(drag);
      return editor.selectItem(pointId);
    }

    final token = editor.lineToken ?? editor.startLineOperation();
    final startHandle = editor.curveHandle;
    if (target == null && _crowded(geometry, stop.position)) {
      return editor.showNotice(CanvasInput.tooClose);
    }
    late String lineId;
    late String endId;
    final (next, problem) = editor.tryGeometryEdit(layerId, (e) {
      endId = target ?? e.addPoint(stop.position);
      lineId = e.connect(
        anchor,
        endId,
        startHandle: startHandle,
        endHandle: -drag,
      );
    });
    if (next == null) return editor.showNotice(problem);
    // Like Straight: a loose point carries the drawing on; an open end or
    // the first point closes it.
    final carryOn = next.geometryOf(layerId).degreeOf(endId) < 2 ? endId : null;
    editor.commit(
      'Draw curve',
      next,
      lineContext: LineContext(
        operation: token,
        anchorBefore: anchor,
        anchorAfter: carryOn,
      ),
    );
    editor.setLineAnchor(carryOn);
    editor.setCurveHandle(carryOn == null ? Vec.zero : drag);
    editor.setPreview(null);
    editor.selectItem(lineId);
  }

  /// Hover with no press: the piece a plain click (a sharp corner) makes.
  Preview? _curveHover(String layerId, Geometry geometry, Offset screen) {
    final stop = _curveStopAt(geometry, screen);
    if (editor.lineAnchor == null && stop.pointId != null) {
      return HoverPreview(stop.pointId!, joinable: true);
    }
    return _curvePreview(layerId, geometry, stop, Vec.zero);
  }

  CurvePreview _curvePreview(
    String layerId,
    Geometry geometry,
    _CurveStop stop,
    Vec drag,
  ) {
    final anchor = editor.lineAnchor;
    final from = anchor == null ? null : geometry.points[anchor];
    final startHandle = editor.curveHandle;
    return CurvePreview(
      from: from,
      fromHandle: from == null ? null : from + startHandle,
      to: stop.position,
      toHandle: stop.position - drag,
      outHandle: stop.position + drag,
      joinTarget: stop.pointId,
      valid:
          anchor == null ||
          _staysValid(layerId, (e) {
            e.connect(
              anchor,
              stop.pointId ?? e.addPoint(stop.position),
              startHandle: startHandle,
              endHandle: -drag,
            );
          }),
      guides: stop.pointId == null
          ? _snapped(editor.camera.toScreen(stop.position)).guides
          : SnapGuides.none,
    );
  }
}

/// Where a Curve press put its point: an existing point ([pointId]) or a
/// new position.
class _CurveStop {
  const _CurveStop(this.position, {this.pointId});

  final Vec position;
  final String? pointId;
}

/// Select dragging one Bézier handle. A smooth point's other handle swings
/// round with it and keeps its own length.
extension _HandleInput on CanvasInput {
  CurveHandle? _curveHandleUnder(Offset screen) => editor.tool == Tool.select
      ? curveHandleAt(visibleCurveHandles(editor), editor.camera, screen)
      : null;

  void _updateHandleDrag(_HandleDrag drag, Offset screen) {
    final handle = drag.handle;
    final offset = editor.camera.toWorld(screen) - handle.anchor;
    final before = drag.original.geometryOf(drag.layerId);
    final partner = drag.partner;
    final Geometry moved;
    try {
      moved = before.edit((e) {
        e.setHandle(handle.lineId, handle.pointId, offset);
        if (partner != null && offset != Vec.zero) {
          e.setHandle(
            partner.lineId,
            handle.pointId,
            -offset / offset.length * partner.length,
          );
        }
      });
    } on GeometryRuleError {
      return;
    }
    final candidate = drag.original.withGeometry(moved);
    drag.candidate = candidate;
    editor.setPreview(
      MovePreview(
        document: candidate,
        moved: {drag.layerId: const {}},
        valid: candidate.newProblemsSince(drag.original).isEmpty,
      ),
    );
  }

  void _finishHandleDrag(_HandleDrag drag) {
    editor.setPreview(null);
    final candidate = drag.candidate;
    if (candidate == null) return;
    editor.commit('Move curve handle', candidate);
  }
}

class _HandleDrag {
  _HandleDrag({
    required this.original,
    required this.layerId,
    required this.handle,
    required this.partner,
  });

  final GardenDocument original;
  final String layerId;
  final CurveHandle handle;
  final ({String lineId, double length})? partner;
  GardenDocument? candidate;
}
