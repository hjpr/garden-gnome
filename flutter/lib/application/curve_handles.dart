import 'dart:ui';

import '../domain/geometry.dart';
import '../domain/vec.dart';
import 'camera.dart';
import 'editor_controller.dart';
import 'tools.dart';

/// Screen distances, in logical pixels, for Bézier handles.
abstract final class HandleReach {
  /// Radius of a drawn handle dot.
  static const double dot = 3.5;

  /// How close the pointer must be to a handle dot to grab it.
  static const double grab = 7;
}

/// One Bézier control handle: the end point it belongs to ([anchor]) and
/// where its dot sits ([tip]), in world metres.
class CurveHandle {
  const CurveHandle(this.lineId, this.pointId, this.anchor, this.tip);

  final String lineId;
  final String pointId;
  final Vec anchor;
  final Vec tip;
}

/// The handles Select shows for the selection: those of every curve line
/// that is selected, touches a selected point, or belongs to a selected
/// shape. Handles with no length are hidden; that end is a sharp corner.
List<CurveHandle> curveHandlesFor(Geometry geometry, Set<String> selection) {
  final lineIds = <String>{};
  for (final id in selection) {
    if (geometry.lines.containsKey(id)) lineIds.add(id);
    if (geometry.points.containsKey(id)) {
      lineIds.addAll(geometry.linesAt(id).map((line) => line.id));
    }
    for (final ring in geometry.shapes[id]?.rings ?? <List<SegmentRef>>[]) {
      lineIds.addAll(ring.map((ref) => ref.segmentId));
    }
  }
  final handles = <CurveHandle>[];
  for (final id in lineIds) {
    final line = geometry.lines[id];
    if (line == null || !line.isBezier) continue;
    for (final pointId in [line.start, line.end]) {
      final anchor = geometry.points[pointId];
      final offset = line.handleAt(pointId);
      if (anchor == null || offset == null || offset == Vec.zero) continue;
      handles.add(CurveHandle(id, pointId, anchor, anchor + offset));
    }
  }
  return handles;
}

/// The handles on screen right now: Select only, on an unlocked layer.
List<CurveHandle> visibleCurveHandles(EditorController editor) {
  final layerId = editor.selectedLayerId;
  if (editor.tool != Tool.select ||
      layerId == null ||
      editor.geometryLockNotice(layerId) != null ||
      !editor.document.layers.containsKey(layerId)) {
    return const [];
  }
  return curveHandlesFor(editor.document.geometryOf(layerId), editor.selection);
}

/// The handle whose dot is under [screen], nearest first.
CurveHandle? curveHandleAt(
  List<CurveHandle> handles,
  Camera camera,
  Offset screen,
) {
  CurveHandle? best;
  var bestGap = HandleReach.grab;
  for (final handle in handles) {
    final gap = (camera.toScreen(handle.tip) - screen).distance;
    if (gap <= bestGap) {
      best = handle;
      bestGap = gap;
    }
  }
  return best;
}

/// The other curve line's handle at [handle]'s point, when the two point
/// in opposite directions: the point is smooth, and moving one handle
/// should swing the other round to keep it smooth.
({String lineId, double length})? smoothPartner(
  Geometry geometry,
  CurveHandle handle,
) {
  final mine = handle.tip - handle.anchor;
  for (final line in geometry.linesAt(handle.pointId)) {
    if (line.id == handle.lineId) continue;
    final other = line.handleAt(handle.pointId);
    if (other == null || other == Vec.zero || mine == Vec.zero) return null;
    final cos = mine.dot(other) / (mine.length * other.length);
    return cos < -0.999 ? (lineId: line.id, length: other.length) : null;
  }
  return null;
}
