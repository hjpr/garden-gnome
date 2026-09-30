part of 'canvas_input.dart';

/// Rotation steps, in radians, while Shift is held.
const double _rotateStep = math.pi / 12;

/// Smallest scale factor a handle can reach, so a shape never collapses
/// to nothing or turns inside out.
const double _minScale = 0.01;

/// Pointer input for the dashed selection box: dragging a handle or an
/// edge scales the selection, and dragging just outside a corner rotates
/// it. Both go through the same preview and commit path as a move, so the
/// result is kept even when it breaks a land rule (and marked invalid).
extension _BoxInput on CanvasInput {
  /// The box grip under [screen], or null. Only Select has a box.
  BoxGrip? _boxGripAt(Offset screen) =>
      selectionBoxOf(editor)?.gripAt(editor.camera, screen);

  _BoxDrag? _startBoxDrag(_Press press) {
    final grip = press.grip;
    final layerId = editor.selectedLayerId;
    final box = selectionBoxOf(editor);
    if (grip == null || layerId == null || box == null) return null;
    final document = editor.document;
    final geometry = document.geometryOf(layerId);
    final selection = editor.selection;

    // Rotating turns the whole piece of land, so the smaller land inside
    // it turns too, as it does when moved. Scaling resizes only the
    // selection: zones keep their size when a property grows.
    final moving = <String, Set<String>>{
      layerId: geometry.definingPoints(selection),
    };
    final circles = <String, Set<String>>{
      layerId: {
        for (final id in selection)
          if (geometry.circles.containsKey(id)) id,
      },
    };
    if (grip.rotate) {
      for (final id in selection) {
        if (!geometry.shapes.containsKey(id) &&
            !geometry.circles.containsKey(id)) {
          continue;
        }
        landInside(document, layerId, id).forEach((other, points) {
          (moving[other] ??= {}).addAll(points);
        });
      }
      final locked = moving.keys.where(editor.isFrozen);
      if (locked.isNotEmpty) {
        editor.showNotice(
          '${document.layers[locked.first]!.name} is locked, so the '
          'selection cannot be rotated',
        );
        return null;
      }
    }
    return _BoxDrag(
      original: document,
      box: box,
      grip: grip,
      pressWorld: editor.camera.toWorld(press.origin),
      moving: moving,
      circles: circles,
      // A circle cannot be stretched, so a selection holding one scales
      // evenly from every handle.
      uniform: circles[layerId]!.isNotEmpty,
    );
  }

  void _updateBoxDrag(_BoxDrag drag, Offset screen, {required bool shift}) {
    final pointer = editor.camera.toWorld(screen);
    if (drag.grip.rotate) {
      final centre = drag.box.centre;
      final from = drag.pressWorld - centre;
      final to = pointer - centre;
      var angle = math.atan2(to.y, to.x) - math.atan2(from.y, from.x);
      // Keep the angle in -180°..180° so the readout stays readable.
      angle = math.atan2(math.sin(angle), math.cos(angle));
      if (shift) angle = (angle / _rotateStep).round() * _rotateStep;
      final cos = math.cos(angle), sin = math.sin(angle);
      Vec turn(Vec p) {
        final d = p - centre;
        return centre + Vec(d.x * cos - d.y * sin, d.x * sin + d.y * cos);
      }

      return _showBoxCandidate(
        drag,
        turn,
        radiusFactor: 1,
        box: drag.box.rotated(angle),
        changed: angle != 0,
      );
    }

    final handle = drag.grip.handle;
    final anchor = drag.box.pointOf(handle.opposite);
    final grabbed = drag.box.pointOf(handle);
    final target = grabbed + (pointer - drag.pressWorld);
    double factor(int side, double target, double grabbed, double anchor) {
      if (side == 0) return 1;
      final span = grabbed - anchor;
      if (span.abs() < 1e-12) return 1;
      return math.max(_minScale, (target - anchor) / span);
    }

    var sx = factor(handle.sx, target.x, grabbed.x, anchor.x);
    var sy = factor(handle.sy, target.y, grabbed.y, anchor.y);
    if (drag.uniform || (shift && handle.isCorner)) {
      final even = handle.sx == 0
          ? sy
          : handle.sy == 0
          ? sx
          : math.max(sx, sy);
      sx = even;
      sy = even;
    }
    // Arcs keep their bulge, so an arc stays a circular arc through its
    // moved ends. That is exact for even scaling and close otherwise.
    Vec scale(Vec p) =>
        anchor + Vec((p.x - anchor.x) * sx, (p.y - anchor.y) * sy);
    _showBoxCandidate(
      drag,
      scale,
      radiusFactor: math.sqrt(sx * sy),
      changed: sx != 1 || sy != 1,
    );
  }

  void _showBoxCandidate(
    _BoxDrag drag,
    Vec Function(Vec) transform, {
    required double radiusFactor,
    required bool changed,
    TransformBox? box,
  }) {
    var candidate = drag.original;
    try {
      drag.moving.forEach((layerId, points) {
        final before = drag.original.geometryOf(layerId);
        final circles = drag.circles[layerId] ?? const {};
        candidate = candidate.withGeometry(
          before.edit((e) {
            for (final id in points) {
              e.movePoint(id, transform(before.points[id]!));
            }
            // Bézier handles turn and stretch with their points, so a
            // curve keeps its shape. The transform is affine, so moving
            // the handle's tip and point is exact.
            for (final line in before.lines.values) {
              if (!line.isBezier) continue;
              for (final end in [line.start, line.end]) {
                if (!points.contains(end)) continue;
                final anchor = before.points[end]!;
                final tip = anchor + line.handleAt(end)!;
                e.setHandle(line.id, end, transform(tip) - transform(anchor));
              }
            }
            if (radiusFactor != 1) {
              for (final id in circles) {
                e.resizeCircle(id, before.circles[id]!.radius * radiusFactor);
              }
            }
          }),
        );
      });
    } on GeometryRuleError {
      return;
    }
    drag.candidate = changed ? candidate : null;
    editor.setPreview(
      MovePreview(
        document: candidate,
        moved: drag.moving,
        valid: candidate.newProblemsSince(drag.original).isEmpty,
        box: box,
      ),
    );
  }

  void _finishBoxDrag(_BoxDrag drag) {
    editor.setPreview(null);
    final candidate = drag.candidate;
    if (candidate == null) return;
    editor.commit(drag.grip.rotate ? 'Rotate' : 'Scale', candidate);
  }
}

/// A Select drag on the selection box: a scale from one handle, or a
/// rotation about the box's centre.
class _BoxDrag {
  _BoxDrag({
    required this.original,
    required this.box,
    required this.grip,
    required this.pressWorld,
    required this.moving,
    required this.circles,
    required this.uniform,
  });

  final GardenDocument original;

  /// The box as it was when the drag began.
  final TransformBox box;
  final BoxGrip grip;
  final Vec pressWorld;

  /// Points that follow the transform, keyed by layer.
  final Map<String, Set<String>> moving;

  /// Circles whose radius follows the scale, keyed by layer.
  final Map<String, Set<String>> circles;

  /// Whether both directions must scale by the same amount.
  final bool uniform;

  /// The drawing as it would be if released now; null while unchanged.
  GardenDocument? candidate;
}
