import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import '../../application/camera.dart';
import '../../domain/bezier.dart';
import '../../domain/curve_edge.dart';
import '../../domain/geometry.dart';
import '../../domain/region.dart';
import '../../domain/vec.dart';

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

/// A whole line in screen coordinates: straight, arc, or a true cubic
/// Bézier curve (drawn exactly, not from its stand-in arcs).
Path linePath(LineSegment line, Map<String, Vec> points, Camera camera) {
  final bezier = line.bezier(points);
  if (bezier == null) return curvePath(line.curve(points), camera);
  return bezierPath(bezier, camera);
}

/// A cubic Bézier curve in screen coordinates.
Path bezierPath(CubicBezier bezier, Camera camera) {
  final a = camera.toScreen(bezier.p0);
  final b = camera.toScreen(bezier.p1);
  final c = camera.toScreen(bezier.p2);
  final d = camera.toScreen(bezier.p3);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..cubicTo(b.dx, b.dy, c.dx, c.dy, d.dx, d.dy);
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

void paintDashedCircle(
  Canvas canvas,
  Offset centre,
  double radius,
  Color colour, {
  required double width,
  double dash = 8,
  double gap = 4,
}) {
  if (radius <= 0) return;
  final rect = Rect.fromCircle(center: centre, radius: radius);
  final circumference = 2 * math.pi * radius;
  final steps = math.max(1, (circumference / (dash + gap)).floor());
  final sweep = 2 * math.pi / steps;
  final dashSweep = sweep * dash / (dash + gap);
  // Dashes wholly off screen are skipped; the rest go in one path. No
  // part of a dash is farther from its start than its arc length.
  final reach = canvas.getLocalClipBounds().inflate(dashSweep * radius + width);
  if (!reach.overlaps(rect)) return;
  final dashes = Path();
  for (var i = 0; i < steps; i++) {
    final angle = i * sweep;
    final start = centre + Offset(math.cos(angle), math.sin(angle)) * radius;
    if (!reach.contains(start)) continue;
    dashes.addArc(rect, angle, dashSweep);
  }
  canvas.drawPath(
    dashes,
    Paint()
      ..color = colour
      ..strokeWidth = width
      ..style = PaintingStyle.stroke,
  );
}

/// Screen-space dashes follow a path's real curves, never their chords.
/// Off-screen dashes are skipped when drawing; traversal still follows the
/// whole path.
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
