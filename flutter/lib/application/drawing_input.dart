import 'dart:ui';

import '../domain/geometry.dart';
import '../domain/geometry_editor.dart';
import '../domain/land_rules.dart';
import '../domain/vec.dart';
import 'construction_state.dart';
import 'editor_controller.dart';
import 'hit_testing.dart';
import 'history.dart';
import 'previews.dart';
import 'snapping.dart';
import 'tools.dart';

/// Point, straight-line and circle commands, including their matching previews.
class DrawingInput {
  const DrawingInput(this.editor, {required this.snapAt});

  final EditorController editor;
  final SnapResult Function(Offset screen) snapAt;

  void placePoint(String layerId, Geometry geometry, Offset screen) {
    final preview = pointPreview(layerId, geometry, screen);
    if (preview.lineId == null && isCrowded(geometry, preview.position)) {
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

  void deletePoint(String layerId, Geometry geometry, Offset screen) {
    final itemId = pointAt(geometry, editor.camera, screen);
    if (itemId == null) return;
    final (next, problem) = editor.tryGeometryEdit(
      layerId,
      (e) => e.delete([itemId]),
    );
    if (next == null) return editor.showNotice(problem);
    editor.commit('Delete point', next);
  }

  /// Line → Straight: each click commits a corner, or joins an existing
  /// point.
  void drawLine(String layerId, Geometry geometry, Offset screen) {
    final anchor = editor.lineAnchor;
    final target = _joinableAt(geometry, screen, from: anchor);

    if (anchor == null) {
      if (target != null) {
        editor.startLineOperation();
        editor.setLineAnchor(target);
        return editor.showNotice(null);
      }
      final position = snapAt(screen).position;
      if (isCrowded(geometry, position)) return editor.showNotice(tooClose);
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

    final position = snapAt(screen).position;
    if (isCrowded(geometry, position)) return editor.showNotice(tooClose);
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
  void drawCircle(String layerId, Geometry geometry, Offset screen) {
    final start = editor.circleStart;
    if (start == null) {
      editor.setCircleStart(_circleStartAt(geometry, screen));
      return editor.showNotice(null);
    }
    final plan = _circlePlan(start, snapAt(screen).position);
    if (plan == null) return;
    if (plan.centreId == null && isCrowded(geometry, plan.centre)) {
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
    return CircleStart(snapAt(screen).position);
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

  Preview? circlePreview(String layerId, Geometry geometry, Offset screen) {
    final start = editor.circleStart;
    if (start == null) {
      final reused = editor.function == ToolFunction.centerCircle
          ? pointAt(geometry, editor.camera, screen)
          : null;
      if (reused != null) return HoverPreview(reused, joinable: true);
      final snap = snapAt(screen);
      return PointPreview(snap.position, valid: true, guides: snap.guides);
    }
    final snap = snapAt(screen);
    final plan = _circlePlan(start, snap.position);
    if (plan == null) return null;
    return CirclePreview(
      start: start.position,
      edge: snap.position,
      centre: plan.centre,
      radius: plan.radius,
      valid: staysValid(layerId, (e) => _addCircle(e, plan)),
      guides: snap.guides,
    );
  }

  static const tooClose =
      'Too close to another point. Place it farther away, or click the point to use it';

  /// New points must sit at least one drawn point marker apart from the
  /// layer's existing points, measured on screen. Reusing a point is fine.
  /// A zone's shapes may touch, so there only unfinished drawing counts:
  /// a new corner may land on a finished shape's corner.
  bool isCrowded(Geometry geometry, Vec position) {
    final reach = editor.camera.metres(PointerReach.pointDiameter);
    final kind = editor.document.layers[geometry.ownerLayerId]?.kind;
    final touchable = kind == null || kind.exclusive
        ? const <String>{}
        : geometry.definingPoints(geometry.closedIds);
    return geometry.points.entries.any(
      (p) => !touchable.contains(p.key) && p.value.distanceTo(position) < reach,
    );
  }

  PointPreview pointPreview(String layerId, Geometry geometry, Offset screen) {
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
        valid: staysValid(layerId, (e) => e.insertPoint(lineId, position)),
        lineId: lineId,
      );
    }
    final snap = snapAt(screen);
    // A guide can land the point on a line of this layer (e.g. its
    // midpoint); it then splits that line rather than sitting on top.
    final landedOn = snap.guides.isEmpty
        ? null
        : _lineThrough(geometry, snap.position);
    if (landedOn != null) {
      return PointPreview(
        snap.position,
        valid: staysValid(
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
          !isCrowded(geometry, snap.position) &&
          staysValid(layerId, (e) => e.addPoint(snap.position)),
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

  Preview? linePreview(String layerId, Geometry geometry, Offset screen) {
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
        valid: staysValid(layerId, (e) => e.connect(anchor, target)),
        joinTarget: target,
      );
    }
    final snap = snapAt(screen);
    return SegmentPreview(
      from,
      snap.position,
      valid: staysValid(
        layerId,
        (e) => e.connect(anchor, e.addPoint(snap.position)),
      ),
      guides: snap.guides,
    );
  }

  Preview? deleteHover(Geometry geometry, Offset screen) {
    final itemId = pointAt(geometry, editor.camera, screen);
    return itemId == null ? null : HoverPreview(itemId, destructive: true);
  }

  /// Whether [change] would be accepted without making any layer invalid.
  /// Previews use this to turn red before the click.
  bool staysValid(String layerId, void Function(GeometryEditor e) change) {
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
}

/// Where a circle would go and, for a centre circle drawn on an existing
/// point, which point is its centre.
class _CirclePlan {
  const _CirclePlan(this.centre, this.radius, {this.centreId});

  final Vec centre;
  final double radius;
  final String? centreId;
}
