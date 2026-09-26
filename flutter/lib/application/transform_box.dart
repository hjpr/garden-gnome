import 'dart:math' as math;
import 'dart:ui';

import '../domain/geometry.dart';
import '../domain/vec.dart';
import 'camera.dart';
import 'editor_controller.dart';
import 'previews.dart';
import 'tools.dart';

/// Screen distances, in logical pixels, for the selection box.
abstract final class BoxReach {
  /// Gap between the selection and its dashed box, so the handles sit
  /// clear of the shape's own corners and edges (which stay draggable:
  /// the edge zone below starts beyond [PointerReach.line]).
  static const double padding = 10;

  /// Radius of a drawn handle dot.
  static const double handleRadius = 4;

  /// How close the pointer must be to a handle dot to grab it.
  static const double handle = 7;

  /// How close the pointer must be to the dashed edge to grab it.
  static const double edge = 4;

  /// How far outside a corner the rotate zone reaches.
  static const double rotate = 24;
}

/// The eight handles around a selection, named by where they sit. [sx]
/// and [sy] are -1, 0 or 1: the handle's side of the box's centre.
enum BoxHandle {
  topLeft(-1, -1),
  top(0, -1),
  topRight(1, -1),
  right(1, 0),
  bottomRight(1, 1),
  bottom(0, 1),
  bottomLeft(-1, 1),
  left(-1, 0);

  const BoxHandle(this.sx, this.sy);

  final int sx;
  final int sy;

  bool get isCorner => sx != 0 && sy != 0;

  /// The handle across the box, which stays put while this one scales.
  BoxHandle get opposite =>
      values.firstWhere((h) => h.sx == -sx && h.sy == -sy);
}

/// What the pointer has hold of on the selection box: a handle (or the
/// edge it sits on) to scale, or the zone just outside a corner to rotate.
class BoxGrip {
  const BoxGrip(this.handle, {this.rotate = false});

  final BoxHandle handle;
  final bool rotate;

  @override
  bool operator ==(Object other) =>
      other is BoxGrip && other.handle == handle && other.rotate == rotate;

  @override
  int get hashCode => Object.hash(handle, rotate);
}

/// The dashed box drawn around a selected shape, in world metres. It is
/// axis-aligned except while a rotation is being dragged, when it turns
/// with the shape by [angle] radians (clockwise on screen).
class TransformBox {
  const TransformBox(this.centre, this.width, this.height, {this.angle = 0});

  final Vec centre;
  final double width;
  final double height;
  final double angle;

  /// The box around the selected [itemIds], or null when the selection
  /// holds no whole shape or circle (a lone point or line gets no box).
  static TransformBox? around(Geometry geometry, Iterable<String> itemIds) {
    var low = const Vec(double.infinity, double.infinity);
    var high = const Vec(double.negativeInfinity, double.negativeInfinity);
    var hasShape = false;
    void include((Vec, Vec) bounds) {
      low = Vec(math.min(low.x, bounds.$1.x), math.min(low.y, bounds.$1.y));
      high = Vec(math.max(high.x, bounds.$2.x), math.max(high.y, bounds.$2.y));
    }

    for (final id in itemIds) {
      if (geometry.shapes.containsKey(id) || geometry.circles.containsKey(id)) {
        final region = geometry.regionOf(id);
        if (region == null) continue;
        hasShape = true;
        include(region.bounds);
      } else if (geometry.lines[id] case final line?) {
        include(line.curve(geometry.points).bounds);
      } else if (geometry.points[id] case final point?) {
        include((point, point));
      }
    }
    if (!hasShape || !low.isFinite || !high.isFinite) return null;
    return TransformBox((low + high) / 2, high.x - low.x, high.y - low.y);
  }

  TransformBox rotated(double by) =>
      TransformBox(centre, width, height, angle: angle + by);

  /// Where [handle] sits on the box itself (no padding), in world metres.
  Vec pointOf(BoxHandle handle) =>
      centre + _turn(Vec(handle.sx * width / 2, handle.sy * height / 2));

  /// Where [handle] is drawn on screen: on the box pushed out by
  /// [BoxReach.padding] pixels.
  Offset screenPointOf(BoxHandle handle, Camera camera) {
    final pad = camera.metres(BoxReach.padding);
    return camera.toScreen(
      centre +
          _turn(
            Vec(handle.sx * (width / 2 + pad), handle.sy * (height / 2 + pad)),
          ),
    );
  }

  /// The four drawn corners on screen, clockwise from the top-left.
  List<Offset> screenCorners(Camera camera) => [
    for (final h in const [
      BoxHandle.topLeft,
      BoxHandle.topRight,
      BoxHandle.bottomRight,
      BoxHandle.bottomLeft,
    ])
      screenPointOf(h, camera),
  ];

  /// What a press at [screen] would take hold of: a handle dot first, then
  /// the dashed edge (scaling from its middle handle), then the zone just
  /// outside a corner (rotating). Null when the pointer is elsewhere.
  BoxGrip? gripAt(Camera camera, Offset screen) {
    for (final handle in BoxHandle.values) {
      if ((screenPointOf(handle, camera) - screen).distance <=
          BoxReach.handle) {
        return BoxGrip(handle);
      }
    }
    // Work in the box's own frame, in screen pixels.
    final ppm = camera.pixelsPerMetreNow;
    final halfW = width / 2 * ppm + BoxReach.padding;
    final halfH = height / 2 * ppm + BoxReach.padding;
    final c = camera.toScreen(centre);
    final d = screen - c;
    final cos = math.cos(-angle), sin = math.sin(-angle);
    final x = d.dx * cos - d.dy * sin;
    final y = d.dx * sin + d.dy * cos;

    if (x.abs() <= halfW) {
      if ((y + halfH).abs() <= BoxReach.edge) {
        return const BoxGrip(BoxHandle.top);
      }
      if ((y - halfH).abs() <= BoxReach.edge) {
        return const BoxGrip(BoxHandle.bottom);
      }
    }
    if (y.abs() <= halfH) {
      if ((x + halfW).abs() <= BoxReach.edge) {
        return const BoxGrip(BoxHandle.left);
      }
      if ((x - halfW).abs() <= BoxReach.edge) {
        return const BoxGrip(BoxHandle.right);
      }
    }
    final outside = x.abs() > halfW || y.abs() > halfH;
    if (!outside) return null;
    for (final handle in BoxHandle.values.where((h) => h.isCorner)) {
      final corner = Offset(handle.sx * halfW, handle.sy * halfH);
      if ((Offset(x, y) - corner).distance <= BoxReach.rotate) {
        return BoxGrip(handle, rotate: true);
      }
    }
    return null;
  }

  Vec _turn(Vec v) {
    if (angle == 0) return v;
    final cos = math.cos(angle), sin = math.sin(angle);
    return Vec(v.x * cos - v.y * sin, v.x * sin + v.y * cos);
  }
}

/// The selection box to show, or null. Select shows it around a selected
/// shape on an unlocked layer; while a drag is in progress it follows the
/// drawing as it would be if released now.
TransformBox? selectionBoxOf(EditorController editor) {
  final layerId = editor.selectedLayerId;
  if (editor.tool != Tool.select ||
      layerId == null ||
      editor.selection.isEmpty ||
      editor.document.isLocked(layerId)) {
    return null;
  }
  final preview = editor.preview;
  if (preview is MovePreview) {
    if (preview.box != null) return preview.box;
    if (!preview.document.layers.containsKey(layerId)) return null;
    return TransformBox.around(
      preview.document.geometryOf(layerId),
      editor.selection,
    );
  }
  return TransformBox.around(
    editor.document.geometryOf(layerId),
    editor.selection,
  );
}
