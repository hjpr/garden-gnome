import 'dart:math' as math;
import 'dart:ui';

import '../domain/curve_edge.dart';
import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/land_rules.dart';
import '../domain/planar.dart';
import '../domain/polygon_shapes.dart';
import '../domain/reference_image.dart';
import '../domain/vec.dart';
import 'area_selection.dart';
import 'carried_land.dart';
import 'curve_handles.dart';
import 'editor_controller.dart';
import 'guides.dart';
import 'hit_testing.dart';
import 'history.dart';
import 'previews.dart';
import 'snapping.dart';
import 'toasts.dart';
import 'tools.dart';
import 'transform_box.dart';

part 'canvas_area_select.dart';
part 'canvas_construction.dart';
part 'canvas_curve.dart';
part 'canvas_reference.dart';
part 'canvas_transform.dart';

/// Turns primary-button pointer input on the canvas into tool actions.
///
/// Positions are logical pixels from the viewport's top-left. Panning and
/// zooming are handled by the canvas widget and never reach this class.
///
/// Drawing is never refused for breaking a land rule. The change is made
/// and the layer is marked invalid; previews turn red to warn first. Only
/// changes the drawing cannot hold, such as a point joining three lines,
/// are refused.
class CanvasInput {
  CanvasInput(this.editor) {
    editor.onCancelOperation = _dropGesture;
  }

  final EditorController editor;

  _Press? _press;
  _Drag? _drag;
  _ReferenceDrag? _referenceDrag;
  _BoxDrag? _boxDrag;
  _AreaDrag? _areaDrag;
  _HandleDrag? _handleDrag;

  /// The selection-box grip under the pointer while hovering, if any.
  BoxGrip? _hoverGrip;

  /// Whether a drag is in progress. Navigation waits until it ends.
  bool get isDragging =>
      _drag != null ||
      _referenceDrag != null ||
      _boxDrag != null ||
      _areaDrag != null ||
      _handleDrag != null ||
      (_press?.curveStop != null && _press!.travelled);

  /// The selection-box grip being dragged, or else the one under the
  /// pointer. The canvas picks its cursor from it.
  BoxGrip? get activeGrip =>
      _boxDrag?.grip ?? (_press == null ? _hoverGrip : null);

  // ------------------------------------------------------------ pointer API

  void hover(Offset screen) {
    if (_press != null) return;
    if (editor.settings.guidesEnabled) {
      editor.hoverGuideItem(
        guideItemAt(editor.document, editor.camera, screen),
      );
    }
    _hoverGrip = editor.tool == Tool.select ? _boxGripAt(screen) : null;
    if (_hoverGrip != null) return editor.setPreview(null);
    if (_curveHandleUnder(screen) != null) return editor.setPreview(null);
    if (editor.tool == Tool.select) {
      final top = _selectHits(screen).firstOrNull;
      return editor.setPreview(
        top == null ? null : HoverPreview(top.itemId, layerId: top.layerId),
      );
    }
    if (editor.tool == Tool.reference) {
      return editor.setPreview(_referenceLinePreview(screen));
    }
    final layerId = editor.selectedLayerId;
    if (layerId == null || editor.document.isLocked(layerId)) {
      return editor.setPreview(null);
    }
    final geometry = editor.document.geometryOf(layerId);
    editor.setPreview(switch ((editor.tool, editor.function)) {
      (Tool.point, ToolFunction.place) => _placePreview(
        layerId,
        geometry,
        screen,
      ),
      (Tool.line, ToolFunction.draw) => _drawPreview(layerId, geometry, screen),
      (Tool.line, ToolFunction.curve) => _curveHover(layerId, geometry, screen),
      (Tool.arc, _) => _arcPreview(layerId, geometry, screen),
      (Tool.polygon, _) => _polygonPreview(layerId, screen),
      (Tool.pattern, _) => _patternHover(geometry, screen),
      (Tool.point, ToolFunction.delete) => _deleteHover(
        geometry,
        screen,
        HitKind.point,
      ),
      (Tool.circle, _) => _circlePreview(layerId, geometry, screen),
      _ => null,
    });
  }

  void press(Offset screen, {required bool shift}) {
    // A curve handle sits on top of everything else Select could grab.
    final handle = _curveHandleUnder(screen);
    _press = _Press(
      screen,
      shift: shift,
      grip: editor.tool == Tool.select && handle == null
          ? _boxGripAt(screen)
          : null,
      handle: handle,
      curveStop: _curvePressStop(screen),
    );
  }

  /// [shift] keeps a corner scale in proportion and turns a rotation in
  /// 15° steps.
  void move(Offset screen, {bool shift = false}) {
    final press = _press;
    if (press == null) return;
    if (_drag == null &&
        _boxDrag == null &&
        _areaDrag == null &&
        _handleDrag == null &&
        !press.travelled) {
      if ((screen - press.origin).distance <= PointerReach.dragThreshold) {
        return;
      }
      press.travelled = true;
      if (press.handle case final handle?) {
        final layerId = editor.selectedLayerId!;
        _handleDrag = _HandleDrag(
          original: editor.document,
          layerId: layerId,
          handle: handle,
          partner: smoothPartner(editor.document.geometryOf(layerId), handle),
        );
      }
      if (editor.tool == Tool.reference) _startReferenceLineDrag(press);
      if (editor.function.drags && _handleDrag == null) {
        _boxDrag = _startBoxDrag(press);
        if (_boxDrag == null && press.grip == null) {
          _referenceDrag = _startReferenceDrag(press);
          if (_referenceDrag == null && _dragTarget(press.origin) == null) {
            // Empty ground: draw a marquee or lasso instead of moving.
            _areaDrag = _startAreaDrag(press);
          } else if (_referenceDrag == null) {
            _drag = _startDrag(press);
          }
        }
      }
    }
    final handleDrag = _handleDrag;
    if (handleDrag != null) return _updateHandleDrag(handleDrag, screen);
    if (press.curveStop case final stop?) {
      return _updateCurveDrag(stop, screen);
    }
    final areaDrag = _areaDrag;
    if (areaDrag != null) return _updateAreaDrag(areaDrag, screen);
    final boxDrag = _boxDrag;
    if (boxDrag != null) return _updateBoxDrag(boxDrag, screen, shift: shift);
    final referenceDrag = _referenceDrag;
    if (referenceDrag != null) {
      return _updateReferenceDrag(referenceDrag, screen);
    }
    final drag = _drag;
    if (drag != null) return _updateDrag(drag, screen);
    // A reference line being dragged out follows the pointer.
    if (editor.tool == Tool.reference) {
      editor.setPreview(_referenceLinePreview(screen));
    }
  }

  void release(Offset screen) {
    final press = _press;
    final drag = _drag;
    final referenceDrag = _referenceDrag;
    final boxDrag = _boxDrag;
    final areaDrag = _areaDrag;
    final handleDrag = _handleDrag;
    _press = null;
    _drag = null;
    _referenceDrag = null;
    _boxDrag = null;
    _areaDrag = null;
    _handleDrag = null;
    if (press == null) return;
    if (handleDrag != null) {
      _finishHandleDrag(handleDrag);
      return hover(screen);
    }
    if (press.curveStop case final stop? when press.travelled) {
      _finishCurveDrag(stop, screen);
      return hover(screen);
    }
    // A click on a curve handle keeps the selection as it is.
    if (press.handle != null) return hover(screen);
    if (areaDrag != null) {
      _finishAreaDrag(areaDrag);
      return hover(screen);
    }
    if (boxDrag != null) {
      _finishBoxDrag(boxDrag);
      return hover(screen);
    }
    if (referenceDrag != null) return _finishReferenceDrag(referenceDrag);
    if (drag != null) return _finishDrag(drag);
    // A click on the selection box keeps the selection as it is.
    if (press.grip != null) return hover(screen);
    if (!press.travelled) {
      _click(screen, shift: press.shift);
    } else if (editor.tool == Tool.reference &&
        editor.referenceLineStart != null) {
      // Letting go of a dragged reference line places its other end.
      _referenceClick(screen);
    }
    hover(screen);
  }

  /// Abandons a held gesture, e.g. when released over a panel.
  void cancel() {
    _dropGesture();
    editor.setPreview(null);
  }

  /// Called when the Select tool's press has been held still for
  /// [PointerReach.hold]. Ends the press and returns everything under it,
  /// best match first, for the user to choose from. Returns an empty list
  /// when there is nothing to choose, or the press has become a drag.
  List<LayerHit> takeHoldChoices() {
    final press = _press;
    if (press == null ||
        press.travelled ||
        press.grip != null ||
        editor.tool != Tool.select) {
      return const [];
    }
    final hits = _selectHits(press.origin);
    if (hits.isEmpty) return const [];
    _dropGesture();
    editor.setPreview(null);
    return hits;
  }

  /// Selects a choice made from the list returned by [takeHoldChoices].
  void choose(LayerHit hit) => editor.selectObject(hit.layerId, hit.itemId);

  /// A short name for a choice, such as "Zone 1 · Line".
  String describe(LayerHit hit) {
    final name = editor.document.layers[hit.layerId]?.name ?? 'Unknown';
    final kind = switch (hit.kind) {
      HitKind.point => 'Point',
      HitKind.line => 'Line',
      HitKind.circle => 'Circle edge',
      HitKind.interior => 'Whole shape',
    };
    return '$name · $kind';
  }

  void _dropGesture() {
    _press = null;
    _drag = null;
    _referenceDrag = null;
    _boxDrag = null;
    _areaDrag = null;
    _handleDrag = null;
    _hoverGrip = null;
  }

  // ------------------------------------------------------------------ clicks

  void _click(Offset screen, {required bool shift}) {
    if (editor.tool == Tool.select) return _selectClick(screen, shift: shift);
    if (editor.tool == Tool.reference) return _referenceClick(screen);

    final layerId = editor.selectedLayerId;
    if (layerId == null) {
      if (editor.document.propertyIds.isEmpty) {
        return editor.toasts.show(noLayersToast, kind: ToastKind.error);
      }
      return editor.showNotice('Select or add a layer to draw on');
    }
    final locked = editor.lockNotice(layerId);
    if (locked != null) return editor.showNotice(locked);
    final geometry = editor.document.geometryOf(layerId);
    switch ((editor.tool, editor.function)) {
      case (Tool.point, ToolFunction.place):
        _placePoint(layerId, geometry, screen);
      case (Tool.point, ToolFunction.delete):
        _deleteAt(layerId, geometry, screen, HitKind.point);
      case (Tool.line, ToolFunction.draw):
        _drawClick(layerId, geometry, screen);
      case (Tool.line, ToolFunction.curve):
        _curvePlace(
          layerId,
          geometry,
          _curveStopAt(geometry, screen),
          Vec.zero,
        );
      case (Tool.circle, _):
        _circleClick(layerId, geometry, screen);
      case (Tool.arc, _):
        _arcClick(layerId, geometry, screen);
      case (Tool.polygon, _):
        _polygonClick(layerId, screen);
      case (Tool.pattern, _):
        _patternClick(layerId, geometry, screen);
      default:
        break;
    }
  }

  /// Select: picks the best item under the pointer on any layer, switching
  /// to its layer. Clicking empty ground clears the selection.
  void _selectClick(Offset screen, {required bool shift}) {
    final top = _selectHits(screen).firstOrNull;
    if (top == null && !shift) {
      if (_referenceUnder(screen) case final image?) {
        return editor.selectReference(image.id);
      }
    }
    if (top == null) return editor.selectItem(null, toggle: shift);
    editor.selectObject(top.layerId, top.itemId, toggle: shift);
  }

  /// Everything Select could pick at [screen]. Locked layers are left out,
  /// so clicks pass through them to the land underneath.
  List<LayerHit> _selectHits(Offset screen) => [
    for (final hit in hitsAcrossLayers(editor.document, editor.camera, screen))
      if (!editor.document.isLocked(hit.layerId)) hit,
  ];

  void _placePoint(String layerId, Geometry geometry, Offset screen) {
    final preview = _placePreview(layerId, geometry, screen);
    if (preview.lineId == null && _crowded(geometry, preview.position)) {
      return editor.showNotice(tooClose);
    }
    late String pointId;
    final (next, problem) = editor.tryGeometryEdit(layerId, (e) {
      pointId = preview.lineId == null
          ? e.addPoint(preview.position)
          : e.insertPoint(preview.lineId!, preview.position);
    });
    if (next == null) return editor.showNotice(problem);
    editor.commit(
      preview.lineId == null ? 'Place point' : 'Insert point',
      next,
    );
    editor.selectItem(pointId);
  }

  void _deleteAt(
    String layerId,
    Geometry geometry,
    Offset screen,
    HitKind kind,
  ) {
    final itemId = kind == HitKind.point
        ? pointAt(geometry, editor.camera, screen)
        : lineAt(geometry, editor.camera, screen);
    if (itemId == null) return;
    final (next, problem) = editor.tryGeometryEdit(
      layerId,
      (e) => e.delete([itemId]),
    );
    if (next == null) return editor.showNotice(problem);
    editor.commit(kind == HitKind.point ? 'Delete point' : 'Delete line', next);
  }

  /// Line → Straight: each click commits a corner, or joins an existing
  /// point.
  void _drawClick(String layerId, Geometry geometry, Offset screen) {
    final anchor = editor.lineAnchor;
    final target = _joinableAt(geometry, screen, from: anchor);

    if (anchor == null) {
      if (target != null) {
        editor.startLineOperation();
        editor.setLineAnchor(target);
        return editor.showNotice(null);
      }
      final position = _snapped(screen).position;
      if (_crowded(geometry, position)) return editor.showNotice(tooClose);
      late String pointId;
      final (next, problem) = editor.tryGeometryEdit(
        layerId,
        (e) => pointId = e.addPoint(position),
      );
      if (next == null) return editor.showNotice(problem);
      final token = editor.lineToken ?? editor.startLineOperation();
      editor.commit(
        'Place point',
        next,
        lineContext: LineContext(operation: token, anchorAfter: pointId),
      );
      editor.setLineAnchor(pointId);
      return editor.selectItem(pointId);
    }

    final token = editor.lineToken ?? editor.startLineOperation();
    if (target != null) {
      late String lineId;
      final (next, problem) = editor.tryGeometryEdit(
        layerId,
        (e) => lineId = e.connect(anchor, target),
      );
      if (next == null) return editor.showNotice(problem);
      // Joining a loose point carries on from it, so existing points can be
      // joined in a run. A point that now has two lines (a closed loop, or
      // the open end of another line) ends the drawing.
      final carryOn = next.geometryOf(layerId).degreeOf(target) < 2
          ? target
          : null;
      editor.commit(
        'Join line',
        next,
        lineContext: LineContext(
          operation: token,
          anchorBefore: anchor,
          anchorAfter: carryOn,
        ),
      );
      editor.setLineAnchor(carryOn);
      editor.setPreview(null);
      return editor.selectItem(lineId);
    }

    final position = _snapped(screen).position;
    if (_crowded(geometry, position)) return editor.showNotice(tooClose);
    late String pointId;
    late String lineId;
    final (next, problem) = editor.tryGeometryEdit(layerId, (e) {
      pointId = e.addPoint(position);
      lineId = e.connect(anchor, pointId);
    });
    if (next == null) return editor.showNotice(problem);
    editor.commit(
      'Draw line',
      next,
      lineContext: LineContext(
        operation: token,
        anchorBefore: anchor,
        anchorAfter: pointId,
      ),
    );
    editor.setLineAnchor(pointId);
    editor.selectItem(lineId);
  }

  /// Circle: the first click is kept aside, not added to the drawing; the
  /// second click adds the circle (and a new centre point, if needed) as
  /// one undoable step. Esc, or changing tool or layer, forgets the first
  /// click.
  void _circleClick(String layerId, Geometry geometry, Offset screen) {
    final start = editor.circleStart;
    if (start == null) {
      editor.setCircleStart(_circleStartAt(geometry, screen));
      return editor.showNotice(null);
    }
    final plan = _circlePlan(start, _snapped(screen).position);
    if (plan == null) return;
    if (plan.centreId == null && _crowded(geometry, plan.centre)) {
      return editor.showNotice(tooClose);
    }
    late String circleId;
    final (next, problem) = editor.tryGeometryEdit(
      layerId,
      (e) => circleId = _addCircle(e, plan),
    );
    if (next == null) return editor.showNotice(problem);
    editor.commit('Draw circle', next);
    editor.selectItem(circleId);
  }

  /// Where a circle's first click lands. A centre circle may reuse an
  /// existing point as its centre.
  CircleStart _circleStartAt(Geometry geometry, Offset screen) {
    if (editor.function == ToolFunction.centerCircle) {
      final pointId = pointAt(geometry, editor.camera, screen);
      if (pointId != null) {
        return CircleStart(geometry.points[pointId]!, pointId: pointId);
      }
    }
    return CircleStart(_snapped(screen).position);
  }

  /// The centre and radius given the first click and the pointer, or null
  /// while they are too close to make a circle.
  _CirclePlan? _circlePlan(CircleStart start, Vec pointer) {
    final twoPoint = editor.function == ToolFunction.twoPointCircle;
    final centre = twoPoint ? (start.position + pointer) / 2 : start.position;
    final radius = centre.distanceTo(pointer);
    if (radius <= 1e-6) return null;
    return _CirclePlan(
      centre,
      radius,
      centreId: twoPoint ? null : start.pointId,
    );
  }

  String _addCircle(GeometryEditor e, _CirclePlan plan) =>
      e.addCircle(plan.centreId ?? e.addPoint(plan.centre), plan.radius);

  Preview? _circlePreview(String layerId, Geometry geometry, Offset screen) {
    final start = editor.circleStart;
    if (start == null) {
      final reused = editor.function == ToolFunction.centerCircle
          ? pointAt(geometry, editor.camera, screen)
          : null;
      if (reused != null) return HoverPreview(reused, joinable: true);
      final snap = _snapped(screen);
      return PointPreview(snap.position, valid: true, guides: snap.guides);
    }
    final snap = _snapped(screen);
    final plan = _circlePlan(start, snap.position);
    if (plan == null) return null;
    return CirclePreview(
      start: start.position,
      edge: snap.position,
      centre: plan.centre,
      radius: plan.radius,
      valid: _staysValid(layerId, (e) => _addCircle(e, plan)),
      guides: snap.guides,
    );
  }

  // ---------------------------------------------------------------- previews

  static const noLayersToast = 'Add a Property layer to start drawing.';

  static const tooClose =
      'Too close to another point. Place it farther away, or click the point to use it';

  /// New points must sit at least one drawn point marker apart from the
  /// layer's existing points, measured on screen. Reusing a point is fine.
  /// A zone's shapes may touch, so there only unfinished drawing counts:
  /// a new corner may land on a finished shape's corner.
  bool _crowded(Geometry geometry, Vec position) {
    final reach = editor.camera.metres(PointerReach.pointDiameter);
    final kind = editor.document.layers[geometry.ownerLayerId]?.kind;
    final touchable = kind == null || kind.exclusive
        ? const <String>{}
        : geometry.definingPoints(geometry.closedIds);
    return geometry.points.entries.any(
      (p) => !touchable.contains(p.key) && p.value.distanceTo(position) < reach,
    );
  }

  PointPreview _placePreview(String layerId, Geometry geometry, Offset screen) {
    final camera = editor.camera;
    final lineId = lineAt(geometry, camera, screen);
    if (lineId != null && pointAt(geometry, camera, screen) == null) {
      final line = geometry.lines[lineId]!;
      final position = line.closestPoint(
        geometry.points,
        camera.toWorld(screen),
      );
      return PointPreview(
        position,
        valid: _staysValid(layerId, (e) => e.insertPoint(lineId, position)),
        lineId: lineId,
      );
    }
    final snap = _snapped(screen);
    // A guide can land the point on a line of this layer (e.g. its
    // midpoint); it then splits that line rather than sitting on top.
    final landedOn = snap.guides.isEmpty
        ? null
        : _lineThrough(geometry, snap.position);
    if (landedOn != null) {
      return PointPreview(
        snap.position,
        valid: _staysValid(
          layerId,
          (e) => e.insertPoint(landedOn, snap.position),
        ),
        lineId: landedOn,
        guides: snap.guides,
      );
    }
    return PointPreview(
      snap.position,
      valid:
          !_crowded(geometry, snap.position) &&
          _staysValid(layerId, (e) => e.addPoint(snap.position)),
      guides: snap.guides,
    );
  }

  /// A line of [geometry] that [position] lies on, away from its ends.
  String? _lineThrough(Geometry geometry, Vec position) {
    final reach = editor.camera.metres(PointerReach.pointDiameter);
    for (final line in geometry.lines.values) {
      if (line.distanceTo(geometry.points, position) < 1e-9 &&
          geometry.points[line.start]!.distanceTo(position) >= reach &&
          geometry.points[line.end]!.distanceTo(position) >= reach) {
        return line.id;
      }
    }
    return null;
  }

  Preview? _drawPreview(String layerId, Geometry geometry, Offset screen) {
    final anchor = editor.lineAnchor;
    final target = _joinableAt(geometry, screen, from: anchor);
    if (anchor == null) {
      return target == null ? null : HoverPreview(target, joinable: true);
    }
    final from = geometry.points[anchor]!;
    if (target != null) {
      return SegmentPreview(
        from,
        geometry.points[target]!,
        valid: _staysValid(layerId, (e) => e.connect(anchor, target)),
        joinTarget: target,
      );
    }
    final snap = _snapped(screen);
    return SegmentPreview(
      from,
      snap.position,
      valid: _staysValid(
        layerId,
        (e) => e.connect(anchor, e.addPoint(snap.position)),
      ),
      guides: snap.guides,
    );
  }

  Preview? _deleteHover(Geometry geometry, Offset screen, HitKind kind) {
    final itemId = kind == HitKind.point
        ? pointAt(geometry, editor.camera, screen)
        : lineAt(geometry, editor.camera, screen);
    return itemId == null ? null : HoverPreview(itemId, destructive: true);
  }

  /// Whether [change] would be accepted without making any layer invalid.
  /// Previews use this to turn red before the click.
  bool _staysValid(String layerId, void Function(GeometryEditor e) change) {
    final (next, _) = editor.tryGeometryEdit(layerId, change);
    return next != null && next.newProblemsSince(editor.document).isEmpty;
  }

  /// A point the Line tool could attach to: fewer than two lines, and not
  /// already joined to [from].
  String? _joinableAt(Geometry geometry, Offset screen, {String? from}) =>
      pointAt(
        geometry,
        editor.camera,
        screen,
        accept: (id) =>
            id != from &&
            geometry.degreeOf(id) < 2 &&
            (from == null ||
                !geometry.lines.values.any(
                  (l) => l.connects(from, id) && l.isStraight,
                )),
      );

  // ------------------------------------------------------------------- drags

  _Drag? _startDrag(_Press press) {
    final target = _dragTarget(press.origin);
    if (target == null) return null;
    final layerId = target.layerId;
    final itemId = target.itemId;

    final alreadySelected =
        layerId == editor.selectedLayerId && editor.selection.contains(itemId);
    if (!alreadySelected) {
      if (editor.tool == Tool.select) {
        editor.selectObject(layerId, itemId);
      } else {
        editor.selectItem(itemId);
      }
    }

    final document = editor.document;
    final geometry = document.geometryOf(layerId);
    // Moving a whole property shape carries its zones' shapes inside it
    // along too.
    final carried = target.kind == HitKind.interior
        ? landInside(document, layerId, itemId)
        : const <String, Set<String>>{};
    final lockedInside = carried.keys.where(document.isLocked);
    if (lockedInside.isNotEmpty) {
      editor.showNotice(
        '${document.layers[lockedInside.first]!.name} is locked, so '
        '${geometry.labelOf(itemId)} cannot be moved as a whole',
      );
      return null;
    }
    final moving = <String, Set<String>>{
      layerId: geometry.definingPoints(editor.selection),
      ...carried,
    };

    final pressWorld = editor.camera.toWorld(press.origin);
    if (target.kind == HitKind.circle) {
      final circle = geometry.circles[itemId]!;
      return _Drag(
        original: document,
        moving: {
          layerId: {circle.center},
        },
        anchorStart: geometry.points[circle.center]!,
        grabOffset: Vec.zero,
        resizing: (layerId: layerId, circleId: itemId),
      );
    }
    final anchor = switch (target.kind) {
      HitKind.point => itemId,
      HitKind.line => _nearestOf(
        geometry,
        geometry.definingPoints([itemId]),
        pressWorld,
      ),
      HitKind.circle => itemId,
      HitKind.interior => _nearestOf(
        geometry,
        geometry.definingPoints([itemId]),
        pressWorld,
      ),
    };
    return _Drag(
      original: document,
      moving: moving,
      anchorStart: geometry.points[anchor]!,
      grabOffset: pressWorld - geometry.points[anchor]!,
    );
  }

  /// What a Select drag starting at [screen] would pick up.
  LayerHit? _dragTarget(Offset screen) => _selectHits(screen).firstOrNull;

  void _updateDrag(_Drag drag, Offset screen) {
    final pointer = editor.camera.toWorld(screen);
    if (drag.resizing case final target?) {
      return _updateResize(drag, target, screen);
    }
    final snap = _snappedMove(drag, pointer - drag.grabOffset);
    final delta = snap.position - drag.anchorStart;
    var candidate = drag.original;
    drag.moving.forEach((layerId, points) {
      final before = drag.original.geometryOf(layerId);
      candidate = candidate.withGeometry(
        before.edit((e) {
          for (final id in points) {
            e.movePoint(id, before.points[id]! + delta);
          }
        }),
      );
    });
    drag.delta = delta;
    drag.candidate = candidate;
    editor.setPreview(
      MovePreview(
        document: candidate,
        moved: drag.moving,
        valid: candidate.newProblemsSince(drag.original).isEmpty,
        guides: snap.guides,
      ),
    );
  }

  /// Select dragging a circle's edge: the centre stays put and the edge
  /// follows the pointer.
  void _updateResize(
    _Drag drag,
    ({String layerId, String circleId}) target,
    Offset screen,
  ) {
    final snap = _snappedWorld(
      editor.camera.toWorld(screen),
      exclude: drag.moving,
    );
    final radius = snap.position.distanceTo(drag.anchorStart);
    final before = drag.original.geometryOf(target.layerId);
    final Geometry resized;
    try {
      resized = before.edit((e) => e.resizeCircle(target.circleId, radius));
    } on GeometryRuleError {
      return;
    }
    final candidate = drag.original.withGeometry(resized);
    drag.candidate = candidate;
    drag.delta = snap.position - drag.anchorStart;
    editor.setPreview(
      MovePreview(
        document: candidate,
        moved: drag.moving,
        valid: candidate.newProblemsSince(drag.original).isEmpty,
        guides: snap.guides,
      ),
    );
  }

  void _finishDrag(_Drag drag) {
    editor.setPreview(null);
    final candidate = drag.candidate;
    if (candidate == null || drag.delta == Vec.zero) return;
    editor.commit(drag.resizing == null ? 'Move' : 'Resize circle', candidate);
  }

  String _nearestOf(Geometry geometry, Iterable<String> ids, Vec to) {
    final sorted = ids.toList()..sort(compareItemIds);
    return sorted.reduce(
      (best, id) =>
          geometry.points[id]!.distanceTo(to) <
              geometry.points[best]!.distanceTo(to)
          ? id
          : best,
    );
  }

  // ---------------------------------------------------------------- snapping

  SnapResult _snapped(Offset screen) =>
      _snappedWorld(editor.camera.toWorld(screen), exclude: const {});

  /// Snaps [world] to guides and the grid. Each axis takes a guide within
  /// reach first, then the grid if snapping is on. [exclude] holds points
  /// (keyed by layer) that are themselves moving, so they cannot guide.
  SnapResult _snappedWorld(
    Vec world, {
    required Map<String, Set<String>> exclude,
  }) {
    final gridded = editor.settings.snappingEnabled
        ? snapToGrid(world, editor.camera).position
        : world;
    return snapToGuides(
      world,
      editor.camera,
      activeGuideSet(moving: exclude),
      fallback: gridded,
    );
  }

  /// Where a move's anchor goes. Every moving point, and the outermost
  /// points of every moving circle, may line up with a guide; whichever
  /// is closest pulls the whole move. The grid still places the anchor
  /// on an axis no guide claims.
  SnapResult _snappedMove(_Drag drag, Vec anchor) {
    final gridded = editor.settings.snappingEnabled
        ? snapToGrid(anchor, editor.camera).position
        : anchor;
    final set = activeGuideSet(moving: drag.moving);
    if (set.isEmpty) return SnapResult(gridded);
    final shift = anchor - drag.anchorStart;
    final handles = [for (final p in drag.handles) p + shift];
    final fit = fitToGuides(handles, set, editor.camera);
    final moved = anchor + fit.shift;
    return SnapResult(
      Vec(fit.freeX ? gridded.x : moved.x, fit.freeY ? gridded.y : moved.y),
      guides: fit.guides,
    );
  }

  /// The guides in use now: those of the geometry last hovered, skipping
  /// anything being dragged. Empty while Guides is off.
  GuideSet activeGuideSet({Map<String, Set<String>>? moving}) {
    if (!editor.settings.guidesEnabled) return GuideSet.empty;
    return activeGuides(
      editor.document,
      editor.recentGuideItems,
      moving: moving ?? _drag?.moving ?? const {},
    );
  }
}

/// The positions that can line up with a guide while [moving] points
/// move: the points themselves and the outermost points of circles
/// centred on them.
List<Vec> _moveHandles(
  GardenDocument document,
  Map<String, Set<String>> moving,
) {
  final handles = <Vec>[];
  moving.forEach((layerId, ids) {
    final geometry = document.geometryOf(layerId);
    for (final id in ids) {
      handles.add(geometry.points[id]!);
    }
    for (final circle in geometry.circles.values) {
      if (ids.contains(circle.center)) {
        handles.addAll(
          circleExtremes(geometry.points[circle.center]!, circle.radius),
        );
      }
    }
  });
  return handles;
}

class _Press {
  _Press(
    this.origin, {
    required this.shift,
    this.grip,
    this.handle,
    this.curveStop,
  });

  final Offset origin;
  final bool shift;

  /// The selection-box grip the press landed on, if any. It then scales
  /// or rotates the selection instead of picking what is underneath.
  final BoxGrip? grip;

  /// The Bézier handle the press landed on (Select), if any.
  final CurveHandle? handle;

  /// Line → Curve: where the press put its point. Dragging from here
  /// pulls out that point's handles.
  final _CurveStop? curveStop;

  /// Set once the pointer moves past the drag threshold; the press is then
  /// no longer a click.
  bool travelled = false;
}

class _Drag {
  _Drag({
    required this.original,
    required this.moving,
    required this.anchorStart,
    required this.grabOffset,
    this.resizing,
  }) : handles = resizing == null ? _moveHandles(original, moving) : const [];

  final GardenDocument original;

  /// Positions at the start of the move that guides can line up; see
  /// [_moveHandles].
  final List<Vec> handles;

  /// The points being moved, keyed by layer.
  final Map<String, Set<String>> moving;

  /// The point that snapping follows; everything moves with it.
  final Vec anchorStart;

  /// Where the pointer grabbed, relative to the anchor.
  final Vec grabOffset;

  /// Set when the drag resizes a circle instead of moving points. The
  /// anchor is then the circle's centre.
  final ({String layerId, String circleId})? resizing;

  GardenDocument? candidate;
  Vec delta = Vec.zero;
}

/// Where a circle would go and, for a centre circle drawn on an existing
/// point, which point is its centre.
class _CirclePlan {
  const _CirclePlan(this.centre, this.radius, {this.centreId});

  final Vec centre;
  final double radius;
  final String? centreId;
}
