import 'dart:ui';

import '../domain/document.dart';
import 'camera.dart';
import 'hit_testing.dart';
import 'snapping.dart';

/// A reference to one item in one layer's geometry.
class ItemRef {
  const ItemRef(this.layerId, this.itemId);

  final String layerId;
  final String itemId;

  @override
  bool operator ==(Object other) =>
      other is ItemRef && other.layerId == layerId && other.itemId == itemId;

  @override
  int get hashCode => Object.hash(layerId, itemId);
}

/// The items most recently hovered, newest first, that guides come from.
///
/// To line point B up with point A the user hovers A, then goes and
/// grabs B. Two things would spoil that:
/// - On the way to B the pointer brushes past other lines. So an item is
///   only remembered once the pointer has rested on it for [dwell].
/// - Grabbing B means hovering B as well. So a few items are kept, and
///   the one being moved is skipped (see [activeGuides]), leaving A.
class GuideMemory {
  GuideMemory({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  static const int depth = 5;
  static const Duration dwell = Duration(milliseconds: 150);

  /// Replaceable so tests can control time.
  DateTime Function() clock;

  final List<ItemRef> _recent = [];
  ItemRef? _under;
  DateTime? _since;

  List<ItemRef> get recent => List.unmodifiable(_recent);

  /// Reports the item under the pointer ([item] is null over empty
  /// ground). Returns whether the remembered items changed.
  bool hover(ItemRef? item) {
    if (item == _under) return _rememberUnder();
    final changed = _rememberUnder();
    _under = item;
    _since = item == null ? null : clock();
    return changed;
  }

  /// Checks again whether the pointer has now rested long enough on the
  /// item under it. Returns whether the remembered items changed.
  bool settle() => _rememberUnder();

  bool _rememberUnder() {
    final under = _under;
    final since = _since;
    if (under == null || since == null) return false;
    if (clock().difference(since) < dwell) return false;
    if (_recent.isNotEmpty && _recent.first == under) return false;
    _recent
      ..remove(under)
      ..insert(0, under);
    if (_recent.length > depth) _recent.removeLast();
    return true;
  }
}

/// The point, line or circle edge under [screen] on any layer, points
/// first, then the nearest. Shape insides are ignored: guides come from
/// the parts the pointer actually touches.
ItemRef? guideItemAt(GardenDocument document, Camera camera, Offset screen) {
  final world = camera.toWorld(screen);
  final perMetre = camera.pixelsPerMetreNow;
  ItemRef? best;
  var bestKind = 2;
  var bestGap = double.infinity;
  void consider(String layerId, String id, int kind, double gap) {
    if (kind < bestKind || (kind == bestKind && gap < bestGap)) {
      best = ItemRef(layerId, id);
      bestKind = kind;
      bestGap = gap;
    }
  }

  for (final layerId in document.drawingOrder) {
    final geometry = document.geometryOf(layerId);
    for (final entry in geometry.points.entries) {
      final gap = world.distanceTo(entry.value) * perMetre;
      if (gap <= PointerReach.point) consider(layerId, entry.key, 0, gap);
    }
    if (bestKind == 0) continue;
    for (final line in geometry.lines.values) {
      final gap = line.distanceTo(geometry.points, world) * perMetre;
      if (gap <= PointerReach.line) consider(layerId, line.id, 1, gap);
    }
    for (final circle in geometry.circles.values) {
      final centre = geometry.points[circle.center]!;
      final gap = (world.distanceTo(centre) - circle.radius).abs() * perMetre;
      if (gap <= PointerReach.line) consider(layerId, circle.id, 1, gap);
    }
  }
  return best;
}

/// The guides of the newest remembered item that still exists and is not
/// being moved. [moving] holds the points in motion, keyed by layer; an
/// item that depends on any of them cannot guide itself.
GuideSet activeGuides(
  GardenDocument document,
  List<ItemRef> recent, {
  Map<String, Set<String>> moving = const {},
}) {
  for (final item in recent) {
    if (!document.layers.containsKey(item.layerId)) continue;
    final geometry = document.geometryOf(item.layerId);
    if (!geometry.contains(item.itemId)) continue;
    final inMotion = moving[item.layerId];
    if (inMotion != null &&
        geometry.definingPoints([item.itemId]).any(inMotion.contains)) {
      continue;
    }
    final set = guidesOf(geometry, item.itemId);
    if (!set.isEmpty) return set;
  }
  return GuideSet.empty;
}
