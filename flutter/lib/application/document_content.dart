import 'package:flutter/foundation.dart';

import '../domain/document.dart';
import '../domain/geometry.dart';

/// Compares drawing snapshots for dirty tracking, ignoring ID counters.
/// Layer identity is intentional: immutable layer replacements represent a
/// property edit, while history restores the original instances.
bool sameContent(GardenDocument a, GardenDocument b) {
  if (identical(a, b)) return true;
  if (a.id != b.id || !listEquals(a.propertyIds, b.propertyIds)) {
    return false;
  }
  if (!listEquals(a.references, b.references)) return false;
  if (a.hasReferenceLayer != b.hasReferenceLayer) return false;
  if (!listEquals(a.features, b.features)) return false;
  if (a.climate != b.climate || !mapEquals(a.plantings, b.plantings)) {
    return false;
  }
  if (a.layers.length != b.layers.length) return false;
  for (final entry in a.layers.entries) {
    if (!identical(entry.value, b.layers[entry.key])) return false;
  }
  if (a.geometries.length != b.geometries.length) return false;
  for (final entry in a.geometries.entries) {
    final other = b.geometries[entry.key];
    if (other == null) return false;
    final mine = entry.value;
    if (identical(mine, other)) continue;
    if (!_sameCircles(mine.circles, other.circles)) return false;
    if (!identical(mine.points, other.points) ||
        !identical(mine.lines, other.lines) ||
        !identical(mine.shapes, other.shapes) ||
        !listEquals(mine.stack, other.stack)) {
      if (!mapEquals(mine.points, other.points) ||
          !_sameLines(mine.lines, other.lines) ||
          !listEquals(mine.stack, other.stack) ||
          !_sameShapes(mine.shapes, other.shapes)) {
        return false;
      }
    }
  }
  return true;
}

bool _sameLines(Map<String, LineSegment> a, Map<String, LineSegment> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null ||
        other.start != entry.value.start ||
        other.end != entry.value.end ||
        other.bulge != entry.value.bulge ||
        other.startHandle != entry.value.startHandle ||
        other.endHandle != entry.value.endHandle) {
      return false;
    }
  }
  return true;
}

bool _sameCircles(Map<String, Circle> a, Map<String, Circle> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    if (other == null ||
        other.center != entry.value.center ||
        other.radius != entry.value.radius ||
        other.label != entry.value.label) {
      return false;
    }
  }
  return true;
}

bool _sameShapes(Map<String, ClosedShape> a, Map<String, ClosedShape> b) {
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    final other = b[entry.key];
    final mine = entry.value;
    if (other == null ||
        other.label != mine.label ||
        other.rings.length != mine.rings.length) {
      return false;
    }
    for (var ring = 0; ring < mine.rings.length; ring++) {
      final a = mine.rings[ring], b = other.rings[ring];
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i].segmentId != b[i].segmentId ||
            a[i].reversed != b[i].reversed) {
          return false;
        }
      }
    }
  }
  return true;
}
