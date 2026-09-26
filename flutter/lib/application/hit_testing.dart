import 'dart:ui';

import '../domain/document.dart';
import '../domain/geometry.dart';
import '../domain/planar.dart';
import 'camera.dart';

/// Screen distances, in logical pixels, used when reading pointer input.
abstract final class PointerReach {
  /// How close the pointer must be to pick up a point.
  static const double point = 8;

  /// How close the pointer must be to a line to pick it or insert on it.
  static const double line = 6;

  /// How far the pointer may travel before a press becomes a drag.
  static const double dragThreshold = 4;

  /// Diameter of drawn point markers.
  static const double pointDiameter = 6;

  /// How long a still press lasts before it lists everything underneath.
  static const Duration hold = Duration(milliseconds: 500);
}

/// What part of a layer a hit landed on, best first: a point beats a line,
/// a line beats a circle's edge, and an edge beats the inside.
enum HitKind { point, line, circle, interior }

/// Something under the pointer in one layer's geometry.
class Hit {
  const Hit(this.kind, this.id, this.distance);

  final HitKind kind;
  final String id;

  /// Screen distance from the pointer, in logical pixels.
  final double distance;
}

/// A [Hit] together with the layer it belongs to.
class LayerHit {
  const LayerHit(this.layerId, this.hit);

  final String layerId;
  final Hit hit;

  HitKind get kind => hit.kind;
  String get itemId => hit.id;
}

/// Everything under [screen] in one layer, best match first.
///
/// Points rank above lines, lines above shape interiors. Within a kind, the
/// nearest wins (for interiors, the shape highest in the stack); exact
/// ties go to the lower ID number.
List<Hit> hitsAt(Geometry geometry, Camera camera, Offset screen) {
  final world = camera.toWorld(screen);
  final hits = <Hit>[];
  for (final entry in geometry.points.entries) {
    final d = _pixels(camera, world.distanceTo(entry.value));
    if (d <= PointerReach.point) hits.add(Hit(HitKind.point, entry.key, d));
  }
  for (final line in geometry.lines.values) {
    final d = _pixels(camera, line.curve(geometry.points).distanceTo(world));
    if (d <= PointerReach.line) hits.add(Hit(HitKind.line, line.id, d));
  }
  for (final circle in geometry.circles.values) {
    final centre = geometry.points[circle.center]!;
    final d = _pixels(camera, (world.distanceTo(centre) - circle.radius).abs());
    if (d <= PointerReach.line) hits.add(Hit(HitKind.circle, circle.id, d));
  }
  for (final id in [...geometry.shapes.keys, ...geometry.circles.keys]) {
    final region = geometry.regionOf(id);
    if (region != null && region.locate(world) != PointLocation.outside) {
      hits.add(Hit(HitKind.interior, id, 0));
    }
  }
  hits.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    if (a.kind == HitKind.interior) {
      // The shape highest in the stack is the one on top.
      final byStack = geometry.stack
          .indexOf(b.id)
          .compareTo(geometry.stack.indexOf(a.id));
      if (byStack != 0) return byStack;
    }
    final byDistance = a.distance.compareTo(b.distance);
    return byDistance != 0 ? byDistance : compareItemIds(a.id, b.id);
  });
  return hits;
}

/// Everything under [screen] on every layer, best match first.
///
/// Points rank above lines, and lines above insides. Within a kind the
/// innermost layer wins (an area before its plot, a plot before its
/// field), so a click inside nested land picks the smallest piece. After
/// that, the nearest wins.
List<LayerHit> hitsAcrossLayers(
  GardenDocument document,
  Camera camera,
  Offset screen,
) {
  final hits = [
    for (final layerId in document.drawingOrder)
      for (final hit in hitsAt(document.geometryOf(layerId), camera, screen))
        LayerHit(layerId, hit),
  ];
  int depth(LayerHit h) => document.layers[h.layerId]!.kind.index;
  hits.sort((a, b) {
    final byKind = a.kind.index.compareTo(b.kind.index);
    if (byKind != 0) return byKind;
    final byDepth = depth(b).compareTo(depth(a));
    if (byDepth != 0) return byDepth;
    return a.hit.distance.compareTo(b.hit.distance);
  });
  return hits;
}

/// The nearest point within reach that [accept] allows.
String? pointAt(
  Geometry geometry,
  Camera camera,
  Offset screen, {
  bool Function(String pointId)? accept,
}) {
  for (final hit in hitsAt(geometry, camera, screen)) {
    if (hit.kind != HitKind.point) continue;
    if (accept == null || accept(hit.id)) return hit.id;
  }
  return null;
}

/// The nearest line within reach, if any.
String? lineAt(Geometry geometry, Camera camera, Offset screen) {
  for (final hit in hitsAt(geometry, camera, screen)) {
    if (hit.kind == HitKind.line) return hit.id;
  }
  return null;
}

double _pixels(Camera camera, double metres) =>
    metres * camera.pixelsPerMetreNow;
