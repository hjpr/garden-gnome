import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../application/camera.dart';
import '../../domain/curve_edge.dart';
import '../../domain/region.dart';

/// One path builder for land fills, hole clipping, selection and labels.
/// Arcs stay circular at every zoom; even-odd fill leaves every hole empty.
///
/// Regions are immutable, so each one's outline is built once in world
/// metres and then only moved and scaled onto the screen for each frame.
Path regionPath(Region region, Camera camera) =>
    worldRegionPath(region).transform(cameraMatrix(camera));

/// [region]'s outline in world metres, built once per region.
Path worldRegionPath(Region region) =>
    _worldPaths[region] ??= _buildRegionPath(region);

final _worldPaths = Expando<Path>('world region paths');

/// The transform [Camera.toScreen] applies, for moving world-metre paths
/// onto the screen.
Float64List cameraMatrix(Camera camera) {
  final s = camera.pixelsPerMetreNow;
  return Float64List.fromList([
    s, 0, 0, 0, //
    0, s, 0, 0,
    0, 0, 1, 0,
    -camera.topLeft.x * s, -camera.topLeft.y * s, 0, 1,
  ]);
}

Path _buildRegionPath(Region region) {
  final path = Path()..fillType = PathFillType.evenOdd;
  for (final contour in region.contours) {
    if (contour.isEmpty) continue;
    final start = contour.first.start;
    path.moveTo(start.x, start.y);
    for (final edge in contour) {
      _appendWorldEdge(path, edge);
    }
    path.close();
  }
  return path;
}

void _appendWorldEdge(Path path, CurveEdge edge) {
  if (!edge.isArc) {
    path.lineTo(edge.end.x, edge.end.y);
    return;
  }
  path.arcTo(
    Rect.fromCircle(
      center: Offset(edge.centre.x, edge.centre.y),
      radius: edge.radius,
    ),
    edge.startAngle,
    edge.sweep,
    false,
  );
}

/// An individual straight or circular edge in screen coordinates.
Path curvePath(CurveEdge edge, Camera camera) {
  final start = camera.toScreen(edge.start);
  final path = Path()..moveTo(start.dx, start.dy);
  if (!edge.isArc) {
    final end = camera.toScreen(edge.end);
    return path..lineTo(end.dx, end.dy);
  }
  return path..arcTo(
    Rect.fromCircle(
      center: camera.toScreen(edge.centre),
      radius: edge.radius * camera.pixelsPerMetreNow,
    ),
    edge.startAngle,
    edge.sweep,
    false,
  );
}

/// Screen-space dashes follow a path's real curves, never their chords.
///
/// Dashes wholly off screen are skipped and the rest are drawn in one
/// call, so a long dashed outline seen close up costs no more than the
/// part in view.
void dashedPath(
  Canvas canvas,
  Path path,
  Color color, {
  required double width,
  double dash = 8,
  double gap = 4,
}) {
  // A dash is never longer than [dash], so one starting farther than that
  // outside the view cannot reach it.
  final reach = canvas.getLocalClipBounds().inflate(dash + width);
  if (!reach.overlaps(path.getBounds())) return;
  final dashes = Path();
  for (final metric in path.computeMetrics()) {
    for (var distance = 0.0; distance < metric.length; distance += dash + gap) {
      final start = metric.getTangentForOffset(distance)?.position;
      if (start == null || !reach.contains(start)) continue;
      final end = math.min(distance + dash, metric.length);
      dashes.addPath(metric.extractPath(distance, end), Offset.zero);
    }
  }
  canvas.drawPath(
    dashes,
    Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke,
  );
}
